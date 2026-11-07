# Deploying to a persistent Linux host from GitHub Actions

## What this workflow does

`.github/workflows/deploy-rehlds-host.yml` is a **manual deployment workflow**. It synchronizes the repository to your Linux host over SSH, runs the host provisioner, and restarts the ReHLDS service.

It does not keep a GitHub runner alive. After deployment completes, systemd on the Linux host is responsible for starting the game server at boot and restarting it if the game process exits.

## Host prerequisites

- Ubuntu or Debian x86_64.
- A machine or VPS that remains powered on and permits game-server hosting.
- A user account with SSH access.
- That user can run the provisioner with passwordless sudo (or an administrator can configure the service before using the workflow).
- SSH host key pinned in advance.

## GitHub Actions secrets

Create these repository secrets under **Settings → Secrets and variables → Actions**:

| Secret | Value |
| --- | --- |
| `CS16_SSH_HOST` | Public IP or DNS name of your Linux host |
| `CS16_SSH_USER` | SSH login username |
| `CS16_SSH_PORT` | SSH port, usually `22` |
| `CS16_SSH_PRIVATE_KEY` | Private SSH key for that deployment user |
| `CS16_SSH_KNOWN_HOSTS` | The host's verified SSH known_hosts line |

Never paste the private key into chat or commit it to the repository. On the server, use a dedicated deploy key and restrict its permissions. Verify the SSH host fingerprint through a trusted channel before adding it to `CS16_SSH_KNOWN_HOSTS`.

The remote user must be able to execute these commands without an interactive password prompt:

```bash
sudo -n bash ~/cs16-deploy/scripts/provision-ubuntu-host.sh
sudo -n systemctl restart cs16-rehlds
sudo -n systemctl is-active cs16-rehlds
```

An administrator can use a narrowly scoped sudoers rule for these exact commands rather than granting broad passwordless sudo.

## Deploy

Once all secrets exist and the host is ready:

1. Open the repository's Actions tab.
2. Select **Deploy ReHLDS to persistent Linux host**.
3. Choose **Run workflow**.

The workflow uses strict SSH host-key checking and will fail before making changes if required secrets are missing or host verification fails.

## After deployment

Check the game service:

```bash
sudo systemctl status cs16-rehlds
sudo journalctl -u cs16-rehlds -f
```

Check Playit:

```bash
sudo systemctl status playit
sudo journalctl -u playit -f
```

The workflow does not claim that the public tunnel works. Confirm the Playit UDP tunnel in the dashboard and join from a separate Internet connection before publishing the address.
