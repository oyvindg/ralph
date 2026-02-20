# tasks.jsonc Syntax Reference

Reusable task and condition definitions for hooks.jsonc.

## Best Practice

**Define commands in tasks.jsonc, not in hooks.jsonc.**

```jsonc
// tasks.jsonc - commands live here
{
  "tasks": {
    "test": { "run": "npm test" },
    "lint": { "run": "npm run lint" },
    "deploy": { "run": "./deploy.sh" }
  }
}

// hooks.jsonc - only references and properties
{
  "quality-gate": {
    "system": [
      { "run": "task:lint", "allow_failure": true },
      { "run": "task:test" }
    ]
  }
}
```

Why:
- **Single source of truth** - commands defined once, reused everywhere
- **Easier maintenance** - change command in one place
- **Cleaner separation** - tasks.jsonc = what, hooks.jsonc = when
- **Testable** - tasks can be run standalone via `task:name`

Inline commands in hooks.jsonc are supported but discouraged:
```jsonc
// Works, but avoid this
{ "run": "npm test" }

// Prefer this
{ "run": "task:test" }
```

## File Location

Resolution order (first match wins):
1. `$RALPH_TASKS_JSON` environment variable
2. `.ralph/tasks.jsonc`
3. `.ralph/tasks.json`
4. `.ralph/tasks/tasks.jsonc` (legacy)
5. `.ralph/tasks/tasks.json` (legacy)

Can also be configured in `profile.jsonc`:
```jsonc
{
  "defaults": {
    "tasks_json": ".ralph/tasks.jsonc"
  }
}
```

## Hook Lifecycle

Tasks defined in `tasks.jsonc` are executed via `hooks.jsonc` during Ralph's lifecycle events.

### Events

Ralph fires these events during execution:

| Event | When | Typical Use |
|-------|------|-------------|
| `before-session` | Once at session start | Setup, workflow selection, branch creation |
| `after-session` | Once at session end | Cleanup, summary, notifications |
| `before-step` | Before each plan step | Checkpoint, pre-validation |
| `after-step` | After each plan step | Version control, logging |
| `quality-gate` | After step completion | Test execution, human approval |
| `on-error` | On step/hook failure | Error handling, notifications |
| `human-gate-confirm` | When human guard active | Approval prompt |

### Phases

Each event has three execution phases:

| Phase | Order | Purpose |
|-------|-------|---------|
| `before-system` | 1st | User hooks before Ralph's built-in behavior |
| `system` | 2nd | Ralph's built-in shell hooks (`.ralph/hooks/*.sh`) |
| `after-system` | 3rd | User hooks after Ralph's built-in behavior |

### Execution Order

```
before-session
  ├── before-system  (hooks.jsonc commands)
  ├── system         (hooks.jsonc commands + shell hooks)
  └── after-system   (hooks.jsonc commands)

for each step:
  before-step
    ├── before-system
    ├── system
    └── after-system

  [AI engine executes step]

  after-step
    ├── before-system
    ├── system
    └── after-system

  quality-gate
    ├── before-system
    ├── system
    └── after-system

after-session
  ├── before-system
  ├── system
  └── after-system
```

### hooks.jsonc Structure

```jsonc
{
  // Event name as top-level key
  "before-session": {
    // Phase as nested key
    "before-system": [
      // Array of commands/tasks
      { "run": "task:setup-workflow" },
      { "run": "echo 'Starting session'" }
    ],
    "after-system": [
      { "run": "task:log-session-start" }
    ]
  },

  "after-step": {
    "after-system": [
      { "run": "task:version-control" }
    ]
  },

  "quality-gate": {
    "system": [
      { "run": "npm test", "allow_failure": false }
    ]
  }
}
```

### Custom Phases

You can define custom phases for specific use cases:

```jsonc
{
  "before-session": {
    // Standard phases
    "before-system": [...],

    // Custom phase for plan overwrite confirmation
    "plan-overwrite-confirm": [
      {
        "select": {
          "prompt": "Overwrite existing plan?",
          "options": [
            { "code": "yes", "label": "Overwrite", "run": "true" },
            { "code": "no", "label": "Cancel", "run": "false" }
          ]
        }
      }
    ]
  }
}
```

