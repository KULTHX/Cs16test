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

## Always-on external watchdog

The game session itself runs on a GitHub-hosted runner, so GitHub's six-hour maximum still applies. A separate watchdog function on Vercel Schedules checks the Actions workflow every 15 minutes. If it finds an active or queued session, it does nothing. If no session is active, it dispatches a new 20-slot session.

The Vercel schedule is a heartbeat for monitoring, not a fixed timetable for starting the game server. The game starts only when the watchdog sees that no session is active. The Vercel Hobby plan currently includes 5,000 Schedule runs per month; a 10-minute heartbeat uses about 2,880 runs in a 30-day month.

The GitHub workflow also has an in-session watchdog that restarts ReHLDS or Playit if either process crashes while its runner is alive. A manual Stop cancels only the active session; the next Vercel watchdog check will start a replacement unless three consecutive runs have failed. A new GitHub runner still needs time to install the game files and reconnect the tunnel, so short disconnects are possible. This design is automatic recovery, not a guarantee of perfectly uninterrupted 24/7 service.

### One-time watchdog permission

Create a fine-grained GitHub personal access token restricted to **KULTHX/Cs16test** with **Actions: Read and write** permission. Add it to the Vercel project `cs16-community-status` as a Production environment variable named `GITHUB_ACTIONS_TOKEN`. Do not paste the token into chat or repository files. Redeploy the Vercel project after saving the variable.

The watchdog pauses automatic relaunch after three consecutive failed workflow runs to avoid an endless retry loop if the configuration has a persistent error. Check Vercel runtime logs and GitHub Actions, fix the cause, then resume by resetting the failure history or manually launching the workflow.

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
ssh -i PATH_TO_FRIEND_PRIVATE_KEY -p PORT runner@bore.pub
```

Replace `PATH_TO_FRIEND_PRIVATE_KEY` with the actual private-key path and `PORT` with the port printed after `BORE SSH TUNNEL READY`. On the first connection, verify the SSH host fingerprint against the SHA-256 fingerprint printed in the same GitHub Actions run before accepting it.

### Security and limitations

Bore is a TCP relay; it does not encrypt the forwarded stream itself. The SSH protocol supplies encryption and authentication end-to-end. The public Bore endpoint is reachable from the Internet while the session is active, so key-only SSH authentication, disabled password login, disabled root login, and disabled TCP/agent forwarding are intentional protections. Do not add an unknown public key to `authorized_keys`.

If Bore fails or cannot reach `bore.pub`, the CS 1.6 server and Playit tunnel continue running. The in-session watchdog retries the SSH tunnel and logs the new public address when it reconnects. The Vercel watchdog's Start/Stop behavior is unchanged.

## Start and monitor

After adding `PLAYIT_SECRET_KEY`, configuring the UDP tunnel, and adding `GITHUB_ACTIONS_TOKEN` to the Vercel Production environment, the Vercel watchdog starts sessions automatically. You can also manually launch **CS 1.6 self-healing session (GitHub-hosted)** from the Actions tab.

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
