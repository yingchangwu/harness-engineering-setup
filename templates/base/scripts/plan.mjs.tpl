#!/usr/bin/env node

import fs from "node:fs";
import path from "node:path";
import { execFileSync } from "node:child_process";
import { fileURLToPath } from "node:url";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const VALID_STATUSES = new Set([
  "planning",
  "in_progress",
  "blocked",
  "parked",
  "pending_review",
  "complete"
]);

const VALID_WORK_TYPES = new Set(["mvp", "harness", "docs", "ops", "spike"]);
const VALID_REVIEW_GATES = new Set(["auto", "required", "skip"]);

const META_KEY_ORDER = [
  "story_id",
  "status",
  "work_type",
  "owner_name",
  "owner_email",
  "branch",
  "review_gate",
  "tracker_target",
  "created_at",
  "updated_at"
];

const REQUIRED_META_KEYS = new Set(META_KEY_ORDER);

const repoRoot = resolveRepoRoot();
const workflowConfig = loadWorkflowConfig();
const activePlansDir = path.join(repoRoot, workflowConfig.paths.activePlansDir);
const archivePlansDir = path.join(repoRoot, workflowConfig.paths.archivePlansDir);
const bypassLogPath = path.join(repoRoot, ".harness-engineering", "plan-bypass.log");

main(process.argv.slice(2));

function main(args) {
  const [command, ...rest] = args;

  switch (command) {
    case "list":
      commandList(rest);
      break;
    case "show":
      commandShow(rest);
      break;
    case "check":
      commandCheck(rest);
      break;
    case "ensure":
      commandEnsure(rest);
      break;
    case "claim":
      commandClaim(rest);
      break;
    case "status":
      commandStatus(rest);
      break;
    case "archive":
      commandArchive(rest);
      break;
    case "hook":
      commandHook(rest);
      break;
    case "help":
    case "--help":
    case "-h":
    case undefined:
      printHelp(0);
      break;
    default:
      fail(`Unknown command: ${command}\n\n${helpText()}`);
  }
}

function commandList(args) {
  const json = takeBooleanFlag(args, "--json");
  assertNoExtraArgs(args, "list");

  const plans = loadAllActivePlans().map((plan) => summarizePlan(buildPlanReport(plan, {
    strictOwner: false
  })));

  if (json) {
    console.log(JSON.stringify(plans, null, 2));
    return;
  }

  if (plans.length === 0) {
    console.log("No active plans.");
    return;
  }

  const headers = ["ID", "STATUS", "TYPE", "OWNER", "BRANCH", "TRACKER", "READY"];
  const rows = plans.map((plan) => [
    plan.id,
    plan.status,
    plan.work_type,
    plan.owner_email,
    plan.branch,
    plan.tracker_target,
    plan.ready_for_commit ? "yes" : "no"
  ]);

  printTable(headers, rows);
}

function commandShow(args) {
  const json = takeBooleanFlag(args, "--json");
  const [planId] = args;
  requireArg(planId, "show <plan-id>");
  assertNoExtraArgs(args.slice(1), "show");

  const report = buildPlanReport(loadActivePlan(planId), { strictOwner: false });
  if (json) {
    console.log(JSON.stringify(report, null, 2));
    return;
  }

  printPlanReport(report);
}

function commandCheck(args) {
  const json = takeBooleanFlag(args, "--json");
  const strictOwner = takeBooleanFlag(args, "--strict-owner");
  const [planId] = args;

  if (args.length > 1) {
    fail("Usage: plan check [plan-id] [--json] [--strict-owner]");
  }

  const plans = planId ? [loadActivePlan(planId)] : loadAllActivePlans();
  if (!planId && plans.length === 0) {
    console.log(json ? "[]" : "No active plans.");
    return;
  }

  const reports = plans.map((plan) => buildPlanReport(plan, { strictOwner }));
  if (json) {
    console.log(JSON.stringify(reports, null, 2));
  } else {
    for (const report of reports) {
      printPlanReport(report);
      console.log("");
    }
  }

  if (reports.some((report) => report.errors.length > 0)) {
    process.exit(1);
  }
}