Custom phases are invoked explicitly by Ralph internals or shell hooks.

## Basic Structure

```jsonc
{
  // Optional: include other tasks files (merged depth-first)
  "include": ["shared/tasks-base.jsonc"],

  "tasks": {
    // Conditions: reusable shell predicates
    "conditions": {
      "workspace-empty": {
        "run": "test -z \"$(find \"${RALPH_WORKSPACE}\" -mindepth 1 -print -quit)\""
      },
      "has-package-json": {
        "run": "test -f package.json"
      }
    },

    // Regular tasks: runnable commands
    "my-task": {
      "run": "echo 'Hello from task'",
      "when": "test -f .enabled",
      "allow_failure": true,
      "run_in_dry_run": false
    }
  }
}
```

## Task Properties

| Property | Type | Default | Description |
|----------|------|---------|-------------|
| `run` | string | required | Shell command to execute |
| `cmd` | string | - | Alias for `run` |
| `when` | string/object | - | Condition that must pass for task to run |
| `cwd` | string | `$ROOT` | Working directory (relative to workspace root) |
| `allow_failure` | boolean | `false` | Continue even if command fails |
| `run_in_dry_run` | boolean | `false` | Execute even in dry-run mode |
| `human_gate` | boolean/object | `false` | Require user confirmation |
| `prompt` | string | - | Approval prompt text or `{lang.key}` |

## Task Object vs Array Format

**Object format** (keyed by dotted path):
```jsonc
{
  "tasks": {
    "build": { "run": "npm run build" },
    "test.unit": { "run": "npm test" },
    "test.integration": { "run": "npm run test:e2e" }
  }
}
```

**Array format** (with explicit `code`):
```jsonc
{
  "tasks": [
    { "code": "build", "run": "npm run build" },
    { "code": "test.unit", "run": "npm test" }
  ]
}
```

Both formats can be referenced the same way from hooks.jsonc.

## Referencing Tasks from hooks.jsonc

Tasks are referenced using the `run` field with `task:` prefix or `{tasks.}` placeholder syntax.

### Basic Task Reference

```jsonc
// hooks.jsonc
{
  "after-step": {
    "after-system": [
      { "run": "task:version-control" }
    ]
  }
}

// tasks.jsonc
{
  "tasks": {
    "version-control": {
      "run": "lib/tasks/version-control.task.sh"
    }
  }
}
```

### Placeholder Syntax

```jsonc
{
  "after-step": {
    "system": [
      { "run": "{tasks.my-task-name}" }
    ]
  }
}
```

### Task Path Resolution

Dotted paths are resolved as nested keys from the root `tasks` object:

```jsonc
// tasks.jsonc
{
  "tasks": {
    "conditions": {
      "empty-workspace": { "run": "test -z ..." }
    },
    "wizard": {
      "workflow-coding": { "run": "set-workflow.sh coding" }
    }
  }
}

// Reference as:
// - task:conditions.empty-workspace
// - task:wizard.workflow-coding
// - {tasks.conditions.empty-workspace}
```

### Cross-Referencing Tasks

Tasks can reference other tasks anywhere in the hierarchy. All paths are resolved from the root `tasks` object.

**In `when` expressions** - use `task:` prefix or `{tasks.path}` placeholders:

```jsonc
{
  "tasks": {
    "conditions": {
      "is-git-repo": { "run": "test -d .git" },
      "has-changes": { "run": "test -n \"$(git status --porcelain)\"" }
    },

    "deploy": {
      "staging": {
        // Reference conditions from sibling branch
        "when": "{tasks.conditions.is-git-repo} && {tasks.conditions.has-changes}",
        "run": "./deploy.sh staging"
      }
    }
  }
}
```

**In `run` field** - full reference or inline chaining:

