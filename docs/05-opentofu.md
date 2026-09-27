# OpenTofu

The VMs and containers on Proxmox as code, with
[OpenTofu](https://opentofu.org/) and the
[bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest)
provider.

## Why OpenTofu

Terraform is what I use at work. OpenTofu is its open source fork, under
the Linux Foundation, and reads the same HCL and providers. It also has
state encryption built in, which Terraform does not, and that matters in
a public repo: the state holds the Talos machine secrets.

## Proxmox user and role

OpenTofu does not use `root`. It gets its own user with a role that holds
only what the provider needs. Both are created by the Ansible playbook
([03. Ansible](03-ansible.md)) and checked on every run.

| Item | Value |
|------|-------|
| User | `tofu@pve`, no password, so it cannot log in to the web UI |
| Role | `TofuProvisioner`, granted on `/` |
| Token | `tofu@pve!opentofu`, privilege separation off |

The role's privileges:

| Privilege | Why |
|-----------|-----|
| `Datastore.AllocateSpace`, `Datastore.Audit` | Create VM and container disks |
| `Datastore.AllocateTemplate` | Download the Talos ISO and the container template |
| `SDN.Use` | Attach VMs to `vmbr0` |
| `Sys.Audit` | Read node information |
| `Sys.Modify` | Required by the ISO download API. The broadest one here |
| `VM.Allocate`, `VM.Audit`, `VM.Clone`, `VM.PowerMgmt` | Create, read, clone, start and stop VMs and containers |
| `VM.Config.*` (CD-ROM, CPU, Cloudinit, Disk, HWType, Memory, Network, Options) | Configure them |
| `VM.GuestAgent.Audit` | Read the IPs reported by the guest agent |

Not included: managing users, permissions, realms or groups, the console,
host power, backups, snapshots and migration.

**Privilege separation off:** the token gets exactly the user's
permissions. With it on, the token needs its own permission entry and
gets the overlap of both. That helps when a user has broad rights and a
token should only get a slice; `tofu@pve` has nothing but this role, so
it would only mean managing the same permissions twice.

## API token

Created by hand, since it is a secret, in **Datacenter → Permissions →
API Tokens → Add**:

| Field | Value |
|-------|-------|
| User | `tofu@pve` |
| Token ID | `opentofu` |
| Privilege Separation | unticked |
| Expire | never |

The popup shows the secret once. It went straight into a SOPS file (see
[04. Secrets](04-secrets.md)), from a terminal outside the editor:

```bash
EDITOR=nano sops secrets/opentofu.sops.yaml
```

```yaml
proxmox_api_token: "tofu@pve!opentofu=<secret>"
```

The format is the token ID, `=`, then the secret. Checks that never print
the secret:

```bash
grep -c "ENC\[" secrets/opentofu.sops.yaml   # 2: one value plus the SOPS MAC
curl -sk -H "Authorization: PVEAPIToken=$(sops decrypt --extract '["proxmox_api_token"]' secrets/opentofu.sops.yaml)" \
  https://pve.<tailnet>.ts.net:8006/api2/json/version   # version 9.2.20
```

Without the header the same request gets `401`. There is no copy in
Bitwarden: if the file is lost, the token is removed and a new one made.

## Install

On the laptop, from the official release, checked against its SHA256SUMS:

```bash
gh release download v1.12.6 -R opentofu/opentofu \
  -p 'tofu_1.12.6_linux_amd64.tar.gz' -p 'tofu_1.12.6_SHA256SUMS'
grep ' tofu_1.12.6_linux_amd64.tar.gz$' tofu_1.12.6_SHA256SUMS | sha256sum -c -
tar xzf tofu_1.12.6_linux_amd64.tar.gz tofu && install -m 755 tofu ~/.local/bin/
```

## Project

| File | What it is |
|------|------------|
| [opentofu/versions.tf](../opentofu/versions.tf) | OpenTofu and provider versions, state encryption |
| [opentofu/providers.tf](../opentofu/providers.tf) | The Proxmox endpoint |
| [opentofu/variables.tf](../opentofu/variables.tf) | The host address and the state passphrase |
| [opentofu/main.tf](../opentofu/main.tf) | Reads the Proxmox version |
| [opentofu/openbao.tf](../opentofu/openbao.tf) | The OpenBao container, its template and firewall |
| [opentofu/run.sh](../opentofu/run.sh) | Runs `tofu` with the secrets from SOPS in its environment |
| `opentofu/terraform.tfstate` | The state, encrypted, kept in git |
| `opentofu/.terraform.lock.hcl` | Pinned provider checksums, kept in git |

`run.sh` decrypts the API token and the state passphrase from
`secrets/opentofu.sops.yaml`, and the host address from
`secrets/env.sops.yaml`, into environment variables for that one
command. Nothing is written to disk in plain text:

```bash
opentofu/run.sh init
opentofu/run.sh plan
opentofu/run.sh apply
```

The provider talks to the web UI's self-signed certificate
(`insecure = true`). The traffic stays inside the tailnet; a real
certificate is in the Backlog.

## State encryption

The state records everything OpenTofu manages, including secrets: later
the Talos cluster CA and etcd keys, the kubeconfig and the talosconfig.
OpenTofu encrypts the state and every saved plan with AES-GCM, using a key
derived (PBKDF2) from a passphrase. `enforced = true` makes it refuse to
write anything unencrypted.

The passphrase was generated straight into the SOPS file, never shown:

```bash
openssl rand -base64 32 \
  | python3 -c 'import json,sys; print(json.dumps(sys.stdin.read().strip()))' \
  | sops set --value-stdin secrets/opentofu.sops.yaml '["state_passphrase"]'
```

Encrypted, the state can live in git, and the repo is its backup. It only
contains `encrypted_data`; with a wrong passphrase OpenTofu stops with
"decryption failed for all provided methods". The commit guard
([04. Secrets](04-secrets.md#commit-guard)) also refuses a state without
`encrypted_data`.

The passphrase for this project stays in SOPS: this state creates
OpenBao, so its key cannot live in OpenBao
([04. Secrets, What stays in SOPS](04-secrets.md#what-stays-in-sops)).
Later projects that do not build OpenBao, such as its configuration, can
use OpenBao as their key provider.

A single state file in git has no locking. That is fine with one person
running OpenTofu from one laptop. Every old state also stays in git
history: if the passphrase and the age key ever leaked, those could be
read too, and a new passphrase only protects new commits. The production
way is a remote backend with locking; see the POC trade-offs in the
[readme](../README.md#poc-trade-offs).

The Garage bucket ([06. Object storage](06-object-storage.md)) could be
that backend, but not for this project. This state creates the Garage
container, so losing Garage would lose the state needed to rebuild it.
Garage also has no versioning and no copy off the host, while git has
both. A remote backend fits later projects, once the buckets have a copy
off the host.

Every run needs the age private key, which lives only on the laptop
(`~/.config/sops/age/keys.txt`): it decrypts the SOPS file, which holds
the passphrase that decrypts the state. Another machine needs a copy of
the key from Bitwarden. CI would get its own age key, added as a second
recipient in `.sops.yaml`, never this one.

`.terraform.lock.hcl` is in git as well, as OpenTofu recommends: it pins
the provider versions and checksums and holds no secrets.

## First plan

Only reads Proxmox, to prove the connection, the token and the
encryption:

```bash
opentofu/run.sh plan
# data.proxmox_version.pve: Read complete
# + proxmox_version = "9.2.20"
```

## OpenBao container

The first real resources, in [opentofu/openbao.tf](../opentofu/openbao.tf).
Why OpenBao runs in its own container is in
[04. Secrets, OpenBao](04-secrets.md#openbao).

| Resource | What it does |
|----------|--------------|
| `proxmox_download_file.debian_13_lxc` | Downloads `debian-13-standard_13.6-1_amd64.tar.zst` to `local` and checks it against the SHA512 from Proxmox's template catalogue |
| `proxmox_virtual_environment_container.openbao` | Container `130`, unprivileged, 1 core, 512 MB RAM, no swap, 8 GB on `local-lvm`, `192.168.1.30`, DNS `1.1.1.1`, starts at boot with `order = 1`, before the VMs |
| `proxmox_virtual_environment_firewall_options.openbao` | Container firewall on, inbound `DROP`, outbound `ACCEPT` |
| `proxmox_virtual_environment_firewall_rules.openbao` | Only UDP `41641` in, for Tailscale direct connections |

`nesting` is on so `systemd` runs properly inside the container, the
Proxmox default for Debian 12 and later. There is no root password and no
SSH server: the container is reached through the host with `pct`.

```bash
opentofu/run.sh plan    # Plan: 4 to add, 0 to change, 0 to destroy.
opentofu/run.sh apply   # shows the plan again, then asks for "yes"
```

`0 to destroy` is the line to read on every plan: anything destroyed that
was not expected is a reason to stop.

Checks on the host:

```bash
pct list                         # 130  running  openbao
pct config 130                   # unprivileged: 1, memory: 512, onboot: 1, ...
cat /etc/pve/firewall/130.fw     # policy_in: DROP, IN ACCEPT -p udp -dport 41641
pct enter 130                    # a shell inside: Debian 13.6, eth0 192.168.1.30/24
```

The token's `TofuProvisioner` role was enough for all of it, firewall
included: no extra privilege was needed.

## References

- [OpenTofu](https://opentofu.org/)
- [OpenTofu state encryption](https://opentofu.org/docs/language/state/encryption/)
- [bpg/proxmox provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Proxmox user management and API tokens](https://pve.proxmox.com/wiki/User_Management)

[Back to the build log](../README.md#work-in-progress)
