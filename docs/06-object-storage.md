# Object storage

An S3-compatible bucket store for backups:
[Garage](https://garagehq.deuxfleurs.fr/) in its own LXC container, next
to OpenBao and outside the cluster. The first user is the daily OpenBao
Raft snapshot; the etcd snapshots, Velero and Longhorn backups follow once
the cluster exists.

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

Written before building, so each choice has its reason next to it.

| Item | Design | Why |
|------|--------|-----|
| Container | ID `140`, Debian 13 LXC, unprivileged, `192.168.1.40`, 1 vCPU, 0.5 GB RAM, start on boot | Same as OpenBao. Garage idles at well under 100 MB |
| Disks | 4 GB root with the metadata, plus a separate 10 GB data volume for the objects | The data volume grows on its own (`size` in OpenTofu) without touching the root disk. 10 GB is plenty for OpenBao snapshots; grow it when the cluster backups arrive |
| Created by | OpenTofu, same template as OpenBao | Same as every other machine |
| Configured by | Ansible through `pve` (`pct exec`), no SSH server | Same as OpenBao |
| Install | The static binary from the Garage releases, pinned by SHA256 in the role, with a `systemd` unit | There is no Debian package |
| Mode | Single node, replication factor 1, LMDB metadata with automatic snapshots | One node is all there is. Metadata snapshots let Garage recover from a corrupted database |
| Listens on | S3 API `3900` on the LAN. RPC `3901` and admin API `3903` on `127.0.0.1` only | Only the S3 API is needed from outside. The `garage` CLI runs inside the container |
| Tailscale | None | Nothing on the tailnet needs it: every client is on the LAN, and I manage it through `pct` |
| Firewall | Inbound `DROP`, then `3900` from each client's IP, added only when that client exists | Least privilege: OpenBao (`.30`) first; the Talos nodes (`.11` to `.29`) later |
| Buckets and keys | One bucket and one access key per client. A key can only read and write its own bucket | One leaked key exposes one set of backups, not all of them |
| Key storage | Secret keys go to OpenBao (`kv`), never to git | App secrets live in OpenBao |
| Retention | Lifecycle rule per bucket, objects expire after 14 days | Old backups clean themselves up. Two weeks is enough to notice a problem and roll back |
| TLS | None for now, plain HTTP | Traffic never leaves the host: every client is on the same `vmbr0` bridge. The backups are encrypted before upload where the tool supports it |

### Buckets

| Bucket | Client | When |
|--------|--------|------|
| `openbao-snapshots` | OpenBao container, daily timer | Now |
| `etcd-snapshots` | Talos etcd backup job in the cluster | With the cluster |
| `velero` | Velero | With the cluster |
| `longhorn` | Longhorn backup target | With the cluster |

Pods reach Garage from their node's IP, since Cilium masquerades traffic
that leaves the cluster, so the node range in the firewall is enough.

Velero and Longhorn need two settings to work with Garage: path-style
URLs (`s3ForcePathStyle: true`) and no request checksums
(`checksumAlgorithm: ""`), which newer AWS SDKs send by default and Garage
does not accept.

### OpenBao snapshots

1. A `bao` policy that can only read `sys/storage/raft/snapshot`, and a
   periodic token with only that policy, created by hand and kept in a
   file only root can read in the container.
2. A daily `systemd` timer runs `bao operator raft snapshot save`, keeps
   the last three snapshots on the container, and copies the new one to
   `openbao-snapshots` with `rclone`.
3. A Raft snapshot holds the data still encrypted by OpenBao. Restoring it
   needs the unseal key, which is not on either container.

### Budget

| Resource | Before | After |
|----------|--------|-------|
| RAM for the host | 3.5 GB | 3 GB |
| vCPU | 15 on 12 threads | 16 on 12 threads |
| `local-lvm` | 280 GB of 348 GB | 294 GB of 348 GB |

### Limits

It shares the host and the NVMe with everything it backs up. It protects
against a deleted container, a bad upgrade or a rebuilt cluster, not
against losing the host or the drive (see the POC trade-offs in the
[readme](../README.md#poc-trade-offs)). No versioning or object lock
either: a client whose key leaks can delete its own bucket. A copy off the
host, most likely to Cloudflare R2, is in the Backlog.

### What stays out of Garage

| Item | Why |
|------|-----|
| The OpenTofu state | This state creates the Garage container, so it cannot live in it. Git also gives it version history and a copy off the host, which Garage does not ([05. OpenTofu](05-opentofu.md#state-encryption)) |
| The snapshot schedule | OpenTofu only acts when it runs, so the daily job is a timer that Ansible sets up. OpenTofu can later own the declarative parts: the bucket, its key and lifecycle rule, and the OpenBao snapshot policy |

### Build order

1. OpenTofu: container `140`, the data volume and the firewall.
2. Ansible: the binary, the config and the unit, plus compliance checks.
3. By hand in the container: the `openbao-snapshots` bucket and its key,
   stored in OpenBao.
4. The snapshot policy, token and timer on the OpenBao container.

## References

- [Garage documentation](https://garagehq.deuxfleurs.fr/documentation/)
- [Garage configuration file](https://garagehq.deuxfleurs.fr/documentation/reference-manual/configuration/)
- [Garage S3 compatibility](https://garagehq.deuxfleurs.fr/documentation/reference-manual/s3-compatibility/)
- [OpenBao Raft snapshots](https://openbao.org/docs/commands/operator/raft/)
- [rclone S3 backend](https://rclone.org/s3/)

[Back to the build log](../README.md#work-in-progress)
