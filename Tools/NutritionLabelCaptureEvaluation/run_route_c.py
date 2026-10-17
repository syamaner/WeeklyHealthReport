#!/usr/bin/env python3
"""Run route C on DEVELOPMENT photos through Inspect, under the logging rules (not yet enabled).

Route C stays disabled until the contract sets `route_c.enabled` true; this runner
refuses to start before then. When it runs:

- the Inspect log directory must be outside the repository (a `.eval` log holds model
  requests and responses), and `log_images=False`, so image bytes are never written into
  the log;
- `GenerateConfig.extra_headers` is left empty, and the solver refuses any configured or
  logged header that looks like a credential; the key stays in the provider client;
- the model is `openrouter/<slug>` with the pinned provider block (one endpoint, no
  fallbacks, ZDR, data collection denied) and the persistent spend ledger.
"""

from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path
from typing import Any

HERE = Path(__file__).resolve().parent
REPO = HERE.parents[1]
sys.path.insert(0, str(HERE))

import openrouter_route  # noqa: E402
from openrouter_route import RouteCModel  # noqa: E402

CONTRACT = HERE / "frozen-contract-v1.json"


def outside_repository(path: Path) -> bool:
    resolved = path.expanduser().resolve()
    return resolved != REPO and REPO not in resolved.parents


def eval_kwargs(target: RouteCModel, log_dir: Path) -> dict[str, Any]:
    """Keyword arguments for `inspect_ai.eval`; pure, so the logging rules are testable."""
    if not outside_repository(log_dir):
        raise SystemExit("--log-dir must be outside the repository")
    return {
        "model": f"openrouter/{target.model}",
        "model_args": openrouter_route.model_args(target),
        "log_dir": str(log_dir),
        "log_images": False,
        "display": "none",
        "max_samples": 1,
    }


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cases-file", type=Path, required=True, help="development photo cases (JSON list)")
    parser.add_argument("--ledger", type=Path, required=True)
    parser.add_argument("--log-dir", type=Path, required=True)
    parser.add_argument("--label", required=True)
    parser.add_argument("--model", required=True)
    parser.add_argument("--endpoint", required=True)
    parser.add_argument("--provider-name", required=True)
    args = parser.parse_args(argv)

    contract = json.loads(CONTRACT.read_text(encoding="utf-8"))
    if contract["route_c"].get("enabled") is not True:
        raise SystemExit("route C is disabled in the contract; no call is made")
    target = RouteCModel(label=args.label, model=args.model, endpoint=args.endpoint, provider_name=args.provider_name)
    kwargs = eval_kwargs(target, args.log_dir)

    from inspect_ai import eval as inspect_eval

    from inspect_task import label_capture_route_c_development

    task = label_capture_route_c_development(
        cases_file=str(args.cases_file),
        ledger=str(args.ledger),
        model=target.model,
        endpoint=target.endpoint,
        provider_name=target.provider_name,
        label=target.label,
        enabled=True,
    )
    log = inspect_eval(task, **kwargs)[0]
    print(f"route C {target.label}: {log.status}")
    return 0 if log.status == "success" else 1


if __name__ == "__main__":
    sys.exit(main())
