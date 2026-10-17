"""One OpenRouter chat-completions client with a bounded retry policy (owner decision 5, 17 October 2026).

Shared by the route C solver and the untouched truth drafting, so both follow one policy:

- **Retryable:** a transport or network error, a timeout, HTTP 408, 429, 500, 502, 503 or
  504, and OpenRouter's provider-overloaded answers (HTTP 529, or an error body whose code
  is one of those statuses or whose message says the provider is overloaded).
- **Never retried:** every content outcome. An HTTP 200 answer is returned to the caller,
  which scores a schema failure, a `finish_reason` other than `stop` or a model or provider
  mismatch as a failed case. Any other HTTP status (400, 401, 402, 403, 404, 413, 422, ...)
  is final too.
- **Backoff:** exponential with full jitter (base 2 s, cap 60 s); a `Retry-After` header is
  respected in both forms (delta-seconds and HTTP-date) as the minimum wait.
- **Bounds:** at most 5 attempts and a total deadline of 180 s per call. Each attempt gets the
  time left as a **whole-attempt** deadline (phase 4): `http_post` aborts the connection when it
  passes, however slowly the body arrives. Before phase 4 the time left was only a per-read
  socket timeout, so one slow attempt could run past 180 s (263 s in the phase 3 development
  arms, which ran without the whole-call deadline). A call that exhausts its retries returns
  its last cause.
- **Ledger:** the caller's `on_attempt` hook sees every attempt, so each one is recorded
  with its reported cost, or as unknown.

Why not Inspect's own retry for `openrouter/...`: Inspect 0.3.276 classifies 429 and 5xx
and parses `Retry-After`, but its backoff (`wait_exponential_jitter`) does not use the
header (it only feeds the concurrency controller), and the OpenAI SDK client it builds keeps
the SDK's default of two internal retries, which sleep on `Retry-After` before Inspect sees
the error. Attempts inside either loop never reach the spend ledger, and the two loops
compound. Route C therefore calls OpenRouter here, with Inspect's model API unused (the task
runs on `mockllm/model` and the solver never calls `generate`), so there is exactly one
retry loop. Inspect still supplies the dataset, scorer, metrics and logs.

Pure apart from the injected `post`, `sleep`, `clock` and `rng`; the key only ever goes in
the Authorization header of the real `post`, never into a result, log or ledger.
"""

from __future__ import annotations

import http.client
import json
import random
import re
import socket
import ssl
import threading
import time
import urllib.error
import urllib.parse
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import UTC, datetime
from decimal import Decimal
from email.utils import parsedate_to_datetime
from typing import Any

ENDPOINT_URL = "https://openrouter.ai/api/v1/chat/completions"
GENERATION_URL = "https://openrouter.ai/api/v1/generation?id="
RETRYABLE_STATUSES = frozenset({408, 429, 500, 502, 503, 504, 529})
RETRYABLE_ERROR_KIND = "retryable_error_unknown_cost"  # the same strings as budget.py
REJECTED_ERROR_KIND = "rejected_no_generation_unknown_cost"


def attempt_kind(status: int, body: dict[str, Any] | None, retryable: bool) -> str | None:
    """The ledger kind of an attempt that returned no generation, else None.

    - a retryable error with no generation returned: RETRYABLE_ERROR_KIND;
    - a non-retryable HTTP 4xx with no `id` and no `usage`: REJECTED_ERROR_KIND.
    Neither counts toward the three-unknown stop. An HTTP 200 answer is never relabelled:
    without a cost it still counts.
    """
    if status == 200:
        return None
    has_generation = isinstance(body, dict) and bool(body.get("id") or body.get("usage"))
    if has_generation:
        return None
    if retryable:
        return RETRYABLE_ERROR_KIND
    if 400 <= status < 500:
        return REJECTED_ERROR_KIND
    return None


@dataclass(frozen=True)
class RetryPolicy:
    max_attempts: int = 5
    deadline_seconds: float = 180.0
    base_seconds: float = 2.0
    cap_seconds: float = 60.0


