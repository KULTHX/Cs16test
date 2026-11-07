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

let connectCommand = "";

function setStatus(state) {
  statusPill.classList.remove("online", "offline", "pending");
  statusPill.classList.add(state);
}

async function refreshStatus() {
  try {
    const response = await fetch("./status.json", { cache: "no-store" });
    if (!response.ok) throw new Error("Status data unavailable");
    const data = await response.json();

    const isOnline = data.status === "online";
    const state = isOnline ? "online" : (data.status === "offline" ? "offline" : "pending");
    setStatus(state);
    statusLabel.textContent = isOnline ? "ONLINE" : (state === "offline" ? "OFFLINE" : "PREPARING");

    playersValue.innerHTML = Number.isInteger(data.players)
      ? `${data.players}<span class="metric-denom"> / ${data.maxPlayers ?? 20}</span>`
      : `—<span class="metric-denom"> / ${data.maxPlayers ?? 20}</span>`;
    playersFoot.textContent = isOnline ? "Live server status" : "No public host verified";
    mapValue.textContent = data.map || "de_dust2";

    if (data.publicAddress && data.publicPort) {
      addressValue.textContent = `${data.publicAddress}:${data.publicPort}`;
      addressHint.textContent = "Use this address in the CS 1.6 console.";
      connectCommand = `connect ${data.publicAddress}:${data.publicPort}`;
      copyButton.disabled = false;
    } else {
      addressValue.textContent = "Not assigned yet";
      addressHint.textContent = "The address will appear after the host and UDP tunnel are configured.";
      connectCommand = "";
      copyButton.disabled = true;
    }

    notice.textContent = data.message || "Server status loaded.";
    lastCheck.textContent = data.updatedAt
      ? new Date(data.updatedAt).toLocaleString()
      : "Not available";
  } catch (error) {
    setStatus("pending");
    statusLabel.textContent = "STATUS UNKNOWN";
    notice.textContent = "The status file could not be loaded. The game server may still be running; this page has no live result.";
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

refreshStatus();
