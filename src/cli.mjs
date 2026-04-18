import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import { doctorRepository, formatDoctorReport } from "./doctor.mjs";
import { listProfiles } from "./profile-config.mjs";
import { scaffoldRepository } from "./scaffold.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const packageJson = JSON.parse(
  fs.readFileSync(path.resolve(__dirname, "..", "package.json"), "utf8"),
);

export function runCli(argv) {
  const [command, ...rest] = argv;

  if (!command || command === "help" || command === "--help" || command === "-h") {
    printHelp(0);
  }

  if (command === "--version" || command === "-v" || command === "version") {
    console.log(packageJson.version);
    return;
  }

  try {
    switch (command) {
      case "init":
        runInit(rest);
        return;
      case "adopt":
        runAdopt(rest);
        return;
      case "doctor":
        runDoctor(rest);
        return;
      default:
        throw new Error(`Unknown command: ${command}`);
    }
  } catch (error) {
    console.error(error.message);
    process.exit(1);
  }
}

function runInit(args) {
  const options = parseCommandOptions(args, {
    defaultTarget: ".",
    requireTarget: false,
    defaultGitInit: true
  });

  const result = scaffoldRepository({
    targetDir: options.targetDir,
    workflowVersion: packageJson.version,
    profile: options.profile,
    agents: options.agents,
    guardedPaths: options.guardedPaths,
    mode: "init",
    force: options.force || !options.targetProvided,
    repoName: options.repoName,
    gitInit: options.gitInit
  });

  printScaffoldSummary("Initialized", result);
}

function runAdopt(args) {
  const options = parseCommandOptions(args, {
    defaultTarget: ".",
    requireTarget: false,
    defaultGitInit: true
  });

  const result = scaffoldRepository({
    targetDir: options.targetDir,
    workflowVersion: packageJson.version,
    profile: options.profile,
    agents: options.agents,
    guardedPaths: options.guardedPaths,
    mode: "adopt",
    force: true,
    repoName: options.repoName,
    gitInit: options.gitInit
  });

  printScaffoldSummary("Adopted", result);
}

function runDoctor(args) {
  const options = parseCommandOptions(args, {
    defaultTarget: ".",
    requireTarget: false,
    defaultGitInit: true
  });
  const report = doctorRepository(options.targetDir);
  console.log(formatDoctorReport(report));
  process.exit(report.ok ? 0 : 1);
}

function parseCommandOptions(args, defaults) {
  const options = {
    targetDir: defaults.defaultTarget,
    targetProvided: false,
    profile: "generic",
    agents: "codex,claude",
    guardedPaths: "src/",
    force: false,
    repoName: "",
    gitInit: defaults.defaultGitInit
  };

  for (let index = 0; index < args.length; index += 1) {
    const arg = args[index];

    if (arg === "--profile") {
      options.profile = requireValue(args[++index], "--profile");
      continue;
    }

    if (arg === "--agents") {
      options.agents = requireValue(args[++index], "--agents");
      continue;
    }

    if (arg === "--guarded") {
      options.guardedPaths = requireValue(args[++index], "--guarded");
      continue;
    }

    if (arg === "--repo-name") {
      options.repoName = requireValue(args[++index], "--repo-name");
      continue;
    }

    if (arg === "--force") {
      options.force = true;
      continue;
    }

    if (arg === "--git-init") {
      options.gitInit = true;
      continue;
    }

    if (arg === "--no-git-init") {
      options.gitInit = false;
      continue;
    }

    if (arg.startsWith("--")) {
      throw new Error(`Unknown option: ${arg}`);
    }

    if (options.targetProvided) {
      throw new Error(`Unexpected extra argument: ${arg}`);
    }
    options.targetDir = arg;
    options.targetProvided = true;
  }

  if (defaults.requireTarget && !options.targetDir) {
    throw new Error("A target directory is required.");
  }

  if (!options.targetDir) {
    options.targetDir = ".";
  }

  return options;
}

function requireValue(value, optionName) {
  if (!value || value.startsWith("--")) {
    throw new Error(`Missing value for ${optionName}`);
  }
  return value;
}

function printScaffoldSummary(label, result) {
  console.log(`${label} harness-engineering workflow in ${result.absoluteTargetDir}`);
  console.log(`  profile: ${result.workflowConfig.profile}`);
  console.log(`  agents: ${result.workflowConfig.agents.join(", ")}`);
  console.log(`  guarded paths: ${result.workflowConfig.guardedPaths.join(", ")}`);
  console.log(`  active plans: ${result.workflowConfig.paths.activePlansDir}`);
  console.log(`  archive plans: ${result.workflowConfig.paths.archivePlansDir}`);
  if (result.workflowConfig.paths.trackerRoot) {
    console.log(`  tracker root: ${result.workflowConfig.paths.trackerRoot}`);
  }
  console.log(`  files written: ${result.writtenFiles.length}`);
  console.log(`  git: ${result.gitResult.message}`);
}

function printHelp(exitCode) {
  console.log(
    [
      `he-setup ${packageJson.version}`,
      "",
      "Usage:",
      "  he-setup init [target-dir] [options]",
      "  he-setup adopt [target-dir] [options]",
      "  he-setup doctor [target-dir]",
      "",
      "Options:",
      `  --profile <name>        ${listProfiles().join(" | ")} (default: generic)`,
      "  --agents <list>         comma-separated: codex, claude (default: codex,claude)",
      "  --guarded <list>        comma-separated guarded paths (default: src/)",
      "  --repo-name <name>      override derived repo name",
      "  --force                 allow init into a non-empty directory",
      "  --git-init              initialize git if needed",
      "  --no-git-init           skip git init if the repo does not exist yet",
      "",
      "Examples:",
      "  he-setup init",
      "  he-setup init --profile mvp --agents codex,claude",
      "  he-setup adopt",
      "  he-setup doctor",
      "  he-setup init ../my-solution --profile generic"
    ].join("\n"),
  );
  process.exit(exitCode);
}
