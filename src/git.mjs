import { spawnSync } from "node:child_process";

function runGit(args, cwd) {
  return spawnSync("git", args, {
    cwd,
    encoding: "utf8"
  });
}

export function isGitAvailable() {
  return runGit(["--version"], process.cwd()).status === 0;
}

export function isGitRepo(targetDir) {
  const result = runGit(["rev-parse", "--is-inside-work-tree"], targetDir);
  return result.status === 0;
}

export function initGitRepo(targetDir) {
  const result = runGit(["init"], targetDir);
  return {
    ok: result.status === 0,
    stderr: (result.stderr || "").trim()
  };
}
