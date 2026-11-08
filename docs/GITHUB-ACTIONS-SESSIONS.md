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

## SSH terminal access through Bore

This optional feature gives the registered SSH public-key holder a normal Linux terminal on the **currently active GitHub Actions runner**. The runner's SSH daemon listens only on `127.0.0.1:22`; Bore v0.6.0 forwards that local TCP port to a random public port on `bore.pub`. The existing Playit UDP tunnel for CS 1.6 is unchanged.

The runner is temporary and has GitHub's bounded job lifetime. The authorized client public key remains in the repository across sessions, but the Bore public port changes when a new tunnel is created. Files and packages installed directly on the runner disappear when the runner is replaced. Save important work back to Git or another persistent store.

### Access control and connection

- The authorized public key is stored at `config/ssh/authorized_keys`. The matching private key must remain on the friend's own computer; never commit or share that private key.
- SSH password authentication and root login are disabled. Only public-key authentication is accepted, and the account is `runner`.
- The SSH server host key is generated for each runner session unless `SSH_HOST_ED25519_PRIVATE_KEY` is already configured as a GitHub Actions secret. Its SHA-256 fingerprint is printed in the Actions log.
- Bore logs the public endpoint, for example `bore.pub:45123`. The port is assigned by the Bore relay and is not fixed.
- Connect from the friend's computer using the private key that matches the registered public key:

```bash
ssh -i ~/.ssh/cs16_friend -p PORT runner@bore.pub
```

Replace `PORT` with the port printed after `BORE SSH TUNNEL READY`. On the first connection, verify the SSH host fingerprint against the SHA-256 fingerprint printed in the same GitHub Actions run before accepting it.

### Security and limitations

Bore is a TCP relay; it does not encrypt the forwarded stream itself. The SSH protocol supplies encryption and authentication end-to-end. The public Bore endpoint is reachable from the Internet while the session is active, so key-only SSH authentication, disabled password login, disabled root login, and disabled TCP/agent forwarding are intentional protections. Do not add an unknown public key to `authorized_keys`.

If Bore fails or cannot reach `bore.pub`, the CS 1.6 server and Playit tunnel continue running. The in-session watchdog retries the SSH tunnel and logs the new public address when it reconnects. The Vercel watchdog's Start/Stop behavior is unchanged.

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
- SSH is bound to localhost only and exposed through a separate Bore TCP tunnel; the Playit UDP tunnel remains dedicated to game traffic.
