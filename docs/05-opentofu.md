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
| [tofu/versions.tf](../tofu/versions.tf) | OpenTofu and provider versions, state encryption |
| [tofu/providers.tf](../tofu/providers.tf) | The Proxmox endpoint |
| [tofu/variables.tf](../tofu/variables.tf) | The host address and the state passphrase |
| [tofu/main.tf](../tofu/main.tf) | The resources. For now only reads the Proxmox version |
| [tofu/run.sh](../tofu/run.sh) | Runs `tofu` with the secrets from SOPS in its environment |
| `tofu/terraform.tfstate` | The state, encrypted, kept in git |
| `tofu/.terraform.lock.hcl` | Pinned provider checksums, kept in git |

`run.sh` decrypts the API token and the state passphrase from
`secrets/opentofu.sops.yaml` into environment variables for that one
command, and reads the host address from the local `.env`. Nothing is
written to disk in plain text:

```bash
tofu/run.sh init
tofu/run.sh plan
tofu/run.sh apply
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

Once OpenBao runs, the passphrase moves there as the key provider. It
stays in SOPS until then, because OpenTofu creates OpenBao.

A single state file in git has no locking. That is fine with one person
running OpenTofu from one laptop.

## First plan

Only reads Proxmox, to prove the connection, the token and the
encryption:

```bash
tofu/run.sh plan
# data.proxmox_version.pve: Read complete
# + proxmox_version = "9.2.20"
```

## References

- [OpenTofu](https://opentofu.org/)
- [OpenTofu state encryption](https://opentofu.org/docs/language/state/encryption/)
- [bpg/proxmox provider](https://registry.terraform.io/providers/bpg/proxmox/latest/docs)
- [Proxmox user management and API tokens](https://pve.proxmox.com/wiki/User_Management)

[Back to the build log](../README.md#work-in-progress)
