#!/usr/bin/env python3
"""Minimal App Store Connect client for the internal TestFlight release workflow.

Design rules (docs/testflight-ci-release-v1.md):

- Standard library only. The ES256 signature comes from the system `openssl`, so no
  third-party package is installed on a runner that holds release credentials.
- The private key is read only from the file named by `ASC_KEY_PATH`. Its contents,
  the signed token and request headers are never printed, logged or returned.
- Every write is followed by a read-back. Anything ambiguous fails closed.
- Internal testing only: the client refuses a group that is not internal or that has
  a public link, and it has no call for external groups or App Review.
"""

from __future__ import annotations

import argparse
import base64
import json
import os
import re
import subprocess
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass
from pathlib import Path
from typing import Any, Callable, Optional


API_ROOT = "https://api.appstoreconnect.apple.com"
TOKEN_LIFETIME_SECONDS = 15 * 60  # Apple allows at most 20 minutes.
BUILD_NUMBER_PATTERN = re.compile(r"^[1-9][0-9]{0,5}$")
VERSION_PATTERN = re.compile(r"^[0-9]+\.[0-9]+(\.[0-9]+)?$")
WHAT_TO_TEST_LIMIT = 4000
TERMINAL_BAD_STATES = {"FAILED", "INVALID"}


class ReleaseError(Exception):
    """A fail-closed stop. The message must never contain credential material."""


# --------------------------------------------------------------------------- JWT


def _b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode("ascii")


def _read_der_length(data: bytes, offset: int) -> tuple[int, int]:
    first = data[offset]
    offset += 1
    if first < 0x80:
        return first, offset
    count = first & 0x7F
    if count == 0 or count > 2:
        raise ReleaseError("unexpected DER length in ECDSA signature")
    value = int.from_bytes(data[offset : offset + count], "big")
    return value, offset + count


def der_to_raw_signature(der: bytes, size: int = 32) -> bytes:
    """Convert an ASN.1 DER ECDSA signature to the JOSE r||s form required by ES256."""
    if len(der) < 8 or der[0] != 0x30:
        raise ReleaseError("ECDSA signature is not a DER sequence")
    seq_len, offset = _read_der_length(der, 1)
    if offset + seq_len != len(der):
        raise ReleaseError("ECDSA signature has trailing or missing bytes")
    parts = []
    for _ in range(2):
        if der[offset] != 0x02:
            raise ReleaseError("ECDSA signature component is not an integer")
        length, offset = _read_der_length(der, offset + 1)
        value = der[offset : offset + length]
        offset += length
        value = value.lstrip(b"\x00")
        if len(value) > size:
            raise ReleaseError("ECDSA signature component is too long")
        parts.append(value.rjust(size, b"\x00"))
    if offset != len(der):
        raise ReleaseError("ECDSA signature has trailing bytes")
    return parts[0] + parts[1]


def sign_es256(signing_input: bytes, key_path: Path) -> bytes:
    """Sign with `openssl`; the key path is an argument, the key itself never leaves the file."""
    try:
        result = subprocess.run(
            ["openssl", "dgst", "-sha256", "-sign", str(key_path)],
            input=signing_input,
            capture_output=True,
            check=False,
        )
    except FileNotFoundError as error:
        raise ReleaseError("openssl is not available") from error
    if result.returncode != 0 or not result.stdout:
        # stderr from openssl names the file and the failure, never the key bytes,
        # but it is still withheld to keep the log surface minimal.
        raise ReleaseError("openssl could not sign the App Store Connect token")
    return der_to_raw_signature(result.stdout)


def make_token(key_id: str, issuer_id: str, key_path: Path, now: Optional[int] = None) -> str:
    issued = int(time.time()) if now is None else now
    header = {"alg": "ES256", "kid": key_id, "typ": "JWT"}
    payload = {
        "iss": issuer_id,
        "iat": issued,
        "exp": issued + TOKEN_LIFETIME_SECONDS,
        "aud": "appstoreconnect-v1",
    }
    signing_input = (
        _b64url(json.dumps(header, separators=(",", ":")).encode())
        + "."
        + _b64url(json.dumps(payload, separators=(",", ":")).encode())
    ).encode("ascii")
    signature = sign_es256(signing_input, key_path)
    return signing_input.decode("ascii") + "." + _b64url(signature)


# --------------------------------------------------------------------- transport

Transport = Callable[[str, str, Optional[dict], str], tuple[int, Any]]