```jsonc
{
  "tasks": {
    "utils": {
      "cleanup": { "run": "rm -rf .cache tmp" },
      "notify": { "run": "curl -X POST $WEBHOOK" }
    },
    "deploy": {
      // Full task reference
      "pre-deploy": { "run": "task:utils.cleanup" },

      // Inline chaining with task: prefix
      "staging": {
        "run": "task:utils.cleanup && ./deploy.sh staging && task:utils.notify"
      },

      // Mixed placeholder and task: syntax
      "production": {
        "run": "{tasks.utils.cleanup} && ./deploy.sh prod && task:utils.notify"
      }
    }
  }
}
```

Supported inline patterns:
- `task:utils.cleanup && task:utils.notify` - chained tasks
- `{tasks.utils.cleanup} && ./script.sh` - placeholder with shell
- `echo START | task:utils.step1` - task after pipe
- `task:a; task:b` - task after semicolon

Each task reference is wrapped in parentheses when expanded:
```bash
# "task:a && task:b" expands to:
( cmd-from-a ) && ( cmd-from-b )
```

**Via hook entries** - alternative to inline chaining:

```jsonc
// hooks.jsonc - chain tasks via multiple entries
{
  "before-session": {
    "before-system": [
      { "run": "task:utils.cleanup" },
      { "run": "task:deploy.staging" },
      { "run": "task:utils.notify" }
    ]
  }
}
```

**In `select` options** - reference tasks for menu choices:

```jsonc
{
  "before-session": {
    "before-system": [
      {
        "select": {
          "prompt": "Select workflow:",
          "options": [
            { "code": "dev", "label": "Development", "run": "task:workflow.dev" },
            { "code": "prod", "label": "Production", "run": "task:workflow.prod" }
          ]
        }
      }
    ]
  }
}

// tasks.jsonc
{
  "tasks": {
    "workflow": {
      "dev": { "run": "export ENV=dev && source .env.dev" },
      "prod": { "run": "export ENV=prod && source .env.prod" }
    }
  }
}
```

Note: Properties like `human_gate`, `when`, `allow_failure` are set on the hook entry in hooks.jsonc, not inherited from tasks.jsonc.

The path lookup always starts from `tasks`, so:
- `task:conditions.is-git-repo` resolves to `tasks.conditions.is-git-repo`
- `{tasks.utils.cleanup}` resolves to `tasks.utils.cleanup`

## When Expressions

### Shell Command (string)

```jsonc
{
  "my-task": {
    "when": "test -f package.json",
    "run": "npm install"
  }
}
```

### Task Reference

Reference a condition defined in tasks.jsonc:

```jsonc
{
  "my-task": {
    "when": "task:conditions.has-package-json",
    "run": "npm install"
  }
}
```

### Placeholder Expansion

Combine multiple conditions with shell operators:

```jsonc
{
  "before-session": {
    "before-system": [
      {
        "when": "{tasks.conditions.workspace-empty} && {tasks.conditions.workflow-not-set}",
        "select": { ... }
      }
    ]
  }
}
```

Expands to: `( <cmd-a> ) && ( <cmd-b> )` before evaluation.

### Object Form

```jsonc
{
  "my-task": {
    "when": { "task": "conditions.my-condition" },
    "run": "do-something.sh"
  }
}

// or direct command
{
  "my-task": {
    "when": { "run": "test -f .enabled" },
    "run": "do-something.sh"
  }
}
```

## Include / Composition

Merge multiple task files (children processed first, parent overrides):

```jsonc
{
  "include": "base-tasks.jsonc"
}

// or array
{
  "includes": [
    "shared/conditions.jsonc",
    "shared/workflows.jsonc"
  ]
}
```

Paths are relative to the including file. Absolute paths and `~` expansion supported.

Merge behavior:
- Arrays: concatenated
- Objects: deep-merged (parent overrides children for scalars)
- `include`/`includes` keys are stripped from merged result

## Human Gate

Require user confirmation before running:

```jsonc
{
  "tasks": {
    "deploy": {
      "run": "deploy.sh",
      "human_gate": true
    }
  }
}
```

With custom prompt:

```jsonc
{
  "tasks": {
    "deploy": {
      "run": "deploy.sh",
      "human_gate": {
        "prompt": "Deploy to production?",
        "default": "no"
      }
    }
  }
}
```

