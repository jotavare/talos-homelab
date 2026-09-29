# Services VM

The services that run outside the cluster, as Docker containers in a VM
managed by OpenTofu: OpenBao, Garage, a Caddy reverse proxy and
Tailscale. It
replaced the OpenBao container (`130`) and the Garage container (`140`).

## Why

The first version ran each service in its own LXC container, installed
from packages and configured by Ansible. It worked, but every service had
its own way of being installed, reached and given a certificate.
Containers put all of it in one readable place: which images, which
volumes, which ports, how the services reach each other. They started as
Docker Compose files deployed by Ansible, and are now OpenTofu
resources ([Why OpenTofu, and why a separate project](#why-opentofu-and-why-a-separate-project)).

| Choice | Picked | Why |
|--------|--------|-----|
| Where Docker runs | A VM | Proxmox recommends a VM for Docker. Docker inside an LXC container shares the host kernel, and updates to Docker, `runc`, LXC or the kernel have broken it before |
| Reverse proxy | Caddy | The whole config is a short `Caddyfile` in git, and it gets Let's Encrypt certificates by itself |
| Secrets for the stack | OpenBao | App secrets live in OpenBao ([04. Secrets](04-secrets.md#where-secrets-live)) |

Reverse proxies considered:

| Proxy | Config | Certificates | Verdict |
|-------|--------|--------------|---------|
| **Caddy** | `Caddyfile` in git | Built in, DNS-01 through a Cloudflare module, so a small `Dockerfile` | Picked |
| Nginx Proxy Manager | Clicked in its web UI, stored in its own database | Built in, Cloudflare DNS-01 from the UI | Easiest to click, but the proxy hosts are not in git, so a rebuild means clicking them again |
| Traefik | YAML or container labels in git | Built in, Cloudflare included | Already used at work |

## Design

Written before building and corrected where the build changed it.

### VM

| Item | Design | Why |
|------|--------|-----|
| ID, IP | `130`, `192.168.1.30` | Taken over from the OpenBao container it replaced |
| Size | 2 vCPU, 1.5 GB RAM, 32 GB disk | Debian, Docker and the stack use well under 1 GB idle. The data volumes live on the same disk |
| Image | Debian 13 cloud image, cloud-init with my SSH key | Same OS as the containers, no installer to click through |
| Created by | OpenTofu | Like every other machine |
| Containers managed by | The OpenTofu project `opentofu/foundation/`, over SSH as `debian` (in the `docker` group), through `pve` as a jump host | The VM itself is not on the tailnet, only the stack is |
| Docker | Debian's `docker.io` package | Security updates through `unattended-upgrades`, like the rest. Installed once; cloud-init for a rebuilt VM is in the Backlog |
| VM firewall | Inbound `DROP`. SSH from `pve` (`.10`) only. Garage's S3 port later, from its clients | Nothing else needs to reach the VM on the LAN |
| Backups | Added to the daily backup job | Same as the containers |

### Stack

Four containers, each a `docker_container` resource in
[opentofu/foundation/](../opentofu/foundation/). They share one internal
Docker network, `backend`, which has no route out; Tailscale is also on
`services`, a normal bridge, for the way out to the internet:

| Service | Image | Does |
|---------|-------|------|
| `tailscale` | `tailscale/tailscale:v1.102.5`, pinned by digest | Joins the tailnet as one device, `services`, `tag:services`. Caddy shares its network, so the proxy is only reachable over the tailnet. Also on `backend` |
| `caddy` | Built from [services/caddy/Dockerfile](../services/caddy/Dockerfile): `caddy:2.11.4` plus `caddy-dns/cloudflare` v0.2.4 | Listens on 443 of the tailnet address. Certificates for each name from Let's Encrypt through Cloudflare DNS-01 |
| `openbao` | `openbao/openbao:2.7.0`, pinned by digest | The same OpenBao, on `backend` only, port `8200`. Only Caddy reaches it |
| `garage` | `dxflrs/garage:v2.4.1`, pinned by digest | S3 API on `backend`, reached through Caddy as `s3.home.<domain>` ([06. Object storage](06-object-storage.md)) |

Every image is pinned to a version and a digest, so an update is a
commit and a `tofu apply`.

### Names

| Name | Caddy sends it to |
|------|-------------------|
| `https://openbao.home.<domain>` | `127.0.0.1:8200`, OpenBao |
| `https://pve.home.<domain>` | `192.168.1.10:8006`, the Proxmox web UI |

Both DNS records point to the stack's tailnet IP. No port, no browser
warning. The Proxmox UI keeps working on `:8006` too, with its own
certificate.

Caddy ends TLS and speaks plain HTTP to OpenBao over `backend`, a Docker
network inside the VM with no route out. To the Proxmox UI it speaks
HTTPS and checks Proxmox's own Let's Encrypt certificate.

OpenBao is not in Tailscale's network on purpose: it starts on its own,
before Tailscale has a key, which the deploy needs (below).

### Secrets

The stack's secrets come from OpenBao:

| Secret | OpenBao path | Used by |
|--------|--------------|---------|
| Cloudflare token for DNS-01 | `kv/services/caddy` | Caddy |
| Tailscale auth key, pre-signed for Tailnet Lock | `kv/services/tailscale` | The `tailscale` container, first start only |
| Garage RPC secret | `kv/services/garage` | Garage |

| Step | How |
|------|-----|
| Store | By hand with `bao kv put`, logged in as `jotavare` |
| Deploy | OpenTofu reads them with my `bao login` token and copies them into the container with an `upload` block, mode `0600`. Nothing is written to the VM's own disk |
| Use | Files in `/run/secrets/`. Tailscale reads `TS_AUTHKEY=file:/run/secrets/...`, Caddy reads `{file./run/secrets/cloudflare_token}`. Never environment variables with the value |

After a reboot OpenBao starts sealed, but the stack still comes up:
Caddy keeps its certificates on a volume and Tailscale its node state, so
neither needs a secret until a renewal or a new deploy.

The `docker` provider has no write-only arguments, so these secrets are
also in the foundation project's state, encrypted with its passphrase.

### Moving OpenBao

Same version on both sides, so the Raft data moved as it was:

1. The stack's secrets were stored in the old OpenBao, under `kv/`.
2. OpenBao stopped in the container, its `/opt/openbao/data` saved as a
   117 KB tar on `pve`, and a final backup of the container taken and
   marked protected, so retention never deletes it. That backup is the
   rollback: `pct restore 130 <archive>`.
3. OpenTofu removed the container (`3 to destroy`) and created VM `130`.
4. The data went into `/srv/openbao`, owned by the image's `openbao`
   user.
5. Ansible started OpenBao, unsealed it with the same key, logged in as
   `jotavare`, read the secrets and started Tailscale and Caddy.
6. Both DNS names now point at the stack.

Nothing inside OpenBao was created again: same unseal key, same login,
same data.

### Budget

| Resource | Before | Now | After Garage moves in |
|----------|--------|-----|-----------------------|
| RAM for the host | 3 GB | 2.5 GB | 2.5 GB |
| Guests outside the cluster | Two containers, 1 GB | VM 1.5 GB | VM 1.5 GB |

The VM uses about 0.5 GB of its 1.5 GB with the stack running.

### What went away

- Tailscale inside the OpenBao container, and Tailscale Serve on `pve`.
- The OpenBao and Garage containers, their Ansible roles, and the Debian
  container template.
- The Compose files and the Ansible `services` role.
- The `lego` idea for OpenBao's certificate.

## Why OpenTofu, and why a separate project

Every container here is something the main OpenTofu project needs during
its own runs: OpenBao for its tokens and state key, Garage for its state,
Caddy and Tailscale to reach both. If the main project managed them, an
apply that replaced one would cut the ground from under itself: a sealed
OpenBao cannot encrypt the state at the end of the run.

So the stack has its own project, `opentofu/foundation/`, which does not
stand on it. It is called foundation because everything else is built on
what it runs:

| | Main project `opentofu/` | Foundation `opentofu/foundation/` |
|--|--------------------------|-----------------------------------|
| Manages | VM 130, DNS, backups, certificates, later Talos | The containers, images, network and volumes inside VM 130 |
| Reaches its target | Proxmox and Cloudflare APIs | Docker on the VM, over SSH through `pve`, not through Caddy |
| State | Garage, Transit key in OpenBao | A local file on the laptop for now, encrypted with a passphrase |
| Secrets | Ephemeral reads from OpenBao | Read from OpenBao at plan time, kept in its encrypted state |

Settings the `openbao` container needs (the domain) come from a local,
git-ignored `terraform.tfvars`, not from OpenBao. When OpenBao itself is
broken, `tofu apply -target=docker_container.openbao` still works without
it.

Other options were considered and dropped: Ansible (works, but the goal
is OpenTofu wherever possible), the `docker_compose` resource (does not
notice a changed Compose file, and relative bind mounts point at the
laptop), Portainer with GitOps (secrets in its own database, one more
service), and one LXC container per service (same loop, more machines).

## Setup

| File | What it is |
|------|------------|
| [opentofu/foundation/versions.tf](../opentofu/foundation/versions.tf) | Providers, state encryption with the passphrase |
| [opentofu/foundation/providers.tf](../opentofu/foundation/providers.tf) | Docker over SSH, the secrets from OpenBao |
| [opentofu/foundation/variables.tf](../opentofu/foundation/variables.tf) | The passphrase, the `pve` address, the domain and the email |
| [opentofu/foundation/network.tf](../opentofu/foundation/network.tf) | `backend`, `services` and the three volumes |
| [opentofu/foundation/openbao.tf](../opentofu/foundation/openbao.tf), [garage.tf](../opentofu/foundation/garage.tf), [caddy.tf](../opentofu/foundation/caddy.tf) | Images and containers |
| [services/openbao/openbao.hcl](../services/openbao/openbao.hcl) | Raft storage, listener on `8200` without TLS (Caddy does TLS) |
| [services/garage/garage.toml](../services/garage/garage.toml) | Garage, see [06. Object storage](06-object-storage.md#setup) |
| [services/caddy/Caddyfile](../services/caddy/Caddyfile) | The three names, DNS-01 through Cloudflare |
| [services/caddy/Dockerfile](../services/caddy/Dockerfile) | Caddy with the Cloudflare module, built on the VM's Docker (`use_legacy_builder`, since the laptop has no Docker) |

The config files are copied in with `upload` blocks, so a changed file
replaces only its own container.

Running it:

```bash
bao login -method=userpass username=<user>
cd opentofu/foundation
export TF_VAR_state_passphrase="$(bao kv get -mount=kv -field=state_passphrase foundation)"
tofu plan
tofu apply
```

The passphrase is in OpenBao for everyday runs and in Bitwarden for the
day OpenBao is down. Without the variable set, `tofu` asks for it.

An apply that replaces `openbao` leaves it sealed. Unseal it afterwards:

```bash
ssh -t -J root@<PROXMOX_HOST> debian@192.168.1.30 docker exec -it openbao bao operator unseal
```

### The switch from Compose

1. The existing network and volumes were imported (`import` blocks), so
   the Tailscale identity and Caddy's certificates stayed.
2. Images first, with the old containers still running.
3. A saved plan made while OpenBao was up, then the four Compose
   containers removed and the plan applied. A saved plan needs no
   OpenBao to apply.
4. OpenBao unsealed with the same key.
5. Two fixes found on the way: Garage refused its secret file at mode
   `0644` (now `0600`), and Caddy's `network_mode` has to point at
   Tailscale's container ID, not its name, or every plan wants to replace
   it.

Afterwards the Compose files, the Ansible `services` role and the old
secret files in `/srv/secrets` were removed. Both projects plan with
`No changes`, and all three names answer with a valid certificate.

## References

- [Docker Compose](https://docs.docker.com/compose/)
- [Caddy](https://caddyserver.com/docs/) and [caddy-dns/cloudflare](https://github.com/caddy-dns/cloudflare)
- [Tailscale in Docker](https://tailscale.com/kb/1282/docker)
- [OpenBao Docker image](https://hub.docker.com/r/openbao/openbao)
- [Proxmox: containers or VMs for Docker](https://pve.proxmox.com/wiki/Linux_Container)

[Back to the build log](../README.md#work-in-progress)
