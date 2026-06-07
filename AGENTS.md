# Krang - Requirement-Aware Mutation Testing

Krang is an agentic mutation testing system for pull requests. It analyzes PR diffs in the context of JIRA requirements, generates surgical mutations that negate or stress the changed behavior, runs tests to see if they catch the mutation, and reports survivors.

## Agents

| Agent | Role | Tool Access |
|---|---|---|
| `@krang-planner` | Analyzes PR + JIRA, produces ranked mutation candidates | Read-only (git log, grep) |
| `@krang-executor` | Applies mutation patch, builds, runs tests, reports outcome | Full (edit, write, bash) |
| `@krang-replanner` | Generates next batch given prior results | Read-only (git log, grep) |

## Workflow

```
1. @krang-planner  →  plan.json  (ranked mutation candidates)
2. @krang-executor →  result.json (for each candidate)
3. @krang-replanner → plan.json  (next batch, if needed)
4. Repeat 2-3 until coverage is adequate or budget exhausted
```

## Quick Start

```bash
# Install into current project
bash install.sh project

# Or install globally
bash install.sh global

# Then in the target project:
# opencode @krang-planner <context>
```

## Slash Commands

If opencode.json is loaded, these are available:

- `/krang-plan` - Run planner
- `/krang-execute` - Execute a mutation
- `/krang-replan` - Replan
- `/krang-run` - Full cycle

## State

Krang persists state in `.krang/`:
- `plan.json` - Current mutation candidates
- `results.json` - Execution results
- `prior_state.json` - Full analysis state for replanning
