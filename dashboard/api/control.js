import { timingSafeEqual } from "node:crypto";

const OWNER = "KULTHX";
const REPO = "Cs16test";
const WORKFLOW = "cs16-public-session.yml";
const BRANCH = "main";
const ACTIVE_STATES = new Set(["queued", "in_progress", "waiting", "requested", "pending"]);

function safeEqual(left, right) {
  const a = Buffer.from(String(left));
  const b = Buffer.from(String(right));
  return a.length === b.length && timingSafeEqual(a, b);
}

function githubHeaders(token) {
  return {
    Accept: "application/vnd.github+json",
    Authorization: `Bearer ${token}`,
    "X-GitHub-Api-Version": "2022-11-28",
    "Content-Type": "application/json"
  };
}

async function github(path, token, options = {}) {
  const response = await fetch(`https://api.github.com/repos/${OWNER}/${REPO}/${path}`, {
    ...options,
    headers: { ...githubHeaders(token), ...(options.headers || {}) },
    signal: AbortSignal.timeout(10000)
  });
  if (!response.ok) {
    const text = (await response.text()).slice(0, 350);
    throw new Error(`GitHub API ${response.status}: ${text}`);
  }
  if (response.status === 204) return null;
  return response.json();
}

async function getActiveRuns(token) {
  const query = new URLSearchParams({ branch: BRANCH, per_page: "20" });
  const data = await github(
    `actions/workflows/${encodeURIComponent(WORKFLOW)}/runs?${query.toString()}`,
    token
  );
  return (data.workflow_runs || []).filter(run => ACTIVE_STATES.has(run.status));
}

export default async function handler(request, response) {
  if (request.method !== "POST") {
    response.setHeader("Allow", "POST");
    return response.status(405).json({ message: "Method not allowed" });
  }

  const configuredKey = process.env.SERVER_CONTROL_SECRET;
  const suppliedKey = request.headers.authorization?.replace(/^Bearer\s+/i, "") || "";
  if (!configuredKey || !safeEqual(suppliedKey, configuredKey)) {
    return response.status(401).json({ message: "Invalid admin key." });
  }

  const token = process.env.GITHUB_ACTIONS_TOKEN;
  if (!token) {
    return response.status(503).json({ message: "GitHub Actions token is not configured." });
  }

  let body;
  try {
    body = typeof request.body === "string" ? JSON.parse(request.body) : request.body;
  } catch {
    return response.status(400).json({ message: "Invalid JSON body." });
  }

  try {
    const action = body?.action;
    const activeRuns = await getActiveRuns(token);

    if (action === "start") {
      if (activeRuns.length) {
        return response.status(200).json({
          ok: true,
          action,
          message: `A session is already ${activeRuns[0].status} (run #${activeRuns[0].id}).`,
          runId: activeRuns[0].id
        });
      }

      await github(
        `actions/workflows/${encodeURIComponent(WORKFLOW)}/dispatches`,
        token,
        {
          method: "POST",
          body: JSON.stringify({ ref: BRANCH, inputs: { maxplayers: "20" } })
        }
      );

      return response.status(202).json({
        ok: true,
        action,
        message: "Start request accepted. GitHub is preparing a new server runner."
      });
    }

    if (action === "stop") {
      if (!activeRuns.length) {
        return response.status(200).json({
          ok: true,
          action,
          message: "No active session was found."
        });
      }

      const results = await Promise.allSettled(activeRuns.map(run =>
        github(`actions/runs/${run.id}/cancel`, token, { method: "POST" })
      ));
      const canceled = results.filter(item => item.status === "fulfilled").length;
      if (!canceled) throw new Error("GitHub did not accept the cancellation request.");

      return response.status(202).json({
        ok: true,
        action,
        canceled,
        message: `Cancellation requested for ${canceled} active session(s). The external watchdog should relaunch the server on its next check.`
      });
    }

    return response.status(400).json({ message: "Action must be start or stop." });
  } catch (error) {
    console.error("Server control failed:", error?.message || error);
    return response.status(502).json({ message: error?.message || "Server control request failed." });
  }
}
