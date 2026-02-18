# ralph

`ralph.sh` is an iterative loop for AI-assisted work.

The loop itself is tool-agnostic in concept: repeat a goal over multiple iterations, feed previous output back in, and improve step by step.

This repository's implementation is currently wired to OpenAI Codex CLI.

## Requirements

- Bash
- `codex` CLI installed and available in `PATH`
- Authenticated Codex CLI session
- OpenAI account with active billing/access for Codex usage

If `codex` is missing, `ralph.sh` prints an install/setup link:
`https://developers.openai.com/codex/cli/`

## Make Executable

If needed, make the script executable:

```bash
chmod +x ./ralph.sh
```

Then run it directly (`./ralph.sh ...`) or via Bash (`bash ./ralph.sh ...`).

## Usage

```bash
./ralph.sh --iterations 5 --prompt "Improve X with measurable outcomes"
```

Dry run:

```bash
./ralph.sh --iterations 2 --prompt "Test run" --dry-run
```

With plan file and model:

```bash
./ralph.sh -i 3 -p "Refactor module safely" -P AGENTS.md -m gpt-5.3-codex
```

Run against a specific workspace (optional):

```bash
./ralph.sh -i 3 -p "Tune strategy preset" -w ~/myrepo -P ~/.codex/AGENTS.md
```

Call Ralph from another repository:

```bash
cd ~/myrepo
~/ralph.sh -i 5 -p "Improve fitness_score with minimal risk" -P ~/.codex/AGENTS.md
```

Or stay in current directory and target another repo explicitly:

```bash
~/ralph.sh -i 5 -p "Improve fitness_score with minimal risk" -w ~/myrepo -P ~/.codex/AGENTS.md
```

## Example Prompts

**Bug fix with verification:**

```bash
./ralph.sh -i 3 -p "Fix the failing test in tests/auth.test.js. Each iteration: identify root cause, apply fix, run tests, verify fix doesn't break other tests."
```

**Incremental refactoring:**

```bash
./ralph.sh -i 5 -p "Refactor the UserService class to use dependency injection. Each iteration: extract one dependency, update tests, ensure all tests pass before proceeding."
```

**Code review and cleanup:**

```bash
./ralph.sh -i 4 -p "Review src/api/ for security issues. Each iteration: identify one vulnerability, apply fix, document the change. Focus on input validation and SQL injection."
```

**Performance optimization:**

```bash
./ralph.sh -i 3 -p "Optimize database queries in src/db/queries.js. Each iteration: profile slowest query, optimize it, measure improvement. Stop when queries are under 100ms."
```

**Business and strategy:**

```bash
# Budget optimization
./ralph.sh -i 4 -p "Review Q2 budget in budget.csv. Each iteration: identify largest cost category, find 10% savings potential, document trade-offs in budget-review.md."

# Sales pitch improvement
./ralph.sh -i 3 -p "Improve sales pitch in pitch.md. Each iteration: strengthen one weak point (value prop, objection handling, call-to-action), make it more concrete with numbers."

# Competitive analysis
./ralph.sh -i 5 -p "Analyze competitors in our market. Each iteration: research one competitor (pricing, features, positioning), add comparison to competitive-analysis.md."

# OKR refinement
./ralph.sh -i 3 -p "Refine Q3 OKRs in okrs.md. Each iteration: check one objective for measurability, tighten key results, ensure alignment with company goals."

# Process improvement
./ralph.sh -i 4 -p "Optimize customer onboarding flow. Each iteration: identify one bottleneck, propose fix, estimate impact on conversion rate. Document in onboarding-improvements.md."
```

**Everyday tasks (non-code):**

```bash
# Improve a job application
./ralph.sh -i 3 -p "Improve my CV in resume.md. Each iteration: identify weakest section, rewrite for clarity and impact, check for typos."

# Research and summarize
./ralph.sh -i 4 -p "Research best practices for home office ergonomics. Each iteration: find one key area (desk, chair, lighting, breaks), summarize recommendations, add to notes.md."

# Plan a trip
./ralph.sh -i 3 -p "Plan a weekend trip to Bergen. Each iteration: research one aspect (transport, accommodation, activities), add details to trip-plan.md with costs."

# Learn a new topic
./ralph.sh -i 5 -p "Explain how solar panels work. Each iteration: go one level deeper (basic concept → physics → efficiency factors → installation → economics). Write to solar-notes.md."
```

## How `ralph.sh` Works

For each iteration, Ralph:

1. Builds a prompt file containing:
   - your objective (`--prompt`)
   - optional plan content (`--plan`)
   - previous iteration output (`last_response.md`)