@dataclass
class Attempt:
    number: int
    status: int  # 0 for a transport error or timeout
    body: dict[str, Any] | None
    seconds: float
    retryable: bool
    cause: str | None
    retry_after: float | None = None


@dataclass
class CallResult:
    status: int
    body: dict[str, Any] | None
    attempts: list[Attempt] = field(default_factory=list)
    exhausted: bool = False  # the last attempt was retryable but no retry was left
    cause: str | None = None

    @property
    def retries(self) -> int:
        return max(len(self.attempts) - 1, 0)


def parse_retry_after(value: str | None, now: datetime) -> float | None:
    """Seconds to wait from a `Retry-After` value: delta-seconds or an HTTP-date; None if absent or invalid."""
    if value is None:
        return None
    text = value.strip()
    if not text:
        return None
    try:
        seconds = float(text)
    except ValueError:
        try:
            when = parsedate_to_datetime(text)
        except (TypeError, ValueError, IndexError):
            return None
        if when.tzinfo is None:
            when = when.replace(tzinfo=UTC)
        return max((when - now).total_seconds(), 0.0)
    if seconds != seconds or seconds in (float("inf"), float("-inf")):  # NaN or infinite
        return None
    return max(seconds, 0.0)


def classify(status: int, body: dict[str, Any] | None) -> tuple[bool, str | None]:
    """(retryable, cause) for one attempt. An HTTP 200 answer without an error is final with no cause."""
    if status == 0:
        return True, "transport error or timeout"
    error = body.get("error") if isinstance(body, dict) else None
    if status == 200 and not isinstance(error, dict):
        return False, None
    message = str(error.get("message", "")) if isinstance(error, dict) else ""
    code = error.get("code") if isinstance(error, dict) else None
    overloaded = "overload" in message.lower()
    if status in RETRYABLE_STATUSES or overloaded or (isinstance(code, int) and code in RETRYABLE_STATUSES):
        return True, f"HTTP {status}" + (f" {message[:120]}" if message else "")
    return False, f"HTTP {status}" + (f" {message[:120]}" if message else "")


def backoff_seconds(attempt: int, policy: RetryPolicy, rng: random.Random, retry_after: float | None) -> float:
    """Full-jitter exponential backoff, never shorter than the server's `Retry-After`."""
    ceiling = min(policy.cap_seconds, policy.base_seconds * (2 ** (attempt - 1)))
    wait = rng.uniform(0, ceiling)
    return max(wait, retry_after or 0.0)


PostFn = Callable[[dict[str, Any], float], tuple[int, dict[str, Any] | None, dict[str, str], float]]
DEFAULT_POLICY = RetryPolicy()


def call_with_retry(
    body: dict[str, Any],
    post: PostFn,
    *,
    policy: RetryPolicy = DEFAULT_POLICY,
    sleep: Callable[[float], None] = time.sleep,
    clock: Callable[[], float] = time.monotonic,
    now: Callable[[], datetime] = lambda: datetime.now(UTC),
    rng: random.Random | None = None,
    on_attempt: Callable[[Attempt], None] | None = None,
) -> CallResult:
    """POST `body` until a final answer, the attempt cap or the deadline; every attempt goes to `on_attempt`."""
    rng = rng or random.Random()
    started = clock()
    attempts: list[Attempt] = []
    while True:
        remaining = policy.deadline_seconds - (clock() - started)
        if remaining <= 0:
            last = attempts[-1] if attempts else None
            return CallResult(
                status=last.status if last else 0,
                body=last.body if last else None,
                attempts=attempts,
                exhausted=True,
                cause=f"deadline of {policy.deadline_seconds:.0f} s reached" + (f" after {last.cause}" if last else ""),
            )
        status, response, headers, seconds = post(body, remaining)
        retryable, cause = classify(status, response)
        retry_after = parse_retry_after({k.lower(): v for k, v in headers.items()}.get("retry-after"), now()) if retryable else None
        attempt = Attempt(len(attempts) + 1, status, response, seconds, retryable, cause, retry_after)
        attempts.append(attempt)
        if on_attempt is not None:
            on_attempt(attempt)
        if not retryable:
            return CallResult(status=status, body=response, attempts=attempts, cause=cause)
        if attempt.number >= policy.max_attempts:
            return CallResult(
                status=status, body=response, attempts=attempts, exhausted=True, cause=f"{policy.max_attempts} attempts: {cause}"
            )
        wait = backoff_seconds(attempt.number, policy, rng, retry_after)
        if clock() - started + wait >= policy.deadline_seconds:
            return CallResult(
                status=status,
                body=response,
                attempts=attempts,
                exhausted=True,
                cause=f"deadline of {policy.deadline_seconds:.0f} s would pass while waiting {wait:.1f} s after {cause}",
            )
        sleep(wait)