def urllib_transport(method: str, url: str, body: Optional[dict], token: str) -> tuple[int, Any]:
    data = None if body is None else json.dumps(body).encode()
    request = urllib.request.Request(url, data=data, method=method)
    request.add_header("Authorization", "Bearer " + token)
    request.add_header("Accept", "application/json")
    if data is not None:
        request.add_header("Content-Type", "application/json")
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            raw = response.read()
            return response.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as error:
        raw = error.read()
        try:
            parsed = json.loads(raw) if raw else None
        except json.JSONDecodeError:
            parsed = None
        return error.code, parsed
    except urllib.error.URLError as error:
        raise ReleaseError(f"App Store Connect request failed: {error.reason}") from error


def describe_errors(payload: Any) -> str:
    if not isinstance(payload, dict):
        return "no error detail"
    errors = payload.get("errors") or []
    details = [
        f"{item.get('status', '?')} {item.get('code', '?')}: {item.get('detail') or item.get('title') or ''}".strip()
        for item in errors
        if isinstance(item, dict)
    ]
    return "; ".join(details) or "no error detail"


@dataclass
class Client:
    token_factory: Callable[[], str]
    transport: Transport = urllib_transport
    root: str = API_ROOT

    def request(self, method: str, path: str, body: Optional[dict] = None, expect=(200,)) -> Any:
        url = path if path.startswith("https://") else self.root + path
        if not url.startswith(self.root + "/"):
            raise ReleaseError("refusing a request outside the App Store Connect API")
        status, payload = self.transport(method, url, body, self.token_factory())
        if status not in expect:
            raise ReleaseError(f"{method} {urllib.parse.urlsplit(url).path} returned {status}: {describe_errors(payload)}")
        return payload

    def get_all(self, path: str) -> list[dict]:
        items: list[dict] = []
        url: Optional[str] = path
        pages = 0
        while url:
            pages += 1
            if pages > 50:
                raise ReleaseError("pagination did not finish within 50 pages")
            payload = self.request("GET", url)
            data = payload.get("data") if isinstance(payload, dict) else None
            if not isinstance(data, list):
                raise ReleaseError(f"expected a list from {urllib.parse.urlsplit(url).path}")
            items.extend(data)
            url = (payload.get("links") or {}).get("next")
        return items


# ------------------------------------------------------------------ operations


def validate_identity(build_number: str, version: str) -> None:
    if not BUILD_NUMBER_PATTERN.fullmatch(build_number):
        raise ReleaseError("build number must be a positive integer of at most six digits")
    if not VERSION_PATTERN.fullmatch(version):
        raise ReleaseError("marketing version must look like 1.2 or 1.2.3")


def builds_path(app_id: str, build_number: str, version: Optional[str]) -> str:
    query = {
        "filter[app]": app_id,
        "filter[version]": build_number,
        "limit": "200",
    }
    if version is not None:
        query["filter[preReleaseVersion.version]"] = version
    return "/v1/builds?" + urllib.parse.urlencode(query)


def check_group(client: Client, app_id: str, group_id: str) -> dict:
    payload = client.request("GET", f"/v1/betaGroups/{group_id}?include=app")
    data = payload.get("data") or {}
    attributes = data.get("attributes") or {}
    app_ref = (((data.get("relationships") or {}).get("app") or {}).get("data") or {}).get("id")
    if app_ref != app_id:
        raise ReleaseError("beta group does not belong to the configured app")
    if attributes.get("isInternalGroup") is not True:
        raise ReleaseError("beta group is not an internal group; external testing is out of scope")
    if attributes.get("publicLinkEnabled") is True:
        raise ReleaseError("beta group has a public TestFlight link; refusing to release")
    return {"group_name": attributes.get("name"), "internal": True, "public_link": False}


def preflight(client: Client, app_id: str, group_id: str, build_number: str, version: str) -> dict:
    validate_identity(build_number, version)
    group = check_group(client, app_id, group_id)
    # Any version train: a build number is consumed once for this app, whatever happens.
    existing = client.get_all(builds_path(app_id, build_number, None))
    if existing:
        raise ReleaseError(f"build number {build_number} already exists for this app; choose a fresh one")
    return {**group, "build_number_unused": True}


def wait_for_build(
    client: Client,
    app_id: str,
    build_number: str,
    version: str,
    timeout_seconds: int,
    interval_seconds: int = 30,
    sleep: Callable[[float], None] = time.sleep,
    clock: Callable[[], float] = time.monotonic,
) -> dict:
    deadline = clock() + timeout_seconds
    while True:
        builds = client.get_all(builds_path(app_id, build_number, version))
        if len(builds) > 1:
            raise ReleaseError("more than one build matches this version and build number")
        if builds:
            build = builds[0]
            state = (build.get("attributes") or {}).get("processingState")
            if state == "VALID":
                return build
            if state in TERMINAL_BAD_STATES:
                raise ReleaseError(f"Apple processing ended in state {state}")
        if clock() >= deadline:
            raise ReleaseError(
                "timed out waiting for Apple processing; the upload may still succeed, "
                "so check App Store Connect read-only before trying another build"
            )
        sleep(interval_seconds)


