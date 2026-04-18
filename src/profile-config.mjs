export const PROFILE_PRESETS = {
  generic: {
    description: "General-purpose workflow scaffold with plan directories under docs/plans.",
    examplePlanId: "task-1",
    defaultWorkType: "harness",
    defaultReviewGate: "auto",
    defaultTrackerTarget: "none",
    paths: {
      plansDir: "docs/plans",
      activePlansDir: "docs/plans/active",
      archivePlansDir: "docs/plans/archive",
      trackerRoot: null,
      planTemplate: "docs/agent-policies/plan-template.md"
    }
  },
  mvp: {
    description: "MVP delivery workflow scaffold with docs/mvp plans and tracker structure.",
    examplePlanId: "s1.8",
    defaultWorkType: "mvp",
    defaultReviewGate: "auto",
    defaultTrackerTarget: "docs/mvp/tracker/sprint-N.md",
    paths: {
      plansDir: "docs/mvp/plans",
      activePlansDir: "docs/mvp/plans/active",
      archivePlansDir: "docs/mvp/plans/archive",
      trackerRoot: "docs/mvp/tracker",
      planTemplate: "docs/agent-policies/plan-template.md"
    }
  }
};

const SUPPORTED_AGENTS = new Set(["codex", "claude"]);

export function listProfiles() {
  return Object.keys(PROFILE_PRESETS);
}

export function normalizeProfile(profile) {
  if (!profile) {
    return "generic";
  }

  if (!(profile in PROFILE_PRESETS)) {
    throw new Error(
      `Unsupported profile: ${profile}. Allowed: ${listProfiles().join(", ")}`,
    );
  }

  return profile;
}

export function normalizeAgents(agentsValue) {
  const source = agentsValue ?? "codex,claude";
  const agents = source
    .split(",")
    .map((value) => value.trim().toLowerCase())
    .filter(Boolean);

  if (agents.length === 0) {
    throw new Error("At least one agent wrapper must be selected.");
  }

  const unique = [...new Set(agents)];
  for (const agent of unique) {
    if (!SUPPORTED_AGENTS.has(agent)) {
      throw new Error(
        `Unsupported agent wrapper: ${agent}. Allowed: ${Array.from(SUPPORTED_AGENTS).join(", ")}`,
      );
    }
  }

  return unique;
}

export function normalizeGuardedPaths(guardedValue) {
  const source = guardedValue ?? "src/";
  const guardedPaths = source
    .split(",")
    .map((value) => value.trim().replace(/\\/g, "/"))
    .filter(Boolean)
    .map((value) => (value.endsWith("/") ? value : `${value}/`));

  if (guardedPaths.length === 0) {
    throw new Error("At least one guarded path is required.");
  }

  return [...new Set(guardedPaths)];
}

export function buildWorkflowConfig({
  workflowVersion,
  profile,
  agents,
  guardedPaths
}) {
  const preset = PROFILE_PRESETS[normalizeProfile(profile)];
  return {
    workflowVersion,
    profile: normalizeProfile(profile),
    agents: normalizeAgents(agents),
    guardedPaths: normalizeGuardedPaths(guardedPaths),
    paths: {
      plansDir: preset.paths.plansDir,
      activePlansDir: preset.paths.activePlansDir,
      archivePlansDir: preset.paths.archivePlansDir,
      trackerRoot: preset.paths.trackerRoot,
      planTemplate: preset.paths.planTemplate
    },
    defaults: {
      workType: preset.defaultWorkType,
      reviewGate: preset.defaultReviewGate,
      trackerTarget: preset.defaultTrackerTarget
    }
  };
}

export function buildTemplateContext({
  repoName,
  workflowVersion,
  profile,
  agents,
  guardedPaths
}) {
  const normalizedProfile = normalizeProfile(profile);
  const normalizedAgents = normalizeAgents(agents);
  const normalizedGuardedPaths = normalizeGuardedPaths(guardedPaths);
  const preset = PROFILE_PRESETS[normalizedProfile];

  const trackerEnabled = Boolean(preset.paths.trackerRoot);

  return {
    REPO_NAME: repoName,
    WORKFLOW_VERSION: workflowVersion,
    PROFILE: normalizedProfile,
    PROFILE_DESCRIPTION: preset.description,
    EXAMPLE_PLAN_ID: preset.examplePlanId,
    PLANS_DIR: preset.paths.plansDir,
    ACTIVE_PLANS_DIR: preset.paths.activePlansDir,
    ARCHIVE_PLANS_DIR: preset.paths.archivePlansDir,
    TRACKER_ROOT: preset.paths.trackerRoot ?? "none",
    PLAN_TEMPLATE_PATH: preset.paths.planTemplate,
    DEFAULT_WORK_TYPE: preset.defaultWorkType,
    DEFAULT_REVIEW_GATE: preset.defaultReviewGate,
    DEFAULT_TRACKER_TARGET: preset.defaultTrackerTarget,
    AGENTS_LIST: normalizedAgents.join(", "),
    GUARDED_PATHS_CSV: normalizedGuardedPaths.join(","),
    GUARDED_PATHS_BULLETS: normalizedGuardedPaths.map((value) => `- \`${value}\``).join("\n"),
    OPTIONAL_TRACKER_POLICY_DOC: trackerEnabled
      ? "- `docs/agent-policies/implementation-tracker-boundary.md` — what belongs in the implementation tracker and what does not"
      : "",
    TRACKER_READ_FIRST: trackerEnabled
      ? `3. \`${preset.paths.trackerRoot}/README.md\` — tracker structure and active sprint files`
      : "",
    TRACKER_POLICY_SECTION: trackerEnabled
      ? `- This profile includes an implementation tracker under \`${preset.paths.trackerRoot}\`. Keep delivery tracking there and keep per-task plans in \`${preset.paths.activePlansDir}\`.`
      : "- This profile does not create an implementation tracker. Keep `tracker_target: none` unless you add your own tracker root and update `.harness-engineering/setup.json`.",
    TRACKER_CONTRIBUTING_SECTION: trackerEnabled
      ? `- MVP work should point \`tracker_target\` at the relevant tracker file under \`${preset.paths.trackerRoot}\`.
- Harness/docs/ops/spike work should keep \`tracker_target: none\`.`
      : "- This profile does not create a tracker. Keep `tracker_target: none` in generated plan files.",
    TRACKER_TEMPLATE_HINT: trackerEnabled
      ? `Use the relevant tracker file under \`${preset.paths.trackerRoot}\`.`
      : "Leave `tracker_target: none` unless you deliberately add a tracker root later."
  };
}
