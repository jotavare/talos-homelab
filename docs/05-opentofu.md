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
| `VM.Backup` | Put VMs and containers in a backup job |
| `VM.Config.*` (CD-ROM, CPU, Cloudinit, Disk, HWType, Memory, Network, Options) | Configure them |
| `VM.GuestAgent.Audit` | Read the IPs reported by the guest agent |

Not included: managing users, permissions, realms or groups, the console,
host power, snapshots and migration.

A backup job also needs `Datastore.Allocate` on the storage it writes to.
That privilege can change or remove the storage and delete any volume on
it, backups included, so it is not in the main role. A second role,
`TofuBackupStorage`, adds it on `/storage/local` only:

| Role | Path | Privileges |
|------|------|------------|
| `TofuProvisioner` | `/` | The table above |
| `TofuBackupStorage` | `/storage/local` | `Datastore.Allocate`, `Datastore.AllocateSpace`, `Datastore.AllocateTemplate`, `Datastore.Audit` |

The second role repeats the storage privileges of the first on purpose.
In Proxmox a permission entry on a more specific path replaces the
inherited one for the same user. With only `Datastore.Allocate` there,
the token lost `Datastore.Audit` on `local`, could no longer see the
Debian template, and the next plan wanted to destroy and recreate both
containers. The `0 to destroy` line caught it before anything was
applied.

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
| [opentofu/providers.tf](../opentofu/providers.tf) | The Proxmox endpoint and the Cloudflare provider |
| [opentofu/variables.tf](../opentofu/variables.tf) | Values that come from SOPS: addresses, domain, zone, passphrase, a token |
| [opentofu/main.tf](../opentofu/main.tf) | Reads the Proxmox version |
| [opentofu/openbao.tf](../opentofu/openbao.tf) | The OpenBao container, its template and firewall |
| [opentofu/garage.tf](../opentofu/garage.tf) | The Garage container, its data volume and firewall |
| [opentofu/backups.tf](../opentofu/backups.tf) | The daily backup job for the containers |
| [opentofu/dns.tf](../opentofu/dns.tf) | DNS records in Cloudflare |
| [opentofu/acme.tf](../opentofu/acme.tf) | The Let's Encrypt certificate for the Proxmox web UI |
| [opentofu/run.sh](../opentofu/run.sh) | Runs `tofu` with the secrets from SOPS in its environment |
| `opentofu/terraform.tfstate` | The state, encrypted, kept in git |
| `opentofu/.terraform.lock.hcl` | Pinned provider checksums, kept in git |

`run.sh` is a table: each `load` line names an environment variable, the
SOPS file in [secrets/](../secrets/) and the key to decrypt into it, for
that one command. Nothing is written to disk in plain text. A new value
is one more line:

```sh
load TF_VAR_domain                     env.sops.yaml       DOMAIN
load CLOUDFLARE_API_TOKEN              opentofu.sops.yaml  cloudflare_dns_token
```

Run it with:

```bash
opentofu/run.sh init
opentofu/run.sh plan
opentofu/run.sh apply
```

