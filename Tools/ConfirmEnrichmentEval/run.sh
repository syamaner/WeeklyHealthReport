#!/usr/bin/env bash
# Confirm enrichment evaluation (docs/confirm-enrichment-openrouter-v1-phase.md sections 8 and 9). Run by
# the owner from the private evaluation folder. It fetches origin/main first with the OpenRouter key unset,
# so the tool's preflight can read the committed privacy record locally; the tool itself never runs git
# over the network. Usage: run.sh REPO_DIR -- <tool arguments>
set -euo pipefail
repo="${1:?usage: run.sh REPO_DIR -- <tool arguments>}"
shift
[[ "${1:-}" == "--" ]] && shift
env -u OPENROUTER_API_KEY git -C "$repo" fetch origin
exec swift run --package-path "$repo/Tools/ConfirmEnrichmentEval" ConfirmEnrichmentEval "$@" --repo "$repo"
