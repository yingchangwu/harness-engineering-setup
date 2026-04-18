# he-setup-cli

Reusable CLI to scaffold the harness-engineering workflow into any repo.

It installs:

- `AGENTS.md` and `CONTRIBUTING.md`
- plan helper scripts and commit-msg hook
- Planner / Developer / Reviewer role docs
- optional Codex and Claude subagent wrappers
- profile-aware plan directories

Profiles:

- `generic` -> `docs/plans/**`
- `mvp` -> `docs/mvp/plans/**` plus `docs/mvp/tracker/**`

The generated repo stores its workflow settings in `.harness-engineering/setup.json`. The generated plan tooling reads that file, so plan paths are config-driven rather than hardcoded.

## Install / Run

Install globally:

```bash
npm install -g he-setup-cli
```

Then use it from the target repo root:

```bash
cd /path/to/your/project
he-setup init
he-setup doctor
```

You can still target another directory explicitly:

```bash
he-setup init ../my-solution --profile mvp
```

Or run from a local clone of this repo:

```bash
node bin/harness-engineering-setup.mjs init
```

## Commands

### `init`

Initialize the current repo by default.

```bash
he-setup init
```

What it does:

- scaffolds into the current working directory when no path is provided
- creates the target directory if an explicit target path is given
- writes workflow docs, hooks, scripts, and agent wrappers
- creates or updates `package.json` with `plan:*` scripts
- initializes git if needed
- sets `core.hooksPath` to `.githooks`

### `adopt`

Install the workflow into an existing repo.

```bash
he-setup adopt
```

### `doctor`

Validate a scaffolded repo.

```bash
he-setup doctor
```

Checks:

- workflow config exists and parses
- expected scaffolded files exist
- active/archive plan directories exist
- `package.json` contains the plan scripts
- git hook path is configured

## Profile Attribute

`profile` is the workflow preset. It decides the default folder layout and policy surface.

- `generic` -> `docs/plans/active`, `docs/plans/archive`
- `mvp` -> `docs/mvp/plans/active`, `docs/mvp/plans/archive`, `docs/mvp/tracker`

The generated manifest keeps both the selected `profile` and the exact path configuration so future tooling can use the configured paths directly instead of assuming a layout.

## Development

```bash
npm test
```
