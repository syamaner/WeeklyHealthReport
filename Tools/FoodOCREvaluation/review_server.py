#!/usr/bin/env python3
"""Localhost-only annotation server for blinded nutrition-panel review packs."""

from __future__ import annotations

import argparse
import json
import mimetypes
import os
import tempfile
from datetime import datetime, timezone
from http import HTTPStatus
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path
from typing import Any
from urllib.parse import urlparse

FAMILIES = {
    "bilingual", "bound", "crumpled", "curved", "difficult_crop", "flat",
    "glossy", "missing_row", "multi_column", "nested_rows", "per_100g",
    "per_100ml", "per_serving", "salt", "small_font", "sodium",
}
BASES = {"per_100g", "per_100ml", "per_serving", "reference_intake"}
COMPARATORS = {None, "<", "<="}
CELL_KEYS = {
    "row_id", "parent_row_id", "header_id", "basis", "printed_text",
    "comparator", "decimal_text", "unit", "serving_conversion",
}


def canonical_json(value: Any) -> bytes:
    return (json.dumps(value, ensure_ascii=False, sort_keys=True, separators=(",", ":")) + "\n").encode()


def validate_annotation(value: dict[str, Any], panel: dict[str, Any]) -> dict[str, Any]:
    if value.get("panel_id") != panel["panel_id"] or value.get("image_sha256") != panel["image_sha256"]:
        raise ValueError("panel identity or image hash mismatch")
    if not str(value.get("reviewer", "")).strip():
        raise ValueError("reviewer is required")
    if not str(value.get("full_transcript", "")).strip():
        raise ValueError("exact visible transcript is required")
    if not value.get("verification_assertion"):
        raise ValueError("visual verification assertion is required")
    if float(value.get("correction_seconds", 0)) <= 0:
        raise ValueError("correction time must be positive")
    families = value.get("families", [])
    if not isinstance(families, list) or not set(families).issubset(FAMILIES):
        raise ValueError("unknown layout family")
    cells = value.get("cells", [])
    if not isinstance(cells, list):
        raise ValueError("cells must be an array")
    if not cells and not value.get("requires_decline"):
        raise ValueError("record cells or mark the panel as requiring decline")
    seen: set[tuple[str, str]] = set()
    for cell in cells:
        if set(cell) != CELL_KEYS:
            raise ValueError("each cell must contain exactly the frozen fields")
        if not all(str(cell[key]).strip() for key in ("row_id", "header_id", "printed_text", "decimal_text", "unit")):
            raise ValueError("cell identifiers, printed text, number and unit are required")
        if cell["basis"] not in BASES or cell["comparator"] not in COMPARATORS:
            raise ValueError("invalid basis or comparator")
        key = cell["row_id"], cell["header_id"]
        if key in seen:
            raise ValueError(f"duplicate row/header cell: {key[0]}/{key[1]}")
        seen.add(key)
    normalized = {
        "schema_version": 1,
        "panel_id": panel["panel_id"],
        "image_sha256": panel["image_sha256"],
        "reviewer": str(value["reviewer"]).strip(),
        "started_at": value.get("started_at"),
        "verified_at": datetime.now(timezone.utc).isoformat(),
        "correction_seconds": round(float(value["correction_seconds"]), 3),
        "full_transcript": str(value["full_transcript"]).strip(),
        "cells": cells,
        "families": sorted(set(families)),
        "requires_decline": bool(value.get("requires_decline")),
        "decline_reason": str(value.get("decline_reason", "")).strip() or None,
        "verification_assertion": True,
        "verification_status": "independently_verified",
    }
    if normalized["requires_decline"] and not normalized["decline_reason"]:
        raise ValueError("decline reason is required")
    return normalized


