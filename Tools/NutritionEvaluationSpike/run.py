"""Single-command offline development spike. See README for evidence boundaries."""
import argparse
import hashlib
import html
import importlib.util
import json
import os
import socket
import shutil
import subprocess
import sys
from pathlib import Path

from extraction import replay
from scoring import parser_rows, safeguard_rows, summary

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]


def write(path, value):
    path.write_text(json.dumps(value, indent=2, allow_nan=False) + "\n")


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def command(args, out, env, allowed_codes=(0,)):
    result = subprocess.run([str(a) for a in args], cwd=out, env=env,
                            capture_output=True, text=True, timeout=240)
    with (out / "execution.log").open("a") as log:
        log.write("COMMAND " + json.dumps([str(a) for a in args]) + "\n")
        log.write(result.stdout + result.stderr)
    if result.returncode not in allowed_codes:
        raise RuntimeError(f"Command failed ({result.returncode}); see execution.log")


def verify_offline():
    # A successful connection would be an immediate failure. EPERM demonstrates
    # the OS policy rather than an unreachable host or absent server.
    with socket.socket() as connection:
        try:
            connection.connect(("127.0.0.1", 9))
        except PermissionError:
            return
        except OSError as error:
            raise RuntimeError("Run via run.sh: OS network denial was not established") from error
    raise RuntimeError("Network unexpectedly available")


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--promptfoo", type=Path, required=True)
    parser.add_argument("--documents", type=Path, default=Path("/private/tmp/gemini-nutrition-v2-documents-host"))
    args = parser.parse_args()
    verify_offline()
    out = args.output.resolve()
    out.mkdir(parents=True, exist_ok=False)
    env = {key: os.environ[key] for key in ("PATH", "HOME", "TMPDIR", "LANG", "DEVELOPER_DIR") if key in os.environ}
    env.update(PROMPTFOO_DISABLE_TELEMETRY="1", PROMPTFOO_DISABLE_UPDATE="1",
               PROMPTFOO_CONFIG_DIR=str(out / "promptfoo-state"), PROMPTFOO_PYTHON=sys.executable,
               PYTHONDONTWRITEBYTECODE="1")
    try:
        package = next(parent / "package.json" for parent in args.promptfoo.resolve().parents
                       if (parent / "package.json").is_file()
                       and json.loads((parent / "package.json").read_text()).get("name") == "promptfoo")
        version = json.loads(package.read_text())["version"]
        if version != "0.123.1":
            raise ValueError("Expected Promptfoo 0.123.1")
        lock = package.parents[2] / "package-lock.json"
        shutil.copyfile(lock, out / "dependency-lock.json")
        build = out / "build"
        build.mkdir()
        common = ["swiftc", "-module-cache-path", str(build / "module-cache")]
        query = ROOT / "Tools/FoodQueryEvaluation"
        command(common + [ROOT / "Packages/FoodLedgerKit/Sources/FoodLedgerApplication/FoodQueryParser.swift",
                           query / "run.swift", "-o", build / "query-runner"], out, env)
        command([build / "query-runner", query / "synthetic-v5.json", out / "query-predictions.json"], out, env)
        spec = importlib.util.spec_from_file_location("query_score", query / "score.py")
        scorer = importlib.util.module_from_spec(spec)
        sys.modules["query_score"] = scorer
        spec.loader.exec_module(scorer)
        fixture = json.loads((query / "synthetic-v5.json").read_text())
        frozen = json.loads((query / "manifest-v5.json").read_text())
        if sha(query / "synthetic-v5.json") != frozen["sha256"]:
            raise ValueError("Query fixture hash changed")
        predictions = json.loads((out / "query-predictions.json").read_text())
        query_report = scorer.evaluate(fixture, predictions)
        write(out / "query-report.json", query_report)
        rows = parser_rows(fixture, predictions)
        print("Query parser: " + str(len(rows)) + " development cases", flush=True)

        extraction_root = ROOT / "Tools/GeminiNutritionExtractionEvaluation"
        report, extraction_rows, drift = replay(extraction_root, args.documents.resolve())
        write(out / "extraction-report.json", report)
        rows += extraction_rows
        print("Extraction: historical development report reproduced", flush=True)

        sources = ROOT / "Packages/FoodLedgerKit/Sources"
        for module in ("FoodLedgerDomain", "FoodLedgerApplication", "FoodLedgerTestSupport"):
            module_sources = sorted((sources / module).glob("*.swift"))
            dependencies = [] if module == "FoodLedgerDomain" else ["-I", build, "-L", build, "-lFoodLedgerDomain"]
            if module == "FoodLedgerTestSupport":
                dependencies += ["-lFoodLedgerApplication"]
            command(common + ["-emit-library", "-emit-module", "-module-name", module,
                              "-emit-module-path", build / (module + ".swiftmodule"),
                              "-o", build / ("lib" + module + ".dylib")]
                    + dependencies + module_sources, out, env)
        command(common + [HERE / "safeguard.swift", "-parse-as-library", "-I", build, "-L", build,
                           "-lFoodLedgerDomain", "-lFoodLedgerApplication", "-lFoodLedgerTestSupport",
                           "-Xlinker", "-rpath", "-Xlinker", build, "-o", build / "safeguard-runner"], out, env)
        command([build / "safeguard-runner", out / "safeguard-observations.json"], out, env)
        rows += safeguard_rows(json.loads((out / "safeguard-observations.json").read_text()))
        write(out / "observations.json", rows)
        aggregate = summary(rows)
        write(out / "summary.json", dict(schema_version=1, status="development_spike_only",
              suites=aggregate, ai=dict(extraction="legacy_development_replay", synthetic_proposal_failures=1,
                                      independent_acceptance="not_run"),
              safeguards="pass" if all(r["expectation_met"] for r in rows if r["suite"] == "safeguard") else "fail",
              user_outcomes="incomplete_control_save_only", provider_calls=0, judges=0,
              historical_resource_drift=drift))
        config = dict(description="Offline nutrition spike: regression expectations are not population quality",
                      prompts=["{{case_id}}"], providers=[dict(id="file://" + str(HERE / "provider.py"),
                      config=dict(observations=str(out / "observations.json")))],
                      tests=[])
        config["defaultTest"] = {"assert": [{"type": "python", "value": "file://" + str(HERE / "assertions.py")} ]}
        config["tests"] = [dict(description=r["suite"] + ": " + r["id"], vars=dict(case_id=r["id"]),
                                 metadata=dict(suite=r["suite"], family=r["family"], evidence=r["evidence"])) for r in rows]
        write(out / "promptfooconfig.json", config)
        command([args.promptfoo.resolve(), "eval", "--config", out / "promptfooconfig.json",
                 "--output", out / "promptfoo.json", out / "promptfoo.html", "--max-concurrency", "1",
                 "--no-cache", "--no-share", "--no-write", "--no-table", "--no-progress-bar"], out, env,
                allowed_codes=(0, 100))
        promptfoo_result = json.loads((out / "promptfoo.json").read_text())
        stats = promptfoo_result["results"]["stats"]
        actual_rows = promptfoo_result["results"]["results"]
        if len(actual_rows) != len(rows) or stats["errors"] or stats["successes"] + stats["failures"] != len(rows):
            raise ValueError("Promptfoo did not score the complete expected roster")
        # This manifest binds both the freshly executed code and retained references.
        inputs = list(HERE.glob("*.py")) + list(HERE.glob("*.swift")) + [HERE / "run.sh",
                 query / "synthetic-v5.json", query / "manifest-v5.json", query / "score.py", query / "run.swift",
                 extraction_root / "development-replay-v3.json", extraction_root / "development-report-v3.json",
                 extraction_root / "corpus-v1.json", extraction_root / "candidate_v3.py", extraction_root / "candidate_v2.py",
                 extraction_root / "evaluate.py", extraction_root / "evidence_binding.py",
                 args.documents.resolve() / "manifest.json", package, lock]
        inputs += list((HERE / "tests").glob("*.py"))
        inputs += [extraction_root / name for name in (
            "collect.py", "prompt-v3.txt", "response-schema-v3.json", "response-schema-v2.json",
            "frozen-contract-v3.json", "frozen-contract-v2.json")]
        for module in ("FoodLedgerDomain", "FoodLedgerApplication", "FoodLedgerTestSupport"):
            inputs += list((sources / module).glob("*.swift"))
        git = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT, text=True).strip()
        write(out / "manifest.json", dict(schema_version=1, head=git, promptfoo=version,
             python=sys.version, network_policy="OS deny network*, verified EPERM", provider_calls=0,
             keychain_policy="security process-exec denied", cache=False, source_tree_dirty=True,
             promptfoo_local_adapter_invocations=len(rows), promptfoo_model_requests=0,
             input_sha256={str(p): sha(p) for p in sorted(set(inputs))},
             output_sha256={p.name: sha(p) for p in out.glob("*.json") if p.name != "manifest.json"},
             extraction_document_text_hashes_verified=True, unrelated_resource_drift=drift))
        table = "".join("<tr><td>" + html.escape(suite) + "</td><td>" + str(values["expectations_met"]) + "/" +
                        str(values["cases"]) + "</td><td>" + html.escape(", ".join(values["failures"]) or "None") + "</td></tr>"
                        for suite, values in aggregate.items())
        (out / "report.html").write_text("<!doctype html><meta charset='utf-8'><title>Nutrition evaluation spike</title>"
            "<style>body{font:16px system-ui;max-width:1000px;margin:40px auto;padding:20px}td,th{padding:10px;text-align:left}"
            "table{border-collapse:collapse}tr{border-bottom:1px solid #ccc}</style><h1>Offline nutrition evaluation spike</h1>"
            "<p>Development regression and historical replay evidence. Overall acceptance: incomplete.</p>"
            "<table><tr><th>Suite</th><th>Expectations met</th><th>Failures</th></tr>" + table + "</table>"
            "<h2>AI capability</h2><p>20 historical extraction cases rescored. Parser is deterministic. "
            "One deliberately synthetic unsupported claim remains an AI-stage failure even when correctly blocked.</p>"
            "<h2>Safeguards</h2><p>Actual production save service: unsupported count without conversion must block; "
            "supported grams must save. Inspect the case details for observed results.</p>"
            "<h2>User outcomes</h2><p>Only a synthetic control save is exercised. Independent acceptance, daily totals, "
            "physical speech, user effort and live AI inference are not run.</p>"
            "<p>No network access, provider calls or judges. Historical resource drift: " + html.escape(str(drift)) + "</p>"
            "<p><a href='promptfoo.html'>Promptfoo case comparison</a> · <a href='summary.json'>Summary JSON</a> · "
            "<a href='manifest.json'>Manifest</a></p>")
        print(json.dumps(aggregate), flush=True)
        if any(not row["expectation_met"] for row in rows):
            raise RuntimeError("Regression expectation failed; reports retained")
    except Exception as error:
        write(out / "run-error.json", dict(status="failed_or_incomplete", error=str(error)))
        raise


if __name__ == "__main__":
    main()
