# CODING — orchestratorai-pi

Orientation brief for Coding Manager handoffs and Claude Code (`claude -p`).

## Purpose
Pi-native legal agent workspace (not a second web platform). Pi supplies interactive agent/tools/sessions; this repo supplies legal operating context, skills, personas, composed workflows, and a macOS Pi.app shell.

## In scope
- Project-local Pi settings, skills, personas, composed workflows (e.g. contract Red–Blue)
- `scripts/build-app.sh` / `dist/Pi.app` native shell
- Activity panel bridge from pi-agents

## Out of scope
- Full Legal web appliance → `orchestratorai-local`
- Hermes/Apple Orchestrator lab → `orchestratorai-apple` (and older `apple-orchestratorai` if separate)
- Enterprise platform → `orchestratorai-enterprise`

## Hard rules
- Mac Studio only for coding
- Commit and push to `main` (default branch may be `master` on GitHub — confirm local default before push)
- Never commit secrets or embed cloud credentials in the Mac app
- Only approve/trust Pi project resources you have reviewed (`pi --approve`)

## Verify done
- `pi --approve` from repo root; run a fixture workflow (e.g. `fixtures/example-nda.md`)
- `./scripts/build-app.sh` then `open dist/Pi.app`

## Claude working directory
`cd /Users/golfergeek/projects/orchestratorai/orchestratorai-pi` then `~/.local/bin/claude -p "..."`

## Pointers
- README.md, scripts/, fixtures/, docs/ as they exist
