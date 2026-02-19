# ralph

`ralph.sh` is an iterative loop for AI-assisted work.

The loop itself is tool-agnostic in concept: repeat a goal over multiple iterations, feed previous output back in, and improve step by step.

This repository's implementation supports multiple AI engines and uses a hook-based architecture for customization.

## Requirements

- Bash
- At least one AI engine available (see [AI Engines](#ai-engines))
- `jq` for JSON processing

## Install in a Specific Repo

### Option 0: Install from GitHub Releases (recommended for new machines)

1. Download and extract a Ralph release archive from GitHub Releases.
2. Run installer from extracted folder:

```bash
chmod +x install.sh
./install.sh --setup-force
```

This installs:
- Ralph runtime: `~/.local/share/ralph`
- CLI symlink: `~/.local/bin/ralph`
- Global baseline config: `~/.ralph` (via `ralph --setup`)

### Option 1: Use Ralph directly from GitHub repo clone

```bash
git clone https://github.com/oyvindg/ralph ~/.ralph-tool
chmod +x ~/.ralph-tool/ralph.sh

cd ~/myrepo
~/.ralph-tool/ralph.sh -g "Refactor module safely" -s 3
```

### Option 2: Download `ralph.sh` directly into the target repo

```bash
cd ~/myrepo
mkdir -p .tools/ralph
curl -fsSL https://raw.githubusercontent.com/oyvindg/ralph/main/ralph.sh -o .tools/ralph/ralph.sh
chmod +x .tools/ralph/ralph.sh

.tools/ralph/ralph.sh -g "Improve test reliability" -s 3
```

If you keep project-specific `.ralph/` config in the target repo, Ralph will use that automatically.

### Option 3: Install/update global baseline config (`~/.ralph`)

```bash
cd ~/.ralph-tool
chmod +x .ralph/lib/setup/install-global.sh

# Keep existing files in ~/.ralph
.ralph/lib/setup/install-global.sh

# Overwrite existing files in ~/.ralph
.ralph/lib/setup/install-global.sh --force
```

## AI Engines

Ralph auto-detects available AI engines. List them with:

```bash
./ralph.sh --list-engines
```

| Engine | Detection | Setup |
|--------|-----------|-------|
| `codex` | `codex` CLI in PATH | [OpenAI Codex CLI](https://developers.openai.com/codex/cli/) |
| `claude` | `claude` CLI in PATH | [Claude Code CLI](https://claude.ai/claude-code) |
| `ollama` | `ollama` running locally | [Ollama](https://ollama.ai/) |
| `openai` | `OPENAI_API_KEY` set | OpenAI API key |
| `anthropic` | `ANTHROPIC_API_KEY` set | Anthropic API key |
| `mock` | Always available | Built-in for testing |

Override engine selection:

```bash
./ralph.sh -g "Improve X" --engine claude           # Uses plan steps
./ralph.sh -g "Improve X" --engine claude -s 3      # Limit to 3 steps
./ralph.sh -g "Improve X" --engine ollama -m deepseek-coder
```

## Make Executable

If needed, make the script executable:

```bash
chmod +x ./ralph.sh
```

Then run it directly (`./ralph.sh ...`) or via Bash (`bash ./ralph.sh ...`).

## Usage

```bash
./ralph.sh --goal "Improve X with measurable outcomes"
```

With step limit:

```bash
./ralph.sh --goal "Improve X" --steps 3
```

Dry run:

```bash
./ralph.sh --goal "Test run" --dry-run
```

With plan file and model:

```bash
./ralph.sh -g "Refactor module safely" -G AGENTS.md -m gpt-5.3-codex
```

Run against a specific workspace (optional):

```bash
./ralph.sh -i 3 -g "Tune strategy preset" -w ~/myrepo -G ~/.codex/AGENTS.md
```

Call Ralph from another repository:

```bash
cd ~/myrepo
~/ralph.sh -i 5 -g "Improve fitness_score with minimal risk" -G ~/.codex/AGENTS.md
```

Or stay in current directory and target another repo explicitly:

```bash
~/ralph.sh -i 5 -g "Improve fitness_score with minimal risk" -w ~/myrepo -G ~/.codex/AGENTS.md
```

## Example Prompts

**Software development:**

```bash
# Fix a failing test with iterative debugging
./ralph.sh -i 3 -g "
Fix the failing test in tests/auth.test.js.
Each iteration:
- Identify root cause
- Apply fix
- Run tests
- Verify fix doesn't break other tests
"

# Gradually refactor a class over multiple iterations
./ralph.sh -i 5 -g "
Refactor the UserService class to use dependency injection.
Each iteration:
- Extract one dependency
- Update tests
- Ensure all tests pass before proceeding
"

# Security audit with fixes documented
./ralph.sh -i 4 -g "
Review src/api/ for security issues.
Each iteration:
- Identify one vulnerability
- Apply fix
- Document the change
Focus on input validation and SQL injection.
"

# Profile and optimize slow queries incrementally
./ralph.sh -i 3 -g "
Optimize database queries in src/db/queries.js.
Each iteration:
- Profile slowest query
- Optimize it
- Measure improvement
Stop when queries are under 100ms.
"
```

**Trading strategy development:**

```bash
# Backtest optimization
./ralph.sh -i 5 -g "
Optimize the momentum strategy in strategy.py.
Each iteration:
- Adjust one parameter (lookback, threshold, position size)
- Run backtest
- Compare Sharpe ratio
Document changes in optimization-log.md.
"

# Risk management review
./ralph.sh -i 3 -g "
Review risk controls in risk_manager.py.
Each iteration:
- Identify one edge case (gap risk, liquidity, correlation spike)
- Add protection
- Verify with stress test scenarios
"

# Signal refinement
./ralph.sh -i 4 -g "
Improve entry signals in signals.py.
Each iteration:
- Analyze false positive rate
- Add one filter (volume, volatility, trend)
- Measure improvement in win rate
"

# Portfolio rebalancing
./ralph.sh -i 3 -g "
Refactor rebalance.py for better execution.
Each iteration:
- Reduce slippage impact
- Improve order sizing
- Add transaction cost awareness
Target: reduce turnover by 20%.
"
```

**Business and strategy:**

```bash
# Budget optimization
./ralph.sh -i 4 -g "
Review Q2 budget in budget.csv.
Each iteration:
- Identify largest cost category
- Find 10% savings potential
- Document trade-offs in budget-review.md
"

# Sales pitch improvement
./ralph.sh -i 3 -g "
Improve sales pitch in pitch.md.
Each iteration:
- Strengthen one weak point (value prop, objection handling, call-to-action)
- Make it more concrete with numbers
"

# Competitive analysis
./ralph.sh -i 5 -g "
Analyze competitors in our market.
Each iteration:
- Research one competitor (pricing, features, positioning)
- Add comparison to competitive-analysis.md
"

# OKR refinement
./ralph.sh -i 3 -g "
Refine Q3 OKRs in okrs.md.
Each iteration:
- Check one objective for measurability
- Tighten key results
- Ensure alignment with company goals
"

# Process improvement
./ralph.sh -i 4 -g "
Optimize customer onboarding flow.
Each iteration:
- Identify one bottleneck
- Propose fix
- Estimate impact on conversion rate
Document in onboarding-improvements.md.
"
```

**Everyday tasks (non-code):**

```bash
# Improve a job application
./ralph.sh -i 3 -g "
Improve my CV in resume.md.
Each iteration:
- Identify weakest section
- Rewrite for clarity and impact
- Check for typos
"

# Research and summarize
./ralph.sh -i 4 -g "
Research best practices for home office ergonomics.
Each iteration:
- Find one key area (desk, chair, lighting, breaks)
- Summarize recommendations
- Add to notes.md
"

# Plan a trip
./ralph.sh -i 3 -g "
Plan a weekend trip to Bergen.
Each iteration:
- Research one aspect (transport, accommodation, activities)
- Add details to trip-plan.md with costs
"

# Learn a new topic
./ralph.sh -i 5 -g "
Explain how solar panels work.
Each iteration go one level deeper:
1. Basic concept
2. Physics
3. Efficiency factors
4. Installation
5. Economics
Write to solar-notes.md.
"
```

## How `ralph.sh` Works

Ralph follows a deterministic state machine with hooks as the policy layer:

```
Session Start
    │
    ├─→ before-session.sh (planning)
    │
    └─→ For each step:
            │
            ├─→ Build prompt (objective + plan + last response)
            ├─→ ai.sh (execute AI engine)
            ├─→ quality-gate.sh → testing.sh
            │       │
            │       ├─→ exit 0: continue
            │       ├─→ exit 1: stop session
            │       ├─→ exit 2: replan
            │       └─→ exit 3: retry step
            │
            └─→ after-step.sh (logging)
    │
    └─→ after-session.sh (cleanup)
```

At the end, Ralph prints session paths and leaves all artifacts under `.ralph/sessions/`.

## Configuration

Ralph uses a `.ralph/` directory for configuration:

```
.ralph/
├── profile.toml      # Default settings
├── hooks.json        # Hook orchestration (events, select, includes)
├── tasks.json        # Reusable task catalog (task targets)
├── lang/             # UI language maps (en/no/sv/custom)
├── lib/              # Shared helpers (UI, logging, source-control, issues adapters)
├── hooks/            # Lifecycle hooks
│   ├── ai.sh         # AI engine dispatcher
│   ├── before-session.sh
│   ├── issues.sh     # Optional issue/ticket context adapter
│   ├── after-session.sh
│   ├── quality-gate.sh
│   ├── testing.sh
│   └── after-step.sh
├── lib/tasks/        # Task scripts used by hooks.json/tasks.json
│   └── version-control.task.sh
├── plans/            # Reusable plan templates
│   └── refactor.md
└── sessions/         # Session artifacts (gitignored)
```

Settings resolution: project `.ralph/` overrides global `~/.ralph/`.

### profile.toml

```toml
[defaults]
# steps = 0 means no limit (run all pending steps)
# steps > 0 limits how many steps per session
steps = 0
engine = "codex"
model = "gpt-5.3-codex"
timeout = 0
skip_git_check = false
ticket = ""

# source-control policy (agnostic)
source_control_enabled = true
# auto | git | filesystem
source_control_backend = "auto"
source_control_allow_commits = false
source_control_branch_per_session = false
source_control_branch_name_template = "ralph/{ticket}/{goal_slug}/{session_id}"
source_control_require_ticket_for_branch = false

# issue provider (agnostic)
# none | git | jira
issues_provider = "none"

# filesystem rollback checkpoints (stored per session)
checkpoint_enabled = true
checkpoint_per_step = true

human_guard = true
human_guard_assume_yes = false
# session | step | both
human_guard_scope = "both"

# optional hooks.json override (relative to workspace root or absolute path)
# hooks_json = ".ralph/hooks.json"
# optional tasks.json override (relative to workspace root or absolute path)
# tasks_json = ".ralph/tasks.json"

# optional per-step agent routing
agent_routes = [
  "test|claude|claude-sonnet-4-20250514",
  "validate|claude|claude-sonnet-4-20250514",
  "default|codex|gpt-5.3-codex"
]

[hooks]
disabled = []
```

## Hooks

Hooks are shell scripts that run at lifecycle events. They receive context via environment variables and communicate via exit codes.

| Hook | When | Purpose |
|------|------|---------|
| `before-session.sh` | Session start | Setup, planning |
| `before-step.sh` | Before each step | Step preparation |
| `quality-gate.sh` | After AI response | Validation, testing |
| `testing.sh` | Called by quality-gate | Run project tests |
| `after-step.sh` | After quality-gate passes | Logging, metrics |
| `version-control.task.sh` | Triggered by `hooks.json` `after-step` task | Git/file-based step change log generation |
| `issues.sh` | Called by before-session | Optional ticket/work-item context enrichment (provider adapter) |
| `after-session.sh` | Session end | Cleanup, summary |
| `on-error.sh` | On failure | Error handling |
| `ai.sh` | AI execution | Engine abstraction |

### `hooks.json` (optional command hooks)

In addition to shell hook scripts, Ralph can run command hooks from JSON.

- Default path: `.ralph/hooks.json` (in current workspace)
- Legacy fallback: `.ralph/hooks/hooks.json` (still supported)
- Override path: `RALPH_HOOKS_JSON=<path>`
  - `profile.toml` can also set `hooks_json = "<path>"` (used when env is not set)
  - `profile.toml` can also set `tasks_json = "<path>"` for task catalogs
  - Absolute path is supported
  - Relative path is resolved from workspace root

Example config:

- Source files:
  - `examples/hooks/hooks.example.json`
  - `examples/hooks/other-hooks.example.json` (included by `hooks.example.json`)
  - `examples/hooks/verbose-loggings.json` (adds extra verbose hook logging)
  - `examples/hooks/wizard-select.example.json` (hook-driven startup wizard via `select`)
  - `examples/tasks/tasks.example.json` + `examples/tasks/other-tasks.example.json` (task catalog + include)
- Copy them to activate in your repo:

```bash
mkdir -p .ralph/hooks
cp examples/hooks/hooks.example.json .ralph/hooks.json
cp examples/hooks/other-hooks.example.json .ralph/hooks/other-hooks.example.json
cp examples/tasks/tasks.example.json .ralph/tasks.json
mkdir -p .ralph/tasks
cp examples/tasks/other-tasks.example.json .ralph/tasks/other-tasks.example.json

# Optional: use verbose logging profile
cp examples/hooks/verbose-loggings.json .ralph/hooks/verbose-loggings.json
# then set hooks_json in profile.toml or env:
# hooks_json = ".ralph/hooks/verbose-loggings.json"
# or: RALPH_HOOKS_JSON=.ralph/hooks/verbose-loggings.json
```

Behavior:

- Command runs directly when `human_gate` is omitted or `false`
- Command requires approval when `human_gate` is `true` or an object
- `--human-guard-assume-yes 1` auto-approves those prompts
- `run_in_dry_run: true` is required if command should execute during `--dry-run`
- Use `include` or `includes` at root level to compose hook files:
  - string: `"include": "other-hooks.example.json"`
  - array: `"include": ["a.json", "b.json"]`
  - include paths are resolved relative to the parent hooks file
- `select` entries are supported for interactive menus (single/multi) so wizard logic can live in JSON instead of shell hardcoding.
- Hook entries can reference reusable tasks from `.ralph/tasks.json` via `task`.
- Default setup already uses this pattern for `after-step` -> `version-control` via `task: "version-control"`.
- New standard: each event uses explicit phases:
  - `before-system` (user hooks before shell hook)
  - `system` (system command hooks for that event)
  - `after-system` (user hooks after shell hook)

### `tasks.json` (reusable task catalog)

- Default path: `.ralph/tasks.json` (in current workspace)
- Legacy fallback: `.ralph/tasks/tasks.json` (still supported)
- Override path: `RALPH_TASKS_JSON=<path>`
- Supports `include` / `includes` just like `hooks.json` (for `.ralph/tasks/other-tasks.json`, etc.)

Task reference example:

```json
// .ralph/tasks.json
{
  "tasks": {
    "lint": { "run": "npm run lint", "cwd": ".", "when": "test -f package.json", "run_in_dry_run": true }
  }
}
```

```json
// .ralph/hooks.json
{
  "before-step": {
    "before-system": [
      { "task": "lint" }
    ]
  }
}
```

`when` is optional and runs as a shell condition/command. Task runs only when it exits `0`.

`select` example:

```json
{
  "before-session": {
    "before-system": [
      {
        "select": {
          "mode": "single",
          "prompt": "Choose workspace profile:",
          "options": [
            { "code": "coding", "label": "Coding", "run": "echo coding selected" },
            { "code": "finance", "label": "Finance", "run": "echo finance selected" }
          ]
        }
      }
    ]
  }
}
```

### Exit Codes

| Code | Meaning |
|------|---------|
| 0 | Success, continue |
| 1 | Hard failure, stop session |
| 2 | Replan required |
| 3 | Retry current step |

### Environment Variables

Hooks receive:

```bash
RALPH_SESSION_ID      # Unique session identifier
RALPH_SESSION_DIR     # Session artifacts directory
RALPH_WORKSPACE       # Working directory
RALPH_STEP            # Current step number
RALPH_STEPS           # Total steps
RALPH_PROMPT_FILE     # Path to prompt file
RALPH_RESPONSE_FILE   # Path to response file
RALPH_DRY_RUN         # "1" if dry-run mode
RALPH_ENGINE          # Selected AI engine
RALPH_MODEL           # Model name (if specified)
RALPH_GOAL            # Session goal text
RALPH_TICKET          # Optional work-item/ticket id (from --ticket/profile)
RALPH_ISSUES_PROVIDER # none | git | jira
RALPH_SOURCE_CONTROL_ENABLED
RALPH_SOURCE_CONTROL_BACKEND
RALPH_SOURCE_CONTROL_ALLOW_COMMITS
RALPH_SOURCE_CONTROL_BRANCH_PER_SESSION
RALPH_SOURCE_CONTROL_BRANCH_NAME_TEMPLATE
RALPH_SOURCE_CONTROL_REQUIRE_TICKET_FOR_BRANCH
RALPH_CHECKPOINT_ENABLED
RALPH_CHECKPOINT_PER_STEP
RALPH_HUMAN_GUARD     # "1" enables human approval guard
RALPH_HUMAN_GUARD_ASSUME_YES  # "1" auto-approves guard prompts
RALPH_HUMAN_GUARD_SCOPE  # session | step | both
RALPH_WORKFLOW_TYPE  # selected workflow profile (e.g. coding, finance)
```

## Dry-Run Mode

Dry-run executes the full workflow with a mock AI engine:

```bash
./ralph.sh -g "Test workflow" -d
./ralph.sh -g "Test workflow" -s 3 -d    # Limit to 3 steps
```

- All hooks execute normally
- Sessions are created with full logging
- Mock responses simulate AI output
- No actual AI API calls

### Isolated Dry-Run Examples

Use the repo's `examples/dry-run/` folder for test plans/guides so you do not mix test data with user plans in `.ralph/plans/`.
Plan files are stateful (`status` gets updated), so copy them to a temporary path before each run if you want to preserve the originals.

```bash
# Refactor scenario
cp examples/dry-run/plans/refactor-safe.json /tmp/refactor-safe.plan.json
./ralph.sh -g "Dry-run refactor test" \
  -p /tmp/refactor-safe.plan.json \
  -G examples/dry-run/guides/refactor-guardrails.md \
  -s 2 -d --human-guard 1 --human-guard-assume-yes 1

# Bugfix scenario
cp examples/dry-run/plans/bugfix-triage.json /tmp/bugfix-triage.plan.json
./ralph.sh -g "Dry-run bugfix test" \
  -p /tmp/bugfix-triage.plan.json \
  -G examples/dry-run/guides/bugfix-playbook.md \
  -s 2 -d --human-guard 1 --human-guard-assume-yes 1

# Docs scenario
cp examples/dry-run/plans/docs-cleanup.json /tmp/docs-cleanup.plan.json
./ralph.sh -g "Dry-run docs test" \
  -p /tmp/docs-cleanup.plan.json \
  -G examples/dry-run/guides/docs-style.md \
  -s 2 -d --human-guard 1 --human-guard-assume-yes 1
```

Run all bundled dry examples:

```bash
./dev/run-dry-examples.sh
```

### Self-Improvement Example (Ralph on Ralph)

Use this repository as a practical test case for iterative improvement:

```bash
# Dry-run first (safe)
cp examples/self-improve/plan.json /tmp/ralph-self-improve.plan.json
./ralph.sh -g "Improve ralph incrementally" \
  -p /tmp/ralph-self-improve.plan.json \
  -G examples/self-improve/guide.md \
  -s 2 -d --human-guard 1

# Real run
cp examples/self-improve/plan.json /tmp/ralph-self-improve.plan.json
./ralph.sh -g "Improve ralph incrementally" \
  -p /tmp/ralph-self-improve.plan.json \
  -G examples/self-improve/guide.md \
  -s 2 --human-guard 1
```

### Failure Simulation

Test error handling with mock failures:

```bash
# Force AI failure
RALPH_MOCK_FAIL=1 ./ralph.sh -g "Test" -d

# Random AI failure (30% chance)
RALPH_MOCK_FAIL_RATE=30 ./ralph.sh -g "Test" -s 5 -d

# Empty AI response
RALPH_MOCK_EMPTY=1 ./ralph.sh -g "Test" -d

# AI response with error markers
RALPH_MOCK_ERROR=1 ./ralph.sh -g "Test" -d

# Force test failure
RALPH_MOCK_FAIL_TEST=1 ./ralph.sh -g "Test" -d

# Random test failure (20% chance)
RALPH_MOCK_FAIL_TEST_RATE=20 ./ralph.sh -g "Test" -s 5 -d
```

## AGENTS.md

You can keep reusable instructions in an `AGENTS.md` file (for example repo-local `./AGENTS.md` or global `~/.codex/AGENTS.md`).

Pass it as guide input to include those preferences in each iteration:

```bash
./ralph.sh -i 3 -g "Improve test reliability" -G AGENTS.md
```

## Arguments

| Argument&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; | Short&nbsp;&nbsp;&nbsp; | Required | Description | Example&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp;&nbsp; |
|:---|:---|:---:|---|:---|
| `--goal` | `-g` | Yes | The overall goal for this session | `-g "Fix bug"` |
| `--steps` | `-s` | No | Max steps to run (0=all pending, default from profile) | `-s 3` |
| `--plan` | `-p` | No | Execution plan JSON file name/path (default: `plan.json` under `.ralph/plans/`) | `-p sprint-plan.json` |
| `--guide` | `-G` | No | Optional guidance file (continues with warning if missing) | `-G AGENTS.md` |
| `--workspace` | `-w` | No | Workspace directory (default: current dir) | `-w ~/myrepo` |
| `--model` | `-m` | No | Model name for the AI engine | `-m gpt-5.3-codex` |
| `--engine` | `-e` | No | AI engine to use (auto-detected if not set) | `-e claude` |
| `--ticket` | `-T` | No | Optional work-item/ticket id for branching/commit context | `-T ABC-123` |
| `--list-engines` | | No | List available AI engines and exit | |
| `--timeout` | `-t` | No | Timeout per step in seconds (0=disabled) | `-t 900` |
| `--no-colors` | | No | Disable ANSI colors in output | |
| `--human-guard` | | No | Enable/disable human approval guard (overrides profile/env) | `--human-guard 1` |
| `--human-guard-assume-yes` | | No | Auto-approve human guard prompts (for CI) | `--human-guard-assume-yes 1` |
| `--human-guard-scope` | | No | Where to enforce guard: `session`, `step`, or `both` | `--human-guard-scope step` |
| `--skip-git-repo-check` | | No | Allow running in non-git directories | |
| `--docker` | | No | Run in Docker container | |
| `--docker-build` | | No | Build Docker image only | |
| `--docker-rebuild` | | No | Force rebuild Docker image and run | |
| `--dry-run` | `-d` | No | Run full workflow with mock AI (no API calls) | `-d` |
| `--help` | `-h` | No | Show usage information and exit | `-h` |

## Session Artifacts

Each run creates a session folder: `.ralph/sessions/<timestamp>_<pid>/`

| File | Description |
|------|-------------|
| `summary.md` | Complete session summary with metadata, prompt, stats, and responses |
| `prompt_input.txt` | The original prompt text |
| `prompt_<n>.txt` | Full prompt sent to Codex for iteration N (includes context) |
| `response_<n>.md` | AI response payload for step N |
| `engine_<n>.md` | Raw Codex output/logs for iteration N |
| `changes_step_<n>.md` | Step-level change log. Uses Git metadata when available; falls back to modified-file listing if not in a Git repo. |

`summary.md` includes:

- Session metadata (ID, model, iterations, timestamps)
- The prompt in a highlighted blockquote
- Per-iteration stats table (duration, status, lines/words/chars)
- Per-iteration responses in blockquotes
- Error details if API limits or auth issues occur

## Output and Paths

- Paths printed by Ralph are humanized:
  - paths under `$HOME` are shown as `~/...`
  - paths under workspace root are shown as workspace-relative
- Terminal colors are enabled when output is a TTY.
- Colors are automatically disabled for non-interactive output (e.g. piping to a file).
- Use `--no-colors` to force-disable colors.

## Error Handling

Ralph detects and reports common errors:

| Error | Terminal Output | Summary.md |
|-------|-----------------|------------|
| API usage limit | Red error + hint | `error: usage_limit` with hint |
| Authentication failure | Red error + hint | `error: auth_failed` with hint |
| Empty response | Yellow warning | Response shows `_(empty)_` |
| Timeout | Error message | `result: timeout` |

When errors occur:
- Terminal shows colored error messages
- `summary.md` includes error type and suggested fix
- Session artifacts are preserved for debugging

## Notes

- Tested on Ubuntu only.
- `--dry-run` creates full session artifacts with mock AI responses for workflow testing.
- Ralph auto-detects available AI engines. If none are found (and not in dry-run mode), it exits with an error.
- When called from another repo, Ralph defaults workspace to the caller directory unless `-w` is provided.
- Session artifacts are stored in `.ralph/sessions/` and are gitignored by default.
- If workspace is not a Git repo, `before-session` can prompt to run `git init` (or auto-init when `RALPH_HUMAN_GUARD_ASSUME_YES=1`).
- Enable human approval guards with `RALPH_HUMAN_GUARD=1` (session start + per-step acceptance).
- For non-interactive runs, set `RALPH_HUMAN_GUARD_ASSUME_YES=1` to avoid prompts explicitly.
- With human guard enabled, `before-session` also shows a plan review and asks for plan approval (yes/no), including in `--dry-run`.
- Hook logs are written to `.ralph/sessions/<session_id>/hooks.log` and `.ralph/sessions/<session_id>/events.jsonl`.
- Human/hook choices are also appended to `.ralph/state.json` under `hook_choices` (with timestamp, user, session, step).
- If workspace is effectively empty (only `.git`/`.ralph`), `before-session` shows a startup wizard (interactive) to choose workflow type (`coding`, `project-management`, `finance`, `non-code`). The selection is stored in `.ralph/state.json` and exposed to hooks as `RALPH_WORKFLOW_TYPE`.
- Optional bootstrap hook: add `.ralph/hooks/wizard.sh` to run custom setup logic based on `RALPH_WORKFLOW_TYPE`.
- Human-guard settings precedence: CLI flags > environment variables > `profile.toml` defaults.
- If no test runner is detected, `testing.sh` can prompt to create/run a temporary sanity test suite for the current step.
- You can disable this fallback with `RALPH_TEMP_TEST_SUITE_ON_NO_TESTS=0`.
- `source_control_*` settings in `profile.toml` control whether auto-commits are allowed and whether a new branch is created per session.
- Issue/ticket adapters are optional and agnostic (`issues_provider = none|git|jira`).
- Filesystem checkpoints are stored in `.ralph/sessions/<session_id>/checkpoints/` (`pre`, `step_<n>`), and can be restored with:
  `./.ralph/lib/checkpoint/restore-checkpoint.sh --session-id <id> --checkpoint pre`

## Sandboxing

Ralph runs AI-generated code with full file system access. To limit risk, consider isolating execution:

**Use the workspace flag:**
```bash
./ralph.sh -i 3 -g "Refactor auth" -w /tmp/sandbox-project
```

**Git worktree (isolated branch copy):**
```bash
git worktree add ../sandbox-branch
./ralph.sh -i 3 -g "Experiment with new API" -w ../sandbox-branch
git worktree remove ../sandbox-branch  # cleanup
```

**Docker:**

Ralph has built-in Docker support using `Dockerfile` in the repository root.

```bash
# Build image only
./ralph.sh --docker-build

# Run in docker (auto-builds if needed)
./ralph.sh --docker -i 3 -g "Refactor module"

# Force rebuild and run (use after updating ralph.sh)
./ralph.sh --docker-rebuild -i 3 -g "Refactor module"

# With workspace and plan file
./ralph.sh --docker -i 3 -g "Improve code" -w ~/myproject -G ~/AGENTS.md
```

Docker features:
- Runs as your user (files have correct ownership)
- Auto-mounts workspace and plan file directories
- Mounts `~/.codex/auth.json` for authentication
- Streams output with colors in real-time
- Detects and highlights API rate limit errors

**Firejail (Linux):**
```bash
firejail --private=./sandbox --net=none ./ralph.sh -i 3 -g "Optimize queries"
```

**Best practices:**
- Always use `--dry-run` first to preview what will happen
- Start with low iteration counts to verify behavior
- Use version control so changes can be reverted
- Review session artifacts in `sessions/` before committing changes

**Tip: Use git in your prompt for trackable iterations**

Include git instructions in your prompt so each iteration is committed:

```bash
git checkout -b ralph/improve-tests
./ralph.sh -i 5 -g "Improve test coverage. After each change, commit with a descriptive message."
git push -u origin ralph/improve-tests
gh pr create --title "Ralph: Improve test coverage" --body "Automated improvements"
```

Or add git workflow to your plan file (`AGENTS.md`):

```markdown
## Workflow
- Make small, focused changes
- Run tests before committing
- Commit after each meaningful change with a clear message
- Keep commits atomic and revertable
```

```bash
./ralph.sh -i 5 -g "Improve test coverage" -G AGENTS.md
```

Benefits:
- Review all changes in PR before merging
- Each iteration creates its own commit(s)
- Easy to revert individual changes
- Discard entire branch if unhappy: `git checkout main && git branch -D ralph/improve-tests`

## License

[MIT](LICENSE)
