# CS 1.6 ReHLDS Server Lab

A Counter-Strike 1.6 GoldSrc public-session experiment built with **GitHub Actions + Playit + Vercel only**.

There is no Oracle VM, VPS, home computer, or separately rented game host in this design.

## Verified game stack

**Local GitHub Actions smoke test passed on 2026-11-07:**
- ReHLDS 3.15.0.896-dev.
- Metamod-R 1.3.0.149.
- ReUnion 0.2.0.25, shown as `RUN` in `meta list`.
- GoldSrc protocol 48.
- `de_dust2` reached `Round_Start`.

This proves the engine and plugin stack can start on a GitHub-hosted Linux runner. It does not yet prove public UDP reachability or that 20–32 real players can be sustained.

## The three services

- **GitHub Actions:** starts a temporary Linux runner, installs the server, and runs one public session.
- **Playit:** forwards public UDP traffic to the runner's local `127.0.0.1:27015`.
- **Vercel:** serves the public status page only. It does not run the game server.

## One-off test

The workflow `.github/workflows/cs16-public-session.yml` is scheduled four times per day:
- 00:17 UTC
- 06:17 UTC
- 12:17 UTC
- 18:17 UTC

Each run starts ReHLDS for up to **340 minutes (5 hours 40 minutes)** after setup. The GitHub-hosted job has a six-hour hard limit. The next scheduled run starts a fresh runner and reconnects the Playit agent.

This is an experimental six-hour rotation, not guaranteed 24/7 uptime. Players disconnect when a session ends; the next runner needs time to install files and reconnect. GitHub documents that scheduled runs can be delayed or dropped during high load. The workflow deliberately stays within GitHub's execution limit and does not chain jobs to evade it.

Official limits and scheduling behavior:
- https://docs.github.com/en/actions/reference/limits
- https://docs.github.com/en/actions/reference/workflows-and-actions/events-that-trigger-workflows
- https://docs.github.com/en/actions/how-tos/troubleshoot-workflows

## One-time Playit setup (required before public sessions)

1. Generate a Playit Docker agent secret key:
   https://playit.gg/account/setup/wizard/new-account/docker/docker-name
2. In this repository, open **Settings → Secrets and variables → Actions → New repository secret**.
3. Add the secret:
   - Name: `PLAYIT_SECRET_KEY`
   - Value: the generated Playit Docker agent key.
4. In the Playit dashboard, create a **UDP** tunnel for this agent:
   - Local/origin address: `127.0.0.1`
   - Local/origin port: `27015`
5. Keep the key secret. Do not put it in repository files or chat.

Playit's official agent Docker instructions: https://github.com/playit-cloud/playit-agent#docker

## Start and monitor

After adding `PLAYIT_SECRET_KEY`, run **Actions → CS 1.6 one-off Playit test (GitHub-hosted) → Run workflow** and choose 20 slots. This is a single test, not a recurring service.

A successful run must show:
- ReHLDS version and GoldSrc protocol startup.
- ReUnion status `RUN`.
- The map reaching `Round_Start`.
- Playit agent container remaining active.

Then use the public hostname and port assigned in the Playit dashboard to connect from a real CS 1.6 client on a separate Internet connection.

The Playit tunnel is not considered verified until an external player has joined successfully.

## Player capacity

Start with 20 slots. Increase to 32 only after 20 real clients have joined and the runner remains stable. A `+maxplayers 32` setting is only a slot limit, not proof of performance.

## Public status page

https://cs16-community-status.vercel.app/

The page is live and currently reports `PREPARING`. It will remain that way until an external Playit connection is tested and the status data is updated. The static page does not itself query the game server.

## Repository layout

```text
config/
  server.cfg.example
dashboard/
  index.html
  styles.css
  app.js
  status.json
docs/
  REHLDS-SETUP.md
  TEST-PLAN.md
  GITHUB-ACTIONS-SESSIONS.md
scripts/
  install-base-hlds.sh
  install-rehlds.sh
  install-reunion.sh
  validate-config.sh
.github/workflows/
  validate.yml
  rehlds-smoke.yml
  cs16-public-session.yml
```

## Security

- Never commit RCON passwords, Steam credentials, or the Playit agent key.
- A fresh random RCON password is generated during every session.
- ReHLDS binds to loopback; public traffic is expected through the Playit UDP tunnel.
- Use only server/game files that you are authorized to use.
