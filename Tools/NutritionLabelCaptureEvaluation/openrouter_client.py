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
- **Bounds:** at most 5 attempts and a total deadline of 180 s per call; each attempt's
  socket timeout is the time left. A call that exhausts its retries returns its last cause.
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

import json
import random
import time
import urllib.error
import urllib.request
from collections.abc import Callable
from dataclasses import dataclass, field
from datetime import UTC, datetime
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


def http_post(key: str, title: str) -> PostFn:
    """The real POST to OpenRouter; the key goes in the Authorization header only."""

    def post(body: dict[str, Any], timeout: float) -> tuple[int, dict[str, Any] | None, dict[str, str], float]:
        request = urllib.request.Request(
            ENDPOINT_URL,
            data=json.dumps(body).encode("utf-8"),
            headers={"Authorization": f"Bearer {key}", "Content-Type": "application/json", "X-Title": title},
            method="POST",
        )
        started = time.monotonic()
        headers: dict[str, str] = {}
        try:
            with OPENER.open(request, timeout=max(timeout, 1.0)) as response:
                status, payload = response.status, response.read()
                headers = dict(response.headers.items())
        except urllib.error.HTTPError as error:
            status, payload = error.code, error.read()
            headers = dict(error.headers.items()) if error.headers else {}
        except (urllib.error.URLError, TimeoutError, ConnectionError, OSError):
            return 0, None, {}, time.monotonic() - started
        try:
            parsed = json.loads(payload)
        except json.JSONDecodeError:
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
