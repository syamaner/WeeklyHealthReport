import sys, threading, json, time
from http.server import BaseHTTPRequestHandler, HTTPServer
sys.path.insert(0, sys.argv[1]); import http_client as h
calls = []
class H(BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_GET(self):
        calls.append(time.monotonic())
        if self.path.startswith("/flaky") and len(calls) <= 2:
            self.send_response(429); self.send_header("Retry-After", "1"); self.end_headers(); return
        if self.path.startswith("/redirect"):
            self.send_response(302); self.send_header("Location", "http://example.invalid/elsewhere"); self.end_headers(); return
        if self.path.startswith("/forbidden"):
            self.send_response(403); self.end_headers(); return
        self.send_response(200); self.send_header("Content-Type","application/json"); self.end_headers(); self.wfile.write(b'{"ok":1}')
srv = HTTPServer(("127.0.0.1", 0), H); threading.Thread(target=srv.serve_forever, daemon=True).start()
base = f"http://127.0.0.1:{srv.server_port}"
h.LIMITS_PER_MIN["127.0.0.1"] = 120   # 0.5 s interval for the test
c = h.Client(base_delay=0.2, breaker=3, log=lambda m: print("  log:", m))
t0 = time.monotonic(); print("flaky ->", c.get_json(base + "/flaky"), f"after {time.monotonic()-t0:.1f}s, calls={len(calls)}")
print("interval after 429s:", round(c.interval["127.0.0.1"], 2))
try: c.get_json(base + "/forbidden")
except Exception as e: print("403 not retried:", type(e).__name__, e.code, "calls", len(calls))
before = len(calls)
try:
    c.get_json(base + "/redirect")
    print("redirect FOLLOWED (wrong)")
    sys.exit(1)
except Exception as e:
    print("redirect refused:", type(e).__name__, "calls", len(calls) - before)
    if len(calls) - before != 1:
        print("FAILED: a refused redirect must make exactly one call")
        sys.exit(1)
gaps = [b - a for a, b in zip(calls, calls[1:])]; print("min gap between calls:", round(min(gaps), 2))
try:
    c.get_json(base + "/forbidden")
except Exception: pass
try:
    c.get_json(base + "/forbidden")
except h.CircuitOpen as e: print("breaker:", e)
