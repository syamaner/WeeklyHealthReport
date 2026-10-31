#!/usr/bin/env python3
"""Inspect an exported IPA before the single TestFlight upload (macOS only).

Fails closed unless the bundle, version, team, entitlements, signature, profile and
Drive OAuth configuration match what the release expects. The summary it writes holds
only non-sensitive facts; it never echoes the OAuth values. See
docs/testflight-ci-release-v1.md.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import plistlib
import subprocess
import sys
import tempfile
import zipfile
from pathlib import Path
from typing import Any, Optional


REQUIRED_PURPOSE_STRINGS = (
    "NSHealthShareUsageDescription",
    "NSHealthUpdateUsageDescription",
    "NSCameraUsageDescription",
    "NSMicrophoneUsageDescription",
    "NSSpeechRecognitionUsageDescription",
)


def check_app(
    info: dict,
    entitlements: Any,
    profile: dict,
    expected: dict[str, str],
    now: dt.datetime,
) -> list[str]:
    """Pure checks over decoded plists. Returns failure messages; empty means pass."""
    failures: list[str] = []
    bundle_id = expected["bundle_id"]
    team_id = expected["team_id"]

    if info.get("CFBundleIdentifier") != bundle_id:
        failures.append("bundle identifier does not match")
    if info.get("CFBundleShortVersionString") != expected["version"]:
        failures.append("marketing version does not match the project")
    if info.get("CFBundleVersion") != expected["build_number"]:
        failures.append("build number does not match the dispatch input")
    if info.get("ITSAppUsesNonExemptEncryption") is not False:
        failures.append("ITSAppUsesNonExemptEncryption must be an explicit false")
    for key in REQUIRED_PURPOSE_STRINGS:
        if not str(info.get(key) or "").strip():
            failures.append(f"missing purpose string {key}")

    client_id = info.get("GoogleOAuthClientID")
    scheme = info.get("GoogleOAuthRedirectScheme")
    if client_id in (None, "", "MISSING") or scheme in (None, "", "MISSING"):
        failures.append("Drive OAuth configuration is missing")
    else:
        if client_id != expected["oauth_client_id"] or scheme != expected["oauth_redirect_scheme"]:
            failures.append("Drive OAuth configuration does not match the protected values")
        url_schemes = [
            value
            for entry in info.get("CFBundleURLTypes") or []
            for value in (entry.get("CFBundleURLSchemes") or [])
        ]
        if scheme not in url_schemes:
            failures.append("Drive OAuth redirect scheme is not a registered URL scheme")
        suffix = ".apps.googleusercontent.com"
        if isinstance(client_id, str) and client_id.endswith(suffix):
            reverse = "com.googleusercontent.apps." + client_id[: -len(suffix)]
            if scheme != reverse:
                failures.append("Drive OAuth redirect scheme is not the reverse client id")
        else:
            failures.append("Drive OAuth client id has an unexpected form")

    if not isinstance(entitlements, dict):
        failures.append("entitlements are not a dictionary")
        entitlements = {}
    if entitlements.get("get-task-allow") is not False:
        failures.append("get-task-allow must be false")
    if entitlements.get("application-identifier") != f"{team_id}.{bundle_id}":
        failures.append("application identifier does not match team and bundle")
    if entitlements.get("com.developer.team-identifier") != team_id:
        failures.append("team identifier entitlement does not match")
    if entitlements.get("com.apple.developer.healthkit") is not True:
        failures.append("HealthKit entitlement is missing")

    if team_id not in (profile.get("TeamIdentifier") or []):
        failures.append("provisioning profile belongs to another team")
    if profile.get("ProvisionedDevices") or profile.get("ProvisionsAllDevices"):
        failures.append("provisioning profile is not an App Store distribution profile")
    profile_entitlements = profile.get("Entitlements") or {}
    if profile_entitlements.get("get-task-allow") is not False:
        failures.append("provisioning profile allows debugging")
    if profile_entitlements.get("application-identifier") != f"{team_id}.{bundle_id}":
        failures.append("provisioning profile is for another app")
    expiry = profile.get("ExpirationDate")
    if not isinstance(expiry, dt.datetime):
        failures.append("provisioning profile has no expiry date")
    else:
        if expiry.tzinfo is None:
            expiry = expiry.replace(tzinfo=dt.timezone.utc)
        if expiry <= now:
            failures.append("provisioning profile has expired")
    return failures


def run(command: list[str]) -> bytes:
    result = subprocess.run(command, capture_output=True, check=False)
    if result.returncode != 0:
        raise RuntimeError(f"{command[0]} {command[1]} failed: {result.stderr.decode(errors='replace').strip()[:500]}")
    return result.stdout


def sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as handle:
        for chunk in iter(lambda: handle.read(1 << 20), b""):
            digest.update(chunk)
    return digest.hexdigest()


def inspect(ipa: Path, expected: dict[str, str]) -> dict:
    with tempfile.TemporaryDirectory() as work:
        with zipfile.ZipFile(ipa) as archive:
            for name in archive.namelist():
                if name.startswith("/") or ".." in Path(name).parts:
                    raise RuntimeError("IPA contains an unsafe path")
            archive.extractall(work)
        apps = sorted(Path(work, "Payload").glob("*.app"))
        if len(apps) != 1:
            raise RuntimeError("IPA must contain exactly one app bundle")
        app = apps[0]
        info = plistlib.loads((app / "Info.plist").read_bytes())
        run(["codesign", "--verify", "--deep", "--strict", "--verbose=2", str(app)])
        entitlements = plistlib.loads(run(["codesign", "-d", "--entitlements", "-", "--xml", str(app)]))
        profile = plistlib.loads(run(["security", "cms", "-D", "-i", str(app / "embedded.mobileprovision")]))
        failures = check_app(info, entitlements, profile, expected, dt.datetime.now(dt.timezone.utc))
        return {
            "failures": failures,
            "bundle_id": info.get("CFBundleIdentifier"),
            "version": info.get("CFBundleShortVersionString"),
            "build_number": info.get("CFBundleVersion"),
            "profile_name": profile.get("Name"),
            "profile_uuid": profile.get("UUID"),
            "profile_expiry": str(profile.get("ExpirationDate")),
        }


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--ipa", type=Path, required=True)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args(argv)
    env = os.environ
    expected = {
        "bundle_id": env.get("EXPECTED_BUNDLE_ID", ""),
        "team_id": env.get("EXPECTED_TEAM_ID", ""),
        "version": env.get("EXPECTED_VERSION", ""),
        "build_number": env.get("EXPECTED_BUILD_NUMBER", ""),
        "oauth_client_id": env.get("DRIVE_OAUTH_CLIENT_ID", ""),
        "oauth_redirect_scheme": env.get("DRIVE_OAUTH_REDIRECT_SCHEME", ""),
    }
    if not all(expected.values()):
        print("::error::expected release values are incomplete", file=sys.stderr)
        return 1
    try:
        result = inspect(args.ipa, expected)
    except (RuntimeError, OSError, zipfile.BadZipFile, plistlib.InvalidFileException) as error:
        print(f"::error::IPA inspection failed: {error}", file=sys.stderr)
        return 1
    result["ipa_sha256"] = sha256(args.ipa)
    args.output.write_text(json.dumps(result, indent=2, sort_keys=True, default=str) + "\n", encoding="utf-8")
    for failure in result["failures"]:
        print(f"::error::{failure}", file=sys.stderr)
    return 1 if result["failures"] else 0


if __name__ == "__main__":
    sys.exit(main())
