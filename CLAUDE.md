@AGENTS.md

## Claude Code notes

- `AGENTS.md` above is the single source of repository rules; do not duplicate them here.
- Named subagents for this repository are in `.claude/agents/` (symlinks to `.agents/agents/`): `architecture-gate`, `invariant-reviewer`, `validator`, `journey-qa`. Launch reviewers in parallel and blind to each other when both apply.
- Skills are in `.claude/skills/` (symlinks to `.agents/skills/`).
- Use the iOS Simulator tools for `journey-qa` work; screenshots and taps are headless, so verify rather than asking the user to check.
