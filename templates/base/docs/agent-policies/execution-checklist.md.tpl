# Execution Checklist

Run this before planning, coding, refactoring, or meaningful tool use.

1. Goal — can I state the task in one sentence?
2. Ambiguity — would another reasonable interpretation change the solution?
3. Simplicity — is there a smaller change that solves it?
4. Scope — am I staying inside the active plan?
5. Fabrication — did I verify every file, API, and behavior I am about to reference?
6. Plan file — does `%%ACTIVE_PLANS_DIR%%/{story-id}.md` exist and have a complete Compliance Check?
7. Ownership — have I ensured the plan with `pnpm plan:ensure -- <plan-id>` if I am picking this work up?
8. Announcement — have I stated what I am about to do and why?

If any answer is no or unsure, stop and resolve it first.
