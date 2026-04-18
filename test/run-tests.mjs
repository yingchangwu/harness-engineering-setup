import assert from "node:assert/strict";
import fs from "node:fs";
import os from "node:os";
import path from "node:path";

import { doctorRepository } from "../src/doctor.mjs";
import { scaffoldRepository } from "../src/scaffold.mjs";

const testBaseDir = process.env.HARNESS_SETUP_TEST_DIR
  ? path.resolve(process.env.HARNESS_SETUP_TEST_DIR)
  : fs.mkdtempSync(path.join(os.tmpdir(), "harness-engineering-setup-"));

function newWorkspace(name) {
  const dir = path.join(testBaseDir, `${Date.now()}-${Math.random().toString(16).slice(2)}-${name}`);
  fs.mkdirSync(dir, { recursive: true });
  return dir;
}

function run(name, fn) {
  try {
    fn();
    console.log(`PASS  ${name}`);
  } catch (error) {
    console.error(`FAIL  ${name}`);
    console.error(error.stack || error.message);
    process.exitCode = 1;
  }
}

run("init generic scaffolds the generic layout", () => {
  const targetDir = path.join(newWorkspace("generic"), "repo");
  const result = scaffoldRepository({
    targetDir,
    workflowVersion: "0.1.0",
    profile: "generic",
    agents: "codex,claude",
    guardedPaths: "src/",
    mode: "init",
    gitInit: false
  });

  assert.equal(result.workflowConfig.profile, "generic");
  assert.equal(result.workflowConfig.paths.activePlansDir, "docs/plans/active");
  assert.equal(result.workflowConfig.paths.archivePlansDir, "docs/plans/archive");
  assert.equal(result.workflowConfig.paths.trackerRoot, null);
  assert.ok(fs.existsSync(path.join(targetDir, "docs", "plans", "active")));
  assert.ok(fs.existsSync(path.join(targetDir, ".codex", "agents", "planner.toml")));
  assert.ok(fs.existsSync(path.join(targetDir, ".claude", "agents", "planner.md")));
});

run("init mvp scaffolds the mvp layout", () => {
  const targetDir = path.join(newWorkspace("mvp"), "repo");
  const result = scaffoldRepository({
    targetDir,
    workflowVersion: "0.1.0",
    profile: "mvp",
    agents: "codex",
    guardedPaths: "src/",
    mode: "init",
    gitInit: false
  });

  assert.equal(result.workflowConfig.profile, "mvp");
  assert.equal(result.workflowConfig.paths.activePlansDir, "docs/mvp/plans/active");
  assert.equal(result.workflowConfig.paths.archivePlansDir, "docs/mvp/plans/archive");
  assert.equal(result.workflowConfig.paths.trackerRoot, "docs/mvp/tracker");
  assert.ok(fs.existsSync(path.join(targetDir, "docs", "mvp", "plans", "active")));
  assert.ok(fs.existsSync(path.join(targetDir, "docs", "mvp", "tracker")));
  assert.ok(fs.existsSync(path.join(targetDir, ".codex", "agents", "planner.toml")));
  assert.ok(!fs.existsSync(path.join(targetDir, ".claude")));
});

run("adopt preserves existing package scripts while adding plan scripts", () => {
  const targetDir = path.join(newWorkspace("adopt"), "repo");
  fs.mkdirSync(targetDir, { recursive: true });
  fs.writeFileSync(
    path.join(targetDir, "package.json"),
    JSON.stringify(
      {
        name: "existing-repo",
        scripts: {
          lint: "eslint ."
        }
      },
      null,
      2,
    ),
    "utf8",
  );

  scaffoldRepository({
    targetDir,
    workflowVersion: "0.1.0",
    profile: "generic",
    agents: "codex",
    guardedPaths: "src/",
    mode: "adopt",
    force: true,
    gitInit: false
  });

  const packageJson = JSON.parse(fs.readFileSync(path.join(targetDir, "package.json"), "utf8"));
  assert.equal(packageJson.scripts.lint, "eslint .");
  assert.equal(packageJson.scripts["plan:ensure"], "node scripts/plan.mjs ensure");
});

run("doctor reports the scaffolded files", () => {
  const targetDir = path.join(newWorkspace("doctor"), "repo");
  scaffoldRepository({
    targetDir,
    workflowVersion: "0.1.0",
    profile: "generic",
    agents: "codex",
    guardedPaths: "src/",
    mode: "init",
    gitInit: false
  });

  const report = doctorRepository(targetDir);
  assert.equal(report.checks.some((check) => check.name === "workflow config" && check.ok), true);
  assert.equal(report.checks.some((check) => check.name === "scripts/plan.mjs" && check.ok), true);
  assert.equal(report.checks.some((check) => check.name === "package.json:plan:ensure" && check.ok), true);
});

if (process.exitCode) {
  process.exit(process.exitCode);
}
