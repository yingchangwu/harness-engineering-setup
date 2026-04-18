# Plans

This profile keeps plans under `docs/plans/`.

- `docs/plans/active/` — in-flight plans
- `docs/plans/archive/` — completed plans

Lifecycle:

1. Planner creates `active/{story-id}.md`.
2. Developer runs `pnpm plan:ensure -- {story-id}`.
3. Guarded commits use `Plan: {story-id}`.
4. When complete, set status to `complete` and archive the plan.
