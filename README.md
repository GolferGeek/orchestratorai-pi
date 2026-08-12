# OrchestratorAI - Pi

A local, Pi-native legal agent workspace.

This project is intentionally not a second web platform. Pi supplies the interactive agent, built-in tools, sessions, model interface, and extension system. This repository supplies the legal operating context, skills, agent personas, and eventually reusable workflows.

## Current foundation

- Project-local Pi settings and session storage
- Legal system prompt with document-safety and human-review rules
- Contract-review skill
- Specialized legal contract-reviewer persona
- Local-model setup guidance
- Text-first composed Pi workflows for Red–Blue review, arbitration, and summary generation
- Live workflow activity bridged from pi-agents into the native Activity panel

## Start Pi

From this directory:

```sh
pi --approve
```

The first run may ask you to trust the project because it contains project-local Pi resources. Only approve repositories whose skills and extensions you have reviewed.

## Run the composed contract workflow

Place a synthetic contract in `fixtures/` and ask Pi:

```text
Run the saved contract-review workflow on fixtures/example-nda.md.
Assume we represent the receiving party. Produce the executive summary, detailed report, and identify every assumption.
```

The workflow runs independent Red–Blue reviewers over the complete document, arbitrates their natural-language findings, and generates the report. The macOS app invokes the same saved workflow through Pi RPC.

While a workflow is running, the Activity panel receives lifecycle events for
workflow and agent nodes from the project-local Pi extension. It shows the
composition as it executes without exposing hidden model reasoning or full
intermediate legal findings.

## Open Pi

Build the native macOS shell and open it from Finder:

```sh
./scripts/build-app.sh
open dist/Pi.app
```

The macOS app launches the Pi runtime through its local RPC interface. It uses the Ollama model configured in the user-level Pi model catalog and does not embed cloud credentials.
