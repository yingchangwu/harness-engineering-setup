import fs from "node:fs";
import path from "node:path";

import { isGitAvailable, isGitRepo } from "./git.mjs";
import { managedRelativePathsForConfig } from "./scaffold.mjs";

export function doctorRepository(targetDir) {
  const absoluteTargetDir = path.resolve(targetDir);
  const checks = [];
  let config = null;

  const configPath = path.join(absoluteTargetDir, ".harness-engineering", "setup.json");
  if (!fs.existsSync(configPath)) {
    checks.push(fail("workflow config", ".harness-engineering/setup.json is missing"));
    return { ok: false, checks };
  }

  try {
    config = JSON.parse(fs.readFileSync(configPath, "utf8"));
    checks.push(pass("workflow config", ".harness-engineering/setup.json parsed"));
  } catch (error) {
    checks.push(fail("workflow config", error.message));
    return { ok: false, checks };
  }

  for (const relativePath of managedRelativePathsForConfig(config)) {
    const absolutePath = path.join(absoluteTargetDir, relativePath);
    if (fs.existsSync(absolutePath)) {
      checks.push(pass(relativePath, "present"));
    } else {
      checks.push(fail(relativePath, "missing"));
    }
  }

  const packagePath = path.join(absoluteTargetDir, "package.json");
  if (fs.existsSync(packagePath)) {
    const packageJson = JSON.parse(fs.readFileSync(packagePath, "utf8"));
    const requiredScripts = [
      "plan",
      "plan:list",
      "plan:show",
      "plan:check",
      "plan:ensure",
      "plan:claim",
      "plan:status",
      "plan:archive"
    ];
    for (const script of requiredScripts) {
      if (packageJson.scripts?.[script]) {
        checks.push(pass(`package.json:${script}`, "script present"));
      } else {
        checks.push(fail(`package.json:${script}`, "script missing"));
      }
    }
  } else {
    checks.push(fail("package.json", "missing"));
  }

  const activePlansDir = path.join(absoluteTargetDir, config.paths.activePlansDir);
  const archivePlansDir = path.join(absoluteTargetDir, config.paths.archivePlansDir);
  checks.push(fs.existsSync(activePlansDir) ? pass(config.paths.activePlansDir, "present") : fail(config.paths.activePlansDir, "missing"));
  checks.push(fs.existsSync(archivePlansDir) ? pass(config.paths.archivePlansDir, "present") : fail(config.paths.archivePlansDir, "missing"));

  if (config.paths.trackerRoot) {
    const trackerRoot = path.join(absoluteTargetDir, config.paths.trackerRoot);
    checks.push(fs.existsSync(trackerRoot) ? pass(config.paths.trackerRoot, "present") : fail(config.paths.trackerRoot, "missing"));
  }

  if (!isGitAvailable()) {
    checks.push(pass("git", "git is not available on PATH"));
  } else if (!isGitRepo(absoluteTargetDir)) {
    checks.push(pass("git repo", "directory is not a git repository"));
  } else {
    checks.push(pass("git repo", "repository detected"));
  }

  return {
    ok: checks.every((check) => check.ok),
    checks
  };
}

export function formatDoctorReport(report) {
  return report.checks
    .map((check) => `${check.ok ? "PASS" : "FAIL"}  ${check.name} - ${check.detail}`)
    .join("\n");
}

function pass(name, detail) {
  return { ok: true, name, detail };
}

function fail(name, detail) {
  return { ok: false, name, detail };
}
