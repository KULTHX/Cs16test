# CS 1.6 ReHLDS Server Lab

A reproducible preparation and test project for a public Counter-Strike 1.6 GoldSrc server targeting 20–32 player slots.

## Project status

**Milestone 2: ReHLDS installation scripts and a local smoke-test workflow added.**

The selected engine is **ReHLDS 3.15.0.896** (pinned). The repository contains installation scripts and configuration examples; it does not contain copyrighted game assets, server binaries, credentials, or a permanent game host.

## Stack

- Game: Counter-Strike 1.6 / GoldSrc.
- Engine: ReHLDS (replaces the original HLDS engine binary).
- Base game/server files: installed with SteamCMD app 90 on the `steam_legacy` branch, as required by ReHLDS.
- Target slots: 20–32; 32 is a test target, not a performance guarantee.
- Game port: UDP 27015.
- Initial map: `de_dust2`.
- Initial configuration: vanilla CS 1.6, no extra plugins in the first milestone.

**Important:** SteamCMD is used only to obtain the required base server/game files. The running engine is replaced with ReHLDS. ReHLDS does not remove the requirement for those base files.

## Repository layout

```text
config/
  server.cfg.example
docs/
  REHLDS-SETUP.md
  TEST-PLAN.md
scripts/
  install-base-hlds.sh
  install-rehlds.sh
  validate-config.sh
.github/workflows/
  validate.yml
  rehlds-smoke.yml
```

## Installation outline

On a Linux host where running a game server is permitted:

1. Install SteamCMD and its 32-bit runtime dependencies.
2. Install the base CS 1.6 dedicated-server files:
   `bash scripts/install-base-hlds.sh /path/to/steamcmd.sh /opt/cs16`
3. Replace the engine with the pinned, signature-verified ReHLDS release:
   `REHLDS_VERSION=3.15.0.896 bash scripts/install-rehlds.sh /opt/cs16`
4. Copy `config/server.cfg.example` to `/opt/cs16/cstrike/server.cfg`.
5. Configure a unique RCON password locally; never commit it.
6. Start with `./hlds_run -game cstrike -console -port 27015 +maxplayers 20 +map de_dust2`.
7. Test local startup, then UDP reachability from an external network.
8. Only after that, evaluate a public UDP tunnel such as Playit.

See [docs/REHLDS-SETUP.md](docs/REHLDS-SETUP.md) for details.

## Modified-client compatibility

ReHLDS is an engine replacement; it does not automatically make every modified client or every authentication scheme compatible. The ReHLDS ecosystem documents ReUnion as a separate MetaMod plugin for certain non-Steam GoldSrc client protocols. It is not installed in this milestone. We will first test the exact client builds and protocols, then decide whether a separate compatibility layer is appropriate.

## GitHub Actions role

- `validate.yml` checks configuration and shell syntax.
- `rehlds-smoke.yml` is a **manual, short, loopback-only** install/start test.
- GitHub-hosted runners are temporary CI machines, not persistent public game-server hosts. The smoke-test workflow terminates the server automatically and does not attempt to evade runner limits.

A real public server needs a host that permits a long-running ReHLDS process and inbound UDP traffic.

## Security rules

- Never commit RCON passwords, Steam credentials, tunnel tokens, private keys, or other secrets.
- Store any required CI secrets in GitHub Actions Secrets.
- Do not expose RCON publicly without strong access controls.
- Use server files and game content you are authorized to use.
- Do not claim public reachability until an external query and a real client connection succeed.
