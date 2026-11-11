import { createHash, timingSafeEqual } from "node:crypto";

const OWNER = "KULTHX";
const REPO = "Cs16test";
const WORKFLOW = "cs16-public-session.yml";
const BRANCH = "main";
const EXPECTED_HASH = "66329f6b8966354b78a6164878b327e01c245d7c8b9d270e35cc2d4bdbd4e6a8";
const ACTIVE = new Set(["queued", "in_progress", "waiting", "requested", "pending"]);

function authorized(request) {
  const supplied = new URL(request.url, "https://localhost").searchParams.get("key") || "";
  const actual = createHash("sha256").update(supplied).digest();
  const expected = Buffer.from(EXPECTED_HASH, "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
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
  if (!response.ok) {
    const detail = (await response.text()).slice(0, 350);
    throw new Error(`GitHub API ${response.status}: ${detail}`);
  }
  if (response.status === 204) return null;
  return response.json();
}

async function activeRuns(token) {
  const query = new URLSearchParams({ branch: BRANCH, per_page: "30" });
  const data = await github(
    `actions/workflows/${encodeURIComponent(WORKFLOW)}/runs?${query}`,
    token
  );
  return (data.workflow_runs || []).filter(run => ACTIVE.has(run.status));
}

export default async function handler(request, response) {
  response.setHeader("Cache-Control", "no-store, max-age=0");
  if (request.method !== "GET") {
    response.setHeader("Allow", "GET");
    return response.status(405).json({ error: "Method not allowed" });
  }
  if (!authorized(request)) {
    return response.status(404).json({ error: "Not found" });
  }

  const token = process.env.GITHUB_ACTIONS_TOKEN;
  if (!token) {
    return response.status(503).json({ error: "GitHub Actions token is not configured" });
  }

  try {
    const before = await activeRuns(token);
    const cancelled = [];
    for (const run of before) {
      await github(`actions/runs/${run.id}/cancel`, token, { method: "POST" });
      cancelled.push({ id: run.id, previousStatus: run.status });
    }

    let remaining = [];
    for (let attempt = 0; attempt < 40; attempt += 1) {
      remaining = await activeRuns(token);
      if (remaining.length === 0) break;
      await new Promise(resolve => setTimeout(resolve, 1500));
    }
    if (remaining.length) {
      return response.status(409).json({
        ok: false,
        cancelled,
        remaining: remaining.map(run => ({ id: run.id, status: run.status })),
        error: "GitHub has not finished cancelling the old sessions; no replacement was dispatched."
      });
    }

    const dispatchAt = new Date().toISOString();
    await github(
      `actions/workflows/${encodeURIComponent(WORKFLOW)}/dispatches`,
      token,
      {
        method: "POST",
        body: JSON.stringify({ ref: BRANCH, inputs: { maxplayers: "20" } })
      }
    );

    let replacement = null;
    for (let attempt = 0; attempt < 12; attempt += 1) {
      await new Promise(resolve => setTimeout(resolve, 1500));
      const runs = await github(
        `actions/workflows/${encodeURIComponent(WORKFLOW)}/runs?${new URLSearchParams({ branch: BRANCH, per_page: "10" })}`,
        token
      );
      replacement = (runs.workflow_runs || []).find(run =>
        run.event === "workflow_dispatch" &&
        Date.parse(run.created_at) >= Date.parse(dispatchAt) - 5000
      ) || null;
      if (replacement) break;
    }

    return response.status(202).json({
      ok: true,
      cancelled,
      replacement: replacement ? {
        id: replacement.id,
        status: replacement.status,
        url: replacement.html_url,
        sha: replacement.head_sha
      } : null,
      message: replacement
        ? "Old sessions were cancelled and one replacement session was dispatched."
        : "Old sessions were cancelled and GitHub accepted the replacement dispatch; its run record is not visible yet."
    });
  } catch (error) {
    console.error("One-time restart failed:", error?.message || error);
    return response.status(502).json({ error: error?.message || "Restart failed" });
  }
}
