# Persistent public host and Playit UDP

## Important architecture decision

GitHub repositories store source and GitHub Actions runs temporary CI jobs. Vercel serves web applications and short-lived functions. Neither is a suitable persistent UDP game-server host.

The public game process must run on an always-on Linux machine that you control and that permits game-server hosting. It can be a home Linux PC, a permitted VPS, or a dedicated game host. The host must remain powered and connected to the Internet.

## 1. Provision the Linux host

Supported target: Ubuntu/Debian x86_64 with systemd.

Clone this repository on the host, then run:

```bash
sudo bash scripts/provision-ubuntu-host.sh
```

The script:
- Installs 32-bit dependencies and SteamCMD.
- Installs CS 1.6 base files (SteamCMD app 90, `steam_legacy`).
- Installs Steamworks runtime app 1007 and links the 32-bit Steam client library.
- Installs signed ReHLDS 3.15.0.896.
- Installs Metamod-R 1.3.0.149 and ReUnion 0.2.0.25.
- Creates a local random RCON password if one is not already configured.
- Installs and enables `cs16-rehlds.service`.

The server starts with 20 slots and `de_dust2`. The service uses systemd `Restart=always` and starts at host boot.

## 2. Install and claim Playit

Install the official Playit Linux agent package:

```bash
sudo bash scripts/install-playit-agent.sh
```

Claim the agent to your Playit account once:

```bash
sudo playit setup
```

Follow the claim/link instructions shown by Playit. The claim is a one-time account association on this host; keep the generated agent credentials on the host and out of GitHub.

## 3. Create the UDP tunnel

In the Playit dashboard, create a generic **UDP** tunnel:
- Local/origin address: `127.0.0.1`
- Local/origin port: `27015`
- Protocol: UDP

Playit assigns a public hostname/address and port. The public port may differ from local port 27015. Players use the exact public endpoint assigned by Playit.

After the agent is claimed and the tunnel is configured, enable the system service:

```bash
sudo systemctl enable --now playit
sudo systemctl status playit
```

Playit’s official Linux instructions document installing the package and using systemd to run it persistently. Its public product page lists UDP tunneling as an available protocol for custom services. Check your dashboard for current plan details because provider limits can change.

## 4. Verify from outside the host

First check local service health:

```bash
sudo systemctl status cs16-rehlds
sudo journalctl -u cs16-rehlds -f
sudo systemctl status playit
```

Then, from a separate Internet connection:
1. Query the public Playit endpoint with a current GoldSrc server browser/query tool.
2. Join from a CS 1.6 client using the assigned hostname and port.
3. Confirm the player appears in the server console/log.
4. Test disconnect/reconnect and map changes.

Do not advertise the server as public until an external client has joined successfully.

## 5. Compatibility and identity notes

ReUnion maps protocol 47/48 clients without unique IDs to IP-derived Steam-style IDs. Users behind the same NAT can therefore share an identity. The configuration allows multiple sessions with the same generated ID, but bans and identity-based administration may affect multiple users behind one public IP. The generated `SteamIdHashSalt` is stored in `/opt/cs16/cstrike/addons/reunion/reunion.cfg`; keep it private and stable.

## 6. Service operations

```bash
# Game server
sudo systemctl status cs16-rehlds
sudo systemctl restart cs16-rehlds
sudo journalctl -u cs16-rehlds -f

# Playit tunnel agent
sudo systemctl status playit
sudo systemctl restart playit
sudo journalctl -u playit -f

# Slot count / map
sudo nano /etc/default/cs16-rehlds
sudo systemctl restart cs16-rehlds
```

Start at 20 slots. Increase to 32 only after measured load tests. Do not use a sequence of GitHub Actions jobs to imitate an always-on service.
