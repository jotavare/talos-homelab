# Services VM

The services that run outside the cluster, as one Docker Compose stack
in a VM: OpenBao, a Caddy reverse proxy and Tailscale, later Garage. It
replaced the OpenBao container (`130`), and the Garage container (`140`)
moves in next.

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

Written before building and corrected where the build changed it.

### VM

| Item | Design | Why |
|------|--------|-----|
| ID, IP | `130`, `192.168.1.30` | Taken over from the OpenBao container it replaced |
| Size | 2 vCPU, 1.5 GB RAM, 32 GB disk | Debian, Docker and the stack use well under 1 GB idle. The data volumes live on the same disk |
| Image | Debian 13 cloud image, cloud-init with my SSH key | Same OS as the containers, no installer to click through |
| Created by | OpenTofu | Like every other machine |
| Configured by | Ansible over SSH as `debian` with `sudo`, through `pve` as a jump host | The VM itself is not on the tailnet, only the stack is |
| Docker | Debian's `docker.io` and `docker-compose` packages | Security updates through `unattended-upgrades`, like the rest |
| VM firewall | Inbound `DROP`. SSH from `pve` (`.10`) only. Garage's S3 port later, from its clients | Nothing else needs to reach the VM on the LAN |
| Backups | Added to the daily backup job | Same as the containers |

### Stack

Two Compose projects, one folder each in [services/](../services/),
copied to `/opt/services/` and started by Ansible. They share one internal
Docker network, `backend`, which has no route out:

| Service | Image | Does |
|---------|-------|------|
| `tailscale` (project `proxy`) | `tailscale/tailscale:v1.102.5`, pinned by digest | Joins the tailnet as one device, `services`, `tag:services`. Caddy shares its network, so the proxy is only reachable over the tailnet. Also on `backend` |
| `caddy` (project `proxy`) | Built from [services/proxy/Dockerfile](../services/proxy/Dockerfile): `caddy:2.11.4` plus `caddy-dns/cloudflare` v0.2.4 | Listens on 443 of the tailnet address. Certificates for each name from Let's Encrypt through Cloudflare DNS-01 |
| `openbao` (project `openbao`) | `openbao/openbao:2.7.0`, pinned by digest | The same OpenBao, on `backend` only, port `8200`. Only Caddy reaches it |
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

Caddy ends TLS and speaks plain HTTP to OpenBao over `backend`, a Docker
network inside the VM with no route out. To the Proxmox UI it speaks
HTTPS and checks Proxmox's own Let's Encrypt certificate.

OpenBao is not in Tailscale's network on purpose: it starts on its own,
before Tailscale has a key, which the deploy needs (below).

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
| Deploy | Ansible reads them from OpenBao on the VM itself, over `backend`, logging in as `jotavare`, then writes them as files only root can read in `/srv/secrets/` and logs out |
| Use | Compose `secrets:` mount them at `/run/secrets/`. Tailscale reads `TS_AUTHKEY=file:/run/secrets/...`, Caddy reads `{file./run/secrets/cloudflare_token}`. Never environment variables with the value |

After a reboot OpenBao starts sealed, but the stack still comes up:
Caddy keeps its certificates on a volume and Tailscale its node state, so
neither needs a secret until a renewal or a new deploy.

What stays in SOPS does not change: the Proxmox token, the state
passphrase and the two Cloudflare tokens OpenTofu uses. OpenTofu creates
this VM, so those are needed before OpenBao is there.

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
   `jotavare`, read the secrets and started the proxy.
6. Both DNS names now point at the stack.

Nothing inside OpenBao was created again: same unseal key, same login,
same data.

### Budget

| Resource | Before | Now | After Garage moves in |
|----------|--------|-----|-----------------------|
| RAM for the host | 3 GB | 2 GB | 2.5 GB |
| Guests outside the cluster | Two containers, 1 GB | VM 1.5 GB, Garage 0.5 GB | VM 1.5 GB |

The VM uses about 0.5 GB of its 1.5 GB with the stack running.

### What went away

- Tailscale inside the OpenBao container, and Tailscale Serve on `pve`.
- The OpenBao Ansible role. The Garage role goes when Garage moves in.
- The `lego` idea for OpenBao's certificate.

## Setup

| File | What it is |
|------|------------|
| [services/openbao/compose.yaml](../services/openbao/compose.yaml) | OpenBao, its config and data |
| [services/openbao/openbao.hcl](../services/openbao/openbao.hcl) | Raft storage, listener on `8200` without TLS (Caddy does TLS) |
| [services/proxy/compose.yaml](../services/proxy/compose.yaml) | Tailscale and Caddy, the secret files, UDP `41641` |
| [services/proxy/Caddyfile](../services/proxy/Caddyfile) | The two names, DNS-01 through Cloudflare |
| [services/proxy/Dockerfile](../services/proxy/Dockerfile) | Caddy with the Cloudflare module |
| [ansible/roles/services/](../ansible/roles/services/) | Everything on the VM |

The domain and the email reach the stack through a `.env` file per
project that Ansible writes from SOPS, so neither is in the repo.

What the role does, in order:

| Step | Detail |
|------|--------|
| Packages | `docker.io`, `docker-compose`, `qemu-guest-agent`, `unattended-upgrades` with the host's drop-in |
| Network | Creates `backend` with `--internal` |
| Files | Copies both projects and writes their `.env` |
| Data guard | Stops if `/srv/openbao` is empty, so it never starts a blank OpenBao by mistake |
| OpenBao | Gives the data to the image's user, starts the project and waits for it |
| Unseal | Only if sealed; the key comes from `BAO_UNSEAL_KEY` or a hidden prompt |
| Secrets | Logs in (`BAO_PASSWORD` or a hidden prompt), reads `kv/services/*`, writes `/srv/secrets/*` as `0400`, logs out |
| Proxy | Builds Caddy and starts the project |

```bash
cd ansible
./run.sh services.yml    # asks for the password, and the unseal key if sealed
```

Checks at the end of every run:

| Check | Expects |
|-------|---------|
| Services | `docker`, `qemu-guest-agent`, `unattended-upgrades` running |
| Containers | `openbao`, `tailscale`, `caddy` running |
| Tailnet | The stack's device carries `tag:services` |
| Ports | Nothing on `443` or `8200` on the VM's own interfaces |
| Secrets | Both files owned by root, mode `400` |

Results:

- Both names answer with no port and a valid certificate, over the
  tailnet: `/v1/sys/health` returns `200`, the OpenBao UI and the Proxmox
  UI load.
- From the LAN, `.30:443` and `.30:8200` do not answer.
- Caddy got both certificates on the first start, with the token read from
  OpenBao.

## References

- [Docker Compose](https://docs.docker.com/compose/)
- [Caddy](https://caddyserver.com/docs/) and [caddy-dns/cloudflare](https://github.com/caddy-dns/cloudflare)
- [Tailscale in Docker](https://tailscale.com/kb/1282/docker)
- [OpenBao Docker image](https://hub.docker.com/r/openbao/openbao)
- [Proxmox: containers or VMs for Docker](https://pve.proxmox.com/wiki/Linux_Container)

[Back to the build log](../README.md#work-in-progress)
