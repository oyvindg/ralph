# Ralph Test Suite

This folder contains the repo-local test suite for Ralph, including direct CLI behavior checks.

## Run Tests

Run all tests:

```bash
./tests/run.sh
```

Run a single test file:

```bash
./tests/test_json_lib.sh
```

## Structure

- `run.sh`: test runner with colored status output, per-test duration, and final summary.
- `lib/assert.sh`: lightweight assertion helpers used by all tests.
- `test_script_syntax.sh`: runs `bash -n` against all `.sh` files in the repo.
- `test_json_lib.sh`: validates JSON/JSONC normalization in `.ralph/lib/json.sh`.
- `test_config_profile_jsonc.sh`: tests loading and override behavior for `profile.jsonc`.
- `test_issues_multi.sh`: tests multi-provider issue adapter behavior.
- `test_human_gate.sh`: tests core human-gate behavior in non-interactive/assume-yes flows.
- `test_install.sh`: validates installer flow in an isolated temp environment.
- `test_cli_flags.sh`: smoke-tests all documented CLI flags, including setup and docker delegation via a stubbed docker binary.

## Dependencies

- `bash`
- `jq`

If `jq` is missing, parts of the suite will fail because Ralph config relies on JSON/JSONC parsing.
