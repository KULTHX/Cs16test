import { createHash, timingSafeEqual } from "node:crypto";

const OWNER = "KULTHX";
const REPO = "Cs16test";
const WORKFLOW = "cs16-public-session.yml";
const EXPECTED_HASH = "ee8f16116c1601007154afd4fb37d3fe139288b8175b8923a0e4145a709e5774";
const ACTIVE = new Set(["queued", "in_progress", "waiting", "requested", "pending"]);

function authorized(request) {
  const encoded = new URL(request.url, "https://localhost").searchParams.get("key") || "";
  const supplied = Buffer.from(encoded, "base64url").toString("utf8");
  const actual = createHash("sha256").update(supplied).digest();
  const expected = Buffer.from(EXPECTED_HASH, "hex");
  return actual.length === expected.length && timingSafeEqual(actual, expected);
}

async function api(path, token, options = {}) {
  const result = await fetch(`https://api.github.com/repos/${OWNER}/${REPO}/${path}`, {
    ...options,
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "X-GitHub-Api-Version": "2022-11-28",
      "Content-Type": "application/json",
      ...(options.headers || {})
    },
    signal: AbortSignal.timeout(9000)
  });
  if (!result.ok) throw new Error(`GitHub API ${result.status}: ${(await result.text()).slice(0,300)}`);
  if (result.status === 204) return null;
  return result.json();
}

async function activeRuns(token) {
  const query = new URLSearchParams({branch:"main",per_page:"30"});
  const result = await api(`actions/workflows/${encodeURIComponent(WORKFLOW)}/runs?${query}`,token);
  return (result.workflow_runs || []).filter(run => ACTIVE.has(run.status));
}

export default async function handler(request, response) {
  response.setHeader("Cache-Control","no-store, max-age=0");
  if (request.method !== "GET") return response.status(405).json({error:"Method not allowed"});
  if (!authorized(request)) return response.status(404).json({error:"Not found"});
  const token = process.env.GITHUB_ACTIONS_TOKEN;
  if (!token) return response.status(503).json({error:"Missing GitHub Actions token"});
  try {
    const before = await activeRuns(token);
    const cancelled = [];
    for (const run of before) {
      await api(`actions/runs/${run.id}/cancel`,token,{method:"POST"});
      cancelled.push({id:run.id,previousStatus:run.status});
    }
    let remaining = [];
    for (let attempt=0; attempt<10; attempt++) {
      remaining = await activeRuns(token);
      if (!remaining.length) break;
      await new Promise(resolve => setTimeout(resolve,500));
    }
    if (remaining.length) {
      return response.status(409).json({ok:false,cancelled,remaining:remaining.map(r=>({id:r.id,status:r.status})),error:"Old sessions have not fully stopped; no replacement was started."});
    }
    const dispatchAt = Date.now();
    await api(`actions/workflows/${encodeURIComponent(WORKFLOW)}/dispatches`,token,{
      method:"POST",
      body:JSON.stringify({ref:"main",inputs:{maxplayers:"20"}})
    });
    return response.status(202).json({
      ok:true,
      cancelled,
      map:"zm_laura",
      bots:1,
      dispatchAccepted:true,
      dispatchAt:new Date(dispatchAt).toISOString(),
      message:"Old sessions stopped. A single replacement session was dispatched using the current main script, configured for zm_laura and one YaPB bot."
    });
  } catch (error) {
    console.error("Map test restart failed:",error?.message || error);
    return response.status(502).json({error:error?.message || "Restart failed"});
  }
}
