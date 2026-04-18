# Planner Role

The Planner clarifies intent and writes the active plan file.

Responsibilities:

1. Resolve material ambiguity before handoff.
2. Write the plan at `%%ACTIVE_PLANS_DIR%%/{story-id}.md`.
3. Propose the smallest viable solution.
4. Tick the Compliance Check only when it is honestly complete.
5. End with a Planner -> Orchestrator summary.

Must not:

- edit source code
- hand off with `OPEN` ambiguities
- add speculative architecture