function commandClaim(args) {
  const { options, positionals } = parseOptions(args);
  const [planId] = positionals;
  requireArg(planId, "claim <plan-id>");
  assertNoExtraArgs(positionals.slice(1), "claim");

  const plan = loadActivePlan(planId);
  const current = currentContext();
  const updatedMeta = stampUpdatedAt(
    metaClaimedBy(plan.meta, current, {
      ownerName: options.owner,
      ownerEmail: options.email,
      branch: options.branch
    }),
  );

  writePlan(plan.filePath, updatedMeta, plan.body);

  console.log(
    [
      `Claimed plan ${planId}.`,
      `  owner_name: ${updatedMeta.owner_name}`,
      `  owner_email: ${updatedMeta.owner_email}`,
      `  branch: ${updatedMeta.branch}`
    ].join("\n"),
  );
}

function commandEnsure(args) {
  const takeover = takeBooleanFlag(args, "--takeover");
  const { options, positionals } = parseOptions(args);
  const [planId] = positionals;
  requireArg(planId, "ensure <plan-id> [--status <status>] [--takeover]");
  assertNoExtraArgs(positionals.slice(1), "ensure");

  const desiredStatus = options.status ?? "in_progress";
  if (!VALID_STATUSES.has(desiredStatus)) {
    fail(`Invalid status: ${desiredStatus}\nAllowed: ${Array.from(VALID_STATUSES).join(", ")}`);
  }

  const plan = loadActivePlan(planId);
  const current = currentContext();
  ensureOwnerEmail(current.ownerEmail);

  const ownership = comparePlanOwnership(plan.meta, current);

  if (ownership.claimMissing) {
    const updatedMeta = withStatus(metaClaimedBy(plan.meta, current), desiredStatus);
    writePlanIfChanged(plan.filePath, plan.meta, updatedMeta, plan.body);
    console.log(
      [
        `Ensured plan ${planId}.`,
        "  action: claimed previously unclaimed plan",
        `  status: ${updatedMeta.status}`,
        `  owner_name: ${updatedMeta.owner_name}`,
        `  owner_email: ${updatedMeta.owner_email}`,
        `  branch: ${updatedMeta.branch}`
      ].join("\n"),
    );
    return;
  }

  if (ownership.sameOwnerContext) {
    const updatedMeta = withStatus(metaClaimedBy(plan.meta, current), desiredStatus);
    const changed = writePlanIfChanged(plan.filePath, plan.meta, updatedMeta, plan.body);
    console.log(
      [
        `Ensured plan ${planId}.`,
        changed
          ? "  action: refreshed branch/status for the current owner"
          : "  action: already assigned to the current owner",
        `  status: ${updatedMeta.status}`,
        `  owner_name: ${updatedMeta.owner_name}`,
        `  owner_email: ${updatedMeta.owner_email}`,
        `  branch: ${updatedMeta.branch}`
      ].join("\n"),
    );
    return;
  }

  if (takeover) {
    const updatedMeta = withStatus(metaClaimedBy(plan.meta, current), desiredStatus);
    writePlanIfChanged(plan.filePath, plan.meta, updatedMeta, plan.body);
    console.log(
      [
        `Ensured plan ${planId}.`,
        "  action: takeover",
        `  previous_owner: ${formatClaimSummary(plan.meta)}`,
        `  current_owner: ${formatClaimSummary(updatedMeta)}`,
        `  status: ${updatedMeta.status}`
      ].join("\n"),
    );
    return;
  }

  fail(
    [
      `Cannot ensure plan ${planId}.`,
      `  claimed_by: ${formatClaimSummary(plan.meta)}`,
      `  current:    ${formatCurrentSummary(current)}`,
      "",
      "If this handoff is intentional, run:",
      `  pnpm plan:ensure -- ${planId} --takeover`,
      "",
      "Otherwise coordinate with the current owner first."
    ].join("\n"),
  );
}

function commandStatus(args) {
  const [planId, nextStatus] = args;
  requireArg(planId, "status <plan-id> <status>");
  requireArg(nextStatus, "status <plan-id> <status>");
  assertNoExtraArgs(args.slice(2), "status");

  if (!VALID_STATUSES.has(nextStatus)) {
    fail(`Invalid status: ${nextStatus}\nAllowed: ${Array.from(VALID_STATUSES).join(", ")}`);
  }

  const plan = loadActivePlan(planId);
  writePlan(
    plan.filePath,
    stampUpdatedAt({
      ...plan.meta,
      status: nextStatus
    }),
    plan.body,
  );
  console.log(`Updated ${planId} status -> ${nextStatus}`);
}