## Localization

Prompts and labels support `{lang.key}` syntax:

```jsonc
{
  "tasks": {
    "deploy": {
      "run": "deploy.sh",
      "prompt": "{deploy.confirm}"
    }
  }
}
```

Resolved from `.ralph/lang/<code>.json`:
```json
{
  "deploy.confirm": "Deploy to production?"
}
```

## Environment Variables

Available in task commands:

| Variable | Description |
|----------|-------------|
| `RALPH_WORKSPACE` | Project root directory |
| `RALPH_PROJECT_DIR` | `.ralph` directory path |
| `RALPH_STEP` | Current step number |
| `RALPH_STEP_EXIT_CODE` | Previous step exit code |
| `RALPH_HOOK_DEPTH` | Hook nesting level |
| `DRY_RUN` | `1` if dry-run mode active |

## JSONC Support

Comments are supported:

```jsonc
{
  // Single-line comment
  "tasks": {
    /* Multi-line
       block comment */
    "example": { "run": "echo hello" }
  }
}
```

Note: Comments must be on dedicated lines (not inline after values).

## Examples

### Conditional Workflow Selection

```jsonc
// tasks.jsonc
{
  "tasks": {
    "conditions": {
      "workspace-empty": {
        "run": "test -z \"$(find \"${RALPH_WORKSPACE}\" -mindepth 1 ! -name '.git' ! -name '.ralph' -print -quit)\""
      },
      "workflow-not-set": {
        "run": "test -z \"${RALPH_WORKFLOW_TYPE:-}\""
      }
    },
    "workflow-coding": {
      "when": "test -x \"${RALPH_PROJECT_DIR}/lib/tasks/workflow-select.task.sh\"",
      "run": "\"${RALPH_PROJECT_DIR}/lib/tasks/workflow-select.task.sh\" coding",
      "run_in_dry_run": false,
      "allow_failure": true
    }
  }
}
```

### Version Control Hook

```jsonc
// tasks.jsonc
{
  "tasks": {
    "version-control": {
      "when": "test -x \"${RALPH_PROJECT_DIR}/lib/tasks/version-control.task.sh\"",
      "run": "RALPH_HOOK_DEPTH=\"$(( ${RALPH_HOOK_DEPTH:-0} + 1 ))\" \"${RALPH_PROJECT_DIR}/lib/tasks/version-control.task.sh\"",
      "run_in_dry_run": false,
      "allow_failure": true
    }
  }
}

// hooks.jsonc
{
  "after-step": {
    "after-system": [
      { "run": "task:version-control" }
    ]
  }
}
```

### Complete Lifecycle Example

```jsonc
// tasks.jsonc - reusable command definitions
{
  "tasks": {
    "conditions": {
      "is-node-project": { "run": "test -f package.json" },
      "has-uncommitted": { "run": "test -n \"$(git status --porcelain)\"" }
    },
    "setup": {
      "install-deps": { "run": "npm ci --silent" }
    },
    "test": {
      "unit": { "run": "npm test" },
      "lint": { "run": "npm run lint" }
    },
    "vcs": {
      "auto-commit": {
        "run": "git add -A && git commit -m \"Step ${RALPH_STEP} complete\""
      }
    }
  }
}

// hooks.jsonc - lifecycle bindings with properties
{
  "before-session": {
    "before-system": [
      {
        "run": "task:setup.install-deps",
        "when": "{tasks.conditions.is-node-project}",
        "allow_failure": true
      }
    ]
  },

  "after-step": {
    "after-system": [
      {
        "run": "task:vcs.auto-commit",
        "when": "{tasks.conditions.has-uncommitted}",
        "human_gate": true
      }
    ]
  },

  "quality-gate": {
    "system": [
      { "run": "task:test.lint", "allow_failure": true },
      { "run": "task:test.unit" }
    ]
  },

  "on-error": {
    "system": [
      { "run": "echo 'Step ${RALPH_STEP} failed with code ${RALPH_STEP_EXIT_CODE}'" }
    ]
  }
}
```
