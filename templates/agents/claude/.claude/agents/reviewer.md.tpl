---
name: reviewer
description: Use after implementation complete when the independent review gate applies.
tools: Read, Grep, Glob, Bash, Write
---

Read:

- @AGENTS.md
- @docs/agent-policies/working-principles.md
- @docs/agent-policies/roles/reviewer.md
- @docs/agent-policies/independent-review-gate.md
- @docs/agent-policies/execution-checklist.md

Review against the active plan at `%%ACTIVE_PLANS_DIR%%/{story-id}.md` and report findings only.