2. Runs Codex CLI (`codex exec`) in the selected workspace.
3. Captures the latest model response into `last_response.md`.
4. Appends iteration stats and response content to `summary.md`.

At the end, Ralph prints session paths and leaves all artifacts under `sessions/`.

## AGENTS.md

You can keep reusable instructions in an `AGENTS.md` file (for example repo-local `./AGENTS.md` or global `~/.codex/AGENTS.md`).

Pass it as plan input to include those preferences in each iteration:

```bash
./ralph.sh -i 3 -p "Improve test reliability" -P AGENTS.md
```

## Arguments

| Argument | Short | Required | Description | Example |
|---|---|---|---|---|
| `--iterations N` | `-i N` | Yes | Positive integer for number of iterations. | `--iterations 5` |
| `--prompt "..."` | `-p "..."` | Yes | Objective passed into each iteration. | `-p "Improve test reliability"` |
| `--plan FILE` | `-P FILE` | No | Optional guidance file. If missing/unreadable, Ralph continues with a warning. | `-P ~/.codex/AGENTS.md` |
| `--workspace PATH` | `-w PATH` | No | Workspace directory. If omitted, defaults to caller directory (`$PWD`). If provided, path must exist and be a directory. | `-w ~/myrepo` |
| `--model NAME` | `-m NAME` | No | Codex model name (if omitted, Codex CLI default model is used). | `-m gpt-5.3-codex` |
| `--timeout SEC` | `-t SEC` | No | Timeout in seconds for each iteration command (`0` disables timeout). | `-t 900` |
| `--no-colors` | - | No | Disable ANSI colors in terminal output. | `--no-colors` |
| `--skip-git-repo-check` | - | No | Allow running in non-git directories (passed to Codex). | `--skip-git-repo-check` |
| `--docker` | - | No | Run in Docker container (auto-builds image if needed). | `--docker` |
| `--docker-build` | - | No | Build Docker image only, then exit. | `--docker-build` |
| `--docker-rebuild` | - | No | Force rebuild Docker image and run. | `--docker-rebuild` |
| `--dry-run` | `-d` | No | Print/record commands without running Codex. | `--dry-run` |

## Session Artifacts

Each run creates a session folder: `sessions/<timestamp>_<pid>/`

| File | Description |
|------|-------------|
| `summary.md` | Complete session summary with metadata, prompt, stats, and responses |
| `prompt_input.txt` | The original prompt text |
| `prompt_<n>.txt` | Full prompt sent to Codex for iteration N (includes context) |
| `last_response.md` | Most recent response from Codex |
| `engine_<n>.md` | Raw Codex output/logs for iteration N |

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
- `--dry-run` still creates a session folder and summary, but skips Codex execution.
- If `codex` is missing and not in dry-run mode, Ralph exits with a readable error and setup link.
- When called from another repo, Ralph defaults workspace to the caller directory unless `-w` is provided.

## Sandboxing

Ralph runs AI-generated code with full file system access. To limit risk, consider isolating execution:

**Use the workspace flag:**
```bash
./ralph.sh -i 3 -p "Refactor auth" -w /tmp/sandbox-project
```

**Git worktree (isolated branch copy):**
```bash
git worktree add ../sandbox-branch
./ralph.sh -i 3 -p "Experiment with new API" -w ../sandbox-branch
git worktree remove ../sandbox-branch  # cleanup
```

**Docker:**

Ralph has built-in Docker support using `Dockerfile` in the repository root.

```bash
# Build image only
./ralph.sh --docker-build

# Run in docker (auto-builds if needed)
./ralph.sh --docker -i 3 -p "Refactor module"

# Force rebuild and run (use after updating ralph.sh)
./ralph.sh --docker-rebuild -i 3 -p "Refactor module"

# With workspace and plan file
./ralph.sh --docker -i 3 -p "Improve code" -w ~/myproject -P ~/AGENTS.md
```

Docker features:
- Runs as your user (files have correct ownership)
- Auto-mounts workspace and plan file directories
- Mounts `~/.codex/auth.json` for authentication
- Streams output with colors in real-time
- Detects and highlights API rate limit errors

**Firejail (Linux):**
```bash
firejail --private=./sandbox --net=none ./ralph.sh -i 3 -p "Optimize queries"
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
./ralph.sh -i 5 -p "Improve test coverage. After each change, commit with a descriptive message."
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
./ralph.sh -i 5 -p "Improve test coverage" -P AGENTS.md
```

Benefits:
- Review all changes in PR before merging
- Each iteration creates its own commit(s)
- Easy to revert individual changes
- Discard entire branch if unhappy: `git checkout main && git branch -D ralph/improve-tests`

## License

[MIT](LICENSE)
