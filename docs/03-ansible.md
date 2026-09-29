# Ansible

The Proxmox host configuration as code: one playbook that brings a
freshly installed host to the state described in
[01. Proxmox](01-proxmox.md) and [02. Tailscale](02-tailscale.md).

## Why Ansible

The host steps were done by hand first, to learn them. Doing them by hand
again after a reinstall goes against two goals, Reproducible and
Automation. Ansible is already a tool I know from work, and it fits here:
the host is a normal Debian system with SSH, and the playbook only needs
SSH and Python on it.

Talos VMs are a different story: no SSH, no shell, configured through
their API. They come later with OpenTofu, not Ansible.

## Install

Ansible runs on the laptop (WSL). Installed with
[uv](https://docs.astral.sh/uv/), which needs no root and no
`python3-venv` package:

```bash
curl -LsSf https://astral.sh/uv/install.sh | sh
uv tool install --with hvac ansible-core
uv tool install ansible-lint
ansible-galaxy collection install -r requirements.yml
```

## Layout

| Path | What it is |
|------|------------|
| [ansible/ansible.cfg](../ansible/ansible.cfg) | Settings: inventory, roles path, YAML output |
| [ansible/inventory.yml](../ansible/inventory.yml) | The host `pve` and the services VM. Addresses come from OpenBao, so the tailnet address stays out of the repo |
| [ansible/group_vars/all.yml](../ansible/group_vars/all.yml) | Reads `kv/config` from OpenBao with the `community.hashi_vault` lookup |
| [ansible/proxmox.yml](../ansible/proxmox.yml) | The playbook for the host |
| [ansible/requirements.yml](../ansible/requirements.yml) | The `community.proxmox` and `community.hashi_vault` collections |
| [ansible/roles/proxmox_host/](../ansible/roles/proxmox_host/) | The tasks, handlers and compliance checks (`tasks/verify.yml`) |
| [proxmox/](../proxmox/) | The config files the role copies. Each file lives in one place and is explained in 01. Proxmox |

## What it covers

| Covered by the playbook | Still manual |
|-------------------------|--------------|
| Enterprise repos off, no-subscription and Tailscale repos on | Installing Proxmox, the network settings |
| Tailscale signing key, checked by SHA256 | Root password, web UI 2FA and recovery keys |
| `unattended-upgrades` and its drop-in | Copying the SSH key (`ssh-copy-id`) |
| SSH hardening drop-in, validated with `sshd -t` before it is written | Full upgrade and reboot after the install |
| IPv6 sysctl, smartd config | `tailscale up` login, tag, key expiry, Tailnet Lock |
| `rpcbind` off | SMTP notification target (holds a password) |
| Tailscale `--accept-dns=false --auto-update` | The OpenTofu API token (a secret) |
| OpenTofu user `tofu@pve` and role `TofuProvisioner` | |
| Role `TofuBackupStorage` on `/storage/local` only | |
| Let's Encrypt ACME account `default` (only `root@pam` can register one) | The Cloudflare tokens (secrets) |
| Firewall files, behind a dead-man switch | |

The manual column is either a one-time install step or something that
creates or holds a secret. Those stay by hand on purpose.

## Compliance checks

Every run ends with read-only checks, in check mode too, that the host
still matches everything done since the install, including the manual
steps the playbook cannot apply. A failed check stops the run with a red
task and a pointer to the doc section.

| Check | Expects |
|-------|---------|
| Services | `ssh`, `pve-firewall`, `tailscaled`, `smartmontools` and the daily upgrade timer running |
| Not running | `rpcbind`, `fw-deadman.timer` |
| SSH | Root key only, no password or keyboard login, `MaxAuthTries 3` |
| Firewall | On, management IP sets exactly `100.64.0.0/10` and `fd7a:115c:a1e0::/48` |
| Web UI 2FA | `root@pam` has TOTP and recovery keys |
| Tailscale | Tailnet Lock enabled, `tag:server`, MagicDNS off, auto-update on, resolver `1.1.1.1` |
| IPv6, email | `accept_ra` and `autoconf` 0 on `vmbr0`, default matcher sends to the SMTP target |
| ACME | Account `default` exists, on the Let's Encrypt production directory, status `valid` |
| OpenTofu | Both roles' privileges exact, exactly two permission entries for `tofu@pve` (`/` and `/storage/local`), token `opentofu` exists |
| Pending | Reports packages to upgrade and a needed reboot (a note, not a failure) |

Only the checks, without touching anything:

```bash
ansible-playbook proxmox.yml --check --tags verify
```

## Firewall safety

A firewall change is the one task that can lock the host out. The
playbook applies it the same way as the manual procedure in
[01. Proxmox, Firewall](01-proxmox.md#firewall):

1. Compare the repo files with the host. If nothing changed, skip the
   rest.
2. Arm `fw-deadman`: `pve-firewall stop` in 5 minutes.
3. Copy `cluster.fw` and `host.fw`, wait for `pve-firewall` to load them.
4. Open a brand new SSH connection from the laptop, not the one Ansible
   already has open (that one would survive a bad rule).
5. Only if that works, stop the timer. Otherwise the firewall switches
   itself off and the host is reachable again.

Tested for real on a firewall file change: the timer was armed, the new
files loaded, a fresh SSH connection worked, and the timer was stopped.
The firewall stayed on the whole time.

## Running it

There is no wrapper script. Ansible reads OpenBao with the same login as
the `bao` CLI (`VAULT_ADDR` and `~/.vault-token`), so run `bao login` first:

```bash
cd ansible
ansible-lint proxmox.yml                # production profile passes
ansible-playbook proxmox.yml --check --diff   # what would change
ansible-playbook proxmox.yml                  # apply
```

Ansible in this terminal needs its output sent to a file or pipe that
blocks (`> out.txt 2>&1`), otherwise it refuses to start with
"Ansible requires blocking IO". A normal terminal does not need this.

On the current host a full run reports `changed=0 failed=0`: nothing to
change, and every compliance check passes.

## References

- [Ansible documentation](https://docs.ansible.com/)
- [ansible-lint](https://docs.ansible.com/projects/lint/)
- [uv](https://docs.astral.sh/uv/)
- [Proxmox VE firewall](https://pve.proxmox.com/wiki/Firewall)

[Back to the build log](../README.md#work-in-progress)
