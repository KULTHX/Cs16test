import { Query } from "goldsrc-query";

const OWNER = "KULTHX";
const REPO = "Cs16test";
const WORKFLOW = "cs16-public-session.yml";
const SERVER_HOST = "pgsql-ruined.tun.ply.gg";
const SERVER_PORT = 27138;
const MAX_PLAYERS_FALLBACK = 20;
const ACTIVE_STATES = new Set(["queued", "in_progress", "waiting", "requested", "pending"]);

async function getActiveRun() {
  const token = process.env.GITHUB_ACTIONS_TOKEN;
  if (!token) return null;
  const url = new URL(`https://api.github.com/repos/${OWNER}/${REPO}/actions/workflows/${WORKFLOW}/runs`);
  url.searchParams.set("branch", "main");
  url.searchParams.set("per_page", "10");
  const response = await fetch(url, {
    headers: {
      Accept: "application/vnd.github+json",
      Authorization: `Bearer ${token}`,
      "X-GitHub-Api-Version": "2022-11-28"
    },
    signal: AbortSignal.timeout(4500)
  });
  if (!response.ok) throw new Error(`GitHub Actions status returned ${response.status}`);
  const body = await response.json();
  return (body.workflow_runs || []).find(run => ACTIVE_STATES.has(run.status)) || null;
}

async function queryGameServer() {
  const query = new Query(SERVER_HOST, SERVER_PORT, 1800);
  query.connect();
  try {
    return await query.serverInfo();
  } finally {
    query.close();
  }
}

export default async function handler(request, response) {
  if (request.method !== "GET") {
    response.setHeader("Allow", "GET");
    return response.status(405).json({ message: "Method not allowed" });
  }

  response.setHeader("Cache-Control", "no-store, max-age=0");
  let activeRun = null;
  let runError = null;
  let info = null;
  let queryError = null;

  try {
    activeRun = await getActiveRun();
  } catch (error) {
    runError = error?.message || "GitHub status unavailable";
  }

  try {
    info = await queryGameServer();
  } catch (error) {
    queryError = error?.message || "GoldSrc UDP query timed out";
  }

  const online = Boolean(info);
  const starting = !online && Boolean(activeRun);
  const status = online ? "online" : (starting ? "starting" : "offline");
  const result = {
    status,
    serverName: info?.name || "CS 1.6 ReHLDS Community",
    map: info?.map || null,
    players: Number.isInteger(info?.players) ? info.players : null,
    maxPlayers: Number.isInteger(info?.max_players) ? info.max_players : MAX_PLAYERS_FALLBACK,
    publicAddress: SERVER_HOST,
    publicPort: SERVER_PORT,
    workflowActive: Boolean(activeRun),
    workflowRunId: activeRun?.id || null,
    workflowStatus: activeRun?.status || null,
    workflowUrl: activeRun?.html_url || null,
    updatedAt: new Date().toISOString(),
    message: online
      ? "Live GoldSrc UDP query succeeded."
      : starting
        ? "GitHub runner is active, but the public game query has not answered yet."
        : runError
          ? `No server reply. GitHub status check: ${runError}.`
          : `No response from the game server${queryError ? `: ${queryError}` : ""}.`
  };

  return response.status(200).json(result);
}