class RefuseRedirects(urllib.request.HTTPRedirectHandler):
    """Never follow a redirect: urllib would resend the Authorization header to the new host."""

    def redirect_request(self, req, fp, code, msg, headers, newurl):  # noqa: ANN001, ANN201
        raise urllib.error.HTTPError(req.full_url, code, f"redirect refused ({code})", headers, fp)


OPENER = urllib.request.build_opener(RefuseRedirects)


class DeadlineExceeded(Exception):
    """The attempt's whole-call deadline passed before the full response body arrived."""

    def __init__(self, partial: bytes = b"") -> None:
        super().__init__("whole-call deadline reached")
        self.partial = partial


MINIMUM_ATTEMPT_SECONDS = 0.1
READ_CHUNK_BYTES = 65536
CUT_MARKER = "_deadline_cut"  # set on the body of an attempt the whole-call deadline cut
CUT_BEFORE_SEND = "before_send"  # DNS or connect: the request never reached the provider
CUT_AFTER_SEND = "after_send"  # the request was sent; a generation may exist and may be charged
CUT_UNRECONCILED_KIND = "cut_unreconciled_per_call_ceiling"
GENERATION_ID = re.compile(rb'"id"\s*:\s*"(gen-[A-Za-z0-9_-]+)"')

Resolver = Callable[[str, int], list[Any]]


def _getaddrinfo(host: str, port: int) -> list[Any]:
    return socket.getaddrinfo(host, port, type=socket.SOCK_STREAM)


def resolve_within(host: str, port: int, timeout: float, resolver: Resolver = _getaddrinfo) -> tuple[Any, ...] | None:
    """Resolve `host` in a daemon thread and give up after `timeout` seconds; None on timeout or failure.

    `getaddrinfo` has no portable timeout, so the lookup runs in a thread that is abandoned
    (not killed) when the deadline passes; the attempt then ends as a cut before send.
    """
    found: list[Any] = []

    def run() -> None:
        try:
            found.extend(resolver(host, port))
        except OSError:
            pass

    worker = threading.Thread(target=run, daemon=True)
    worker.start()
    worker.join(max(timeout, 0.0))
    if worker.is_alive() or not found:
        return None
    return found[0][4]  # the first address's sockaddr


class _ResolvedHTTPConnection(http.client.HTTPConnection):
    """Connects to an address resolved in advance (so DNS sits inside the deadline); Host stays the name."""

    def __init__(self, host: str, port: int, address: tuple[Any, ...], timeout: float) -> None:
        super().__init__(host, port, timeout=timeout)
        self._address = address

    def connect(self) -> None:
        self.sock = socket.create_connection((self._address[0], self.port), self.timeout)


