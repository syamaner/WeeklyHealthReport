"""Synthetic tests for the internal TestFlight release helpers.

No release credential, network call or binary upload is involved. The ES256 round
trip uses a throwaway key generated in a temporary directory for the test only.
"""

import base64
import datetime as dt
import importlib.util
import json
import shutil
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path


SCRIPTS = Path(__file__).parents[1]


def load(name: str):
    spec = importlib.util.spec_from_file_location(name, SCRIPTS / f"{name}.py")
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    sys.modules[spec.name] = module
    spec.loader.exec_module(module)
    return module


asc = load("testflight_asc")
guard = load("testflight_guard")
verify = load("testflight_verify_ipa")

SHA = "a" * 40
APP = "6812893951"
GROUP = "group-1"


class FakeTransport:
    def __init__(self, routes):
        self.routes = routes
        self.calls = []

    def __call__(self, method, url, body, token):
        self.calls.append((method, url, body))
        for (route_method, fragment), responses in self.routes.items():
            if route_method == method and fragment in url:
                return responses.pop(0) if len(responses) > 1 else responses[0]
        raise AssertionError(f"unexpected request {method} {url}")


def client(routes):
    transport = FakeTransport(routes)
    return asc.Client(token_factory=lambda: "synthetic", transport=transport), transport


def group_payload(internal=True, public_link=False, app=APP):
    return (200, {"data": {
        "id": GROUP,
        "attributes": {"name": "Internal Testing", "isInternalGroup": internal, "publicLinkEnabled": public_link},
        "relationships": {"app": {"data": {"type": "apps", "id": app}}},
    }})


def build(state="VALID", build_id="build-1", encryption=False):
    return {"id": build_id, "attributes": {"processingState": state, "usesNonExemptEncryption": encryption}}


class DerSignatureTests(unittest.TestCase):
    def test_short_components_are_left_padded(self):
        der = bytes([0x30, 0x06, 0x02, 0x01, 0x05, 0x02, 0x01, 0x07])
        raw = asc.der_to_raw_signature(der)
        self.assertEqual(raw, b"\x00" * 31 + b"\x05" + b"\x00" * 31 + b"\x07")

    def test_leading_zero_on_high_bit_component_is_removed(self):
        r = b"\x00" + b"\x80" + b"\x01" * 31
        s = b"\x02" * 32
        der = bytes([0x30, 2 + len(r) + 2 + len(s), 0x02, len(r)]) + r + bytes([0x02, len(s)]) + s
        self.assertEqual(asc.der_to_raw_signature(der), r[1:] + s)

    def test_malformed_signature_fails_closed(self):
        for der in (b"", b"\x31\x06\x02\x01\x05\x02\x01\x07", bytes([0x30, 0x07, 0x02, 0x01, 0x05, 0x02, 0x01, 0x07])):
            with self.assertRaises(asc.ReleaseError):
                asc.der_to_raw_signature(der)


@unittest.skipUnless(shutil.which("openssl"), "openssl is required")
class TokenTests(unittest.TestCase):
    def test_token_verifies_with_throwaway_key_and_has_bounded_lifetime(self):
        with tempfile.TemporaryDirectory() as work:
            key = Path(work, "throwaway.p8")
            public = Path(work, "throwaway.pub")
            subprocess.run(
                ["openssl", "genpkey", "-algorithm", "EC", "-pkeyopt", "ec_paramgen_curve:P-256", "-out", str(key)],
                check=True, capture_output=True,
            )
            subprocess.run(["openssl", "pkey", "-in", str(key), "-pubout", "-out", str(public)], check=True, capture_output=True)
            token = asc.make_token("KEYID", "issuer", key, now=1_000)
            header, payload, signature = token.split(".")
            pad = lambda value: value + "=" * (-len(value) % 4)
            claims = json.loads(base64.urlsafe_b64decode(pad(payload)))
            self.assertEqual(json.loads(base64.urlsafe_b64decode(pad(header)))["alg"], "ES256")
            self.assertEqual(claims["aud"], "appstoreconnect-v1")
            self.assertLessEqual(claims["exp"] - claims["iat"], 20 * 60)

            raw = base64.urlsafe_b64decode(pad(signature))
            self.assertEqual(len(raw), 64)
            def integer(value):
                value = value.lstrip(b"\x00") or b"\x00"
                if value[0] & 0x80:
                    value = b"\x00" + value
                return bytes([0x02, len(value)]) + value
            body = integer(raw[:32]) + integer(raw[32:])
            der = bytes([0x30, len(body)]) + body
            sig_path = Path(work, "sig.der")
            sig_path.write_bytes(der)
            result = subprocess.run(
                ["openssl", "dgst", "-sha256", "-verify", str(public), "-signature", str(sig_path)],
                input=f"{header}.{payload}".encode(), capture_output=True,
            )
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_missing_key_fails_without_echoing_paths_contents(self):
        with self.assertRaises(asc.ReleaseError):
            asc.make_token("KEYID", "issuer", Path("/nonexistent/AuthKey.p8"))