function commandArchive(args) {
  const [planId] = args;
  requireArg(planId, "archive <plan-id>");
  assertNoExtraArgs(args.slice(1), "archive");

  ensureDir(archivePlansDir);

  const plan = loadActivePlan(planId);
  const report = buildPlanReport(plan, { strictOwner: false });
  if (report.meta.status !== "complete") {
    fail(
      [
        `Cannot archive ${planId} because status is ${report.meta.status}.`,
        "Set the plan status to `complete` first:",
        `  pnpm plan:status -- ${planId} complete`
      ].join("\n"),
    );
  }

  const archivePath = path.join(archivePlansDir, `${planId}.md`);
  if (fs.existsSync(archivePath)) {
    fail(`Archive destination already exists: ${toRepoRelativePath(archivePath)}`);
  }

  writePlan(plan.filePath, stampUpdatedAt(plan.meta), plan.body);
  fs.renameSync(plan.filePath, archivePath);
  console.log(`Archived ${planId} -> ${toRepoRelativePath(archivePath)}`);
}

function commandHook(args) {
  const [commitMessageFile] = args;
  if (!commitMessageFile || !fs.existsSync(commitMessageFile)) {
    process.exit(0);
  }

  const guardedPrefixes = guardedPrefixes();
  const stagedFiles = stagedFilesInIndex();
  const touchedGuardedFiles = stagedFiles.filter((file) =>
    guardedPrefixes.some((prefix) => file.startsWith(prefix)),
  );

  if (touchedGuardedFiles.length === 0) {
    process.exit(0);
  }

  const commitMessage = fs.readFileSync(commitMessageFile, "utf8");
  const trailer = parsePlanTrailer(commitMessage);

  if (trailer.kind === "missing") {
    const activePlanIds = loadAllActivePlans().map((plan) => plan.id);
    const suggestions =
      activePlanIds.length === 0
        ? `No active plans exist under ${workflowConfig.paths.activePlansDir}.`
        : `Active plans: ${activePlanIds.join(", ")}`;

    failWithMessage([
      "Commit blocked: missing `Plan:` trailer",
      "",
      "Changes staged under guarded paths must bind the commit to exactly one active plan:",
      "  Plan: <plan-id>",
      "",
      `Example: Plan: ${activePlanIds[0] ?? examplePlanId()}`,
      suggestions,
      "",
      "Allowed alternatives:",
      "  Plan: none (trivial)",
      "  Plan: bypass (<reason>)"
    ]);
  }

  if (trailer.kind === "invalid") {
    failWithMessage([
      "Commit blocked: invalid `Plan:` trailer",
      "",
      `Found: ${trailer.found}`,
      "",
      "Accepted forms:",
      "  Plan: <plan-id>",
      "  Plan: none (trivial)",
      "  Plan: bypass (<reason>)"
    ]);
  }

  if (trailer.kind === "none") {
    logBypass("none (trivial)", "-");
    console.log('Plan gate bypassed: "none (trivial)" - logged to .harness-engineering/plan-bypass.log');
    process.exit(0);
  }

  if (trailer.kind === "bypass") {
    logBypass("bypass", trailer.reason);
    console.log(`Plan gate bypassed: "${trailer.reason}" - logged to .harness-engineering/plan-bypass.log`);
    process.exit(0);
  }

  const plan = loadActivePlan(trailer.id);
  const report = buildPlanReport(plan, { strictOwner: true });

  if (report.errors.length > 0) {
    const lines = [
      `Commit blocked: plan ${trailer.id} is not commit-ready`,
      "",
      `Plan file: ${toRepoRelativePath(plan.filePath)}`,
      "",
      "Issues:",
      ...report.errors.map((issue) => `  - ${issue}`)
    ];

    if (report.warnings.length > 0) {
      lines.push("", "Warnings:");
      lines.push(...report.warnings.map((warning) => `  - ${warning}`));
    }

    lines.push(
      "",
      "Useful commands:",
      `  pnpm plan:ensure -- ${trailer.id}`,
      `  pnpm plan:ensure -- ${trailer.id} --takeover`,
      `  pnpm plan:check -- ${trailer.id} --strict-owner`,
    );

    failWithMessage(lines);
  }

  process.exit(0);
}

