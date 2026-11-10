# ReHLDS setup and compatibility

## Engine choice

ReHLDS replaces the GoldSrc dedicated-server engine binary. It does not replace Counter-Strike game content. The supported install starts from the pre-anniversary HLDS server files downloaded with SteamCMD, then replaces `engine_i486.so` with the signed ReHLDS binary.

Pinned engine version: **3.15.0.896**.

Official references:
- ReHLDS: https://github.com/rehlds/ReHLDS
- Installation: https://rehlds.dev/docs/rehlds/install/
- Releases: https://github.com/rehlds/ReHLDS/releases

## Base installation

GitHub Actions installs the base files using SteamCMD app 90 on the `steam_legacy` branch, then installs the Steamworks runtime app 1007 for the 32-bit Steam client library.

The ReHLDS installer verifies the release signature, backs up the original engine, and installs the Linux 32-bit ReHLDS engine. ReHLDS requires a CPU with SSE, SSE2, and SSE3.

## ReUnion compatibility for protocols 47/48

ReHLDS alone does not enable every legacy/non-Steam client. ReUnion is a separate Metamod plugin and requires ReHLDS API 3.10+ and Metamod (Metamod-R recommended).

This repository pins:
- Metamod-R **1.3.0.149**
- ReUnion **0.2.0.25**

The installer:
- Places `metamod_i386.so` in `cstrike/addons/metamod`.
- Registers Metamod-R in `liblist.gam`.
- Loads `reunion_mm_i386.so` through Metamod's `plugins.ini`.
- Installs the official `reunion.cfg` with `AuthVersion = 3`.
- Sets `cid_NoSteam47 = 3` and `cid_NoSteam48 = 3` for clients without a unique auth ID.
- Creates a random `SteamIdHashSalt` if none exists.

Type 3 generates a Steam-style ID from the connecting IP. Multiple users behind the same NAT may share an identity. The installer sets `IDClientsLimit = 0` so those users are not blocked by the same-ID connection limit. This has implications for identity-based bans and moderation. Keep the generated salt stable within a session/data set.

After startup, verify the plugin list with `meta list`. ReUnion should show status `RUN`. The smoke-test workflow invokes `meta list` from the HLDS startup command queue; the public-session workflow checks that ReUnion reports `RUN` before declaring the server ready.

## Start a public GitHub-hosted session

The complete temporary-runner setup is automated by:

```text
.github/workflows/cs16-public-session.yml
```

It installs the required files, starts ReHLDS on loopback UDP 27015, and runs the Playit Docker agent using the encrypted `PLAYIT_SECRET_KEY` Actions secret. Do not commit this key.

The workflow is scheduled four times per day. Each job is limited to less than six hours, and GitHub may delay or drop scheduled starts. Players disconnect during each restart and setup interval. See [GITHUB-ACTIONS-SESSIONS.md](GITHUB-ACTIONS-SESSIONS.md) for the setup and limitations.

## Capacity

The session workflow defaults to 20 slots. The 32-slot option should only be selected after a real 20-player test. Slot configuration is not a performance guarantee.
