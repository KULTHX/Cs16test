# ReHLDS Server Test Plan

## Goal

Validate a public Counter-Strike 1.6 ReHLDS server targeting 20–32 player slots. GitHub Actions is used for bounded validation and a short local smoke test, not permanent hosting.

## Stage 0 — Repository and configuration

- [ ] GitHub Actions configuration validation passes.
- [ ] Both installer scripts pass shell syntax checks.
- [ ] Example config uses `sv_lan 0`.
- [ ] No passwords, Steam credentials, or tunnel tokens are committed.

**Pass condition:** CI validation succeeds.

## Stage 1 — Base server files and ReHLDS engine

On a Linux x86 host where game-server operation is permitted:

- [ ] Install the base CS 1.6 dedicated-server files through SteamCMD app 90, branch `steam_legacy`.
- [ ] Confirm `hlds_run`, `engine_i486.so`, and `cstrike/liblist.gam` exist.
- [ ] Install the pinned ReHLDS release and verify its detached GPG signature.
- [ ] Confirm the original engine was backed up and the ReHLDS engine replaced it.
- [x] Start the bounded GitHub Actions smoke test and confirm the startup log identifies ReHLDS 3.15.0.896.

**CI smoke-test result (2026-11-07): PASSED at 20 slots.** The engine reported ReHLDS 3.15.0.896-dev, protocol 48, the server initialized logging, and the first round started. The headless `[S_API FAIL] SteamAPI_Init()` diagnostic appeared but was non-fatal in this run; no fatal startup error or crash occurred. This does not verify a local client query or public access.

**Pass condition for full Stage 1:** The process starts and remains alive with the ReHLDS engine loaded, and a local GoldSrc query succeeds.

## Stage 2 — Local game-server behavior

- [ ] Place `config/server.cfg.example` at `cstrike/server.cfg`.
- [ ] Start on `de_dust2` with `+maxplayers 20`.
- [ ] Confirm a local GoldSrc query receives a response (not yet tested by the CI smoke test).
- [ ] Join from a local CS 1.6 client.
- [ ] Test round transitions and map changes.

**Pass condition:** A local client can connect, play, disconnect, and reconnect.

## Stage 3 — Public UDP reachability

Only after a permitted public host has been selected:

- [ ] Confirm the host or tunnel provider supports inbound UDP.
- [ ] Forward the assigned public UDP port to the HLDS/ReHLDS game port.
- [ ] Query the public endpoint from a separate network.
- [ ] Join using a real external CS 1.6 client.
- [ ] Record the endpoint and any tunnel restrictions.

**Pass condition:** External query and a real external client connection both succeed.

## Stage 4 — Client compatibility

- [ ] Record client build/version and protocol for each test client.
- [ ] Test standard supported clients first.
- [ ] Test modified clients separately and record exact connection errors.
- [ ] Do not assume ReHLDS alone enables every non-Steam protocol.
- [ ] Evaluate any separate compatibility plugin only after reviewing its behavior and security implications.

**Pass condition:** The supported client matrix is documented and repeatable.

## Stage 5 — Capacity and stability

Increase load gradually: 1, 5, 10, 20, then 32 clients only if prior stages remain stable.

Measure CPU, memory, network throughput, packet loss, server frame stability, and join/leave behavior.

**Pass condition:** No sustained resource exhaustion or unacceptable network instability at the declared capacity.

## Stage 6 — Restart and persistence

- [ ] Stop the server cleanly.
- [ ] Restart it on the selected host.
- [ ] Confirm configuration, maps, and server data persist.
- [ ] Confirm public endpoint behavior after restart.
- [ ] Record downtime and any address changes.

## GitHub Actions boundary

The manual ReHLDS smoke workflow binds to loopback and terminates automatically. Hosted runners are temporary and do not guarantee public UDP reachability. Separate CI jobs must not be chained to evade platform limits or used as a permanent game-server hosting scheme.

## Current blockers

- A permanent or otherwise permitted host for the public server has not been selected.
- Public UDP routing has not been tested.
- Playit tunnel has not been configured.
- No 20–32 player performance result has been verified.
- The exact modified-client builds/protocols to support have not yet been tested.