function buildPlanReport(plan, { strictOwner }) {
  const errors = [];
  const warnings = [];
  const meta = plan.meta;

  if (!plan.hasFrontMatter) {
    errors.push("Missing YAML front matter at the top of the plan file.");
  }

  for (const key of REQUIRED_META_KEYS) {
    if (!(key in meta) || meta[key] === "") {
      errors.push(`Missing metadata key: ${key}`);
    }
  }

  if (meta.story_id && meta.story_id !== plan.id) {
    errors.push(`story_id (${meta.story_id}) does not match plan filename (${plan.id}).`);
  }

  if (meta.status && !VALID_STATUSES.has(meta.status)) {
    errors.push(`Invalid status "${meta.status}". Allowed: ${Array.from(VALID_STATUSES).join(", ")}`);
  }

  if (meta.work_type && !VALID_WORK_TYPES.has(meta.work_type)) {
    errors.push(`Invalid work_type "${meta.work_type}". Allowed: ${Array.from(VALID_WORK_TYPES).join(", ")}`);
  }

  if (meta.review_gate && !VALID_REVIEW_GATES.has(meta.review_gate)) {
    errors.push(`Invalid review_gate "${meta.review_gate}". Allowed: ${Array.from(VALID_REVIEW_GATES).join(", ")}`);
  }

  if (meta.work_type === "mvp") {
    if (!workflowConfig.paths.trackerRoot) {
      errors.push("This repo profile does not define a tracker root, so work_type `mvp` is not valid here.");
    } else if (meta.tracker_target === "none") {
      errors.push("MVP plans must point tracker_target at the tracker file, not `none`.");
    }
  }

  if (
    meta.work_type &&
    ["harness", "docs", "ops", "spike"].includes(meta.work_type) &&
    meta.tracker_target &&
    meta.tracker_target !== "none"
  ) {
    errors.push(`${meta.work_type} plans must use tracker_target: none.`);
  }

  const compliance = complianceStatus(plan.body);
  if (!compliance.exists) {
    errors.push("Missing `## Compliance Check` section.");
  }

  if (compliance.unchecked.length > 0) {
    errors.push(`Compliance Check still has unchecked item(s): ${compliance.unchecked.join(" | ")}`);
  }

  const openAmbiguities = openAmbiguityLines(plan.body);
  if (openAmbiguities.length > 0) {
    errors.push(`Ambiguities section still contains OPEN item(s): ${openAmbiguities.join(" | ")}`);
  }

  if (meta.status === "complete") {
    errors.push("Completed plans must be archived before more guarded commits are made.");
  }

  const claimMissing = claimFields(meta).some((entry) => isUnclaimed(entry.value));
  if (claimMissing) {
    warnings.push(`Plan is unclaimed. Run \`pnpm plan:ensure -- ${plan.id}\` before guarded commits.`);
  }

  const branchConflicts = branchConflictsForPlan(plan);
  if (branchConflicts.length > 0) {
    errors.push(
      [
        "Another active plan claims the same branch with a different owner:",
        ...branchConflicts.map((conflict) => `${conflict.id} (${conflict.meta.owner_email})`)
      ].join(" "),
    );
  }

  if (strictOwner) {
    const current = currentContext();

    if (claimMissing) {
      errors.push("Plan ownership metadata is incomplete or still `unclaimed`.");
    } else {
      if (meta.owner_email !== current.ownerEmail) {
        errors.push(
          `owner_email mismatch: plan has ${meta.owner_email}, current git user.email is ${current.ownerEmail || "<empty>"}.`,
        );
      }
      if (meta.branch !== current.branch) {
        errors.push(`branch mismatch: plan has ${meta.branch}, current branch is ${current.branch}.`);
      }
    }
  }

  return {
    id: plan.id,
    file: toRepoRelativePath(plan.filePath),
    meta,
    compliance: {
      exists: compliance.exists,
      complete: compliance.exists && compliance.unchecked.length === 0,
      unchecked: compliance.unchecked
    },
    open_ambiguities: openAmbiguities,
    errors,
    warnings
  };
}

