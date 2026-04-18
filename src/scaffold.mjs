import fs from "node:fs";
import path from "node:path";
import { fileURLToPath } from "node:url";

import {
  buildTemplateContext,
  buildWorkflowConfig,
  normalizeAgents,
  normalizeGuardedPaths,
  normalizeProfile
} from "./profile-config.mjs";
import {
  initGitRepo,
  isGitAvailable,
  isGitRepo
} from "./git.mjs";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const templatesRoot = path.resolve(__dirname, "..", "templates");
const TEMPLATE_TOKEN_PATTERN = /%%([A-Z0-9_]+)%%/g;
const LEGACY_REMOVED_PATHS = [
  ".githooks/commit-msg",
  ".harness-engineering/plan-bypass.log",
  "scripts/hooks/install.sh",
  "scripts/hooks/plan-gate.sh"
];

export function scaffoldRepository({
  targetDir,
  workflowVersion,
  profile,
  agents,
  guardedPaths,
  mode,
  force = false,
  repoName,
  gitInit = true
}) {
  const absoluteTargetDir = path.resolve(targetDir);
  const normalizedProfile = normalizeProfile(profile);
  const normalizedAgents = normalizeAgents(agents);
  const normalizedGuardedPaths = normalizeGuardedPaths(guardedPaths);
  const resolvedRepoName = repoName || path.basename(absoluteTargetDir);

  ensureDir(absoluteTargetDir);

  if (mode === "init" && !force && directoryHasFiles(absoluteTargetDir)) {
    throw new Error(
      `Target directory is not empty: ${absoluteTargetDir}. Use --force or choose another directory.`,
    );
  }

  const workflowConfig = buildWorkflowConfig({
    workflowVersion,
    profile: normalizedProfile,
    agents: normalizedAgents.join(","),
    guardedPaths: normalizedGuardedPaths.join(",")
  });

  const context = buildTemplateContext({
    repoName: resolvedRepoName,
    workflowVersion,
    profile: normalizedProfile,
    agents: normalizedAgents.join(","),
    guardedPaths: normalizedGuardedPaths.join(",")
  });

  const templateDirectories = [
    path.join(templatesRoot, "base"),
    path.join(templatesRoot, "profiles", normalizedProfile),
    ...normalizedAgents.map((agent) => path.join(templatesRoot, "agents", agent))
  ];

  const writtenFiles = [];
  for (const templateDir of templateDirectories) {
    if (!fs.existsSync(templateDir)) {
      continue;
    }

    for (const file of collectTemplateFiles(templateDir)) {
      const relativePath = toDestinationRelativePath(path.relative(templateDir, file));
      const destinationPath = path.join(absoluteTargetDir, relativePath);
      ensureDir(path.dirname(destinationPath));
      const rendered = renderTemplate(fs.readFileSync(file, "utf8"), context);
      fs.writeFileSync(destinationPath, rendered, "utf8");
      writtenFiles.push(relativePath.replace(/\\/g, "/"));
    }
  }

  const configPath = path.join(absoluteTargetDir, ".harness-engineering", "setup.json");
  ensureDir(path.dirname(configPath));
  fs.writeFileSync(configPath, `${JSON.stringify(workflowConfig, null, 2)}\n`, "utf8");
  writtenFiles.push(".harness-engineering/setup.json");

  cleanupLegacyFiles(absoluteTargetDir);
  upsertPackageJson(absoluteTargetDir, resolvedRepoName);

  const gitResult = maybeSetupGit(absoluteTargetDir, gitInit);

  return {
    absoluteTargetDir,
    workflowConfig,
    writtenFiles,
    gitResult
  };
}

export function managedRelativePathsForConfig(config) {
  const context = buildTemplateContext({
    repoName: "placeholder",
    workflowVersion: config.workflowVersion,
    profile: config.profile,
    agents: config.agents.join(","),
    guardedPaths: config.guardedPaths.join(",")
  });

  const directories = [
    path.join(templatesRoot, "base"),
    path.join(templatesRoot, "profiles", config.profile),
    ...config.agents.map((agent) => path.join(templatesRoot, "agents", agent))
  ];

  const paths = new Set([".harness-engineering/setup.json", "package.json"]);
  for (const templateDir of directories) {
    if (!fs.existsSync(templateDir)) {
      continue;
    }
    for (const file of collectTemplateFiles(templateDir)) {
      const relativePath = toDestinationRelativePath(path.relative(templateDir, file));
      const destination = relativePath.replace(/\\/g, "/");
      paths.add(destination);
      if (destination.endsWith(".gitkeep")) {
        continue;
      }

      const rendered = renderTemplate(fs.readFileSync(file, "utf8"), context);
      if (rendered.length === 0) {
        paths.add(destination);
      }
    }
  }
  return [...paths].sort((left, right) => left.localeCompare(right));
}

