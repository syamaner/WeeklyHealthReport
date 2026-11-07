"""Shared HTTP client for every network script in this workspace.

- Proactive per-host rate limit, set below each service's published limit.
- Retries 429, 5xx, timeouts and connection errors with exponential backoff and
  full jitter, capped; honours Retry-After (seconds or HTTP date).
- After a 429 the host's interval doubles for the rest of the run (adaptive
  slow-down), and it never speeds back up past the published limit.
- Other 4xx (400, 401, 403, 404) are not retried: they are returned as errors.
- Circuit breaker: after N consecutive failed requests the run aborts instead of
  hammering a service that is refusing us.
"""
import email.utils
import json
import random
import re
import time
import urllib.error
import urllib.parse
import urllib.request
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from private_config import CONFIG  # noqa: E402

UA = "PersonalFoodCatalogue/0.2 (private, non-commercial)"

# Published limits (requests per minute per IP), checked 2026-11-07:
# Open Food Facts API docs: 10/min for search, 15/min for product reads.
LIMITS_PER_MIN = {
    "search.openfoodfacts.org": 10,
    "world.openfoodfacts.org": 10,     # search and product share this host; use the stricter limit
    "uk.openfoodfacts.org": 10,
}
DEFAULT_PER_MIN = 6
SAFETY = 1.15                          # stay ~15 % under the limit
RETRY_STATUS = {408, 429, 500, 502, 503, 504}


# Outbound gate: anything a script sends must look like a food title, never personal text.
_DENY = [re.compile(x, re.I) for x in (
    r"[\w.+-]+@[\w-]+\.[\w.]+",                       # email
    r"\b[A-Z]{1,2}\d[A-Z\d]?\s*\d[A-Z]{2}\b",            # UK postcode
    r"\d{7,}",                                        # long numbers (orders, cards, phones)
    r"[£$€]",                                          # currency
    r"\b\d+\.\d{2}\b",                                 # price-like decimals
    r"\b(Mr|Mrs|Miss|Ms|Mx|Dr)\.?\s+[A-Z][a-z]+",       # honorific and name
    r"\b\d+\s+(\w+\s+){1,3}(road|street|lane|avenue|close|gardens|drive|way)\b",
    r"\b(order|invoice|payment|card|account|delivery|customer)\b",
)]
_BRAND_HONORIFICS = tuple(CONFIG["brand_honorifics"])  # exact brand exceptions, kept private


CJK_FOOD_BIGRAMS = set()  # two-character Chinese fragments from TFDA food names
FOOD_WORDS = None  # set by fetch scripts: words from the bundled CoFID, USDA and TFDA names


def load_food_words(work):
    """Food vocabulary from the generic name lists in work/ (CoFID, USDA, TFDA names) and the
    mapped concepts, varieties and aliases."""
    global FOOD_WORDS
    words = set()
    for name in ("cofid-names.txt", "usda-names.txt", "tfda-names.txt"):
        p = work / name
        if p.exists():
            for line in p.read_text(encoding="utf-8").splitlines():
                for w in re.findall(r"[^\W\d_]{3,}", line.casefold()):
                    words.add(w.rstrip("s"))
    # Mapped concepts, varieties and aliases (generated from food titles, never from personal text)
    import json as _json
    for name in ("mapping-validated.json", *sorted(p.name for p in work.glob("intake-mapping-*.json"))):
        p = work / name
        if p.exists():
            for m in _json.loads(p.read_text(encoding="utf-8")):
                for text in [m.get("concept") or "", m.get("variety") or "", *(m.get("aliases") or [])]:
                    for w in re.findall(r"[^\W\d_]{3,}", str(text).casefold()):
                        words.add(w.rstrip("s"))
    global CJK_FOOD_BIGRAMS
    bigrams = set()
    p = work / "tfda-names.txt"
    if p.exists():
        for line in p.read_text(encoding="utf-8").splitlines():
            parts = line.split("\t")
            zh = parts[2] if len(parts) > 2 else ""
            cjk = "".join(ch for ch in zh if "\u4e00" <= ch <= "\u9fff")
            bigrams |= {cjk[i:i + 2] for i in range(len(cjk) - 1)}
    CJK_FOOD_BIGRAMS = bigrams
    FOOD_WORDS = words
    return words


def safe_query(text: str) -> str:
    """Return text unchanged if it may leave the machine as a search query, else raise.

    Besides the deny patterns, a query must contain at least one word from the generic food
    vocabulary, so a bare personal name ("Alice Smith") can never be sent.

    The receipt extractor already gates its output; this is the last line of defence at the
    point of sending, so no fetch script can skip it.
    """
    probe = text
    for b in _BRAND_HONORIFICS:
        probe = probe.replace(b, "")
    if not text.strip() or len(text) > 160 or any(rx.search(probe) for rx in _DENY):
        raise ValueError("query refused by the outbound privacy gate")
    if FOOD_WORDS is None:
        raise ValueError("food vocabulary not loaded; call load_food_words(work) first")
    tokens = {w.rstrip("s") for w in re.findall(r"[^\W\d_]{3,}", text.casefold())}
    cjk = "".join(ch for ch in text if "\u4e00" <= ch <= "\u9fff")
    cjk_food = any(cjk[i:i + 2] in CJK_FOOD_BIGRAMS for i in range(len(cjk) - 1))
    if not (tokens & FOOD_WORDS) and not cjk_food:
        raise ValueError("query refused: no known food word")
    return text