function summarizePlan(report) {
  return {
    id: report.id,
    status: report.meta.status ?? "<missing>",
    work_type: report.meta.work_type ?? "<missing>",
    owner_email: report.meta.owner_email ?? "<missing>",
    branch: report.meta.branch ?? "<missing>",
    tracker_target: report.meta.tracker_target ?? "<missing>",
    ready_for_commit: report.errors.length === 0
  };
}

function printPlanReport(report) {
  console.log(`Plan ${report.id}`);
  console.log(`  file: ${report.file}`);
  console.log(`  status: ${report.meta.status ?? "<missing>"}`);
  console.log(`  work_type: ${report.meta.work_type ?? "<missing>"}`);
  console.log(`  owner_name: ${report.meta.owner_name ?? "<missing>"}`);
  console.log(`  owner_email: ${report.meta.owner_email ?? "<missing>"}`);
  console.log(`  branch: ${report.meta.branch ?? "<missing>"}`);
  console.log(`  review_gate: ${report.meta.review_gate ?? "<missing>"}`);
  console.log(`  tracker_target: ${report.meta.tracker_target ?? "<missing>"}`);
  console.log(
    `  compliance: ${
      report.compliance.exists ? (report.compliance.complete ? "complete" : "incomplete") : "missing"
    }`,
  );

  if (report.open_ambiguities.length > 0) {
    console.log(`  OPEN ambiguities: ${report.open_ambiguities.join(" | ")}`);
  }

  if (report.errors.length === 0) {
    console.log("  errors: none");
  } else {
    console.log("  errors:");
    for (const error of report.errors) {
      console.log(`    - ${error}`);
    }
  }

  if (report.warnings.length === 0) {
    console.log("  warnings: none");
  } else {
    console.log("  warnings:");
    for (const warning of report.warnings) {
      console.log(`    - ${warning}`);
    }
  }
}

function resolveRepoRoot() {
  if (process.env.PLAN_REPO_ROOT) {
    return path.resolve(process.env.PLAN_REPO_ROOT);
  }

  const fromGit = gitOutput(["rev-parse", "--show-toplevel"], process.cwd());
  if (fromGit) {
    return path.resolve(fromGit);
  }

  let current = process.cwd();
  while (true) {
    if (fs.existsSync(path.join(current, ".harness-engineering", "setup.json"))) {
      return current;
    }

    const parent = path.dirname(current);
    if (parent === current) {
      break;
    }
    current = parent;
  }

  fail("Could not determine repo root. Run this command from the repo or via the wrapper scripts.");
}

function loadWorkflowConfig() {
  const configPath = path.join(repoRoot, ".harness-engineering", "setup.json");
  if (!fs.existsSync(configPath)) {
    fail(`Workflow config missing: ${toRepoRelativePath(configPath)}`);
  }

  const config = JSON.parse(fs.readFileSync(configPath, "utf8"));
  if (!config.paths?.activePlansDir || !config.paths?.archivePlansDir) {
    fail("Workflow config is missing required paths.* entries.");
  }
  return config;
}

function loadAllActivePlans() {
  ensureDir(activePlansDir);
  return fs
    .readdirSync(activePlansDir, { withFileTypes: true })
    .filter((entry) => entry.isFile() && entry.name.endsWith(".md"))
    .filter((entry) => entry.name !== ".gitkeep")
    .map((entry) => loadPlanFile(path.join(activePlansDir, entry.name)))
    .sort((left, right) => left.id.localeCompare(right.id));
}

function loadActivePlan(planId) {
  const planPath = path.join(activePlansDir, `${planId}.md`);
  if (!fs.existsSync(planPath)) {
    fail(
      [
        `Active plan not found: ${workflowConfig.paths.activePlansDir}/${planId}.md`,
        "Create the plan first or use one of the active plan ids from `pnpm plan:list`."
      ].join("\n"),
    );
  }
  return loadPlanFile(planPath);
}

function loadPlanFile(filePath) {
  const raw = fs.readFileSync(filePath, "utf8");
  const parsed = parseFrontMatter(raw);
  return {
    id: path.basename(filePath, ".md"),
    filePath,
    raw,
    meta: parsed.meta,
    body: parsed.body,
    hasFrontMatter: parsed.hasFrontMatter
  };
}