function maybeSetupGit(targetDir, gitInit) {
  if (!isGitAvailable()) {
    return {
      available: false,
      initialized: false,
      message: "git is not available on PATH"
    };
  }

  let initialized = false;
  if (!isGitRepo(targetDir)) {
    if (!gitInit) {
      return {
        available: true,
        initialized: false,
        message: "git init skipped"
      };
    }

    const initResult = initGitRepo(targetDir);
    if (!initResult.ok) {
      return {
        available: true,
        initialized: false,
        message: initResult.stderr || "git init failed"
      };
    }
    initialized = true;
  }

  return {
    available: true,
    initialized,
    message: initialized ? "git repository initialized" : "git repository detected"
  };
}

function directoryHasFiles(dirPath) {
  if (!fs.existsSync(dirPath)) {
    return false;
  }

  return fs.readdirSync(dirPath).length > 0;
}

function ensureDir(dirPath) {
  fs.mkdirSync(dirPath, { recursive: true });
}

function collectTemplateFiles(rootDir) {
  const files = [];
  const entries = fs.readdirSync(rootDir, { withFileTypes: true });
  for (const entry of entries) {
    const absolutePath = path.join(rootDir, entry.name);
    if (entry.isDirectory()) {
      files.push(...collectTemplateFiles(absolutePath));
      continue;
    }
    if (entry.isFile() && entry.name.endsWith(".tpl")) {
      files.push(absolutePath);
    }
  }
  return files;
}

function toDestinationRelativePath(relativeTemplatePath) {
  return relativeTemplatePath.replace(/\.tpl$/, "");
}

function renderTemplate(template, context) {
  return template.replace(TEMPLATE_TOKEN_PATTERN, (_match, key) => {
    if (!(key in context)) {
      throw new Error(`Missing template value for token %%${key}%%`);
    }
    return context[key];
  });
}

function cleanupLegacyFiles(targetDir) {
  for (const relativePath of LEGACY_REMOVED_PATHS) {
    const absolutePath = path.join(targetDir, relativePath);
    if (!fs.existsSync(absolutePath)) {
      continue;
    }

    const stats = fs.statSync(absolutePath);
    if (stats.isDirectory()) {
      continue;
    }

    fs.unlinkSync(absolutePath);
  }

  removeDirIfEmpty(path.join(targetDir, ".githooks"));
  removeDirIfEmpty(path.join(targetDir, "scripts", "hooks"));
  removeGitignoreEntry(targetDir, "/.harness-engineering/plan-bypass.log");
}

function upsertPackageJson(targetDir, repoName) {
  const packagePath = path.join(targetDir, "package.json");
  const packageJson = fs.existsSync(packagePath)
    ? JSON.parse(fs.readFileSync(packagePath, "utf8"))
    : {};

  if (!packageJson.name) {
    packageJson.name = slugify(repoName);
  }

  if (!("private" in packageJson)) {
    packageJson.private = true;
  }

  packageJson.scripts = {
    ...(packageJson.scripts || {}),
    plan: "node scripts/plan.mjs",
    "plan:list": "node scripts/plan.mjs list",
    "plan:show": "node scripts/plan.mjs show",
    "plan:check": "node scripts/plan.mjs check",
    "plan:ensure": "node scripts/plan.mjs ensure",
    "plan:claim": "node scripts/plan.mjs claim",
    "plan:status": "node scripts/plan.mjs status",
    "plan:archive": "node scripts/plan.mjs archive"
  };

  fs.writeFileSync(packagePath, `${JSON.stringify(packageJson, null, 2)}\n`, "utf8");
}

function slugify(value) {
  return value
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, "-")
    .replace(/^-+|-+$/g, "") || "repo";
}

function removeDirIfEmpty(dirPath) {
  if (!fs.existsSync(dirPath)) {
    return;
  }

  if (fs.readdirSync(dirPath).length === 0) {
    fs.rmdirSync(dirPath);
  }
}

function removeGitignoreEntry(targetDir, entry) {
  const gitignorePath = path.join(targetDir, ".gitignore");
  if (!fs.existsSync(gitignorePath)) {
    return;
  }

  const lines = fs
    .readFileSync(gitignorePath, "utf8")
    .split(/\r?\n/)
    .filter((line) => line !== entry);

  const content = lines.filter((line, index, all) => !(index === all.length - 1 && line === "")).join("\n");
  fs.writeFileSync(gitignorePath, content ? `${content}\n` : "", "utf8");
}
