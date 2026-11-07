# ReHLDS Server Test Plan

## Goal

Run public Counter-Strike 1.6 sessions using only GitHub-hosted runners, Playit UDP, and Vercel for the status page. No external VM, VPS, Oracle account, or home server is part of the target design.

## Stage 0 — Repository and configuration

- [x] Shell syntax checks pass for the installation scripts.
- [x] Example server config uses `sv_lan 0`.
- [x] No passwords, Steam credentials, or tunnel tokens are committed.
- [x] Public Vercel status dashboard returns HTTP 200.

## Stage 1 — ReHLDS engine

- [x] SteamCMD app 90 base files install.
- [x] Steamworks runtime app 1007 installs and provides a 32-bit `steamclient.so`.
- [x] ReHLDS 3.15.0.896 release signature verifies.
- [x] Local 20-slot smoke test reports protocol 48, ReHLDS version, server bind, log initialization, and `Round_Start`.

The initial headless `[S_API FAIL] SteamAPI_Init()` diagnostic appeared but was non-fatal in the verified smoke run.

## Stage 2 — ReUnion compatibility

- [x] Metamod-R loads.
- [x] ReUnion appears in `meta list` with status `RUN` in GitHub Actions on 2026-11-07.
- [ ] Protocol 47 client without unique auth ID can connect.
- [ ] Protocol 48 client without unique auth ID can connect.
- [ ] Standard Steam client can connect.
- [ ] Verify two clients behind the same NAT can both connect; document shared IP-derived IDs and ban implications.

## Stage 3 — Scheduled GitHub-hosted session

- [x] Create a session workflow that installs ReHLDS, Metamod-R, and ReUnion.
- [x] Schedule sessions four times per day.
- [x] Keep each session below the six-hour GitHub-hosted job limit.
- [x] Add teardown and session-log artifacts.
- [ ] Add the repository Actions secret `PLAYIT_SECRET_KEY`.
- [ ] Create a UDP tunnel in the Playit dashboard to `127.0.0.1:27015`.
- [ ] Run the first public session and confirm the Playit agent connects.

**Important:** scheduled runs may be delayed or dropped by GitHub. There will be a downtime window between sessions while a new runner installs the files and reconnects Playit. This is not a guaranteed 24/7 service.

## Stage 4 — Public UDP and players

- [ ] Query the public Playit endpoint from another Internet connection.
- [ ] Join from a real CS 1.6 client using the Playit-assigned address and port.
- [ ] Test standard Steam and supported protocol 47/48 clients.
- [ ] Confirm reconnects and map changes.
- [ ] Start at 20 players, then increase to 32 only after measured stability.

## Stage 5 — Vercel status page

- [x] Publish the static status dashboard.
- [ ] Update status only after a public external client successfully joins.
- [ ] Add reliable session-state reporting if it can be done without exposing credentials.

## Current blockers

- `PLAYIT_SECRET_KEY` has not yet been added to GitHub Actions Secrets.
- A UDP tunnel has not yet been configured in Playit.
- No external client has joined yet.
- 20–32-player performance has not been measured.
