# GitHub-hosted CS 1.6 sessions (no external server)

## Architecture

This mode uses only:
- GitHub-hosted Actions runners for the temporary Linux game-server process.
- Playit UDP agent to expose the runner's loopback game port to players.
- Vercel for the status webpage.

It does **not** use Oracle, a VPS, a home computer, or another permanent host.

## In-session watchdog (no schedule)

The workflow `.github/workflows/cs16-public-session.yml` does not use a cron schedule and does not chain new workflow runs. A single runner session starts ReHLDS and Playit, then checks both processes every 10 seconds. If the ReHLDS process exits, the watchdog attempts to start it again and waits for `Round_Start` plus ReUnion `RUN`. If the Playit container exits, the watchdog recreates it using the repository secret.

The session is bounded to 5 hours 40 minutes, while the complete Actions job has a six-hour timeout. This allows automatic recovery from a child-process crash only while the GitHub runner remains alive. It cannot restart a job after GitHub ends the runner, overcome account or platform limits, or provide guaranteed 24/7 uptime. A fresh runner needs a new explicit trigger.

### Important GitHub limits

- GitHub-hosted jobs have a maximum execution time of six hours; this workflow uses a 5-hour-40-minute session budget and a 360-minute job timeout.
- The watchdog revives the ReHLDS and Playit processes within that session, not the GitHub runner or workflow itself.
- No cron schedule or self-chaining workflow is configured.

Official documentation:
- Job execution limits: https://docs.github.com/en/actions/reference/limits
- Workflow triggers: https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows

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

## Start / monitor

After the one-time Playit secret and UDP tunnel setup, trigger the watchdog by updating `.github/one-off-test.trigger` or launch it from **Actions → CS 1.6 self-healing session (GitHub-hosted)**. Choose 20 slots.

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
- Do not enable SSH secrets or deploy credentials for this hosting mode.
