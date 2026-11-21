#!/usr/bin/env bash
# Confirm enrichment evaluation (docs/confirm-enrichment-openrouter-v1-phase.md sections 8 and 9). Run by
# the owner from the private evaluation folder. It fetches origin/main first with the OpenRouter key unset,
# so the tool's preflight can read the committed privacy record locally; the tool itself never runs git
# over the network. Usage: run.sh REPO_DIR -- <tool arguments>, for example
#   run.sh REPO_DIR -- select --export EXPORT.jsonl.gz --private PRIVATE_DIR
#   (select dates every case by the export's modification time: keep it when copying, `cp -p`, and
#   download with `curl -R`, so the same export and seed reproduce the same manifests)
#   run.sh REPO_DIR -- send --part details --cases PRIVATE_DIR/development-cases.json --private PRIVATE_DIR
set -euo pipefail
repo="${1:?usage: run.sh REPO_DIR -- <tool arguments>}"
shift
[[ "${1:-}" == "--" ]] && shift
env -u OPENROUTER_API_KEY git -C "$repo" fetch origin
# Build with the key unset too, then run the built binary: only the tool's own process holds the key.
env -u OPENROUTER_API_KEY swift build --package-path "$repo/Tools/ConfirmEnrichmentEval" --product ConfirmEnrichmentEval
bin="$(env -u OPENROUTER_API_KEY swift build --package-path "$repo/Tools/ConfirmEnrichmentEval" --show-bin-path)"
exec "$bin/ConfirmEnrichmentEval" "$@" --repo "$repo"
