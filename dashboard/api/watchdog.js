import { handleSchedule } from "@vercel/schedules";

const OWNER = "KULTHX";
const REPO = "Cs16test";
const WORKFLOW = "cs16-public-session.yml";
const BRANCH = "main";
const ACTIVE_STATES = new Set([
  "queued",
  "in_progress",
  "waiting",
  "requested",
  "pending",
]);

function headers(token) {
  return {
    Accept: "application/vnd.github+json",
    Authorization: `Bearer ${token}`,
    "X-GitHub-Api-Version": "2022-11-28",
    "Content-Type": "application/json",
  };
}

async function githubRequest(path, token, options = {}) {
  const response = await fetch(`https://api.github.com/repos/${OWNER}/${REPO}/${path}`, {
    ...options,
    headers: { ...headers(token), ...(options.headers || {}) },
  });

  if (!response.ok) {
    const detail = (await response.text()).slice(0, 500);
    throw new Error(`GitHub API returned ${response.status}: ${detail}`);
  }

  if (response.status === 204) return null;
  return response.json();
}

async function runWatchdog(metadata) {
  const token = process.env.GITHUB_ACTIONS_TOKEN;
  if (!token) {
    throw new Error("Missing GITHUB_ACTIONS_TOKEN in Vercel Production environment.");
  }

  const query = new URLSearchParams({ branch: BRANCH, per_page: "20" });
  const data = await githubRequest(
    `actions/workflows/${encodeURIComponent(WORKFLOW)}/runs?${query.toString()}`,
    token,
  );
  const runs = Array.isArray(data?.workflow_runs) ? data.workflow_runs : [];

  const active = runs.find((run) => ACTIVE_STATES.has(run.status));
  if (active) {
    console.log(JSON.stringify({
      event: "watchdog_session_already_active",
      schedule: metadata.name,
      runId: active.id,
      runStatus: active.status,
    }));
    return;
  }

  // A cancelled run is a stopped session, not a permanent pause.
  // The external watchdog should create a replacement at its next check.

  const completed = runs
    .filter((run) => run.status === "completed")
    .sort((a, b) => Date.parse(b.run_started_at || b.created_at) - Date.parse(a.run_started_at || a.created_at));

  let consecutiveFailures = 0;
  for (const run of completed) {
    if (run.conclusion === "success") break;
    if (["failure", "timed_out", "action_required", "startup_failure"].includes(run.conclusion)) {
      consecutiveFailures += 1;
    } else {
      break;
    }
  }

  // Avoid an infinite retry storm if the workflow has a persistent configuration error.
  if (consecutiveFailures >= 3) {
    console.error(JSON.stringify({
      event: "watchdog_paused_after_repeated_failures",
      schedule: metadata.name,
      consecutiveFailures,
      lastRunId: completed[0]?.id ?? null,
    }));
    return;
  }

  await githubRequest(
    `actions/workflows/${encodeURIComponent(WORKFLOW)}/dispatches`,
    token,
    {
      method: "POST",
      body: JSON.stringify({
        ref: BRANCH,
        inputs: { maxplayers: "20" },
      }),
    },
  );

  console.log(JSON.stringify({
    event: "watchdog_started_new_session",
    schedule: metadata.name,
    scheduledAt: metadata.scheduledAt,
    consecutiveFailures,
    maxplayers: 20,
  }));
}

// Vercel Schedules delivers a private POST invocation to this function.
export const POST = handleSchedule(runWatchdog);
