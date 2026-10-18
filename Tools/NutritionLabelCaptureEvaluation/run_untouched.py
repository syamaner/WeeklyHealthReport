#!/usr/bin/env python3
"""The single untouched Taiwan run (phase 5, #255): route B, or one route C arm, exactly once.

Refuses to start unless:

- the contract is `frozen_for_untouched_run` and every pinned artefact hash matches;
- the untouched set is unsealed with the explicit flag and the sealed manifest's SHA-256
  (`cases.load_untouched_photos`, which also checks the pinned untouched truth and every
  photo's bytes);
- the run register outside the repository has no entry for this route and arm (no rerun,
  ever; a started arm that failed stays recorded and is reported, never silently rerun);
- the log directory is outside the repository and empty, and `log_images` is False;
- for route C: the arm is one of the three frozen untouched arms with its development
  settings; the free catalogue lookup still shows the same slug, endpoint, provider, prices
  and parameters (any change stops the run, nothing is substituted); the free key and
  account lookups cover the arm's projection and margin; and both fictional qualification
  labels pass first (development budget, no untouched image).

Every route goes through the decline gate (`decline_gate_solver`). The summary holds
aggregate counts, call statistics and case ids only, never a model answer or an image.
"""

from __future__ import annotations

import argparse
import hashlib
import json
import os
import subprocess
import sys
from datetime import UTC, datetime
from decimal import Decimal
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))

import cases  # noqa: E402
import run_route_c  # noqa: E402
from openrouter_route import RouteCModel  # noqa: E402

CONTRACT = HERE / "frozen-contract-v1.json"
MANIFEST = HERE / "fixtures" / "off-taiwan-manifest-v1.json"
TRUTH = HERE / "fixtures" / "ground-truth-off-taiwan-untouched-v1.json"
MODELS_URL = "https://openrouter.ai/api/v1/models/{slug}/endpoints"
REQUIRED_PARAMETERS = ("response_format", "structured_outputs", "reasoning", "max_tokens")


def now() -> str:
    return datetime.now(UTC).isoformat(timespec="seconds")


def frozen_contract() -> dict[str, Any]:
    import validate_contract

    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    if contract.get("status") != "frozen_for_untouched_run":
        raise SystemExit("the contract is not frozen for the untouched run")
    errors = validate_contract.validate(contract)
    if errors:
        raise SystemExit("the frozen contract does not validate: " + "; ".join(errors))
    return contract


def untouched_arm(contract: dict[str, Any], arm: str) -> RouteCModel:
    """One of the frozen untouched arms, with exactly its development pin and reasoning setting."""
    arms = contract["untouched_run"]["route_c_arms"]
    if arm not in arms:
        raise SystemExit(f"{arm!r} is not a frozen untouched arm ({', '.join(arms)})")
    spec = arms[arm]
    target = run_route_c.pinned_target(contract, spec["label"], spec["reasoning"])
    if target.model != spec["slug"] or target.endpoint != spec["endpoint"]:
        raise SystemExit(f"{arm}: the frozen arm does not match its development pin")
    return target


def catalogue_check(endpoints: dict[str, Any], pin: dict[str, Any]) -> list[str]:
    """Pure: differences between today's catalogue entry and the pinned development endpoint."""
    problems: list[str] = []
    if not endpoints or "error" in endpoints:
        return [f"catalogue lookup failed: {endpoints.get('error') if endpoints else 'empty'}"]
    if endpoints.get("id") != pin["slug"]:
        problems.append(f"slug {endpoints.get('id')!r} is not {pin['slug']!r}")
    modalities = (endpoints.get("architecture") or {}).get("input_modalities") or []
    if "image" not in modalities:
        problems.append("image input is not listed")
    matches = [e for e in endpoints.get("endpoints") or [] if e.get("tag") == pin["endpoint"]]
    if len(matches) != 1:
        return [*problems, f"endpoint {pin['endpoint']!r} appears {len(matches)} times"]
    endpoint = matches[0]
    catalogue = pin["catalogue_2026_10_17"]
    if endpoint.get("provider_name") != pin["provider_name"]:
        problems.append(f"provider {endpoint.get('provider_name')!r} is not {pin['provider_name']!r}")
    pricing = endpoint.get("pricing") or {}
    for field, pinned in (("prompt", "prompt_usd_per_million"), ("completion", "completion_usd_per_million")):
        try:
            per_million = Decimal(str(pricing.get(field))) * Decimal(1_000_000)
        except ArithmeticError:
            problems.append(f"{field} price is not a number")
            continue
        if per_million != Decimal(catalogue[pinned]):
            problems.append(f"{field} price {per_million} per million is not {catalogue[pinned]}")
    supported = set(endpoint.get("supported_parameters") or [])
    missing = [name for name in REQUIRED_PARAMETERS if name not in supported]
    if missing:
        problems.append("parameters no longer supported: " + ", ".join(missing))
    if endpoint.get("status") != catalogue.get("status"):
        problems.append(f"endpoint status {endpoint.get('status')!r} is not {catalogue.get('status')!r}")
    return problems


