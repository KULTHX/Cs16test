# CS 1.6 ReHLDS Server Lab

A reproducible Counter-Strike 1.6 GoldSrc server project targeting 20–32 player slots.

## Project status

**Milestone 3 passed:** the ReHLDS-only local smoke test ran on GitHub Actions on 2026-11-07. It installed and verified ReHLDS 3.15.0.896, initialized GoldSrc protocol 48, loaded the map, and reached `World triggered "Round_Start"`.

**Milestone 4 added:** the repository now includes a persistent-host deployment package, a systemd service with automatic restart, Metamod-R/ReUnion compatibility for protocol 47/48 clients, and a Playit Linux-agent installer. The extended ReUnion smoke test is being validated separately. No public endpoint or 20–32 player capacity has been claimed yet.

GitHub Actions remains a temporary CI environment, not a persistent public game host. The production game process must run on an always-on Linux host that permits dedicated game servers.

## Stack

- Game: Counter-Strike 1.6 / GoldSrc.
- Engine: ReHLDS 3.15.0.896 (replaces the original HLDS engine binary).
- Compatibility layer: Metamod-R 1.3.0.149 + ReUnion 0.2.0.25.
- Base server/game files: SteamCMD app 90, `steam_legacy` branch, as required by ReHLDS.
- Steamworks runtime: app 1007, for the 32-bit Steam client library used by the dedicated server.
- Game port: UDP 27015.
- Initial map: `de_dust2`.
- Initial production target: 20 slots. Increase only after player/network tests; 32 is the configured ceiling, not a performance guarantee.

ReHLDS replaces the engine but does not replace the Counter-Strike game files. SteamCMD is used to obtain the required base files.

## Repository layout

```text
config/
  server.cfg.example
deploy/
  cs16-rehlds.service
  cs16-rehlds.env.example
  start-cs16-rehlds.sh
docs/
  REHLDS-SETUP.md
  TEST-PLAN.md
  PUBLIC-HOST-PLAYIT.md
scripts/
  install-base-hlds.sh
  install-rehlds.sh
  install-reunion.sh
  install-playit-agent.sh
  provision-ubuntu-host.sh
  validate-config.sh
.github/workflows/
  validate.yml
  rehlds-smoke.yml
```

## Deploy on an always-on Ubuntu/Debian host

Clone this repository on a Linux x86_64 machine that you control and where hosting a game server is permitted, then run:

```bash
sudo bash scripts/provision-ubuntu-host.sh
```

The provisioner installs SteamCMD, the CS 1.6 base files, Steamworks runtime, ReHLDS, Metamod-R, and ReUnion. It generates a private RCON password on the host if one is not already configured, then installs and starts the `cs16-rehlds` systemd service.

The systemd unit uses `Restart=always`, so it brings the game server process back when it exits unexpectedly. It also starts on host boot.

## Expose the server with Playit UDP

Install the official Linux agent:

```bash
sudo bash scripts/install-playit-agent.sh
sudo playit setup
sudo systemctl enable --now playit
```

The `playit setup` command is the one-time account claim. In the Playit dashboard, create a **UDP** tunnel whose local/origin endpoint is `127.0.0.1:27015`. Share the public address and port Playit assigns. The players do not install Playit.

See [docs/PUBLIC-HOST-PLAYIT.md](docs/PUBLIC-HOST-PLAYIT.md) before publishing the address.

## Modified-client compatibility

ReUnion is configured to allow protocol 47 and 48 GoldSrc clients that do not provide a unique authorization ID. These fallback IDs are IP-derived and salted. Players sharing one public IP (for example, behind the same NAT) can therefore share an identity; the configuration disables ReUnion's same-ID connection limit to avoid blocking a group behind one address. This has trade-offs for bans and identity tracking. Do not change the generated `SteamIdHashSalt` after opening the server unless you intend to change generated player IDs.

## Operations

```bash
sudo systemctl status cs16-rehlds
sudo journalctl -u cs16-rehlds -f
sudo systemctl restart cs16-rehlds
sudo systemctl status playit
```

Set `CS16_SLOTS=20`, `CS16_PORT=27015`, and `CS16_MAP=de_dust2` in `/etc/default/cs16-rehlds`. The launcher accepts a maximum of 32 slots. Do not increase the slot count until the server has been tested with real clients.

## Security and boundaries

- Never commit RCON passwords, Steam credentials, Playit agent keys, private keys, or other secrets.
- The provisioner generates a private RCON password locally. Retrieve it on the host only when needed.
- Do not expose RCON without a strong password.
- Use game/server files you are authorized to use.
- Vercel can host a web status/control panel later; it cannot host the persistent UDP game process.
- GitHub Actions validates and tests builds only. It is not used to chain temporary runners into a permanent game host.