function parseFrontMatter(raw) {
  const match = raw.match(/^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/);
  if (!match) {
    return {
      hasFrontMatter: false,
      meta: {},
      body: raw
    };
  }

  const meta = {};
  for (const line of match[1].split(/\r?\n/)) {
    if (!line.trim()) {
      continue;
    }
    const entry = line.match(/^([A-Za-z0-9_]+):\s*(.*)$/);
    if (!entry) {
      continue;
    }
    meta[entry[1]] = unquote(entry[2].trim());
  }

  return {
    hasFrontMatter: true,
    meta,
    body: match[2]
  };
}

function writePlan(filePath, meta, body) {
  const normalizedMeta = stripDeprecatedOwnershipFields(meta);
  const extraKeys = Object.keys(normalizedMeta)
    .filter((key) => !META_KEY_ORDER.includes(key))
    .sort((left, right) => left.localeCompare(right));

  const lines = ["---"];
  for (const key of [...META_KEY_ORDER, ...extraKeys]) {
    if (!(key in normalizedMeta)) {
      continue;
    }
    lines.push(`${key}: ${String(normalizedMeta[key])}`);
  }
  lines.push("---", "");

  const normalizedBody = body.replace(/^\r?\n/, "");
  fs.writeFileSync(filePath, `${lines.join("\n")}${normalizedBody}`, "utf8");
}

function writePlanIfChanged(filePath, previousMeta, nextMeta, body) {
  if (stableStringifyMeta(previousMeta) === stableStringifyMeta(nextMeta)) {
    return false;
  }
  writePlan(filePath, stampUpdatedAt(nextMeta), body);
  return true;
}

function stableStringifyMeta(meta) {
  const normalizedMeta = stripDeprecatedOwnershipFields(meta);
  const ordered = {};
  for (const key of [
    ...META_KEY_ORDER,
    ...Object.keys(normalizedMeta).sort((left, right) => left.localeCompare(right))
  ]) {
    if (!(key in normalizedMeta) || key in ordered) {
      continue;
    }
    ordered[key] = normalizedMeta[key];
  }
  return JSON.stringify(ordered);
}

function claimFields(meta) {
  return [
    { key: "owner_name", value: meta.owner_name },
    { key: "owner_email", value: meta.owner_email },
    { key: "branch", value: meta.branch }
  ];
}

function complianceStatus(body) {
  const section = sectionLines(body, "Compliance Check");
  if (!section.exists) {
    return { exists: false, unchecked: [] };
  }

  return {
    exists: true,
    unchecked: section.lines
      .map((line) => line.trim())
      .filter((line) => /^- \[ \]/.test(line))
  };
}

function openAmbiguityLines(body) {
  const section = sectionLines(body, "Ambiguities");
  if (!section.exists) {
    return [];
  }

  return section.lines
    .map((line) => line.trim())
    .filter((line) => /\bOPEN\b/.test(line));
}

function sectionLines(body, heading) {
  const lines = body.split(/\r?\n/);
  const headingLine = `## ${heading}`;
  const startIndex = lines.findIndex((line) => line.trim() === headingLine);
  if (startIndex === -1) {
    return { exists: false, lines: [] };
  }

  const collected = [];
  for (let index = startIndex + 1; index < lines.length; index += 1) {
    if (lines[index].startsWith("## ")) {
      break;
    }
    collected.push(lines[index]);
  }

  return { exists: true, lines: collected };
}

function branchConflictsForPlan(plan) {
  const branch = plan.meta.branch;
  const ownerEmail = plan.meta.owner_email;
  if (isUnclaimed(branch) || isUnclaimed(ownerEmail)) {
    return [];
  }

  return loadAllActivePlans().filter((other) => {
    if (other.id === plan.id) {
      return false;
    }
    if (other.meta.status === "complete") {
      return false;
    }
    return other.meta.branch === branch && other.meta.owner_email !== ownerEmail;
  });
}

