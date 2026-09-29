# Object storage

An S3-compatible bucket store for backups:
[Garage](https://garagehq.deuxfleurs.fr/) as a container
on the services VM, next to OpenBao and outside the cluster. Its first
user is the OpenTofu state; the etcd snapshots, Velero and Longhorn
backups follow once the cluster exists.

## Why outside the cluster

Backups of the cluster cannot live in the cluster. A broken or rebuilt
cluster would take its own backups down with it, and OpenBao, which runs
outside the cluster, needs somewhere to send its snapshots before the
cluster even exists. Same reasoning as for OpenBao in
[04. Secrets, OpenBao](04-secrets.md#openbao).

## Why Garage

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

## Design

| Item | Design | Why |
|------|--------|-----|
| Runs in | A container on the services VM, managed by OpenTofu, image `dxflrs/garage:v2.4.1` pinned by digest ([07. Services VM](07-services.md)) | One place for the services outside the cluster |
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

### Buckets

| Bucket | Client | When |
|--------|--------|------|
| `opentofu-state` | OpenTofu's state backend, key `opentofu` | Now |
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

### OpenBao snapshots

Optional. The daily VM backup
([01. Proxmox, Container backups](01-proxmox.md#container-backups))
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

### Limits

It shares the host and the NVMe with everything it backs up. It protects
against a deleted bucket, a bad upgrade or a rebuilt cluster, not
against losing the host or the drive (see the POC trade-offs in the
[readme](../README.md#poc-trade-offs)). No versioning or object lock
either: a client whose key leaks can delete its own bucket. A copy off the
host, most likely to Cloudflare R2, is in the Backlog.

### The OpenTofu state

The OpenTofu state lives here, even though OpenTofu creates the VM that
Garage runs in. That loop is accepted on purpose; the way out is the VM's
daily backup and the break-glass copies in Bitwarden
([04. Secrets, The loop](04-secrets.md#the-loop-and-the-way-out)).

## Setup

The container is in [opentofu/services/garage.tf](../opentofu/services/garage.tf)
([07. Services VM](07-services.md#setup)):

| File | What it is |
|------|------------|
| [garage.tf](../opentofu/services/garage.tf) | Garage on `backend`, the RPC secret in `/run/secrets/`, data under `/srv/garage` |
| [garage.toml](../opentofu/services/files/garage/garage.toml) | Replication factor 1, LMDB, S3 API on `3900`, region `garage` |

Buckets and keys, made with the CLI inside the container:

```bash
ssh -J root@<PROXMOX_HOST> debian@192.168.1.30
sudo docker exec garage /garage bucket create opentofu-state
sudo docker exec garage /garage key create opentofu
sudo docker exec garage /garage bucket allow --read --write opentofu-state --key opentofu
```

The key went straight into OpenBao (`kv/opentofu`), never printed.

## References

- [Garage documentation](https://garagehq.deuxfleurs.fr/documentation/)
- [Garage configuration file](https://garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/)
- [Garage S3 compatibility](https://garagehq.deuxfleurs.fr/documentation/reference-manual/s3-compatibility/)
- [OpenBao Raft snapshots](https://openbao.org/docs/commands/operator/raft/)
- [rclone S3 backend](https://rclone.org/s3/)

[Back to the build log](../README.md#work-in-progress)