def register_start(register: Path, route: str, arm: str, log_dir: Path) -> None:
    """Record the start before the first untouched call; refuse if this route and arm ever started."""
    data = (
        json.loads(register.read_text(encoding="utf-8"))
        if register.exists()
        else {"schema_version": "untouched-run-register-v1", "runs": []}
    )
    for entry in data["runs"]:
        if entry["route"] == route and entry["arm"] == arm:
            raise SystemExit(
                f"route {route} arm {arm} already started at {entry['started_at']} ({entry['status']}); the untouched set is never rerun"
            )
    data["runs"].append({"route": route, "arm": arm, "started_at": now(), "status": "started", "log_dir": str(log_dir)})
    register.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def register_finish(register: Path, route: str, arm: str, status: str) -> None:
    data = json.loads(register.read_text(encoding="utf-8"))
    for entry in data["runs"]:
        if entry["route"] == route and entry["arm"] == arm:
            entry["status"] = status
            entry["finished_at"] = now()
    register.write_text(json.dumps(data, indent=2) + "\n", encoding="utf-8")


def git_head() -> str:
    return subprocess.run(["git", "-C", str(REPO), "rev-parse", "HEAD"], capture_output=True, text=True, check=True).stdout.strip()


def summarise_log(log: Any, loaded: list[dict[str, Any]], route: str, target: RouteCModel | None) -> dict[str, Any]:
    import run_route_b
    import score as scoring

    if route == "C":
        assert target is not None
        rows = run_route_c.per_case_rows(log, loaded)
        summary = run_route_c.summarise(target, loaded, rows, log)
    else:
        by_id = {sample.id: sample for sample in log.samples or []}
        per_case, rows = [], []
        for case in loaded:
            sample = by_id.get(case["id"])
            scored = (sample.scores or {}).get("label_capture_scorer") if sample is not None else None
            metadata = (scored.metadata if scored is not None else None) or {}
            candidate = json.loads(sample.output.completion) if sample and sample.output and sample.output.completion else {}
            per_case.append({**metadata, "candidate_decline_reasons": candidate.get("decline_reasons", [])})
            rows.append(
                {
                    "id": case["id"],
                    "error": str(sample.error.message)[:300] if sample is not None and sample.error else None,
                    "declined": bool(candidate.get("declined")),
                    "decline_reasons": candidate.get("decline_reasons", []),
                    "table_exact": metadata.get("tables_exact"),
                    "false_ready": metadata.get("false_ready"),
                }
            )
        summary = {"route": "B", **run_route_b.summarise(loaded, per_case, scoring.load_thresholds()), "per_case": rows}
        summary["inspect_status"] = log.status
        summary["inspect_log"] = Path(log.location).name
    summary["split"] = "untouched"
    return summary


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--route", choices=("B", "C"), required=True)
    parser.add_argument("--arm", help="route C: gemini-on, sol-on or luna-off")
    parser.add_argument("--unseal", action="store_true")
    parser.add_argument("--manifest-sha256", required=True)
    parser.add_argument("--image-root", type=Path, default=Path.home() / "WHR-label-eval-private" / "off-taiwan-v1")
    parser.add_argument("--register", type=Path, default=Path.home() / "WHR-label-eval-private" / "untouched-run-register-v1.json")
    parser.add_argument("--ledger", type=Path, default=Path.home() / "WHR-label-eval-private" / "spend-ledger-v1.json")
    parser.add_argument("--log-dir", type=Path, required=True)
    parser.add_argument("--summary", type=Path, required=True)
    parser.add_argument("--qualification-dir", type=Path, default=Path.home() / "WHR-label-eval-private" / "runs" / "route-c-qualification")
    parser.add_argument("--env-file", type=Path)
    parser.add_argument("--projected-cost-usd", type=float, default=0.0)
    parser.add_argument("--vision-binary", type=Path)
    parser.add_argument("--parser-binary", type=Path)
    parser.add_argument("--checks-only", action="store_true", help="route C: run the free credit and catalogue checks, then stop")
    args = parser.parse_args(argv)

    contract = frozen_contract()
    for path in (args.log_dir, args.summary, args.register, args.ledger):
        if not run_route_c.outside_repository(path):
            raise SystemExit(f"refusing a path inside the repository: {path}")
    if args.log_dir.exists() and any(args.log_dir.iterdir()):
        raise SystemExit("--log-dir must be empty")
    if not args.unseal:
        raise SystemExit("the untouched set is sealed; pass --unseal")

    target: RouteCModel | None = None
    result: dict[str, Any] = {"route": args.route, "contract_status": contract["status"], "git_head": git_head()}
    arm = args.arm or "route-b"
    if args.route == "C":
        if not args.arm:
            raise SystemExit("route C needs --arm")
        target = untouched_arm(contract, args.arm)
        key = os.environ.get("OPENROUTER_API_KEY")
        if not key:
            from draft_untouched_truth import key_from_env_file

            key = key_from_env_file(args.env_file) if args.env_file else None
        if not key:
            raise SystemExit("OPENROUTER_API_KEY is not set")
        spec = contract["untouched_run"]["route_c_arms"][args.arm]
        pin = contract["route_c"]["models"][spec["label"]]
        listing = run_route_c._get(MODELS_URL.format(slug=pin["slug"]), key)
        problems = catalogue_check(listing, pin)
        credit = run_route_c.key_credit(key)
        reservation = Decimal(contract["route_c"]["sealed_reservation_per_call_usd"]) * Decimal(
            contract["route_c"]["sealed_run_reserved_calls"]
        )
        allowed, needed = run_route_c.credit_gate(credit, Decimal(str(args.projected_cost_usd)))
        available = credit.get("available")
        covers_reservation = isinstance(available, int | float) and Decimal(str(available)) >= reservation
        result["pre_run_checks"] = {
            "catalogue_problems": problems,
            "key_credit": credit,
            "arm_credit_gate": {"allowed": allowed, "needed_usd": str(needed)},
            "sealed_reservation_usd": str(reservation),
            "credit_covers_sealed_reservation": covers_reservation,
        }
        print(json.dumps(result["pre_run_checks"], ensure_ascii=False))
        if problems:
            raise SystemExit("the catalogue changed since development; stopping without substitution: " + "; ".join(problems))
        if not allowed or not covers_reservation:
            raise SystemExit("refusing to start: the credit does not cover the arm or the sealed reservation")
        if args.checks_only:
            args.summary.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            return 0

        import openrouter_client
        from inspect_task import configure_route_c_transport

        configure_route_c_transport(
            openrouter_client.http_post(key, "WeeklyHealthReport label evaluation untouched"),
            lambda generation: openrouter_client.generation_cost(key, generation),
        )
        qualifying = run_route_c.qualification_cases(args.qualification_dir)
        qual_dir = args.log_dir / "qualification"
        log = run_route_c.run(target, qualifying, args.ledger, qual_dir, "qualification")
        rows = run_route_c.per_case_rows(log, qualifying)
        passed = all(r["attempted"] and not r["failed"] and not r["error"] and not r["declined"] for r in rows)
        result["qualification"] = {
            "passed": passed,
            "cases": [{k: r[k] for k in ("id", "failed", "error", "declined", "cost_usd")} for r in rows],
        }
        if not passed:
            args.summary.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
            raise SystemExit("qualification failed; no untouched image was sent")
    else:
        if not args.vision_binary or not args.parser_binary:
            raise SystemExit("route B needs --vision-binary and --parser-binary")
        pinned = contract["untouched_run"]["route_b"]
        for name, path in (("vision_binary_sha256", args.vision_binary), ("parser_binary_sha256", args.parser_binary)):
            if hashlib.sha256(path.read_bytes()).hexdigest() != pinned[name]:
                raise SystemExit(f"{path} does not match the frozen {name}")

    from inspect_ai import eval as inspect_eval

    from inspect_task import label_capture_untouched_photos

    run_dir = args.log_dir / "untouched"
    run_dir.mkdir(parents=True, exist_ok=False)
    manifest_record = {
        "written_at": now(),
        "route": args.route,
        "arm": arm,
        "git_head": result["git_head"],
        "contract_sha256": hashlib.sha256(CONTRACT.read_bytes()).hexdigest(),
        "frozen_artefacts": contract["frozen_artefacts"],
        "target": None if target is None else {"slug": target.model, "endpoint": target.endpoint, "reasoning": target.reasoning},
    }
    (run_dir / "run-manifest.json").write_text(json.dumps(manifest_record, indent=2) + "\n", encoding="utf-8")
    register_start(args.register, args.route, arm, run_dir)
    task = label_capture_untouched_photos(
        route=args.route,
        manifest=str(MANIFEST),
        image_root=str(args.image_root),
        truth=str(TRUTH),
        unseal=True,
        manifest_sha256=args.manifest_sha256,
        ledger=str(args.ledger),
        label=None if target is None else target.label,
        model=None if target is None else target.model,
        endpoint=None if target is None else target.endpoint,
        provider_name=None if target is None else target.provider_name,
        reasoning="off" if target is None else target.reasoning,
        enabled=args.route == "C",
        vision_binary=str(args.vision_binary) if args.vision_binary else None,
        parser_binary=str(args.parser_binary) if args.parser_binary else None,
    )
    try:
        log = inspect_eval(task, **run_route_c.eval_kwargs(run_dir))[0]
    except BaseException as error:
        register_finish(args.register, args.route, arm, f"failed: {type(error).__name__}")
        raise
    loaded = cases.load_untouched_photos(MANIFEST, args.image_root, unseal=True, manifest_sha256=args.manifest_sha256, truth_path=TRUTH)
    result.update(summarise_log(log, loaded, args.route, target))
    register_finish(args.register, args.route, arm, "complete" if log.status == "success" else f"inspect status {log.status}")
    args.summary.write_text(json.dumps(result, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
    print(json.dumps({k: result.get(k) for k in ("inspect_status", "calls_overall")}, ensure_ascii=False))
    return 0 if log.status == "success" else 4


if __name__ == "__main__":
    sys.exit(main())
