# NAS

A file server on the second Proxmox host, `pve-desktop`, an old desktop
PC: a ZFS pool on its hard drive, shared over SMB for my devices and over
NFS for the cluster. Apps on Talos, Immich first, keep their files here.

## Hardware

| Part | Value |
|------|-------|
| Host | `pve-desktop`, Proxmox VE 9.2, standalone |
| CPU | Intel Core i5-4460, 4 cores |
| RAM | 12 GB |
| System disk | Samsung 850 EVO 250 GB SSD (Proxmox) |
| Data disk | WD Blue 1 TB HDD, the whole disk is the pool |
| Network | USB WiFi only, `192.168.1.11`. No cable can reach the desk |
| Runs | Together with `pve`, not 24/7 on its own |

## Why on the host, not a VM

The plan was TrueNAS in a VM with the hard drive passed through. WiFi
rules that out: a WiFi client cannot bridge, so a VM cannot get its own
address on the LAN. The workaround, a NAT network on the host with
forwarded ports, makes NFS fragile and hides the NAS behind the host.

So the NAS is the host itself. Proxmox is Debian with ZFS built in, and
NFS and Samba are two packages. No VM, no passthrough, and the address
the cluster mounts is the host's own.

| Option | Why not |
|--------|---------|
| TrueNAS VM | Needs a bridged network, so a cable |
| TrueNAS on the bare metal | Gives up Proxmox on that machine, and `democratic-csi` is not needed for one share |
| A Proxmox cluster with `pve` | Two nodes lose quorum whenever one reboots, so neither could start or change VMs. Two standalone hosts managed by the same code avoid that |

## Setup

All by Ansible, since it is host configuration. The base role is the
same one `pve` uses (repositories, unattended upgrades, SSH hardening,
IPv6 autoconf off, Tailscale package):

| File | What it is |
|------|------------|
| [ansible/nas.yml](../ansible/nas.yml) | The playbook for the `nas` group |
| [ansible/roles/nas/](../ansible/roles/nas/) | Tasks, handlers and checks (`tasks/verify.yml`) |
| [nas/smb.conf](../nas/smb.conf) | One share, `files`, SMB3 only, no guest, no NetBIOS, macOS metadata kept with `fruit` |
| [nas/nfs.conf](../nas/nfs.conf) | NFS 4.1 and 4.2 only, so `rpcbind` and `rpc-statd` stay masked |
| [nas/k8s.exports](../nas/k8s.exports) | `/tank/k8s` to the Talos nodes only, `no_root_squash` for the CSI driver |
| [nas/zfs.conf](../nas/zfs.conf) | ZFS ARC capped at 2 GB, the rest of the RAM stays free |
| [nas/smartd.conf](../nas/smartd.conf) | SMART tests on both disks, the HDD left alone in standby |
| [nas/wifi-power-save-off.service](../nas/wifi-power-save-off.service) | Turns off WiFi power saving at boot, which otherwise drops idle connections |

```bash
cd ansible
ansible-playbook proxmox.yml --limit pve-desktop
ansible-playbook nas.yml
```

The data disk is found by its model under `/dev/disk/by-id`, so the
serial number stays out of the repo. The pool is only created when it
does not exist, and the play stops if the model matches anything other
than one disk.

The disk held an old NTFS partition with 328 GB of game files. It was
checked read-only first, then wiped by the playbook.

## Pool

| Item | Value |
|------|-------|
| Pool | `tank`, one disk, `ashift=12` |
| Properties | `compression=lz4`, `atime=off`, `xattr=sa`, `acltype=posixacl` |
| `tank/files` | My files, shared over SMB |
| `tank/k8s` | Volumes for the cluster, exported over NFS |

ZFS checksums every block, so a dying disk shows up as errors in
`zpool status` instead of silently bad photos. With one disk it can
detect damage but not repair it.

## Shares

| Share | For | Address | Login |
|-------|-----|---------|-------|
| SMB `files` | Laptop, phone | `\\192.168.1.11\files` | User `nas`, password in OpenBao `kv/nas` |
| NFS `/tank/k8s` | Talos nodes `.12` and `.21` to `.23` | `192.168.1.11:/tank/k8s` | By IP, no login |

On Windows: File Explorer, Map network drive, `\\192.168.1.11\files`,
with the `nas` user. The password is generated straight into OpenBao and
set by Ansible with `smbpasswd`, never printed:

```bash
bao kv get -mount=kv -field=smb_password nas
```

The cluster will use
[csi-driver-nfs](https://github.com/kubernetes-csi/csi-driver-nfs): a
storage class on `192.168.1.11:/tank/k8s`, and each volume becomes a
folder there. Immich keeps its photo library on it. Its database stays on
the cluster's own disks: a database over NFS on WiFi is slow and can
corrupt.

## Limits

| Limit | Effect |
|-------|--------|
| One disk | No redundancy. A dead disk loses everything on it |
| No backup | Nothing is copied off the pool yet. Keep originals elsewhere until a second disk or an off-site copy exists |
| WiFi | 100 to 400 Mbps depending on signal, and the link can drop. Fine for files and photos, not for databases |
| Off when `pve` is off | Apps that mount it must wait for it at boot |

## Still to do

- `tailscale up` on `pve-desktop` with `tag:server`, then reach it from
  outside the LAN.
- The Proxmox firewall on `pve-desktop`, like on `pve`: management over
  the tailnet only, SMB from my devices, NFS from the Talos nodes. Until
  then SMB and NFS listen on the LAN, behind the password and the export
  list.

## References

- [OpenZFS](https://openzfs.github.io/openzfs-docs/)
- [Samba `smb.conf`](https://www.samba.org/samba/docs/current/man-html/smb.conf.5.html)
- [Debian NFS server setup](https://wiki.debian.org/NFSServerSetup)
- [csi-driver-nfs](https://github.com/kubernetes-csi/csi-driver-nfs)

[Back to the build log](../README.md#work-in-progress)
