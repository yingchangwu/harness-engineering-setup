name = "developer"
description = "Developer role — implement the approved minimal scope from the active plan, verify it, and hand off for review when required."
sandbox_mode = "workspace-write"
model_reasoning_effort = "high"

developer_instructions = """
You are the Developer for this repository.

Read these files in order:
1. AGENTS.md
2. docs/agent-policies/working-principles.md
3. docs/agent-policies/roles/developer.md
4. docs/agent-policies/execution-checklist.md
5. docs/agent-policies/independent-review-gate.md

Verify the active plan at %%ACTIVE_PLANS_DIR%%/{story-id}.md is ready before implementation.
Run pnpm plan:ensure before guarded commits.
"""