class _ResolvedHTTPSConnection(http.client.HTTPSConnection):
    """As above for TLS: the certificate is still verified against the host name (SNI and hostname check)."""

    def __init__(self, host: str, port: int, address: tuple[Any, ...], timeout: float) -> None:
        super().__init__(host, port, timeout=timeout, context=ssl.create_default_context())
        self._address = address
        self._tls = ssl.create_default_context()

    def connect(self) -> None:
        raw = socket.create_connection((self._address[0], self.port), self.timeout)
        self.sock = raw  # visible to the watchdog during the TLS handshake
        self.sock = self._tls.wrap_socket(raw, server_hostname=self.host)


def _abort(connection: http.client.HTTPConnection) -> None:
    """Watchdog action: shut the socket down so a blocked connect, send or read returns at once."""
    sock = connection.sock
    if sock is not None:
        try:
            sock.shutdown(socket.SHUT_RDWR)
        except OSError:
            pass
    connection.close()


def read_until(read_chunk: Callable[[int], bytes], deadline: float, clock: Callable[[], float] = time.monotonic) -> bytes:
    """Read a body chunk by chunk, stopping with `DeadlineExceeded` once `deadline` has passed.

    `read_chunk` returns whatever bytes are available (at most the size asked) and `b""` at the end.
    The bytes read before the cut travel on the exception, so a generation id can still be found.
    """
    parts: list[bytes] = []
    while True:
        if clock() >= deadline:
            raise DeadlineExceeded(b"".join(parts))
        try:
            chunk = read_chunk(READ_CHUNK_BYTES)
        except (OSError, http.client.HTTPException) as error:
            if clock() >= deadline:
                raise DeadlineExceeded(b"".join(parts)) from error
            raise
        if not chunk:
            return b"".join(parts)
        parts.append(chunk)


def cut_body(stage: str, partial: bytes = b"") -> dict[str, Any]:
    """The body recorded for a cut attempt: the stage, plus a generation id if the partial body held one."""
    body: dict[str, Any] = {CUT_MARKER: stage}
    match = GENERATION_ID.search(partial)
    if match:
        body["id"] = match.group(1).decode("ascii")
    return body


def cut_stage(body: Any) -> str | None:
    return body.get(CUT_MARKER) if isinstance(body, dict) else None


def charge_for_cut(body: Any, cost: Decimal | None, per_call_usd: Decimal) -> tuple[Decimal | None, str | None]:
    """Spend after a deadline cut (owner decision, 18 October 2026).

    A cut after the request was sent may still have produced a charged generation. If its id
    was returned, the caller has already looked it up (`cost`); when that found nothing, or no
    id was returned, the attempt is charged conservatively at the per-call stop and marked
    CUT_UNRECONCILED_KIND. A cut before the request was sent (DNS or connect) cannot have a
    generation and is left to the ordinary no-generation handling. Returns (cost, kind override).
    """
    if cut_stage(body) != CUT_AFTER_SEND or cost is not None:
        return cost, None
    return per_call_usd, CUT_UNRECONCILED_KIND