class AscPreflightTests(unittest.TestCase):
    def test_passes_for_internal_group_and_unused_build(self):
        c, _ = client({
            ("GET", "/v1/betaGroups/"): [group_payload()],
            ("GET", "/v1/builds?"): [(200, {"data": [], "links": {}})],
        })
        self.assertTrue(asc.preflight(c, APP, GROUP, "26", "0.2.0")["build_number_unused"])

    def test_refuses_used_build_number(self):
        c, _ = client({
            ("GET", "/v1/betaGroups/"): [group_payload()],
            ("GET", "/v1/builds?"): [(200, {"data": [build()], "links": {}})],
        })
        with self.assertRaisesRegex(asc.ReleaseError, "already exists"):
            asc.preflight(c, APP, GROUP, "25", "0.2.0")

    def test_refuses_external_group_public_link_and_other_app(self):
        for payload in (group_payload(internal=False), group_payload(public_link=True), group_payload(app="999")):
            c, _ = client({("GET", "/v1/betaGroups/"): [payload]})
            with self.assertRaises(asc.ReleaseError):
                asc.preflight(c, APP, GROUP, "26", "0.2.0")

    def test_refuses_bad_identity_before_any_request(self):
        c, transport = client({})
        for number in ("0", "26a", "1234567", ""):
            with self.assertRaises(asc.ReleaseError):
                asc.preflight(c, APP, GROUP, number, "0.2.0")
        self.assertEqual(transport.calls, [])

    def test_follows_pagination_and_refuses_foreign_hosts(self):
        c, _ = client({
            ("GET", "page=2"): [(200, {"data": [{"id": "b"}], "links": {}})],
            ("GET", "/v1/items"): [(200, {"data": [{"id": "a"}], "links": {"next": asc.API_ROOT + "/v1/items?page=2"}})],
        })
        self.assertEqual([item["id"] for item in c.get_all("/v1/items")], ["a", "b"])
        c2, _ = client({("GET", "/v1/items"): [(200, {"data": [], "links": {"next": "https://example.com/v1/x"}})]})
        with self.assertRaisesRegex(asc.ReleaseError, "outside"):
            c2.get_all("/v1/items")


class AscDistributeTests(unittest.TestCase):
    def routes(self, builds_responses, members=("build-1",), whats_new="Test notes"):
        return {
            ("GET", "/v1/betaGroups/group-1?include"): [group_payload()],
            ("GET", "/v1/builds?"): builds_responses,
            ("GET", "/betaBuildLocalizations"): [
                (200, {"data": [{"id": "loc-1", "attributes": {"locale": "en-GB", "whatsNew": None}}], "links": {}}),
                (200, {"data": [{"id": "loc-1", "attributes": {"locale": "en-GB", "whatsNew": whats_new}}], "links": {}}),
            ],
            ("PATCH", "/v1/betaBuildLocalizations/loc-1"): [(200, {"data": {}})],
            ("POST", "/relationships/builds"): [(204, None)],
            ("GET", "/v1/betaGroups/group-1/builds"): [(200, {"data": [{"id": m} for m in members], "links": {}})],
        }

    def test_waits_for_processing_then_sets_notes_and_assigns_group_once(self):
        c, transport = client(self.routes([
            (200, {"data": [], "links": {}}),
            (200, {"data": [build("PROCESSING")], "links": {}}),
            (200, {"data": [build("VALID")], "links": {}}),
        ]))
        out = asc.distribute(c, APP, GROUP, "26", "0.2.0", "Test notes", 600,
                             sleep=lambda _: None, clock=lambda: 0.0)
        self.assertEqual(out["build_id"], "build-1")
        self.assertEqual(len([call for call in transport.calls if call[0] == "POST"]), 1)
        self.assertEqual(len([call for call in transport.calls if call[0] == "PATCH"]), 1)

    def test_failed_processing_duplicates_and_timeout_fail_closed(self):
        cases = [
            [(200, {"data": [build("INVALID")], "links": {}})],
            [(200, {"data": [build(), build(build_id="build-2")], "links": {}})],
        ]
        for responses in cases:
            c, _ = client(self.routes(responses))
            with self.assertRaises(asc.ReleaseError):
                asc.wait_for_build(c, APP, "26", "0.2.0", 0, sleep=lambda _: None, clock=lambda: 0.0)
        c, _ = client(self.routes([(200, {"data": [], "links": {}})]))
        with self.assertRaisesRegex(asc.ReleaseError, "read-only"):
            asc.wait_for_build(c, APP, "26", "0.2.0", 0, sleep=lambda _: None, clock=lambda: 0.0)

    def test_read_back_mismatches_fail(self):
        c, _ = client(self.routes([(200, {"data": [build()], "links": {}})], whats_new="something else"))
        with self.assertRaisesRegex(asc.ReleaseError, "read-back"):
            asc.set_what_to_test(c, "build-1", "Test notes")
        c, _ = client(self.routes([(200, {"data": [build()], "links": {}})], members=("other",)))
        with self.assertRaisesRegex(asc.ReleaseError, "not listed"):
            asc.add_to_group(c, GROUP, "build-1")

    def test_non_exempt_encryption_is_refused(self):
        c, _ = client(self.routes([(200, {"data": [build(encryption=True)], "links": {}})]))
        with self.assertRaisesRegex(asc.ReleaseError, "encryption"):
            asc.distribute(c, APP, GROUP, "26", "0.2.0", "Test notes", 0)

    def test_http_errors_report_status_without_token(self):
        c, _ = client({("GET", "/v1/betaGroups/"): [(403, {"errors": [{"status": "403", "code": "FORBIDDEN", "detail": "no"}]})]})
        with self.assertRaises(asc.ReleaseError) as raised:
            asc.check_group(c, APP, GROUP)
        self.assertIn("403", str(raised.exception))
        self.assertNotIn("synthetic", str(raised.exception))


