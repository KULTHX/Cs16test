import { timingSafeEqual } from "node:crypto";

const OWNER = "KULTHX";
const REPO = "Cs16test";
const WORKFLOW = "cs16-public-session.yml";
const BRANCH = "main";
const ACTIVE = new Set(["queued", "in_progress", "waiting", "requested", "pending"]);

function safeEqual(left, right) {
  const a = Buffer.from(String(left));
  const b = Buffer.from(String(right));
  return a.length === b.length && timingSafeEqual(a, b);
}

async function github(path, token, options = {}) {
  const response = await fetch(`https://api.github.com/repos/${OWNER}/${REPO}/${path}`, {
    ...options,
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "X-GitHub-Api-Version": "2022-11-28",
      "Content-Type": "application/json",
      ...(options.headers || {})
    },
    signal: AbortSignal.timeout(12000)
  });
  const raw = await response.text();
  if (!response.ok && response.status !== 204) {
    throw new Error(`GitHub API ${response.status}: ${raw.slice(0, 350)}`);
  }
  if (!raw.trim()) return null;
  return JSON.parse(raw);
}

export default async function handler(request, response) {
  response.setHeader("Cache-Control", "no-store, max-age=0");
  response.setHeader("Pragma", "no-cache");

  if (request.method !== "GET") {
    response.setHeader("Allow", "GET");
    return response.status(405).json({ message: "Method not allowed" });
  }

  const expected = process.env.ROLLOVER_TRIGGER_KEY || "";
  const supplied = typeof request.query?.key === "string" ? request.query.key : "";
  if (!expected || !safeEqual(supplied, expected)) {
    return response.status(401).json({ message: "Unauthorized." });
  }

  const token = process.env.GITHUB_ACTIONS_TOKEN;
  if (!token) return response.status(503).json({ message: "Missing GitHub Actions token." });

  try {
    const latestCommit = await github("commits/main", token);
    const currentCommit = latestCommit?.sha;
    if (!currentCommit) throw new Error("Could not determine the latest main commit.");

    const params = new URLSearchParams({ branch: BRANCH, event: "workflow_dispatch", per_page: "20" });
    const data = await github(`actions/workflows/${encodeURIComponent(WORKFLOW)}/runs?${params.toString()}`, token);
    const active = (data?.workflow_runs || []).filter(run => ACTIVE.has(run.status));
    const current = active.find(run => run.head_sha === currentCommit);

    if (current) {
      return response.status(200).json({
        ok: true,
        action: "already_running",
        runId: current.id,
        message: "The Zombie Plague session is already queued or running."
      });
    }

    const cancelled = [];
    for (const run of active) {
      const result = await github(`actions/runs/${run.id}/cancel`, token, { method: "POST" });
      cancelled.push({ runId: run.id, priorStatus: run.status, cancelAccepted: true });
    }

    await github(
      `actions/workflows/${encodeURIComponent(WORKFLOW)}/dispatches`,
      token,
      { method: "POST", body: JSON.stringify({ ref: BRANCH, inputs: { maxplayers: "20" } }) }
    );

    return response.status(202).json({
      ok: true,
      action: "restart",
      cancelled,
      requestedCommit: currentCommit,
      message: "Old session cancellation accepted; a fresh Zombie Plague session was dispatched."
    });
  } catch (error) {
    console.error("Rollover failed:", error?.message || error);
    return response.status(502).json({ ok: false, message: error?.message || "Rollover failed." });
  }
}
