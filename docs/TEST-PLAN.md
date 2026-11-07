# CS 1.6 Server Test Plan

## Goal

Validate a public Counter-Strike 1.6 server, initially targeting 20–32 player slots, without assuming that GitHub Actions provides a persistent or publicly reachable game host.

## Stage 0 — Repository and configuration

- [ ] GitHub Actions validation workflow passes.
- [ ] Example config uses `sv_lan 0`.
- [ ] Player limit is between 20 and 32.
- [ ] No passwords or tokens are committed.

**Pass condition:** CI validates the tracked files.

## Stage 1 — Dedicated server on an authorized host

On a host where running a game server is permitted:

- [ ] Install HLDS using legitimate Steam/Valve distribution methods.
- [ ] Install/verify the Counter-Strike 1.6 server content.
- [ ] Place the server configuration at `cstrike/server.cfg`.
- [ ] Start with `de_dust2` and a conservative player limit using the HLDS launch argument `+maxplayers N` (for example, `+maxplayers 20`). The `maxplayers` value is a startup argument, not a `server.cfg` directive.
- [ ] Confirm the server process remains healthy.
- [ ] Confirm the server responds to a local GoldSrc server query.

**Pass condition:** HLDS starts without fatal errors and answers a local query.

## Stage 2 — External UDP reachability

- [ ] Confirm which public endpoint and UDP port are assigned by the host or tunnel provider.
- [ ] Confirm that UDP forwarding targets the actual HLDS host and game port.
- [ ] Query the endpoint from a network outside the host.
- [ ] Join using a real CS 1.6 client from an external connection.

**Pass condition:** An external client can query the server and complete a connection. A successful local query alone is not enough.

## Stage 3 — Capacity and stability

Increase test load gradually: 1, 5, 10, 20, then up to 32 clients only if the previous level is stable.

Measure:

- CPU and memory usage.
- Server frame stability.
- Network throughput and packet loss.
- Join/leave behavior.
- Map changes and round transitions.

**Pass condition:** No sustained resource exhaustion or unacceptable network instability at the chosen capacity.

## Stage 4 — Restart and persistence

- [ ] Stop the server cleanly.
- [ ] Restart it on the selected host.
- [ ] Confirm config, maps, and required data persist.
- [ ] Confirm the public endpoint behavior after restart.
- [ ] Record downtime and any address changes.

## GitHub Actions boundary

Actions is used for repository validation and bounded CI tasks. A hosted runner is temporary, with a finite job duration and no guarantee of inbound UDP reachability. Restarting separate jobs is not a dependable 24/7 hosting design and must not be used to evade platform limits.

## Current blockers

- A permitted host for the HLDS process has not yet been selected.
- Public UDP routing has not yet been tested.
- Tunnel provider and credentials have not yet been configured.
- No performance claim for 20–32 players has been verified.