class GuardTests(unittest.TestCase):
    def test_dispatch_rules(self):
        guard.check_dispatch("workflow_dispatch", "refs/heads/main", guard.EXPECTED_REPOSITORY, "1", SHA)
        bad = [
            ("push", "refs/heads/main", guard.EXPECTED_REPOSITORY, "1", SHA),
            ("pull_request", "refs/heads/main", guard.EXPECTED_REPOSITORY, "1", SHA),
            ("workflow_dispatch", "refs/heads/feature", guard.EXPECTED_REPOSITORY, "1", SHA),
            ("workflow_dispatch", "refs/tags/v1", guard.EXPECTED_REPOSITORY, "1", SHA),
            ("workflow_dispatch", "refs/heads/main", "someone/WeeklyHealthReport", "1", SHA),
            ("workflow_dispatch", "refs/heads/main", guard.EXPECTED_REPOSITORY, "2", SHA),
            ("workflow_dispatch", "refs/heads/main", guard.EXPECTED_REPOSITORY, "1", "abc"),
        ]
        for args in bad:
            with self.assertRaises(guard.GuardError, msg=args):
                guard.check_dispatch(*args)

    def test_build_number(self):
        guard.check_build_number("26")
        for value in ("", "0", "026", "26 ", "2.6", "1234567", "26;echo"):
            with self.assertRaises(guard.GuardError):
                guard.check_build_number(value)

    def test_marketing_version_must_be_unique(self):
        self.assertEqual(guard.marketing_version("MARKETING_VERSION = 0.2.0;\nMARKETING_VERSION = 0.2.0;"), "0.2.0")
        for text in ("", "MARKETING_VERSION = 0.2.0;\nMARKETING_VERSION = 0.3.0;"):
            with self.assertRaises(guard.GuardError):
                guard.marketing_version(text)

    def test_ci_must_have_succeeded_on_main_push_for_the_exact_sha(self):
        good = {"head_sha": SHA, "event": "push", "head_branch": "main", "status": "completed", "conclusion": "success"}
        self.assertTrue(guard.ci_succeeded({"workflow_runs": [good]}, SHA))
        for change in ({"head_sha": "b" * 40}, {"event": "pull_request"}, {"head_branch": "x"},
                       {"status": "in_progress"}, {"conclusion": "failure"}):
            self.assertFalse(guard.ci_succeeded({"workflow_runs": [{**good, **change}]}, SHA))
        with self.assertRaises(guard.GuardError):
            guard.ci_succeeded({}, SHA)

    def test_what_to_test_from_release_doc(self):
        doc = "# R\n\n## What to Test (owner approved)\n\nIntro.\n\n```text\nLine one.\n\nLine two.\n```\n\n## Next\n"
        self.assertEqual(guard.extract_what_to_test(doc), "Line one.\n\nLine two.")
        for text in ("# R\n```text\nx\n```\n", "## What to Test\n\nno block\n## Other\n```text\nx\n```\n", "## What to Test\n```text\n```\n"):
            with self.assertRaises(guard.GuardError):
                guard.extract_what_to_test(text)

    def test_exactly_one_what_to_test_source_and_safe_paths(self):
        with tempfile.TemporaryDirectory() as work:
            root = Path(work)
            (root / "docs/releases").mkdir(parents=True)
            (root / "docs/releases/r.md").write_text("## What to Test\n```text\nNotes\n```\n")
            self.assertEqual(guard.resolve_what_to_test("", "docs/releases/r.md", root), "Notes")
            self.assertEqual(guard.resolve_what_to_test("Inline", "", root), "Inline")
            for inline, doc in (("", ""), ("a", "docs/releases/r.md"), ("", "../secrets.md"),
                                ("", "docs/releases/../x.md"), ("", "README.md"), ("", "docs/releases/missing.md"),
                                ("x" * 4001, "")):
                with self.assertRaises(guard.GuardError, msg=(inline[:5], doc)):
                    guard.resolve_what_to_test(inline, doc, root)

    def test_outputs_refuse_newlines(self):
        with tempfile.TemporaryDirectory() as work:
            path = Path(work, "out")
            guard.write_output(str(path), {"sha": SHA})
            self.assertEqual(path.read_text(), f"sha={SHA}\n")
            with self.assertRaises(guard.GuardError):
                guard.write_output(str(path), {"x": "a\nb=c"})