def validate_assistant_draft(value: dict[str, Any], panel: dict[str, Any]) -> dict[str, Any]:
    """Keep machine-assisted preparation outside the human ground-truth path."""
    if value.get("panel_id") != panel["panel_id"] or value.get("image_sha256") != panel["image_sha256"]:
        raise ValueError("panel identity or image hash mismatch")
    transcript = str(value.get("full_transcript", "")).strip()
    if not transcript:
        raise ValueError("transcript is required")
    cells = value.get("cells", [])
    if not isinstance(cells, list):
        raise ValueError("cells must be an array")
    families = value.get("families", [])
    if not isinstance(families, list) or not set(families).issubset(FAMILIES):
        raise ValueError("unknown layout family")
    seen: set[tuple[str, str]] = set()
    for cell in cells:
        if set(cell) != CELL_KEYS:
            raise ValueError("each cell must contain exactly the frozen fields")
        if not all(str(cell[key]).strip() for key in ("row_id", "header_id", "printed_text", "decimal_text", "unit")):
            raise ValueError("incomplete cell")
        if cell["basis"] not in BASES or cell["comparator"] not in COMPARATORS:
            raise ValueError("invalid basis or comparator")
        key = cell["row_id"], cell["header_id"]
        if key in seen:
            raise ValueError(f"duplicate row/header cell: {key[0]}/{key[1]}")
        seen.add(key)
    requires_decline = bool(value.get("requires_decline"))
    decline_reason = str(value.get("decline_reason", "")).strip() or None
    if requires_decline and not decline_reason:
        raise ValueError("decline reason is required")
    if not cells and not requires_decline:
        raise ValueError("record cells or mark the panel as requiring decline")
    return {
        "schema_version": 1,
        "panel_id": panel["panel_id"],
        "image_sha256": panel["image_sha256"],
        "review_status": "assistant_candidate_pending_human",
        "prepared_at": datetime.now(timezone.utc).isoformat(),
        "full_transcript": transcript,
        "cells": cells,
        "families": sorted(set(families)),
        "requires_decline": requires_decline,
        "decline_reason": decline_reason,
        "review_notes": str(value.get("review_notes", "")).strip() or None,
    }