function parsePlanTrailer(message) {
  const matches = message
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter((line) => line.startsWith("Plan:"));

  if (matches.length === 0) {
    return { kind: "missing" };
  }
  if (matches.length > 1) {
    return { kind: "invalid", found: matches.join(" | ") };
  }

  const [line] = matches;
  if (/^Plan: none \(trivial\)$/.test(line)) {
    return { kind: "none" };
  }

  const bypass = line.match(/^Plan: bypass \((.+)\)$/);
  if (bypass) {
    return { kind: "bypass", reason: bypass[1] };
  }

  const normal = line.match(/^Plan:\s+([A-Za-z0-9._-]+)$/);
  if (normal) {
    return { kind: "plan", id: normal[1] };
  }

  return { kind: "invalid", found: line };
}

function logBypass(kind, reason) {
  ensureDir(path.dirname(bypassLogPath));
  fs.appendFileSync(bypassLogPath, `${localTimestamp()} | ${kind} | ${reason}\n`, "utf8");
}

function stagedFilesInIndex() {
  const output = process.env.PLAN_STAGED_FILES || gitOutput(["diff", "--cached", "--name-only"], repoRoot);
  return output
    .split(/\r?\n/)
    .map((line) => line.trim())
    .filter(Boolean)
    .map((line) => line.replace(/\\/g, "/"));
}

function guardedPrefixes() {
  const source = process.env.PLAN_GUARDED_PREFIXES
    ? process.env.PLAN_GUARDED_PREFIXES.split(",")
    : workflowConfig.guardedPaths;
  return source
    .map((value) => value.trim())
    .filter(Boolean)
    .map((value) => value.replace(/\\/g, "/"));
}

function currentContext() {
  return {
    ownerName: process.env.PLAN_GIT_USER_NAME || gitOutput(["config", "--get", "user.name"], repoRoot),
    ownerEmail: process.env.PLAN_GIT_USER_EMAIL || gitOutput(["config", "--get", "user.email"], repoRoot),
    branch:
      process.env.PLAN_GIT_BRANCH || gitOutput(["rev-parse", "--abbrev-ref", "HEAD"], repoRoot) || "detached"
  };
}

function ensureOwnerEmail(ownerEmail) {
  if (!ownerEmail) {
    fail(
      [
        "Cannot claim the plan because `git config user.email` is empty.",
        "Either set git user.email or pass `--email <value>` to `pnpm plan:claim`."
      ].join("\n"),
    );
  }
}

function metaClaimedBy(meta, current, overrides = {}) {
  const ownerEmail = overrides.ownerEmail ?? current.ownerEmail;
  const ownerName = firstNonEmptyValue(
    overrides.ownerName,
    current.ownerName,
    meta.owner_name,
    ownerEmail,
    "unclaimed",
  );
  const branch = overrides.branch ?? current.branch;

  ensureOwnerEmail(ownerEmail);

  return {
    ...stripDeprecatedOwnershipFields(meta),
    owner_name: ownerName || "unclaimed",
    owner_email: ownerEmail,
    branch: branch || "unclaimed"
  };
}

function withStatus(meta, status) {
  return {
    ...meta,
    status
  };
}

function stampUpdatedAt(meta) {
  return {
    ...meta,
    updated_at: localTimestamp()
  };
}

function comparePlanOwnership(meta, current) {
  const claimMissing = claimFields(meta).some((entry) => isUnclaimed(entry.value));
  const sameEmail = meta.owner_email === current.ownerEmail;
  return {
    claimMissing,
    sameEmail,
    sameOwnerContext: sameEmail
  };
}

function formatClaimSummary(meta) {
  return [meta.owner_name || "<empty>", meta.owner_email || "<empty>", meta.branch || "<empty>"].join(" / ");
}

function formatCurrentSummary(current) {
  return [current.ownerName || "<empty>", current.ownerEmail || "<empty>", current.branch || "<empty>"].join(" / ");
}

function stripDeprecatedOwnershipFields(meta) {
  const { owner_machine: _ownerMachine, owner_os_user: _ownerOsUser, ...rest } = meta;
  return rest;
}

function firstNonEmptyValue(...values) {
  for (const value of values) {
    if (typeof value === "string" && value.trim() !== "") {
      return value;
    }
    if (value !== undefined && value !== null && value !== "") {
      return value;
    }
  }
  return "";
}

