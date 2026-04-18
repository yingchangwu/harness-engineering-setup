# CONTRIBUTING.md

## `[solo]` for Ad-Hoc Single-Agent Work

Prefix the prompt with:

```text
[solo] <your request>
```

This keeps the task in the current agent only. It does not bypass plan files, hooks, or commit policy.

## Starting a New Task

1. Create `%%ACTIVE_PLANS_DIR%%/<plan-id>.md` from `%%PLAN_TEMPLATE_PATH%%`.
2. Fill the plan and complete the Compliance Check.
3. Ensure the plan:

```bash
pnpm plan:ensure -- %%EXAMPLE_PLAN_ID%%
```

4. Make guarded commits with:

```text
Plan: %%EXAMPLE_PLAN_ID%%
```

## Resuming a Task

Use the same preflight command:

```bash
pnpm plan:ensure -- %%EXAMPLE_PLAN_ID%%
```

Behavior:

- unclaimed plan -> claims it for the current user
- same owner -> verifies and refreshes branch/status if needed
- different owner -> blocks and tells you to use `--takeover`

Explicit takeover:

```bash
pnpm plan:ensure -- %%EXAMPLE_PLAN_ID%% --takeover
```

## Commit Gate

The commit-msg hook blocks guarded commits when:

- there is no `Plan: <plan-id>` trailer
- the plan id does not exist in `%%ACTIVE_PLANS_DIR%%`
- Compliance Check items are still unchecked
- the plan still contains `OPEN` ambiguities
- owner email or branch metadata no longer match the current git context
- two active plans claim the same branch with different owners

Normal trailer:

```text
Plan: <plan-id>
```

Bypass trailers:

```text
Plan: none (trivial)
Plan: bypass (<reason>)
```

Bypass audit log:

```text
.harness-engineering/plan-bypass.log
```

## Tracker Guidance

%%TRACKER_CONTRIBUTING_SECTION%%

## Commands

```bash
pnpm plan:list
pnpm plan:show -- %%EXAMPLE_PLAN_ID%%
pnpm plan:check
pnpm plan:ensure -- %%EXAMPLE_PLAN_ID%%
pnpm plan:status -- %%EXAMPLE_PLAN_ID%% in_progress
pnpm plan:archive -- %%EXAMPLE_PLAN_ID%%
```
