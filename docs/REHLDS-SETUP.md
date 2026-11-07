# ReHLDS setup and compatibility

## Why this project uses ReHLDS

ReHLDS replaces the GoldSrc dedicated-server engine binary. It does not replace Counter-Strike game content. The supported install starts from the pre-anniversary HLDS server files downloaded with SteamCMD, then replaces `engine_i486.so` with the signed ReHLDS binary.

Pinned engine version: **3.15.0.896**.

Official references:
- ReHLDS: https://github.com/rehlds/ReHLDS
- Installation: https://rehlds.dev/docs/rehlds/install/
- Releases: https://github.com/rehlds/ReHLDS/releases

## Base installation

On a supported Linux x86_64 host:

```bash
bash scripts/install-base-hlds.sh /path/to/steamcmd.sh /opt/cs16
REHLDS_VERSION=3.15.0.896 bash scripts/install-rehlds.sh /opt/cs16
```

The base installer uses SteamCMD app 90 with the `steam_legacy` branch. The ReHLDS installer verifies the release signature, backs up the previous engine, and installs the Linux 32-bit engine binary.

ReHLDS requires a CPU with SSE, SSE2, and SSE3.

## ReUnion compatibility for protocols 47/48

ReHLDS alone does not enable every legacy/non-Steam client. ReUnion is a separate Metamod plugin and requires ReHLDS API 3.10+ and Metamod (Metamod-R recommended).

This repository pins:
- Metamod-R **1.3.0.149**
- ReUnion **0.2.0.25**

Install both after ReHLDS:

```bash
bash scripts/install-reunion.sh /opt/cs16
```

The installer:
- Places `metamod_i386.so` in `cstrike/addons/metamod`.
- Registers Metamod-R in `liblist.gam`.
- Loads `reunion_mm_i386.so` through Metamod's `plugins.ini`.
- Installs the official `reunion.cfg` with `AuthVersion = 3`.
- Sets `cid_NoSteam47 = 3` and `cid_NoSteam48 = 3` for clients without a unique auth ID.
- Creates a random `SteamIdHashSalt` if none exists.

Type 3 generates a Steam-style ID from the connecting IP. This supports clients without a unique ID, but multiple users behind the same NAT may share an identity. The installer sets `IDClientsLimit = 0` so those users are not blocked by the same-ID connection limit. This also means identity-based bans may affect several users behind one public IP. Keep the generated salt stable; changing it changes the generated IDs.

After startup, verify the plugin list with `meta list`. ReUnion should show status `RUN`.

Official references:
- ReUnion: https://github.com/rehlds/ReUnion
- ReUnion installation: https://rehlds.dev/docs/reunion/install/
- ReUnion settings: https://rehlds.dev/docs/reunion/settings/
- Metamod-R installation: https://rehlds.dev/docs/metamod-r/install/

## Local startup

For a manual local run (20 slots):

```bash
cd /opt/cs16
./hlds_run -norestart -game cstrike -console -port 27015 +maxplayers 20 +map de_dust2
```

The server slot count is a launch argument, not a `server.cfg` cvar. A local process-start test does not prove external UDP connectivity.

## Persistent service

For a long-running host, use the included systemd service rather than GitHub Actions:

```bash
sudo bash scripts/provision-ubuntu-host.sh
sudo systemctl status cs16-rehlds
sudo journalctl -u cs16-rehlds -f
```

The service starts at boot and restarts the server process on exit. GitHub Actions runners are temporary and remain limited to bounded validation/smoke tests.

