# ReHLDS setup

## Why this project uses ReHLDS

ReHLDS is the GoldSrc dedicated-server engine replacement selected for this project. It is maintained as a reverse-engineered, bug-fixed HLDS engine with security fixes and server-side improvements.

**Important distinction:** ReHLDS replaces the HLDS engine binary. It does not replace the Counter-Strike game files. The supported installation path still starts with the pre-anniversary HLDS server files installed through SteamCMD, then replaces the Linux engine library with the ReHLDS build.

Pinned version for this milestone: **3.15.0.896**. The version is pinned so builds remain reproducible; update it deliberately after reviewing release notes.

Official references:
- ReHLDS project: https://github.com/rehlds/ReHLDS
- Installation instructions: https://rehlds.dev/docs/rehlds/install/
- Releases: https://github.com/rehlds/ReHLDS/releases

## 1. Install the base Counter-Strike 1.6 server files

Install SteamCMD and its 32-bit runtime dependencies on a Linux x86_64 host. Then run:

```bash
bash scripts/install-base-hlds.sh /path/to/steamcmd.sh /opt/cs16
```

The script uses anonymous SteamCMD access for dedicated-server app **90**, selects the `steam_legacy` branch, and verifies that the expected CS 1.6 files exist.

This is a prerequisite for ReHLDS, not a decision to run the original HLDS engine. The next step replaces `engine_i486.so` with ReHLDS.

Do not use the retired `hldsupdatetool` 5xxx server builds; current ReHLDS installation documentation says those builds are incompatible.

## 2. Replace the engine with ReHLDS

Run:

```bash
REHLDS_VERSION=3.15.0.896 bash scripts/install-rehlds.sh /opt/cs16
```

The installer:
- Downloads the pinned Linux release archive and its detached signature.
- Imports the published ReHLDS signing key and verifies the signature.
- Finds the Linux `engine_i486.so` in the release archive.
- Backs up the existing engine file.
- Installs the ReHLDS engine in the HLDS server root.

The installer fails closed if signature verification fails or the archive does not contain one unambiguous Linux engine binary.

ReHLDS Linux binaries require a CPU with SSE, SSE2, and SSE3 support.

## 3. Configure and start a local server

Copy the example config:

```bash
cp config/server.cfg.example /opt/cs16/cstrike/server.cfg
```

Set a strong, unique RCON password locally on the host. Do not commit it to Git.

Start a 32-slot server:

```bash
cd /opt/cs16
./hlds_run -game cstrike -console -port 27015 +maxplayers 32 +map de_dust2
```

The player limit is a startup argument, not a `server.cfg` cvar. Begin with 20 slots and increase only after measuring CPU, memory, network behavior, and client stability.

For the public server, the host or UDP tunnel must forward the game port to this process. A local startup test does not prove public UDP reachability.

## 4. Modified-client compatibility

ReHLDS itself is an engine replacement; it does not guarantee that every modified client or every authentication scheme can connect.

The ReHLDS ecosystem documents **ReUnion** as a separate MetaMod plugin for compatibility with non-Steam GoldSrc clients using protocols 47/48. ReUnion has its own client-identification and identity-mapping behavior. It is deliberately not installed in this first milestone. First test ReHLDS with standard clients and identify the exact protocol/build used by the modified clients before selecting any additional compatibility layer.

Reference: https://rehlds.dev/docs/reunion/

## 5. GitHub Actions role

GitHub Actions is used for bounded validation and a short, manually triggered local smoke test. The smoke test binds the game server to loopback and shuts it down automatically. It is not a public hosting workflow and does not attempt to bypass runner limits.

A real public server needs a host where a long-running HLDS/ReHLDS process and inbound UDP are supported. The Playit tunnel can be evaluated later on that host.
