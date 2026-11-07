# ReHLDS Server Test Plan

## Goal

Validate a public Counter-Strike 1.6 ReHLDS server targeting 20–32 slots. GitHub Actions is for bounded CI and local smoke testing; a persistent service runs on a separately controlled Linux host.

## Stage 0 — Repository and configuration

- [x] Shell syntax checks pass for all installers and deploy scripts.
- [ ] Example server config uses `sv_lan 0`.
- [ ] No passwords, Steam credentials, or tunnel tokens are committed.

## Stage 1 — ReHLDS engine

- [x] SteamCMD app 90 base files install.
- [x] Steamworks runtime app 1007 installs and provides a 32-bit `steamclient.so`.
- [x] ReHLDS 3.15.0.896 release signature verifies.
- [x] Local 20-slot smoke test reports protocol 48, ReHLDS version, server bind, log initialization, and `Round_Start`.

The initial ReHLDS-only smoke test passed on 2026-11-07. The headless `[S_API FAIL] SteamAPI_Init()` diagnostic appeared, but no fatal startup error or crash occurred in the verified run.

## Stage 2 — ReUnion compatibility

- [x] Metamod-R loads.
- [x] ReUnion appears in `meta list` with status `RUN` in the GitHub Actions smoke test on 2026-11-07.
- [ ] Protocol 47 client without unique auth ID can connect.
- [ ] Protocol 48 client without unique auth ID can connect.
- [ ] Standard Steam client can connect.
- [ ] Verify two clients behind the same NAT can both connect; document shared IP-derived IDs and ban implications.

## Stage 3 — Persistent host

- [ ] Run `scripts/provision-ubuntu-host.sh` on an always-on permitted Linux host.
- [ ] `cs16-rehlds.service` is active.
- [ ] ReHLDS starts automatically after host reboot.
- [ ] Kill the server process and confirm systemd restarts it.
- [ ] Confirm config, maps, logs, ReUnion salt, and other server data persist.

## Stage 4 — Playit UDP

- [ ] Install the official Playit Linux agent.
- [ ] Claim the agent to the Playit account once.
- [ ] Create UDP tunnel to `127.0.0.1:27015`.
- [ ] Confirm Playit agent service starts at boot.
- [ ] Query the public endpoint from an external network.
- [ ] Join from a real external CS 1.6 client using the assigned public address and port.

## Stage 5 — Capacity and stability

Increase test load gradually: 1, 5, 10, 20, then 32 clients only if all prior levels are stable.

Measure CPU, memory, network throughput, packet loss, server frame stability, and join/leave behavior. A 32-slot setting alone is not proof that the host can sustain 32 players.

## Current blockers

- An always-on production host has not been selected or provisioned.
- Vercel status dashboard is live, but currently displays PREPARING and is not connected to a live UDP query.
- The Playit account agent has not been claimed and no public UDP tunnel exists.
- No external client join has been observed yet.
- ReUnion loading is verified locally in CI; real protocol 47/48 client joins still need testing.
- 20–32-player load testing remains outstanding.