class VerifyTests(unittest.TestCase):
    TEAM = "TEAMID1234"
    BUNDLE = "com.example.app"
    CLIENT = "123-abc.apps.googleusercontent.com"
    SCHEME = "com.googleusercontent.apps.123-abc"

    def expected(self):
        return {"bundle_id": self.BUNDLE, "team_id": self.TEAM, "version": "0.2.0", "build_number": "26",
                "oauth_client_id": self.CLIENT, "oauth_redirect_scheme": self.SCHEME}

    def info(self, **changes):
        base = {
            "CFBundleIdentifier": self.BUNDLE, "CFBundleShortVersionString": "0.2.0", "CFBundleVersion": "26",
            "ITSAppUsesNonExemptEncryption": False, "GoogleOAuthClientID": self.CLIENT,
            "GoogleOAuthRedirectScheme": self.SCHEME, "CFBundleURLTypes": [{"CFBundleURLSchemes": [self.SCHEME]}],
            **{key: "Purpose." for key in verify.REQUIRED_PURPOSE_STRINGS},
        }
        base.update(changes)
        return base

    def entitlements(self, **changes):
        base = {"get-task-allow": False, "application-identifier": f"{self.TEAM}.{self.BUNDLE}",
                "com.developer.team-identifier": self.TEAM, "com.apple.developer.healthkit": True}
        base.update(changes)
        return base

    def profile(self, **changes):
        base = {"TeamIdentifier": [self.TEAM], "ExpirationDate": dt.datetime(2030, 1, 1),
                "Entitlements": {"get-task-allow": False, "application-identifier": f"{self.TEAM}.{self.BUNDLE}"}}
        base.update(changes)
        return base

    def check(self, info=None, ents=None, profile=None):
        now = dt.datetime(2026, 10, 16, tzinfo=dt.timezone.utc)
        return verify.check_app(info or self.info(), self.entitlements() if ents is None else ents,
                                profile or self.profile(), self.expected(), now)

    def test_good_app_passes(self):
        self.assertEqual(self.check(), [])

    def test_each_defect_fails(self):
        cases = [
            self.check(info=self.info(CFBundleIdentifier="com.other")),
            self.check(info=self.info(CFBundleVersion="25")),
            self.check(info=self.info(CFBundleShortVersionString="0.3.0")),
            self.check(info=self.info(ITSAppUsesNonExemptEncryption=None)),
            self.check(info=self.info(GoogleOAuthClientID="MISSING")),
            self.check(info=self.info(GoogleOAuthRedirectScheme="com.googleusercontent.apps.other")),
            self.check(info=self.info(CFBundleURLTypes=[])),
            self.check(info=self.info(NSHealthUpdateUsageDescription="")),
            self.check(ents=self.entitlements(**{"get-task-allow": True})),
            self.check(ents=self.entitlements(**{"com.apple.developer.healthkit": None})),
            self.check(ents=self.entitlements(**{"application-identifier": "X.y"})),
            self.check(ents=["not", "a", "dict"]),
            self.check(profile=self.profile(ProvisionedDevices=["udid"])),
            self.check(profile=self.profile(ExpirationDate=dt.datetime(2026, 1, 1))),
            self.check(profile=self.profile(TeamIdentifier=["OTHER"])),
        ]
        for failures in cases:
            self.assertTrue(failures)

    def test_failures_never_echo_oauth_values(self):
        failures = self.check(info=self.info(GoogleOAuthClientID="999-x.apps.googleusercontent.com"))
        self.assertTrue(failures)
        self.assertFalse(any("999" in failure or self.CLIENT in failure for failure in failures))


if __name__ == "__main__":
    unittest.main()
