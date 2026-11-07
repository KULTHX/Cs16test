# CS 1.6 Server Lab

A starter repository for preparing and validating a public Counter-Strike 1.6 (GoldSrc/HLDS) server targeting 20–32 player slots.

## Project status

**Milestone 1: repository scaffold and configuration checks.**

This repository does not include HLDS binaries, Steam game files, Steam credentials, a tunnel token, or a permanently running game host. Those are kept separate from source control.

## Repository layout

```text
config/
  server.cfg.example
docs/
  TEST-PLAN.md
scripts/
  validate-config.sh
.github/
  workflows/
    validate.yml
```

## What GitHub Actions does here

The workflow checks the repository's configuration and shell scripts. GitHub-hosted Actions runners are temporary CI machines, not persistent game-server hosts. A successful CI run does not mean the game server is publicly reachable.

We will only add a bounded, manually triggered server smoke test after selecting an authorized host and confirming its network requirements. We will not create workflows that try to evade runner limits or relaunch indefinitely.

## Server baseline

- Game: Counter-Strike 1.6 / GoldSrc.
- Dedicated server: HLDS.
- Target slots: 20–32 (32 is a target for testing, not a guarantee of performance).
- Default game port: UDP 27015.
- Initial map: `de_dust2`.
- Initial setup: vanilla server, no third-party plugins until the basic server passes tests.

## Setup outline

1. Obtain HLDS and game content through legitimate Steam/Valve distribution methods on the chosen host.
2. Copy `config/server.cfg.example` to the server's `cstrike/server.cfg`.
3. Set a unique RCON password outside Git and outside this repository.
4. Start HLDS with the selected map and a maximum player count no greater than 32. On a Linux HLDS host, the launch arguments are typically passed to `hlds_run`, for example: `./hlds_run -game cstrike -console -port 27015 +maxplayers 32 +map de_dust2`. Keep `maxplayers` in launch arguments, not in `server.cfg`.
5. Verify the server locally, then verify UDP reachability from an external network.
6. Only after direct networking is understood, evaluate a UDP tunnel provider such as Playit.

## Security rules

- Never commit RCON passwords, Steam credentials, tunnel tokens, private keys, or other secrets.
- Store any required CI credentials in GitHub Actions Secrets, not in tracked files.
- Do not expose RCON to the public Internet unless access is restricted and the password is strong and unique.
- Use only server files and game content you are authorized to use.
- Do not publish an address as a working public server until an external query and a real client connection succeed.

See [docs/TEST-PLAN.md](docs/TEST-PLAN.md) for the staged validation plan.
