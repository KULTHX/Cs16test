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

## Private SSH terminal access from Android (Termux)

This optional feature allows an invited friend to use a normal SSH terminal on the **currently active GitHub Actions runner**. Tailscale provides the private network, and SSH listens only on the runner's Tailscale IP. No public SSH port is opened.

Important: the runner is temporary. The SSH client key and server host identity can remain stable, and the same hostname is reused, but access exists only while a GitHub Actions session is active. Files and packages installed directly on the runner are lost when that runner is replaced. GitHub-hosted runners have a bounded job lifetime.

### A. Configure the private network once

1. Create a free Tailscale account and install the official Tailscale app on your phone.
2. Open the Tailscale admin console → **Access controls**. Merge these entries into your existing policy file. Do not erase other rules:

```json
{
  "tagOwners": {
    "tag:cs16-runner": ["autogroup:admin", "autogroup:owner"]
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

This limits access to TCP port 2222 on the tagged runner. Invited tailnet members can use it; do not invite anyone you do not trust with shell access.

3. In Tailscale admin console → **Keys** → **Generate auth key**, create a key with:
   - Reusable: **on**
   - Ephemeral: **on**
   - Tag: **tag:cs16-runner**
   - Pre-approved: **on**, if device approval is enabled
   - Expiry: choose the longest allowed period (up to 90 days); create a replacement when it expires.

4. In GitHub **KULTHX/Cs16test → Settings → Secrets and variables → Actions**, create repository secret:
   - `TAILSCALE_AUTHKEY`: the auth key you just generated.

Keep this key private. Do not commit it or send it in chat. Reusable auth keys are powerful credentials; revoke them in Tailscale if exposed.

### B. Create the stable SSH server identity once

On the owner phone in Termux:

```bash
pkg update -y
pkg install -y openssh
mkdir -p ~/.ssh
chmod 700 ~/.ssh
ssh-keygen -t ed25519 -a 64 -N "" -f ~/.ssh/cs16_server_host -C "cs16-runner-host"
```

Add the contents of this **private host key** to GitHub Actions repository secrets as:
- `SSH_HOST_ED25519_PRIVATE_KEY`: the complete contents of `~/.ssh/cs16_server_host`.

Do not send this private host key to your friend. The repository already contains the friend's **public client key** at `config/ssh/authorized_keys`; the private client key stays with your friend.

The same server host key is loaded into each new runner, so your friend should accept the host identity on the first SSH connection and should not get a host-key change warning on later sessions.

### C. Invite the friend and connect

1. In Tailscale admin console → **Users**, invite your friend's email to the tailnet. Your friend installs the Tailscale app, signs in with their own account, and accepts the invitation.
2. The friend opens Termux and runs:

```bash
pkg update -y
pkg install -y openssh
ssh -i ~/.ssh/cs16_friend -p 2222 runner@cs16-runner
```

If the private key has different permissions, run `chmod 600 ~/.ssh/cs16_friend` first. The first connection asks to trust the SSH host fingerprint; accept only when it matches the fingerprint you provide from the owner's host public key. Tailscale MagicDNS must be enabled for the short hostname `cs16-runner` to resolve.

### What the friend can do

The friend logs in as the temporary Linux user `runner`, which can use the runner's normal `sudo` permissions to install packages and edit files in that active session. It is not a persistent VPS: copy important changes back to the Git repository or another persistent store before the GitHub job ends.

Tailscale's free Personal plan currently allows up to six users. A friend must be invited as a separate user; never share one Tailscale login between people.

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