function gitOutput(args, cwd) {
  try {
    return execFileSync("git", args, {
      cwd,
      encoding: "utf8",
      stdio: ["ignore", "pipe", "ignore"]
    }).trim();
  } catch (_error) {
    return "";
  }
}

function takeBooleanFlag(args, flag) {
  const index = args.indexOf(flag);
  if (index === -1) {
    return false;
  }
  args.splice(index, 1);
  return true;
}

function parseOptions(args) {
  const options = {};
  const positionals = [];

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];
    if (!arg.startsWith("--")) {
      positionals.push(arg);
      continue;
    }

    const key = arg.slice(2);
    const value = args[index + 1];
    if (!value || value.startsWith("--")) {
      fail(`Missing value for option --${key}`);
    }
    options[key] = value;
    index += 1;
  }

  return { options, positionals };
}

function printTable(headers, rows) {
  const widths = headers.map((header, column) =>
    Math.max(header.length, ...rows.map((row) => row[column].length)),
  );

  console.log(headers.map((header, column) => header.padEnd(widths[column], " ")).join("  "));
  console.log(widths.map((width) => "-".repeat(width)).join("  "));
  for (const row of rows) {
    console.log(row.map((cell, column) => cell.padEnd(widths[column], " ")).join("  "));
  }
}

function toRepoRelativePath(filePath) {
  return path.relative(repoRoot, filePath).replace(/\\/g, "/");
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function requireArg(value, usage) {
  if (!value) {
    fail(`Usage: plan ${usage}`);
  }
}

function assertNoExtraArgs(args, command) {
  if (args.length > 0) {
    fail(`Usage: plan ${command}`);
  }
}

function unquote(value) {
  if (
    (value.startsWith('"') && value.endsWith('"')) ||
    (value.startsWith("'") && value.endsWith("'"))
  ) {
    return value.slice(1, -1);
  }
  return value;
}

function isUnclaimed(value) {
  return !value || value === "unclaimed";
}

function localTimestamp() {
  const parts = new Intl.DateTimeFormat("en-CA", {
    year: "numeric",
    month: "2-digit",
    day: "2-digit",
    hour: "2-digit",
    minute: "2-digit",
    hour12: false,
    timeZoneName: "short"
  }).formatToParts(new Date());

  const map = Object.fromEntries(parts.map((part) => [part.type, part.value]));
  return `${map.year}-${map.month}-${map.day} ${map.hour}:${map.minute} ${map.timeZoneName}`;
}

function failWithMessage(lines) {
  console.error(lines.join("\n"));
  process.exit(1);
}

function fail(message) {
  console.error(message);
  process.exit(1);
}

function helpText() {
  return [
    "Usage: pnpm plan -- <command>",
    "",
    "Commands:",
    "  list [--json]                         List active plans",
    "  show <plan-id> [--json]              Show one active plan",
    "  check [plan-id] [--json] [--strict-owner]",
    "                                       Validate active plan metadata and readiness",
    "  ensure <plan-id> [--status STATUS] [--takeover]",
    "                                       Claim if unclaimed, verify if already yours, or fail on owner mismatch",
    "  claim <plan-id> [--owner NAME] [--email EMAIL] [--branch BRANCH]",
    "                                       Claim plan ownership for the current user",
    "  status <plan-id> <status>            Update plan status",
    "  archive <plan-id>                    Move a completed plan from active to archive",
    "  hook <commit-msg-file>               Commit-msg hook entrypoint",
    "",
    "Status values:",
    `  ${Array.from(VALID_STATUSES).join(", ")}`,
    "",
    "Normal guarded commit trailer:",
    "  Plan: <plan-id>",
    "",
    "Bypass trailers:",
    "  Plan: none (trivial)",
    "  Plan: bypass (<reason>)",
    "",
    "Example:",
    `  pnpm plan:ensure -- ${examplePlanId()}`,
    `  pnpm plan:ensure -- ${examplePlanId()} --takeover`,
    "",
    "Repo config:",
    "  .harness-engineering/setup.json"
  ].join("\n");
}

function printHelp(exitCode) {
  console.log(helpText());
  process.exit(exitCode);
}

function examplePlanId() {
  return workflowConfig.profile === "mvp" ? "s1.8" : "task-1";
}
