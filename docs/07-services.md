# Services VM

The services that run outside the cluster, as one Docker Compose stack
in a VM: OpenBao, a Caddy reverse proxy and Tailscale, later Garage. It
replaces the OpenBao container (`130`), and the Garage container (`140`)
moves in once the rest works.

## Why

The first version ran each service in its own LXC container, installed
from packages and configured by Ansible. It worked, but every service had
its own way of being installed, reached and given a certificate. A
Compose file puts all of it in one readable place: which images, which
volumes, which ports, how the services reach each other.

| Choice | Picked | Why |
|--------|--------|-----|
| Where Docker runs | A VM | Proxmox recommends a VM for Docker. Docker inside an LXC container shares the host kernel, and updates to Docker, `runc`, LXC or the kernel have broken it before |
| Reverse proxy | Caddy | The whole config is a short `Caddyfile` in git, and it gets Let's Encrypt certificates by itself |
| Secrets for the stack | OpenBao | App secrets live in OpenBao ([04. Secrets](04-secrets.md#what-stays-in-sops)) |

Reverse proxies considered:

| Proxy | Config | Certificates | Verdict |
|-------|--------|--------------|---------|
| **Caddy** | `Caddyfile` in git | Built in, DNS-01 through a Cloudflare module, so a small `Dockerfile` | Picked |
| Nginx Proxy Manager | Clicked in its web UI, stored in its own database | Built in, Cloudflare DNS-01 from the UI | Easiest to click, but the proxy hosts are not in git, so a rebuild means clicking them again |
| Traefik | YAML or container labels in git | Built in, Cloudflare included | Already used at work |

## Design

Written before building, so each choice has its reason next to it.

### VM

| Item | Design | Why |
|------|--------|-----|
| ID, IP | `131`, `192.168.1.31` | Next to OpenBao's `.30`, in the services range |
| Size | 2 vCPU, 1.5 GB RAM, 32 GB disk | Debian, Docker and the stack use well under 1 GB idle. The data volumes live on the same disk |
| Image | Debian 13 cloud image, cloud-init with my SSH key | Same OS as the containers, no installer to click through |
| Created by | OpenTofu | Like every other machine |
| Configured by | Ansible over SSH, through `pve` as a jump host | The VM itself is not on the tailnet |
| Docker | Debian's `docker.io` and `docker-compose` packages | Security updates through `unattended-upgrades`, like the rest |
| VM firewall | Inbound `DROP`. SSH from `pve` (`.10`) only. Garage's S3 port later, from its clients | Nothing else needs to reach the VM on the LAN |
| Backups | Added to the daily backup job | Same as the containers |

### Stack

`services/compose.yaml` in the repo, copied to the VM and started by
Ansible:

| Service | Image | Does |
|---------|-------|------|
| `tailscale` | `tailscale/tailscale` | Joins the tailnet as one device, `tag:services`. The other services share its network, so the stack is only reachable over the tailnet |
| `caddy` | Built from `services/caddy/Dockerfile`: `caddy` plus the `caddy-dns/cloudflare` module | Listens on 443 of the tailnet address. Certificates for each name from Let's Encrypt through Cloudflare DNS-01 |
| `openbao` | `openbao/openbao:2.7.0`, pinned by digest | The same OpenBao, listening on `127.0.0.1:8200` inside the shared network. Only Caddy reaches it |
| `garage` | `dxflrs/garage:v2.4.1` | Later. The S3 API on the LAN for the cluster |

Every image is pinned to a version and a digest, so an update is a
commit.

### Names

| Name | Caddy sends it to |
|------|-------------------|
| `https://openbao.home.<domain>` | `127.0.0.1:8200`, OpenBao |
| `https://pve.home.<domain>` | `192.168.1.10:8006`, the Proxmox web UI |

Both DNS records point to the stack's tailnet IP. No port, no browser
warning. The Proxmox UI keeps working on `:8006` too, with its own
certificate.

Caddy ends TLS and speaks plain HTTP to OpenBao, over the loopback
interface the two containers share. That traffic never leaves the
network namespace.

### Secrets

The stack's secrets come from OpenBao, not SOPS:

| Secret | OpenBao path | Used by |
|--------|--------------|---------|
| Cloudflare token for DNS-01 | `kv/services/caddy` | Caddy |
| Tailscale auth key, pre-signed for Tailnet Lock | `kv/services/tailscale` | The `tailscale` container, first start only |
| Garage keys | `kv/services/garage` | Later |

| Step | How |
|------|-----|
| Store | By hand with `bao kv put`, logged in as `jotavare` |
| Deploy | Ansible on the laptop reads them from OpenBao with my own login, and writes them to the VM as files only root can read |
| Use | Compose `secrets:` mount them at `/run/secrets/` in the container that needs them, never as environment variables in the Compose file |

After a reboot OpenBao starts sealed, but the stack still comes up:
Caddy keeps its certificates on a volume and Tailscale its node state, so
neither needs a secret until a renewal or a new deploy.

What stays in SOPS does not change: the Proxmox token, the state
passphrase and the two Cloudflare tokens OpenTofu uses. OpenTofu creates
this VM, so those are needed before OpenBao is there.

### Moving OpenBao

Same version on both sides, so the Raft data moves as it is:

1. Store the stack's secrets in the current OpenBao (container `130`).
2. OpenTofu creates the VM, Ansible installs Docker.
3. Stop OpenBao in `130`, copy `/opt/openbao/data` to the VM's volume.
4. Start the stack, unseal with the same key, log in as `jotavare`.
5. Point `openbao.home.<domain>` at the stack, and update the Tailscale
   policy (`tag:talos` to `tag:services`).
6. Leave `130` stopped as the rollback. Remove it once the new one has
   run for a while.

Nothing inside OpenBao is created again: same unseal key, same login, same
data.

### Budget

| Resource | Before | After, both containers retired |
|----------|--------|-------------------------------|
| RAM | Host 3 GB, containers 1 GB | Host 2.5 GB, services VM 1.5 GB |
| vCPU | 16 | 16 |
| `local-lvm` | 294 GB | 304 GB |

The host keeps 2.5 GB, 0.5 GB less than now. Watch it; if it gets tight,
the VM goes to 1 GB.

### What goes away

- Tailscale inside the OpenBao container, and Tailscale Serve on `pve`.
- The OpenBao and Garage Ansible roles, once their containers are gone.
- The `lego` idea for OpenBao's certificate.

## References

- [Docker Compose](https://docs.docker.com/compose/)
- [Caddy](https://caddyserver.com/docs/) and [caddy-dns/cloudflare](https://github.com/caddy-dns/cloudflare)
- [Tailscale in Docker](https://tailscale.com/kb/1282/docker)
- [OpenBao Docker image](https://hub.docker.com/r/openbao/openbao)
- [Proxmox: containers or VMs for Docker](https://pve.proxmox.com/wiki/Linux_Container)

[Back to the build log](../README.md#work-in-progress)
