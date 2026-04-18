# AGENTS.md

## Workflow Profile

- Profile: `%%PROFILE%%`
- Description: %%PROFILE_DESCRIPTION%%
- Plans root: `%%PLANS_DIR%%`
- Active plans: `%%ACTIVE_PLANS_DIR%%`
- Archive plans: `%%ARCHIVE_PLANS_DIR%%`
- Plan template: `%%PLAN_TEMPLATE_PATH%%`
- Agent wrappers: %%AGENTS_LIST%%
- Guarded paths:
%%GUARDED_PATHS_BULLETS%%

## Read First

- `AGENTS.md`
- `CONTRIBUTING.md`
- `docs/agent-policies/working-principles.md`
- `docs/agent-policies/execution-checklist.md`
- `docs/agent-policies/plan-template.md`
%%TRACKER_READ_FIRST%%

## Policy Docs

- `docs/agent-policies/working-principles.md` — hard rules for every task
- `docs/agent-policies/execution-checklist.md` — run before planning, coding, or meaningful tool use
- `docs/agent-policies/plan-template.md` — copy into `%%ACTIVE_PLANS_DIR%%/{story-id}.md`
- `docs/agent-policies/roles/planner.md` — Planner responsibilities and handover
- `docs/agent-policies/roles/developer.md` — Developer responsibilities and handover
- `docs/agent-policies/roles/reviewer.md` — Reviewer responsibilities and handover
- `docs/agent-policies/independent-review-gate.md` — when review is required
- `docs/agent-policies/work-types.md` — work type and tracker guidance
%%OPTIONAL_TRACKER_POLICY_DOC%%

## Core Rules

- Use the Planner -> Developer -> Reviewer workflow for non-trivial tasks.
- The working contract is the active plan file at `%%ACTIVE_PLANS_DIR%%/{story-id}.md`.
- Requests prefixed with `[solo]` stay in the current agent only. That changes routing, not repo safeguards.
- Commits that touch guarded paths must name exactly one plan with `Plan: <plan-id>`.
- Before guarded commits, run `pnpm plan:ensure -- <plan-id>`.
- Use `Plan: none (trivial)` only for genuine trivial changes.
- Use `Plan: bypass (<reason>)` only for intentional audited exceptions.
- Keep the plan metadata current: `status`, `owner_name`, `owner_email`, and `branch`.
%%TRACKER_POLICY_SECTION%%

## Helper Commands

- `pnpm plan:list`
- `pnpm plan:show -- <plan-id>`
- `pnpm plan:check`
- `pnpm plan:ensure -- <plan-id>`
- `pnpm plan:claim -- <plan-id>`
- `pnpm plan:status -- <plan-id> <status>`
- `pnpm plan:archive -- <plan-id>`

## Subagent Workflow

| Role | Purpose | Write scope |
|------|---------|-------------|
| Planner | clarify intent and write the plan | active plan file only |
| Developer | implement the approved scope | least-change workspace edits |
| Reviewer | independent review gate | review findings only |

Handover flows through the orchestrator. Subagents do not hand off directly to each other.
