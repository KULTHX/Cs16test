# GitHub-hosted CS 1.6 sessions (no external server)

## Architecture

This mode uses only:
- GitHub-hosted Actions runners for the temporary Linux game-server process.
- Playit UDP agent to expose the runner's loopback game port to players.
- Vercel for the status webpage.

It does **not** use Oracle, a VPS, a home computer, or another permanent host.

## Always-on watchdog via Vercel Schedules

The dashboard project runs a private Vercel Schedules function every 15 minutes. It queries the status of `.github/workflows/cs16-public-session.yml` using the GitHub Actions API:

- If a run is queued or in progress, the watchdog leaves it alone.
- If no run is active and the latest session ended by failure or timeout, it calls GitHub's workflow-dispatch API to start a fresh 20-slot session.
- If the latest session was cancelled from the dashboard, it treats that as an intentional manual stop. The watchdog remains scheduled and keeps monitoring, but does not relaunch until the administrator presses Start.
- If there are three consecutive failed runs, it pauses relaunches to prevent a permanent failure loop.

The heartbeat is not a fixed schedule for starting the game server. It is a monitoring interval; a new server session is requested only when no active GitHub Actions run is found.

The Vercel Hobby team currently includes 5,000 Schedules executions per month. A 10-minute interval uses about 2,880 executions in a 30-day month. Schedule executions are not a continuously running process, so recovery detection can take up to around 30 minutes, including the required 15-minute jitter, plus runner startup time.

The GitHub runner remains subject to the six-hour job limit. The in-session watchdog restarts ReHLDS and Playit child processes while that runner is alive. Vercel Schedules then detects when the GitHub workflow has ended and dispatches a new session. This provides automatic recovery but cannot promise zero downtime.

### Required GitHub token in Vercel

Create a fine-grained GitHub personal access token restricted to this repository only, with **Actions: Read and write**. Add it to the Vercel project `cs16-community-status` as Production environment variable `GITHUB_ACTIONS_TOKEN`. Keep the token out of chat and Git. Redeploy the production project after saving it.

The static Vercel function is private and can only be invoked by the Vercel Schedules infrastructure. The GitHub token is read only by this function and is not exposed to browser clients.

## One-time Playit setup

1. Create a Playit account and a Docker agent secret key:
   https://playit.gg/account/setup/wizard/new-account/docker/docker-name
2. Add it to the repository under **Settings → Secrets and variables → Actions → New repository secret**:
   - Name: `PLAYIT_SECRET_KEY`
   - Value: your Playit Docker agent secret key
3. (Optional but recommended) Add a second Actions secret named `REUNION_HASH_SALT` containing a random value of at least 32 letters, digits, underscores, or hyphens. Keep the same value across sessions so IP-derived ReUnion IDs remain stable. Generate it privately with `openssl rand -hex 32`; do not paste it into chat. If omitted, each fresh runner generates a new salt, so IP-derived IDs may change between sessions.
4. In the Playit dashboard, create a UDP tunnel for that agent:
   - Tunnel type: UDP
   - Local/origin address: `127.0.0.1`
   - Local/origin port: `27015`
5. Note the assigned public address and port. Do not paste either secret into Git or chat.

Official Playit Docker instructions: https://github.com/playit-cloud/playit-agent#docker

## Optional private SSH terminal from Android (Termux)

This optional feature lets your phone connect to the **currently running GitHub Actions runner** using ordinary OpenSSH. Tailscale provides the private network; SSH listens only on the runner's Tailscale address and is not exposed on the public Internet. The runner is still temporary: the SSH key and hostname stay the same, but access is available only while a session is running. Files and packages installed on that runner disappear when GitHub replaces it.

### 1. Install Tailscale on the phone

Install the official Tailscale Android app and sign in to the same Tailscale account used for this project. Keep Tailscale connected when using Termux.

### 2. Create a restricted Tailscale tag and policy

In the Tailscale admin console, open **Access controls** and merge the following entries into the existing policy file. Do not delete or replace unrelated policy rules:

```json
{
  "tagOwners": {
    "tag:cs16-runner": ["autogroup:admin"]
  },
  "grants": [
    {
      "src": ["autogroup:member"],
      "dst": ["tag:cs16-runner"],
      "ip": ["tcp:2222"]
    }
  ]
}
```

