# Services

The services that run outside the cluster, as Docker containers in a VM
managed by OpenTofu: OpenBao, Garage, Pocket ID, a Caddy reverse proxy
and Tailscale. It replaced the OpenBao container (`130`) and the Garage
container (`140`).

![Services VM: Tailscale forwards tailnet port 443 to a custom Caddy build, which gets certificates from Let's Encrypt and proxies to OpenBao, Pocket ID and Garage on an internal network and to the Proxmox UI on the LAN, while OpenTofu deploys the containers over SSH through pve](../diagrams/services.png)

## Why

The first version ran each service in its own LXC container, installed
from packages and configured by Ansible. It worked, but every service had
its own way of being installed, reached and given a certificate.
Containers put all of it in one readable place: which images, which
volumes, which ports, how the services reach each other. They started as
Docker Compose files deployed by Ansible, and are now OpenTofu
resources ([Why OpenTofu](#why-opentofu)).

| Choice | Picked | Why |
|--------|--------|-----|
| Where Docker runs | A VM | Proxmox recommends a VM for Docker. Docker inside an LXC container shares the host kernel, and updates to Docker, `runc`, LXC or the kernel have broken it before |
| Reverse proxy | Caddy | The whole config is a short `Caddyfile` in git, and it gets Let's Encrypt certificates by itself |
| Secrets for the stack | OpenBao | App secrets live in OpenBao ([Secrets](secrets.md#where-secrets-live)) |

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
| Containers managed by | OpenTofu, over SSH as `debian` (in the `docker` group), through `pve` as a jump host | The VM itself is not on the tailnet, only the stack is |
| Docker | Debian's `docker.io` package | Security updates through `unattended-upgrades`, like the rest. Installed once; cloud-init for a rebuilt VM is [#19](https://github.com/jotavare/talos-homelab/issues/19) |
| VM firewall | Inbound `DROP`. SSH from `pve` (`.10`) only. Garage's S3 port later, from its clients | Nothing else needs to reach the VM on the LAN |
| Backups | Added to the daily backup job | Same as the containers |

### Stack

Five containers, each a `docker_container` resource in
[iac/modules/services/](../iac/modules/services/). The apps share one internal
Docker network, `backend`, which has no route out. Caddy and Tailscale
are also on `services`, a normal bridge, for the way out to the internet:

| Service | Image | Does |
|---------|-------|------|
| `tailscale` | `tailscale/tailscale:v1.102.5`, pinned by digest | Joins the tailnet as one device, `services`, `tag:services`, and forwards tailnet port 443 to `caddy:443` with `tailscale serve` (`TS_SERVE_CONFIG`). Nothing else on the VM listens on the tailnet. Only on `services` |
| `caddy` | Built from [caddy/Dockerfile](../iac/modules/services/caddy/Dockerfile): `caddy:2.11.4` plus `caddy-dns/cloudflare` v0.2.4 | Listens on 443 inside Docker, reached only through the Tailscale forward. Also on `backend` for the apps. Certificates for each name from Let's Encrypt through Cloudflare DNS-01 |
| `openbao` | `openbao/openbao:2.7.0`, pinned by digest | The same OpenBao, on `backend` only, port `8200`. Only Caddy reaches it |
| `pocket-id` | `pocketid/pocket-id:v2.16.0`, pinned by digest | Single sign-on with passkeys, reached as `auth.home.<domain>` ([SSO with Pocket ID](sso.md)) |
| `garage` | `dxflrs/garage:v2.4.1`, pinned by digest | S3 API on `backend`, reached through Caddy as `s3.home.<domain>` ([Object storage](services.md#garage)) |

Every image is pinned to a version and a digest, so an update is a
commit and a `tofu apply`.

### Names

Every `*.home.<domain>` name, and who serves it:

| Name | Served by | Goes to |
|------|-----------|---------|
| `https://openbao.home.<domain>` | Caddy | `openbao:8200`, OpenBao |
| `https://auth.home.<domain>` | Caddy | `pocket-id:1411`, Pocket ID |
| `https://s3.home.<domain>` | Caddy | `garage:3900`, Garage's S3 API |
| `https://pve.home.<domain>` | Caddy | `192.168.1.10:8006`, the Proxmox web UI |
| `https://proxmox.home.<domain>:8006` | Proxmox itself | `pve`'s tailnet IP, for OpenTofu ([OpenTofu](opentofu.md#reaching-proxmox)) |
| `https://immich.home.<domain>` | Cilium Gateway in the cluster | Immich ([Talos, Gateway](platform.md#secrets-certificates-and-the-gateway)) |

Caddy only serves what runs outside the cluster. Apps in the cluster have
their own entry point, the Cilium Gateway, with its own wildcard
certificate.

The Caddy records point to the stack's tailnet IP. No port, no browser
warning. The Proxmox UI keeps working on `:8006` too, with its own
certificate.

Caddy ends TLS and speaks plain HTTP to OpenBao over `backend`, a Docker
network inside the VM with no route out. To the Proxmox UI it speaks
HTTPS and checks Proxmox's own Let's Encrypt certificate.

OpenBao is not in Tailscale's network on purpose: it starts on its own,
before Tailscale has a key, which the deploy needs (below).

### Caddy and Tailscale after a reboot

Caddy first shared the `tailscale` container's network namespace
(`network_mode = "container:..."`), the usual sidecar pattern. After a
reboot of the VM, Docker started Caddy before Tailscale, failed with
`cannot join network of a non running container`, and never retried,
whatever the restart policy. Compose hides this with `depends_on`; plain
`docker_container` resources have no start order.

Now each container has its own network. Tailscale runs in userspace mode
and its serve config forwards raw TCP on 443 to `caddy:443`, so TLS still
ends at Caddy. Either can start first: until Caddy is up, the forward just
fails. Checked with `qm reboot 130`: every container came back on its
own and all four names answered.

### Secrets

The stack's secrets come from OpenBao:

| Secret | OpenBao path | Used by |
|--------|--------------|---------|
| Cloudflare token for DNS-01 | `kv/services/caddy` | Caddy |
| Tailscale auth key, pre-signed for Tailnet Lock | `kv/services/tailscale` | The `tailscale` container, first start only |
| Garage RPC secret | `kv/services/garage` | Garage |
| Pocket ID database encryption key and static API key | `kv/services/pocket-id` | Pocket ID, and OpenTofu for the API key |

| Step | How |
|------|-----|
| Store | By hand with `bao kv put`, logged in as `jotavare` |
| Deploy | OpenTofu reads them with my `bao login` token and copies them into the container with an `upload` block, mode `0600`. Nothing is written to the VM's own disk |
| Use | Files in `/run/secrets/`. Tailscale reads `TS_AUTHKEY=file:/run/secrets/...`, Caddy reads `{file./run/secrets/cloudflare_token}`. Never environment variables with the value |

After a reboot OpenBao starts sealed, but the stack still comes up:
Caddy keeps its certificates on a volume and Tailscale its node state, so
neither needs a secret until a renewal or a new deploy.

The `docker` provider has no write-only arguments, so these secrets are
also in the OpenTofu state, encrypted with its passphrase.

### Moving OpenBao

Same version on both sides, so the Raft data moved as it was:

1. The stack's secrets were stored in the old OpenBao, under `kv/`.
2. OpenBao stopped in the container, its `/opt/openbao/data` saved as a
   117 KB tar on `pve`, and a final backup of the container taken and
   marked protected, so retention never deletes it. That backup was the
   rollback (`pct restore 130 <archive>`), deleted after the VM had run
   for a week.
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

## Why OpenTofu

The containers are `docker_container` resources in the same OpenTofu
project as everything else ([OpenTofu](opentofu.md#project)). Two
things keep that safe even though OpenTofu depends on what runs here:

- The state is a local file encrypted with a passphrase, so an apply that
  restarts Garage or leaves OpenBao sealed can still save it.
- OpenTofu reaches Docker over SSH through `pve` and Proxmox directly, not
  through Caddy, so replacing Caddy or Tailscale does not cut the run.

Settings the `openbao` container needs (the domain) come from the local
`terraform.tfvars`, not from OpenBao. When OpenBao itself is broken,
`tofu apply -target=docker_container.openbao` still works.

Other options were tried or considered: Ansible with Compose (worked, but
the goal is OpenTofu wherever possible), a separate OpenTofu project for
the stack (merged back into one, once the state was local), the
`docker_compose` resource (does not notice a changed Compose file, and
relative bind mounts point at the laptop), Portainer with GitOps (secrets
in its own database, one more service), and one LXC container per
service (more machines, same dependency).

## Setup

All in [iac/modules/services/](../iac/modules/services/):

| File | What it is |
|------|------------|
| [network.tf](../iac/modules/services/network.tf) | `backend`, `services` and the three volumes |
| [openbao.tf](../iac/modules/services/openbao.tf), [garage.tf](../iac/modules/services/garage.tf), [caddy.tf](../iac/modules/services/caddy.tf), [pocketid.tf](../iac/modules/services/pocketid.tf) | Images and containers |
| [openbao/openbao.hcl](../iac/modules/services/openbao/openbao.hcl) | Raft storage, listener on `8200` without TLS (Caddy does TLS) |
| [garage/garage.toml](../iac/modules/services/garage/garage.toml) | Garage, see [Object storage](services.md#garage-setup) |
| [caddy/Caddyfile](../iac/modules/services/caddy/Caddyfile) | The four names, DNS-01 through Cloudflare |
| [caddy/Dockerfile](../iac/modules/services/caddy/Dockerfile) | Caddy with the Cloudflare module, built on the VM's Docker (`use_legacy_builder`, since the laptop has no Docker) |

The config files are copied in with `upload` blocks, so a changed file
replaces only its own container. Run it like the rest of the project
([OpenTofu](opentofu.md#project)).

Every stateful container has `destroy_grace_seconds = 30`: OpenTofu's
default is to kill a container it replaces, which left Pocket ID with a
stale "already running" lock in its database. With a clean stop, a
replacement takes about a second.

An apply that replaces `openbao` leaves it sealed. Unseal it afterwards:

```bash
ssh -t -J root@<PROXMOX_HOST> debian@192.168.1.30 docker exec -it openbao bao operator unseal
```

## The switch from Compose

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

## Garage

An S3-compatible bucket store for backups, as a container on the services
VM, next to OpenBao and outside the cluster.

### Why outside the cluster

Backups of the cluster cannot live in the cluster. A broken or rebuilt
cluster would take its own backups down with it, and OpenBao, which runs
outside the cluster, needs somewhere to send its snapshots before the
cluster even exists. Same reasoning as for OpenBao in
[Secrets, OpenBao](secrets.md#openbao).

### Why Garage

State of the S3 options when this was written:

| Option | Status | Fit here |
|--------|--------|----------|
| **Garage** | v2.3.0, active, single binary, built for small self-hosted setups | Low RAM, single-node mode, lifecycle rules. No versioning or object lock |
| SeaweedFS | Active, more moving parts (master, volume, filer) | The fallback if versioning or object lock become a requirement |
| MinIO | Community edition archived, no more releases | Out |
| RustFS | Still alpha | Out for now, worth another look later |
| Ceph (RGW) | Mature, but several daemons and a lot of RAM | Built for many disks and machines, not one box |
| VersityGW | Active, an S3 gateway in front of a file system | Adds an S3 API to a file system or NAS I do not have |
| Directory on the Proxmox host | Nothing to install | No S3 API, which Velero and Longhorn need, and backups mixed with the host |
| Cloudflare R2 | Managed, 10 GB free, no egress fees | Off the host, but a cloud service for the primary copy, against the self-hosted goal. The best candidate for the copy off the host |
| AWS S3, Google Cloud Storage, Azure Blob | Managed, versioning and object lock | Same as R2, with paid egress on top |

MinIO is the one I know from before. With its community edition gone,
Garage is the new tool, which also fits the goal of learning what I do not
use at work. The cloud services are not out for good: one of them is where
the copy off the host goes.

### Garage design

| Item | Design | Why |
|------|--------|-----|
| Runs in | A container on the services VM, managed by OpenTofu, image `dxflrs/garage:v2.4.1` pinned by digest ([Services](services.md)) | One place for the services outside the cluster |
| Mode | `--single-node`, replication factor 1, LMDB metadata with automatic snapshots every 6 hours | Garage sets up its own one-node layout. Metadata snapshots let it recover from a corrupted database |
| Storage | `/srv/garage/meta` and `/srv/garage/data` on the VM's disk | Covered by the daily VM backup |
| Listens on | S3 API `3900` on the internal `backend` network only. RPC `3901` inside the container | Nothing on the LAN reaches it directly |
| Reached through | Caddy, `https://s3.home.<domain>`, over the tailnet | One name, a real certificate, tailnet only |
| RPC secret | Generated into OpenBao (`kv/services/garage`), written to the VM by Ansible | Not in git; with one node, nothing else needs it |
| Buckets and keys | One bucket and one access key per client. A key can only read and write its own bucket | One leaked key exposes one set of data, not all of it |
| Key storage | In OpenBao, never in git | Every secret lives in OpenBao |
| Retention | Lifecycle rule per backup bucket, objects expire after 14 days | Old backups clean themselves up |

Garage first ran in its own LXC container (`140`), installed as a binary
by Ansible, with its own firewall. It moved into the services stack before
it held any data, and the container was removed.

#### Buckets

| Bucket | Client | When |
|--------|--------|------|
| `openbao-snapshots` | OpenBao, daily timer | Optional |
| `etcd-snapshots` | Talos etcd backup job in the cluster | With the cluster |
| `velero` | Velero | With the cluster |
| `longhorn` | Longhorn backup target | With the cluster |

The Talos nodes reach Garage through `s3.home.<domain>` over the tailnet:
the policy lets `tag:talos` reach `tag:services` on `443`.

Velero and Longhorn need two settings to work with Garage: path-style
URLs (`s3ForcePathStyle: true`) and no request checksums
(`checksumAlgorithm: ""`), which newer AWS SDKs send by default and Garage
does not accept.

#### OpenBao snapshots

Optional. The daily VM backup
([Proxmox, Container backups](proxmox.md#container-backups))
already covers OpenBao. A Raft snapshot adds a small file that restores
into any OpenBao, and restores the data without rolling back the VM.

1. A `bao` policy that can only read `sys/storage/raft/snapshot`, and a
   periodic token with only that policy, created by hand and kept in a
   file only root can read on the VM.
2. A daily `systemd` timer runs `bao operator raft snapshot save`, keeps
   the last three snapshots on the VM, and copies the new one to
   `openbao-snapshots` with `rclone`.
3. A Raft snapshot holds the data still encrypted by OpenBao. Restoring it
   needs the unseal key, which is not on the VM.

#### Limits

It shares the host and the NVMe with everything it backs up. It protects
against a deleted bucket, a bad upgrade or a rebuilt cluster, not
against losing the host or the drive (see the POC trade-offs in the
[readme](../README.md#poc-trade-offs)). No versioning or object lock
either: a client whose key leaks can delete its own bucket. A copy off the
host, most likely to Cloudflare R2, is [#27](https://github.com/jotavare/talos-homelab/issues/27).

#### The OpenTofu state

The OpenTofu state lived here for a while and moved to a local file: an
apply that restarted Garage could not save its own state
([OpenTofu](opentofu.md#how-the-state-got-here)).

### Garage setup

The container is in [modules/services/garage.tf](../iac/modules/services/garage.tf)
([Services](services.md#setup)):

| File | What it is |
|------|------------|
| [garage.tf](../iac/modules/services/garage.tf) | Garage on `backend`, the RPC secret in `/run/secrets/`, data under `/srv/garage` |
| [garage.toml](../iac/modules/services/garage/garage.toml) | Replication factor 1, LMDB, S3 API on `3900`, region `garage` |

Buckets and keys, made with the CLI inside the container:

```bash
ssh -J root@<PROXMOX_HOST> debian@192.168.1.30
sudo docker exec garage /garage bucket create opentofu-state
sudo docker exec garage /garage key create opentofu
sudo docker exec garage /garage bucket allow --read --write opentofu-state --key opentofu
```

The key went straight into OpenBao (`kv/opentofu`), never printed.

## References

- [Docker Compose](https://docs.docker.com/compose/)
- [Caddy](https://caddyserver.com/docs/) and [caddy-dns/cloudflare](https://github.com/caddy-dns/cloudflare)
- [Tailscale in Docker](https://tailscale.com/kb/1282/docker)
- [OpenBao Docker image](https://hub.docker.com/r/openbao/openbao)
- [Proxmox: containers or VMs for Docker](https://pve.proxmox.com/wiki/Linux_Container)
- [Garage documentation](https://garagehq.deuxfleurs.fr/documentation/)
- [Garage configuration file](https://garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/)
- [OpenBao Raft snapshots](https://openbao.org/docs/commands/operator/raft/)

[Back to the build log](../README.md#docs)
