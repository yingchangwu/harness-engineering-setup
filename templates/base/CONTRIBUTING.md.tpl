# CONTRIBUTING.md

## `[solo]` for Ad-Hoc Single-Agent Work

Prefix the prompt with:

```text
[solo] <your request>
```

This keeps the task in the current agent only. It does not bypass plan files or the repo workflow.

## Starting a New Task

1. Create `%%ACTIVE_PLANS_DIR%%/<plan-id>.md` from `%%PLAN_TEMPLATE_PATH%%`.
2. Fill the plan and complete the Compliance Check.
3. Ensure the plan:

```bash
pnpm plan:ensure -- %%EXAMPLE_PLAN_ID%%
```

4. Start implementation.

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