def http_post(key: str, title: str, url: str = ENDPOINT_URL, resolver: Resolver = _getaddrinfo) -> PostFn:
    """The real POST to OpenRouter; the key goes in the Authorization header only.

    Whole-call deadline (phase 4): `timeout` bounds the **whole attempt**, not each socket read.

    - DNS: resolved in a thread with the attempt's deadline (`resolve_within`); a lookup still
      running at the deadline is abandoned and the attempt ends.
    - Connect (TCP and TLS): `connect()` is called explicitly with the time left as its socket
      timeout, and the watchdog can shut the socket during the handshake. Once it returns the
      deadline is checked, and the socket timeout is reset to the time left before sending.
    - Send and receive: a watchdog timer shuts the socket down at the deadline, so a server that
      never sends headers or trickles the body ends there, and the body is read in chunks with
      a deadline check between chunks.

    `call_with_retry` passes the time left of its 180 s budget as `timeout`, so no call, retries
    included, can outlast that budget by more than the watchdog's reaction time. A cut attempt
    returns status 0 with a `cut_body` (stage, and any generation id seen), which the retry
    policy treats like any other timeout and `charge_for_cut` prices. The development arms of
    phase 3 ran without this deadline. Redirects are never followed (`http.client` does not
    follow them), so the key never reaches another host; a 3xx is a final, non-retryable status.
    """
    parts = urllib.parse.urlsplit(url)
    if parts.scheme not in ("https", "http") or not parts.hostname:
        raise ValueError(f"unsupported URL {url!r}")
    host: str = parts.hostname
    port = parts.port or (443 if parts.scheme == "https" else 80)
    path = parts.path + (f"?{parts.query}" if parts.query else "")

    def post(body: dict[str, Any], timeout: float) -> tuple[int, dict[str, Any] | None, dict[str, str], float]:
        started = time.monotonic()
        budget = max(timeout, MINIMUM_ATTEMPT_SECONDS)
        deadline = started + budget

        def left() -> float:
            return deadline - time.monotonic()

        def cut(stage: str, partial: bytes = b"") -> tuple[int, dict[str, Any] | None, dict[str, str], float]:
            return 0, cut_body(stage, partial), {}, time.monotonic() - started

        def failed() -> tuple[int, dict[str, Any] | None, dict[str, str], float]:
            return 0, None, {}, time.monotonic() - started

        address = resolve_within(host, port, budget, resolver)
        if address is None:
            return cut(CUT_BEFORE_SEND) if left() <= 0 else failed()
        if left() <= 0:
            return cut(CUT_BEFORE_SEND)
        connection: http.client.HTTPConnection
        if parts.scheme == "https":
            connection = _ResolvedHTTPSConnection(host, port, address, left())
        else:
            connection = _ResolvedHTTPConnection(host, port, address, left())
        watchdog = threading.Timer(max(left(), 0.0), _abort, args=(connection,))
        watchdog.daemon = True
        watchdog.start()
        sent = False
        try:
            try:
                connection.connect()
            except OSError:
                return cut(CUT_BEFORE_SEND) if left() <= 0 else failed()
            remaining = left()
            if remaining <= 0 or connection.sock is None:
                return cut(CUT_BEFORE_SEND)
            connection.sock.settimeout(remaining)
            sent = True
            connection.request(
                "POST",
                path or "/",
                body=json.dumps(body).encode("utf-8"),
                headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json", "X-Title": title},
            )
            response = connection.getresponse()
            status = response.status
            headers = dict(response.getheaders())
            payload = read_until(response.read1, deadline)
        except DeadlineExceeded as exceeded:
            return cut(CUT_AFTER_SEND, exceeded.partial)
        except (http.client.HTTPException, OSError, ValueError):
            if left() <= 0:
                return cut(CUT_AFTER_SEND if sent else CUT_BEFORE_SEND)
            return failed()
        finally:
            watchdog.cancel()
            connection.close()
        if left() < 0:  # the watchdog fired while the last chunk was in flight
            return cut(CUT_AFTER_SEND, payload)
        try:
            parsed = json.loads(payload)
        except (json.JSONDecodeError, UnicodeDecodeError):
            parsed = None
        return status, parsed if isinstance(parsed, dict) else None, headers, time.monotonic() - started

    return post


def generation_cost(key: str, generation_id: str, timeout: float = 20.0) -> tuple[str, Any]:
    """OpenRouter's generation lookup: ("found", total_cost), ("not_found", None) or ("error", cause)."""
    request = urllib.request.Request(GENERATION_URL + generation_id, headers={"Authorization": f"Bearer {key}"}, method="GET")
    try:
        with OPENER.open(request, timeout=timeout) as response:
            data = json.loads(response.read())
    except urllib.error.HTTPError as error:
        return ("not_found", None) if error.code == 404 else ("error", f"HTTP {error.code}")
    except (urllib.error.URLError, TimeoutError, OSError, json.JSONDecodeError) as error:
        return "error", type(error).__name__
    record = data.get("data") if isinstance(data, dict) else None
    return ("found", record.get("total_cost")) if isinstance(record, dict) else ("not_found", None)