This permits members of your tailnet to reach only TCP port 2222 on the temporary runner.

### 3. Create a Tailscale OAuth client

In the Tailscale admin console, open **Trust credentials → Credentials → OAuth** and create a client with:
- **Devices / Core / Write**
- **Keys / Auth Keys / Write**
- Allowed tag: **tag:cs16-runner**

Keep the client ID and secret private. In GitHub, open **KULTHX/Cs16test → Settings → Secrets and variables → Actions**, then add:
- `TS_OAUTH_CLIENT_ID`: the OAuth client ID
- `TS_OAUTH_SECRET`: the OAuth client secret

The GitHub Action creates a short-lived, tagged Tailscale node for each session and cleans it up when the job ends.

### 4. Generate the two SSH key pairs in Termux

In Termux, install OpenSSH and create the client key (used by your phone) and a separate stable host key (used by the temporary runner):

```bash
pkg update -y
pkg install -y openssh
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -a 64 -f ~/.ssh/cs16_terminal -C "termux-cs16"
ssh-keygen -t ed25519 -a 64 -N "" -f ~/.ssh/ssh_host_ed25519_key -C "cs16-runner-host"
```

Use a passphrase for the phone's client key. The host key uses no passphrase so the runner can start sshd unattended. Do not share `~/.ssh/cs16_terminal` with anyone.

In GitHub **Settings → Secrets and variables → Actions**, add these two repository secrets:
- `SSH_AUTHORIZED_KEYS`: paste the output of `cat ~/.ssh/cs16_terminal.pub`
- `SSH_HOST_ED25519_PRIVATE_KEY`: paste the complete output of `cat ~/.ssh/ssh_host_ed25519_key`

Never paste either private key into chat or commit it to the repository.

### 5. Pin the server identity and connect

In Termux, add the stable host public key to `known_hosts`:

```bash
ssh-keygen -y -f ~/.ssh/ssh_host_ed25519_key | awk '{print "[cs16-runner]:2222 " $1 " " $2}' >> ~/.ssh/known_hosts
chmod 600 ~/.ssh/known_hosts
```

Then connect with the same command whenever the runner is active:

```bash
ssh -i ~/.ssh/cs16_terminal -p 2222 runner@cs16-runner
```

The hostname `cs16-runner` is provided by Tailscale MagicDNS. If the phone cannot resolve it, make sure the Tailscale Android app is connected and MagicDNS is enabled for the tailnet.

Inside the session, the runner account can use the GitHub-hosted runner's normal `sudo` permissions for package installation. This is a temporary workspace, not persistent storage. Save anything important outside the runner before the session ends.

## Start / monitor

After the one-time Playit secret, UDP tunnel, and Vercel `GITHUB_ACTIONS_TOKEN` setup, Vercel Schedules monitors the workflow every 15 minutes and starts a new session only when no active session exists.

Follow the workflow logs. The run must show:
- ReHLDS 3.15.0.896.
- Metamod-R 1.3.0.149.
- ReUnion 0.2.0.25 with status `RUN`.
- First map reaching `Round_Start`.
- Playit agent container staying active.

A running container alone does not prove the public tunnel is reachable. Join from a separate CS 1.6 client using the actual public address and port shown in the Playit dashboard.

## Capacity

Start with 20 slots. Increase to 32 only after 20 real clients have joined and the runner remained stable. A `+maxplayers 32` argument merely configures a slot limit; it does not prove the hardware or network can sustain it.

## Vercel status page

The public page is:
https://cs16-community-status.vercel.app/

It currently reports `PREPARING` until a public session has been externally verified. The static status page does not query UDP itself and must not be treated as proof that the game server is online.

## Security

- Store the Playit secret only as the encrypted `PLAYIT_SECRET_KEY` repository secret.
- The RCON password is generated randomly for each session and is not written to the repository.
- The game server binds to `127.0.0.1:27015`; public game traffic should enter only through the Playit tunnel.
- Optional SSH secrets are used only when Tailscale is connected; the SSH daemon binds exclusively to the runner's private Tailscale IP.