class ApprovalNeeded(SystemExit):
    pass


def owner_approval(work, queries):
    """Owner approval before any search query leaves the machine (owner decision, 7 Nov 2026).

    Every query must be listed in work/outbound-approved.txt (send) or
    work/outbound-declined.txt (never send), one per line, exactly as written. Undecided
    queries are written to work/outbound-pending.txt and the run stops before any network
    call. Queries refused by safe_query are listed as refused and never offered.
    Returns the set of approved queries.
    """
    from workspace_guard import check_output
    read = lambda name: set((work / name).read_text(encoding="utf-8").splitlines()) if (work / name).exists() else set()
    approved, declined = read("outbound-approved.txt"), read("outbound-declined.txt")
    refused, offer = [], []
    for q in dict.fromkeys(queries):
        try:
            safe_query(q)
        except ValueError:
            refused.append(q)
            continue
        if q not in approved and q not in declined:
            offer.append(q)
    if refused:
        check_output(work / "outbound-refused.txt").write_text("\n".join(refused) + "\n", encoding="utf-8")
    if offer:
        check_output(work / "outbound-pending.txt").write_text("\n".join(offer) + "\n", encoding="utf-8")
        raise ApprovalNeeded(f"{len(offer)} search queries need the owner's approval; nothing was sent. "
                             f"Review work/outbound-pending.txt, move lines to outbound-approved.txt or "
                             f"outbound-declined.txt, then run again.")
    pending = work / "outbound-pending.txt"
    if pending.exists():
        pending.unlink()
    return approved


class _NoRedirect(urllib.request.HTTPRedirectHandler):
    """Refuse redirects, as the app's OFF client does: a request never moves to another host."""
    def redirect_request(self, req, fp, code, msg, headers, newurl):
        raise urllib.error.HTTPError(req.full_url, code, f"redirect refused to {newurl}", headers, fp)


_OPENER = urllib.request.build_opener(_NoRedirect)


class CircuitOpen(RuntimeError):
    pass


class Client:
    def __init__(self, max_attempts=6, base_delay=2.0, max_delay=120.0, breaker=5, log=print):
        self.max_attempts, self.base, self.cap, self.breaker = max_attempts, base_delay, max_delay, breaker
        self.next_ok = {}      # host -> earliest monotonic time for the next request
        self.interval = {}     # host -> current seconds between requests
        self.consecutive_failures = 0
        self.log = log

    def _min_interval(self, host):
        return 60.0 / LIMITS_PER_MIN.get(host, DEFAULT_PER_MIN) * SAFETY

    def _wait_turn(self, host):
        iv = self.interval.setdefault(host, self._min_interval(host))
        now = time.monotonic()
        wait = self.next_ok.get(host, now) - now
        if wait > 0:
            time.sleep(wait)
        self.next_ok[host] = time.monotonic() + iv

    @staticmethod
    def _retry_after(headers):
        ra = headers.get("Retry-After") if headers else None
        if not ra:
            return None
        if ra.strip().isdigit():
            return float(ra)
        try:
            return max(0.0, email.utils.parsedate_to_datetime(ra).timestamp() - time.time())
        except (TypeError, ValueError):
            return None

    def get_json(self, url):
        host = urllib.parse.urlsplit(url).hostname
        last = None
        for attempt in range(self.max_attempts):
            self._wait_turn(host)
            try:
                req = urllib.request.Request(url, headers={"User-Agent": UA, "Accept": "application/json"})
                with _OPENER.open(req, timeout=30) as r:
                    data = json.load(r)
                self.consecutive_failures = 0
                return data
            except urllib.error.HTTPError as e:
                last = e
                if e.code not in RETRY_STATUS:
                    self._failed()
                    raise
                if e.code == 429:  # adaptive: slow this host down for the rest of the run
                    self.interval[host] = min(self.interval[host] * 2, 120.0)
                    self.log(f"429 from {host}; interval now {self.interval[host]:.1f}s")
                hint = self._retry_after(e.headers)
            except (urllib.error.URLError, TimeoutError, ConnectionError) as e:
                last, hint = e, None
            backoff = random.uniform(0, min(self.cap, self.base * 2 ** attempt))  # full jitter
            delay = max(backoff, hint or 0)
            self.log(f"retry {attempt + 1}/{self.max_attempts - 1} for {host} in {delay:.1f}s ({last})")
            self.next_ok[host] = max(self.next_ok.get(host, 0), time.monotonic() + delay)
        self._failed()
        raise last if last else RuntimeError(f"request to {host} failed")

    def _failed(self):
        self.consecutive_failures += 1
        if self.consecutive_failures >= self.breaker:
            raise CircuitOpen(f"{self.consecutive_failures} consecutive failures; stopping the run")