def set_what_to_test(client: Client, build_id: str, text: str) -> list[str]:
    if not text.strip():
        raise ReleaseError("What to Test is empty")
    if len(text) > WHAT_TO_TEST_LIMIT:
        raise ReleaseError(f"What to Test is longer than {WHAT_TO_TEST_LIMIT} characters")
    localizations = client.get_all(f"/v1/builds/{build_id}/betaBuildLocalizations")
    if not localizations:
        raise ReleaseError("the build has no beta localisation to update; set What to Test manually")
    locales = []
    for item in localizations:
        client.request(
            "PATCH",
            f"/v1/betaBuildLocalizations/{item['id']}",
            {"data": {"type": "betaBuildLocalizations", "id": item["id"], "attributes": {"whatsNew": text}}},
        )
        locales.append((item.get("attributes") or {}).get("locale") or "?")
    for item in client.get_all(f"/v1/builds/{build_id}/betaBuildLocalizations"):
        if (item.get("attributes") or {}).get("whatsNew") != text:
            raise ReleaseError("What to Test read-back does not match")
    return locales


def add_to_group(client: Client, group_id: str, build_id: str) -> None:
    client.request(
        "POST",
        f"/v1/betaGroups/{group_id}/relationships/builds",
        {"data": [{"type": "builds", "id": build_id}]},
        expect=(204,),
    )
    members = client.get_all(f"/v1/betaGroups/{group_id}/builds?limit=200")
    if build_id not in {item.get("id") for item in members}:
        raise ReleaseError("build is not listed in the internal group after assignment")


def distribute(
    client: Client,
    app_id: str,
    group_id: str,
    build_number: str,
    version: str,
    what_to_test: str,
    timeout_seconds: int,
    sleep: Callable[[float], None] = time.sleep,
    clock: Callable[[], float] = time.monotonic,
) -> dict:
    validate_identity(build_number, version)
    check_group(client, app_id, group_id)
    build = wait_for_build(client, app_id, build_number, version, timeout_seconds, sleep=sleep, clock=clock)
    build_id = build["id"]
    attributes = build.get("attributes") or {}
    if attributes.get("usesNonExemptEncryption") is True:
        raise ReleaseError("build declares non-exempt encryption; that needs a separate decision")
    locales = set_what_to_test(client, build_id, what_to_test)
    add_to_group(client, group_id, build_id)
    return {
        "build_id": build_id,
        "processing_state": attributes.get("processingState"),
        "what_to_test_locales": locales,
        "internal_group_assigned": True,
    }


# --------------------------------------------------------------------------- CLI


def client_from_environment() -> Client:
    key_id = os.environ.get("ASC_KEY_ID", "")
    issuer_id = os.environ.get("ASC_ISSUER_ID", "")
    key_path = Path(os.environ.get("ASC_KEY_PATH", ""))
    if not key_id or not issuer_id or not key_path.is_file():
        raise ReleaseError("ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_PATH (an existing file) are required")
    if key_path.stat().st_mode & 0o077:
        raise ReleaseError("the API key file must not be readable by group or others")
    return Client(token_factory=lambda: make_token(key_id, issuer_id, key_path))


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    sub = parser.add_subparsers(dest="command", required=True)
    for name in ("preflight", "distribute"):
        command = sub.add_parser(name)
        command.add_argument("--app-id", required=True)
        command.add_argument("--group-id", required=True)
        command.add_argument("--build-number", required=True)
        command.add_argument("--version", required=True)
        command.add_argument("--output", type=Path, required=True)
        if name == "distribute":
            command.add_argument("--what-to-test-file", type=Path, required=True)
            command.add_argument("--timeout-seconds", type=int, default=45 * 60)
    args = parser.parse_args(argv)
    try:
        client = client_from_environment()
        if args.command == "preflight":
            result = preflight(client, args.app_id, args.group_id, args.build_number, args.version)
        else:
            text = args.what_to_test_file.read_text(encoding="utf-8").strip()
            result = distribute(
                client,
                args.app_id,
                args.group_id,
                args.build_number,
                args.version,
                text,
                args.timeout_seconds,
            )
    except ReleaseError as error:
        print(f"::error::{error}", file=sys.stderr)
        return 1
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True) + "\n", encoding="utf-8")
    print(json.dumps(result, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
