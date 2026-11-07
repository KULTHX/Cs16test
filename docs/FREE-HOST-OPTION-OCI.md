# No-cost host candidate: Oracle Cloud Always Free

## Why this is a candidate

Oracle currently lists two Always Free AMD compute VMs, each with:
- 1/8 OCPU and 1 GB memory.
- One VNIC with a public IP and up to 50 Mbps network bandwidth.
- x86 architecture, which is the straightforward target for the current 32-bit GoldSrc/ReHLDS binaries.

Oracle also lists up to 10 TB/month of Always Free outbound data transfer. These are provider quotas, not a guarantee that a free VM can sustain a full 32-player game server.

Official references:
- Free Tier overview: https://www.oracle.com/cloud/free/
- Always Free compute details and idle reclamation: https://docs.oracle.com/en-us/iaas/Content/FreeTier/freetier_topic-Always_Free_Resources.htm
- Oracle Cloud price list: https://www.oracle.com/cloud/price-list/

## Important limitations

1. The AMD micro shape is small: 1/8 OCPU and 1 GB RAM. It may be suitable for a basic server or an initial player test, but 20–32 player performance is unverified.
2. Oracle can reclaim idle Always Free compute instances. Its documented idle test uses a seven-day period; for AMD micro instances, CPU utilization at the 95th percentile below 20% and network utilization below 20% are relevant criteria. A quiet game server could be at risk.
3. Free capacity may not be available in the selected region or availability domain. Oracle documents "out of host capacity" errors for Always Free shapes.
4. Account verification requires an accepted payment card. Always Free eligible usage is not the same as unrestricted free compute; monitor the account's limits and billing.
5. The Arm A1 instance has more memory/CPU quota, but the current ReHLDS distribution in this repository is a 32-bit x86 binary. Do not select ARM for this deployment unless an ARM-compatible execution path has been built and tested separately.

## Suggested first configuration

- Shape: `VM.Standard.E2.1.Micro` (AMD x86).
- Image: Ubuntu 22.04 x86_64.
- Boot volume: stay within the tenancy's Always Free block-volume allocation.
- Networking: assign a public IPv4 for SSH; allow inbound TCP 22 only from your own trusted IP where practical.
- Game transport: do not open inbound UDP 27015 to the public Internet when using Playit. The Playit agent makes an outbound connection and forwards the public UDP tunnel to `127.0.0.1:27015`.
- Security: do not open RCON (default port 27015 is the game port; RCON remains configured inside the game server) publicly. Keep the RCON password private.

## Deploy this repository

After creating the VM and confirming SSH access:

1. Add the host's verified SSH host-key line and a dedicated SSH private key to repository Actions secrets.
2. Configure the secrets listed in [DEPLOY-FROM-GITHUB.md](DEPLOY-FROM-GITHUB.md).
3. Run the **Deploy ReHLDS to persistent Linux host** workflow.
4. Start at 20 slots and measure CPU, RAM, packet loss, and latency with real clients.
5. Test 32 slots only if the 20-slot test is stable.

The game process is restarted by systemd on that VM. GitHub Actions only performs bounded deployment work; it is not the game-server runtime.

## Recommendation

Treat the AMD Always Free VM as a proof-of-concept host. Do not advertise a 20–32 player public server until it has passed external connection and load tests, and do not assume Oracle's Always Free capacity is an uptime SLA.
