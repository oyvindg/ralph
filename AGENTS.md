# AGENTS.md

## Purpose
This repository should be declarative and testable. Changes must prioritize clear structure, low risk, and predictable execution.

## Mandatory Criteria
1. Human checks must be defined only in `hooks.json`/`hooks.jsonc`.
2. Human checks must not be hardcoded in shell with fallback policies that bypass the active hooks config.
3. New logic must be organized into functions, not long inline blocks.
4. All functions must have clear, short comments explaining purpose and responsibility.
5. Everything new that is added must have tests.

## Runtime Placement Rules
- Runtime orchestration functions must live in either:
  - `ralph.sh`, or
  - `.ralph/lib/core/*.sh`
- Shared reusable helpers should be placed in `.ralph/lib/*.sh` (outside `core` when not orchestration-specific).
- Avoid introducing runtime control flow in ad-hoc hook scripts when it belongs in core orchestration.

## Adapter Rules
- Adapter logic must be agnostic (provider/backend-neutral).
- Provider-specific details must be isolated in dedicated adapter modules.
- Core orchestration and shared libraries must not be tightly coupled to a single provider.

## Config and Language Rules
- Declarative behavior should be configured via:
  - `.ralph/hooks.jsonc`
  - `.ralph/tasks.json` / `.ralph/tasks.jsonc`
- User-facing text (prompts, labels, menu text, messages meant for localization) must be defined in:
  - `.ralph/lang/*.json`
- Avoid hardcoded user-facing strings in runtime logic when language keys are appropriate.

## Code Style
- Keep diffs small and focused.
- Preserve existing naming conventions.
- Avoid duplication; extract shared logic into dedicated functions.
- Prefer declarative config (`hooks`/`tasks`) before adding imperative shell flow.

## Testing Requirements
- For new functionality: add or update tests that verify expected behavior.
- For bug fixes: add a regression test that fails before the fix and passes after the fix.
- Run relevant tests before marking work as done, at minimum:
  - `tests/run.sh`
- If tests cannot be run, explicitly document why.

## Review Checklist
- Is human-check behavior fully controlled by hooks config?
- Is new logic encapsulated in functions with clear comments?
- Are runtime functions placed in `ralph.sh` or `.ralph/lib/core` as required?
- Are shared helpers placed in `.ralph/lib` appropriately?
- Is adapter logic agnostic, with provider-specific details isolated in adapter modules?
- Are user-facing strings placed in `.ralph/lang` where applicable?
- Are tests present for all new behavior?
- Are error messages clear and actionable?
