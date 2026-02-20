# ralph

Ralph is a repeatable AI work loop for getting meaningful progress on complex tasks instead of one-off chat answers. You give it a goal, it works in steps, checks the result after each step, and keeps going until the plan is complete or you stop it.

Technically, `ralph.sh` is a Bash orchestrator that runs a deterministic step loop over a plan, routes each step to an AI engine, executes hook-based validation, and stores all artifacts under `.ralph/sessions/` for traceability and replay.

## What This Project Solves

- Turns vague goals into step-by-step execution.
- Makes AI-assisted work auditable with saved prompts, responses, and logs.
- Adds guardrails (tests, hooks, human approval, checkpoints) between steps.
- Lets teams standardize behavior via `.ralph/` config files.

## Requirements

- `bash`
- `jq`
- At least one available AI engine (check with `./ralph.sh --list-engines`)

## Install

### Option 1: Install from a release archive (recommended)

```bash
chmod +x install.sh
./install.sh
```

This installs:

- runtime: `~/.local/share/ralph`
- CLI symlink: `~/.local/bin/ralph`
- baseline config: `~/.ralph` (via `ralph --setup`)

### Option 2: Run directly from a repo clone

```bash
git clone https://github.com/oyvindg/ralph ~/ralph
cd ~/ralph
chmod +x ralph.sh
./ralph.sh --version
```

## Quick Start

From the workspace you want to improve:

```bash
/path/to/ralph.sh --goal "Improve test stability and reduce flaky failures"
```

Limit steps:

```bash
/path/to/ralph.sh --goal "Refactor auth module" --steps 3
```

Dry-run (no API calls):

```bash
/path/to/ralph.sh --goal "Validate workflow" --dry-run
```

Use guidance file:

```bash
/path/to/ralph.sh --goal "Fix CI failures" --guide AGENTS.md
```

Run against another workspace explicitly:

```bash
/path/to/ralph.sh --goal "Improve docs quality" --workspace ~/myrepo
```

## Practical Examples

### Bugfix loop

```bash
./ralph.sh --goal "Fix failing auth tests and verify no regressions" --steps 4
```

### Safe refactor loop

```bash
./ralph.sh --goal "Refactor payment service without behavior changes" --steps 5 --guide AGENTS.md
```

### Performance loop

```bash
./ralph.sh --goal "Reduce API p95 latency in /search endpoint" --steps 3
```

### Documentation cleanup loop

```bash
./ralph.sh --goal "Update README and remove outdated docs/examples" --steps 2
```

## How Ralph Works

1. Reads goal, plan, and config.
2. Runs one plan step at a time.
3. Sends step context to selected AI engine.
4. Runs quality hooks and optional tests.
5. Logs outputs and continues/retries/stops based on hook exit codes.

Main extension points live in `.ralph/`:

- `profile.jsonc`: defaults and runtime behavior
- `hooks.jsonc`: command hooks by lifecycle event
- `tasks.jsonc`: reusable task definitions
- `plans/`: reusable plan templates

Project-local `.ralph/` overrides global `~/.ralph/`.

## Session Artifacts

Each run writes artifacts under:

- `.ralph/sessions/<session-id>/`

Typical files include prompts, model responses, per-step logs, and session summaries.

## Full `--help` Output

```text
Usage:
  ./ralph.sh --goal "<goal>" [options]

Required:
      --goal "<text>"     The overall goal for this session

Options:
      --steps <N>         Max steps to run (default: all pending, or profile default)
      --plan <file>       Execution plan file (default: plan.json -> .ralph/plans/plan.json)
      --new-plan          Create/select a new plan interactively, regardless of existing plan state
      --guide <file>      Optional guidance file (e.g., AGENTS.md)
      --workspace <path>  Workspace directory (default: current dir)
      --model <name>      Model name (default: engine default)
      --engine <name>     AI engine: codex, claude, ollama, openai, anthropic
      --ticket <id>       Optional work item/ticket id (agnostic, e.g. ABC-123)
      --timeout <sec>     Timeout per step in seconds (0 = disabled)
      --checkpoint <mode> Checkpoint mode: off|pre|all (or 0|1)
      --checkpoint-per-step <0|1>  Override per-step checkpoint snapshots
      --list-engines      Show available AI engines and exit
      --no-colors         Disable ANSI colors in output
      --verbose           Enable verbose debug logging
      --human-guard <0|1> Enable/disable human approval guard
      --human-guard-assume-yes <0|1>  Auto-approve human guard prompts (CI)
      --human-guard-scope <session|step|both>  Where to enforce guard
      --skip-git-repo-check  Allow running in non-git directories
      --docker            Run in docker container
      --docker-build      Build docker image only
      --docker-rebuild    Run in docker, rebuild image first
      --setup             Install/update global baseline (~/.ralph) and exit
      --setup-force       Overwrite existing global files (used with --setup)
      --setup-target <dir> Install baseline to custom target dir (with --setup)
      --test              Run Ralph repo test suite and exit
      --version          Show version and exit
      --dry-run           Run full workflow with mock AI (no API calls)

Examples:
  ./ralph.sh --goal "Improve test coverage"              # Run all pending steps
  ./ralph.sh --goal "Refactor auth module" --steps 3     # Run max 3 steps
  ./ralph.sh --goal "Debug build" --dry-run              # Dry-run with mock AI
  ./ralph.sh --goal "Optimize queries" --guide AGENTS.md # With guidance file
  ./ralph.sh --goal "Fix bug" --ticket ABC-123           # Attach work item id
  ./ralph.sh --setup                                      # Install ~/.ralph baseline
  ./ralph.sh --test                                       # Run tests/run.sh
```

## Running Ralph Tests

```bash
./tests/run.sh
```

For test-suite details, see `tests/README.md`.
