Copy this template to `%%ACTIVE_PLANS_DIR%%/{story-id}.md` to start a task.

Before the first guarded commit, ensure the plan:

```bash
pnpm plan:ensure -- {story-id}
```

```md
---
story_id: {story-id}
status: planning
work_type: %%DEFAULT_WORK_TYPE%%
owner_name: unclaimed
owner_email: unclaimed
branch: unclaimed
review_gate: %%DEFAULT_REVIEW_GATE%%
tracker_target: %%DEFAULT_TRACKER_TARGET%%
created_at: YYYY-MM-DD HH:MM TZ
updated_at: YYYY-MM-DD HH:MM TZ
---

# Plan — {story-id}

## Request Summary

One paragraph summary of the requested change.

## Clarified Goal

What is the exact outcome?

## Constraints

- In scope:
- Out of scope:
- Technical limits:
- Approval boundaries:

## Ambiguities

- None.

## Assumptions

- None.

## Minimal Proposed Solution

- Smallest viable change:
- Why this is the simplest viable option:
- Alternatives considered:

## Tasks

- [ ] Task 1
- [ ] Task 2

## Risks

- None.

## Compliance Check

- [ ] No ambiguous requirement is being assumed
- [ ] No unnecessary architecture introduced
- [ ] No invented facts, APIs, or behavior
- [ ] Simpler solution considered first
- [ ] Remaining assumptions explicitly stated above
- [ ] Scope matches the requested outcome

## Developer Progress

- None yet.

## Review Findings

- None yet.

## Handover Summaries

### Planner → Orchestrator

- Plan file created and Compliance Check passed.

### Developer → Orchestrator

- None yet.

### Reviewer → Orchestrator

- None yet.
```

Tracker guidance: %%TRACKER_TEMPLATE_HINT%%
