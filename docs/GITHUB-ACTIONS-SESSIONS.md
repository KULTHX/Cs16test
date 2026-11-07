# GitHub-hosted CS 1.6 sessions (no external server)

## Architecture

This mode uses only:
- GitHub-hosted Actions runners for the temporary Linux game-server process.
- Playit UDP agent to expose the runner's loopback game port to players.
- Vercel for the status webpage.

It does **not** use Oracle, a VPS, a home computer, or another permanent host.

## Automatic six-hour session rotation

The workflow `.github/workflows/cs16-public-session.yml` is scheduled four times per day at 00:17, 06:17, 12:17, and 18:17 UTC. Each run installs ReHLDS, starts the Playit agent, and holds the game session for up to 340 minutes (5 hours 40 minutes). The whole GitHub Actions job has a 360-minute timeout to leave room for setup. The next scheduled run starts on a fresh runner and reattaches the Playit agent.

### Important GitHub limits

- GitHub-hosted jobs have a maximum execution time of six hours. This workflow caps the session process at 340 minutes and the complete job at 360 minutes.
- Scheduled events may be delayed during high load, and some queued events may be dropped.
- Scheduled workflows in public repositories are automatically disabled after 60 days without repository activity.
- The schedule is not an uptime guarantee. There can be a gap while a fresh runner installs the game files, and a missed schedule means the server remains offline until the next successful run. It does not immediately restart a failed run, and it does not chain workflows to evade GitHub's six-hour limit.

Official documentation:
- Job execution limits: https://docs.github.com/en/actions/reference/limits
- Scheduled workflow delays and behavior: https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows
- Schedule troubleshooting: https://docs.github.com/en/actions/how-tos/troubleshoot-workflows

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

After the one-time Playit secret and UDP tunnel setup, the schedule starts sessions automatically. A maintainer may also launch an extra session from the Actions tab using **CS 1.6 public session (GitHub-hosted)**. Choose 20 slots.

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