The provider talks to the web UI by its tailnet IP, so it cannot check
the certificate (`insecure = true`). The traffic stays inside the
tailnet. The web UI now has a real certificate
([DNS and certificates](#dns-and-certificates)); switching the provider
to that name is in the Backlog.

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

## Garage container

In [opentofu/garage.tf](../opentofu/garage.tf), next to OpenBao and from
the same template. The design is in
[06. Object storage](06-object-storage.md#design).

| Resource | What it does |
|----------|--------------|
| `proxmox_virtual_environment_container.garage` | Container `140`, unprivileged, 1 core, 512 MB RAM, no swap, 4 GB root plus a 10 GB data volume at `/var/lib/garage/data`, `192.168.1.40`, starts at boot with `order = 1` |
| `proxmox_virtual_environment_firewall_options.garage` | Container firewall on, inbound `DROP`, outbound `ACCEPT` |
| `proxmox_virtual_environment_firewall_rules.garage` | Only TCP `3900` in, and only from OpenBao (`192.168.1.30`) |

The data volume sets `backup = true`: Proxmox leaves mount point volumes
out of backups unless told otherwise.

```bash
opentofu/run.sh plan    # Plan: 3 to add, 0 to change, 0 to destroy.
opentofu/run.sh apply
```

Checks on the host:

```bash
pct config 140                  # mp0: local-lvm:vm-140-disk-1,mp=/var/lib/garage/data,backup=1,size=10G
cat /etc/pve/firewall/140.fw    # policy_in: DROP, IN ACCEPT -source 192.168.1.30 -p tcp -dport 3900
pct exec 140 -- df -h /var/lib/garage/data
```

Idle, the container uses under 20 MB of its 512 MB. Like OpenBao, it
comes with an SSH server from the template, which the Ansible role
removes.

## Backup job

In [opentofu/backups.tf](../opentofu/backups.tf): the daily backup of
both containers, described in
[01. Proxmox, Container backups](01-proxmox.md#container-backups). The
guests come from the container resources, so a new container is one line
in `vmid`.

The job was first created by hand to test it, then brought under
OpenTofu with an `import` block, removed again after the apply:

```hcl
import {
  to = proxmox_backup_job.containers
  id = "daily-containers"
}
```

```bash
opentofu/run.sh plan    # Plan: 1 to import, 0 to add, 0 to change, 0 to destroy.
opentofu/run.sh apply
```

Drift test: `keep-last` changed to 3 on the host showed up in the next
plan as `"keep-last" = "3" -> "7"`, and the apply set it back.

The token can edit this job but, with `Datastore.Allocate` on `local`, it
could also delete the backups there. Worth another look with Proxmox
Backup Server, which has its own users and can keep pruning to itself.

## DNS and certificates

Trusted certificates for the admin UIs, from Let's Encrypt, with nothing
exposed to the internet: the DNS-01 challenge proves the domain with a TXT
record in Cloudflare instead of a web server.

### Names

Public A records in Cloudflare point each name at its tailnet IP:

| Name | Points to |
|------|-----------|
| `pve.home.<domain>` | The Proxmox host's tailnet IP |
| `openbao.home.<domain>` | The OpenBao container's tailnet IP |

They resolve for anyone, but the `100.x` addresses only answer inside the
tailnet. The other options were split DNS on the tailnet (one more
service to run, and nothing resolves when it is down) and `/etc/hosts`
on every device (no phones). Public records reveal the host names, so the
certificates are per host rather than one wildcard: a wildcard would hide
nothing more.

### Cloudflare tokens

Account API tokens, each limited to **DNS: Edit** on the one zone, so a
leaked token can only change this domain's records. One per job, so each
can be revoked alone:

| Token | Used by | Kept in |
|-------|---------|---------|
| `opentofu-dns` | OpenTofu, for the records (`CLOUDFLARE_API_TOKEN`) | `opentofu.sops.yaml` |
| `pve-acme` | Proxmox, to renew its certificate | `opentofu.sops.yaml`, then Proxmox's own plugin config |

The zone ID is in `env.sops.yaml`, so the tokens need no Zone Read
permission. The `pve-acme` token reaches Proxmox through `data_wo`, a
write-only argument: OpenTofu sends it but never stores it in the state.
Changing it means raising `data_wo_version`.

### Proxmox web UI certificate

| Part | Where | Why |
|------|-------|-----|
| ACME account `default`, Let's Encrypt | Ansible ([03. Ansible](03-ansible.md)) | The API only lets `root@pam` register an account |
| DNS plugin `cloudflare` (`proxmox_acme_dns_plugin`) | OpenTofu | Needs `Sys.Modify` on `/`, already in the role |
| Certificate for `pve.home.<domain>` (`proxmox_acme_certificate`) | OpenTofu | Needs `Sys.Modify` on `/nodes/pve`, already in the role |
| Renewal | Proxmox's daily `pve-daily-update` timer | Renews by itself 30 days before expiry, no OpenTofu run needed |

Proxmox cannot issue a wildcard: its ACME domain format only allows
plain labels, so `*` is refused. With per-host certificates that does not
matter.

```bash
opentofu/run.sh plan    # Plan: 4 to add, 0 to change, 0 to destroy.
opentofu/run.sh apply   # the certificate took 51 seconds
```

Checks:

```bash
dig +short @1.1.1.1 pve.home.<domain>          # the host's 100.x address
echo | openssl s_client -connect pve.home.<domain>:8006 2>/dev/null \
  | openssl x509 -noout -issuer -dates          # issuer=C=US, O=Let's Encrypt, 90 days
```

`https://pve.home.<domain>:8006` now opens with no browser warning.

## References

- [OpenTofu](https://opentofu.org/)
- [OpenTofu state encryption](https://opentofu.org/docs/language/state/encryption/)
- [bpg/proxmox provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Proxmox user management and API tokens](https://pve.proxmox.com/wiki/User_Management)
- [Proxmox certificate management](https://pve.proxmox.com/wiki/Certificate_Management)
- [Cloudflare OpenTofu provider](https://registry.terraform.io/providers/cloudflare/cloudflare/latest/docs)
- [Let's Encrypt challenge types](https://letsencrypt.org/docs/challenge-types/)

[Back to the build log](../README.md#work-in-progress)