def atomic_write(path: Path, value: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    descriptor, temporary = tempfile.mkstemp(prefix="annotation-", suffix=".json", dir=path.parent)
    try:
        with os.fdopen(descriptor, "wb") as destination:
            destination.write(canonical_json(value))
        os.replace(temporary, path)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def review_queue(manifest: dict[str, Any], excluded: dict[str, Any]) -> list[dict[str, Any]]:
    """Exclude local review items without altering the sealed corpus manifest."""
    panel_ids = {panel["panel_id"] for panel in manifest["panels"]}
    exclusions = excluded.get("panels", [])
    if not isinstance(exclusions, list):
        raise ValueError("review exclusions must be an array")
    seen: set[str] = set()
    for exclusion in exclusions:
        if not isinstance(exclusion, dict):
            raise ValueError("invalid review exclusion")
        panel_id = exclusion.get("panel_id")
        if panel_id not in panel_ids or panel_id in seen or not str(exclusion.get("reason", "")).strip():
            raise ValueError("unknown, duplicate or unexplained review exclusion")
        seen.add(panel_id)
    return [panel for panel in manifest["panels"] if panel["panel_id"] not in seen]


class ReviewHandler(BaseHTTPRequestHandler):
    server_version = "Issue88Review/1"

    @property
    def review_server(self) -> "ReviewServer":
        return self.server  # type: ignore[return-value]

    def send_json(self, value: Any, status: HTTPStatus = HTTPStatus.OK) -> None:
        body = canonical_json(value)
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        path = urlparse(self.path).path
        if path == "/api/state":
            self.send_json(self.review_server.state())
            return
        if path.startswith("/api/image/"):
            panel_id = path.removeprefix("/api/image/")
            panel = self.review_server.panels_by_id.get(panel_id)
            if not panel:
                self.send_error(HTTPStatus.NOT_FOUND)
                return
            self.send_file(self.review_server.workspace / "images" / panel["image_file"], "image/jpeg")
            return
        relative = "index.html" if path == "/" else path.lstrip("/")
        target = (self.review_server.app_dir / relative).resolve()
        if self.review_server.app_dir.resolve() not in target.parents and target != self.review_server.app_dir.resolve():
            self.send_error(HTTPStatus.FORBIDDEN)
            return
        if not target.is_file():
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        self.send_file(target, mimetypes.guess_type(target.name)[0] or "application/octet-stream")

    def do_POST(self) -> None:  # noqa: N802
        request_path = urlparse(self.path).path
        if request_path not in {"/api/annotation", "/api/assistant-draft"}:
            self.send_error(HTTPStatus.NOT_FOUND)
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
            if length <= 0 or length > 2_000_000:
                raise ValueError("invalid request size")
            incoming = json.loads(self.rfile.read(length))
            panel = self.review_server.panels_by_id.get(incoming.get("panel_id"))
            if not panel:
                raise ValueError("unknown panel")
            if panel not in self.review_server.review_panels:
                raise ValueError("panel excluded from local review queue")
            if request_path == "/api/annotation":
                annotation = validate_annotation(incoming, panel)
                atomic_write(self.review_server.annotation_path(panel), annotation)
            else:
                candidate = validate_assistant_draft(incoming, panel)
                atomic_write(self.review_server.assistant_draft_path(panel), candidate)
            self.send_json({"saved": True, "progress": self.review_server.progress()})
        except (ValueError, TypeError, json.JSONDecodeError) as error:
            self.send_json({"saved": False, "error": str(error)}, HTTPStatus.BAD_REQUEST)

    def send_file(self, path: Path, content_type: str) -> None:
        body = path.read_bytes()
        self.send_response(HTTPStatus.OK)
        self.send_header("Content-Type", content_type)
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self.end_headers()
        self.wfile.write(body)

    def log_message(self, format: str, *args: Any) -> None:
        print(f"review-server: {format % args}")


class ReviewServer(ThreadingHTTPServer):
    def __init__(self, address: tuple[str, int], app_dir: Path, workspace: Path):
        super().__init__(address, ReviewHandler)
        self.app_dir = app_dir
        self.workspace = workspace
        self.manifest = json.loads((workspace / "review-manifest.json").read_text())
        self.panels_by_id = {panel["panel_id"]: panel for panel in self.manifest["panels"]}
        exclusions_path = workspace / "review-exclusions.json"
        exclusions = json.loads(exclusions_path.read_text()) if exclusions_path.exists() else {"panels": []}
        self.review_panels = review_queue(self.manifest, exclusions)

    def annotation_path(self, panel: dict[str, Any]) -> Path:
        return self.workspace / "annotations" / f"{panel['review_index']:03d}.json"

    def assistant_draft_path(self, panel: dict[str, Any]) -> Path:
        return self.workspace / "assistant_drafts" / f"{panel['review_index']:03d}.json"

    def annotation(self, panel: dict[str, Any]) -> dict[str, Any] | None:
        path = self.annotation_path(panel)
        return json.loads(path.read_text()) if path.exists() else None

    def assistant_draft(self, panel: dict[str, Any]) -> dict[str, Any] | None:
        """Load a candidate without treating it as independently verified truth."""
        path = self.assistant_draft_path(panel)
        if not path.exists():
            return None
        value = json.loads(path.read_text())
        if (value.get("panel_id") != panel["panel_id"]
                or value.get("image_sha256") != panel["image_sha256"]
                or value.get("review_status") != "assistant_candidate_pending_human"):
            raise ValueError(f"invalid assistant candidate for panel {panel['review_index']}")
        return value

    def progress(self) -> dict[str, int]:
        reviewed = sum(self.annotation(panel) is not None for panel in self.review_panels)
        return {"reviewed": reviewed, "total": len(self.review_panels), "remaining": len(self.review_panels) - reviewed}

    def state(self) -> dict[str, Any]:
        panels = []
        for panel in self.review_panels:
            item = dict(panel)
            item.pop("public_ocr_evidence", None)
            item["draft_source"] = "machine-assisted OCR"
            item["annotation"] = self.annotation(panel)
            item["assistant_draft"] = self.assistant_draft(panel)
            item["image_path"] = f"/api/image/{panel['panel_id']}"
            panels.append(item)
        return {"schema_version": 1, "blinded": True,
                "review_label": self.manifest.get("review_label", "WeeklyHealthReport · issue #88"),
                "review_description": self.manifest.get("review_description", "Correct the draft against the image. The evaluation split is hidden and the untouched Apple Vision gate remains unopened."),
                "progress": self.progress(), "frozen_total": len(self.manifest["panels"]), "excluded_count": len(self.manifest["panels"]) - len(self.review_panels), "families": sorted(FAMILIES), "panels": panels}


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", required=True, type=Path)
    parser.add_argument("--app-dir", type=Path, default=Path(__file__).with_name("review_app"))
    parser.add_argument("--port", type=int, default=8788)
    args = parser.parse_args()
    server = ReviewServer(("127.0.0.1", args.port), args.app_dir, args.workspace)
    print(f"Local nutrition-panel review: http://127.0.0.1:{args.port}", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
