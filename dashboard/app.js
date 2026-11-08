const statusPill = document.querySelector("#status-pill");
const statusLabel = document.querySelector("#status-label");
const playersValue = document.querySelector("#players-value");
const playersFoot = document.querySelector("#players-foot");
const mapValue = document.querySelector("#map-value");
const addressValue = document.querySelector("#address-value");
const addressHint = document.querySelector("#address-hint");
const notice = document.querySelector("#notice");
const lastCheck = document.querySelector("#last-check");
const copyButton = document.querySelector("#copy-connect");
const startButton = document.querySelector("#start-server");
const stopButton = document.querySelector("#stop-server");
const controlKeyInput = document.querySelector("#control-key");
const controlResult = document.querySelector("#control-result");

let connectCommand = "";
let requestInFlight = false;

function setStatus(state) {
  statusPill.classList.remove("online", "offline", "pending");
  statusPill.classList.add(state);
}

async function refreshStatus() {
  try {
    const response = await fetch("/api/status", { cache: "no-store" });
    if (!response.ok) throw new Error("Live status endpoint unavailable");
    const data = await response.json();

    const isOnline = data.status === "online";
    const isStarting = data.status === "starting";
    const state = isOnline ? "online" : (isStarting ? "pending" : "offline");
    setStatus(state);
    statusLabel.textContent = isOnline ? "ONLINE" : (isStarting ? "STARTING" : "OFFLINE");

    playersValue.innerHTML = Number.isInteger(data.players)
      ? `${data.players}<span class="metric-denom"> / ${data.maxPlayers ?? 20}</span>`
      : `—<span class="metric-denom"> / ${data.maxPlayers ?? 20}</span>`;
    playersFoot.textContent = isOnline
      ? "Live GoldSrc UDP query"
      : (isStarting ? "Runner is active; waiting for server response" : "No live server response");

    mapValue.textContent = data.map || "—";

    if (data.publicAddress && data.publicPort) {
      addressValue.textContent = `${data.publicAddress}:${data.publicPort}`;
      addressHint.textContent = isOnline
        ? "Server is responding. Use this address in CS 1.6."
        : "Public endpoint retained; the game server is not responding right now.";
      connectCommand = `connect ${data.publicAddress}:${data.publicPort}`;
      copyButton.disabled = false;
    } else {
      addressValue.textContent = "Not assigned";
      addressHint.textContent = "Waiting for the Playit public endpoint.";
      connectCommand = "";
      copyButton.disabled = true;
    }

    notice.textContent = data.message || "Live status loaded.";
    lastCheck.textContent = data.updatedAt ? new Date(data.updatedAt).toLocaleString() : "Not available";
  } catch (error) {
    setStatus("pending");
    statusLabel.textContent = "STATUS UNKNOWN";
    playersFoot.textContent = "Live query unavailable";
    notice.textContent = "Could not query the live server. This does not by itself prove the GitHub runner is stopped.";
    lastCheck.textContent = new Date().toLocaleString();
  }
}

copyButton.addEventListener("click", async () => {
  if (!connectCommand) return;
  try {
    await navigator.clipboard.writeText(connectCommand);
    copyButton.textContent = "COPIED";
    window.setTimeout(() => { copyButton.textContent = "Copy connect"; }, 1400);
  } catch {
    copyButton.textContent = "COPY UNAVAILABLE";
  }
});

async function sendControl(action) {
  if (requestInFlight) return;
  const controlKey = controlKeyInput.value.trim();
  if (!controlKey) {
    controlResult.textContent = "Enter the admin control key first.";
    controlKeyInput.focus();
    return;
  }

  if (action === "stop" && !window.confirm(
    "Stop the current CS 1.6 session? The watchdog will keep monitoring but respect this manual stop until you press Start."
  )) return;

  requestInFlight = true;
  startButton.disabled = true;
  stopButton.disabled = true;
  controlResult.textContent = action === "start" ? "Requesting a server session..." : "Requesting session cancellation...";

  try {
    const response = await fetch("/api/control", {
      method: "POST",
      headers: {
        "Content-Type": "application/json",
        "Authorization": `Bearer ${controlKey}`
      },
      body: JSON.stringify({ action })
    });
    const result = await response.json().catch(() => ({}));
    if (!response.ok) {
      throw new Error(result.message || `Control request failed (${response.status})`);
    }
    controlResult.textContent = result.message || (action === "start" ? "Start request accepted." : "Stop request accepted.");
    await refreshStatus();
  } catch (error) {
    controlResult.textContent = error.message || "Could not perform this action.";
  } finally {
    requestInFlight = false;
    startButton.disabled = false;
    stopButton.disabled = false;
  }
}

startButton.addEventListener("click", () => sendControl("start"));
stopButton.addEventListener("click", () => sendControl("stop"));

refreshStatus();
window.setInterval(refreshStatus, 30000);
