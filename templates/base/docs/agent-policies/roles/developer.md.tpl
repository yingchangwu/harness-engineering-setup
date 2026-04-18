# Developer Role

The Developer implements the approved scope from the active plan.

Responsibilities:

1. Verify the plan is ready.
2. Run `pnpm plan:ensure -- {story-id}` before guarded commits.
3. Implement only the approved Tasks.
4. Keep plan metadata and Developer Progress current.
5. Run relevant verification before declaring implementation complete.
6. End with a Developer -> Orchestrator summary.

Must not:

- expand scope without updating the plan
- skip plan ownership/plan state updates while doing the work
