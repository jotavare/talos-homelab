# Proxmox

The physical host: from an empty mini PC to a running Proxmox VE.

## Install USB

### Image

Proxmox VE 9.2, **amd64** ISO from the
[Proxmox downloads page](https://www.proxmox.com/en/downloads). Check it
against the published SHA256 before writing it:

```bash
sha256sum proxmox-ve_9.2-1.iso
```

On Windows: `Get-FileHash .\proxmox-ve_9.2-1.iso`.

### First attempt failed: wrong architecture

The installer stopped at GRUB with:

```
Loading Proxmox VE Installer ...
error: invalid magic number.
Loading initial ramdisk ...
error: you need to load the kernel first.
```

The downloaded ISO was **arm64**. This machine is x86, so GRUB could not
load an ARM kernel. Proxmox only officially ships amd64, arm64 builds are
community ports for Raspberry Pi or Ampere hardware. Downloading the amd64
ISO fixed it.

Other causes of the same error, for next time:

- A bad USB write (use raw/DD mode)
- A corrupted download (check the SHA256)
- Secure Boot or firmware quirks
- UEFI vs legacy boot mismatch
- A flaky USB stick or port

### Writing the USB

| Tool | Notes |
|------|-------|
| **Rufus** (DD mode) | What the Proxmox docs suggest on Windows. If asked to download another GRUB version, click No, then choose **Write in DD Image mode**. Wipes the whole stick. |
| **Etcher** | In the official docs and works out of the box, mixed reputation on forums. |
| **dd** | Standard on Linux and macOS: `sudo dd if=proxmox-ve_9.2-1.iso of=/dev/sdX bs=4M conv=fsync status=progress` |
| **Ventoy** | Not in the official docs, but keeps other files on the stick. Update it first with **Update**, not Install, old versions have issues. |

**Decision: Rufus in DD mode**, the method the Proxmox docs recommend on
Windows. Ventoy was considered to keep the other files on the stick, but
DD mode is the most reliable, and the stick was wiped for it.

Rufus 4.15, portable version:

- Device: the USB stick
- Boot selection: `proxmox-ve_9.2-1.iso` (amd64)
- Partition scheme, target system, file system: greyed out, left as is
  (Rufus treats the ISO as a raw disk image)
- On START: **Write in DD Image mode**, not ISO mode

Afterwards Windows offers to format the stick. Cancel it: a DD-written
stick is not readable by Windows.

### Booting

On this HP, F9 at power-on opens the boot menu, F10 the BIOS. Secure Boot
can stay on, Proxmox supports it since 8.1.

## Install

### Target disk and filesystem

- Disk: `/dev/nvme0n1`, the Intel 670p 512 GB. It is a **QLC** drive.
- Filesystem: **ext4 (LVM-thin)**, the installer default.

Why not ZFS: write amplification on a QLC drive, with Talos etcd writing
constantly, wears it out faster. LVM-thin still gives snapshots and thin
provisioning, and works with the OpenTofu `bpg/proxmox` provider as the
`local-lvm` storage. Worth revisiting if a second disk is added for a ZFS
mirror.

### Locale, password and email

- Country and timezone: local.
- Keymap: **en-us**. If the physical keyboard has a different layout, the
  root password may have been typed with different symbols than intended.
- Root password: strong, stored in a password manager.
- Email: a real address, for alerts like backup failures and SMART
  warnings.

Later, OpenTofu does not get the root password. It gets a dedicated user
and API token, kept in a secrets store.

### Network

The installer pre-filled a SLAAC IPv6 address. Rejected: the ISP prefix
can rotate, and the address is publicly routable. Replaced with static
IPv4.

| Field | Value |
|-------|-------|
| Interface | `nic0` (Intel I219-LM, `e1000e` driver) |
| Hostname | `pve` |
| IP | `192.168.1.10/24` |
| Gateway | `192.168.1.1` (the ISP router) |
| DNS | `1.1.1.1` |
| Pin interface names | Enabled |

Pinning interface names keeps `nic0` stable, so a kernel or hardware
change cannot rename it and break the bridge config.

The address plan behind these values is in the
[Hardware section](../README.md#network) of the readme.

## Post-install

### Access

Web UI at `https://192.168.1.10:8006`, user `root`, realm **Linux PAM**.
The certificate warning and the "no subscription" popup are expected.

- **Root password:** replaced the one set in the installer with a long
  random one from the password manager (Bitwarden, item
  "Proxmox VE · pve · root"). Changed under **Datacenter → Permissions →
  Users → root → Password**.
- **SSH key login:** an Ed25519 key generated on the admin laptop, with
  the private key backed up in Bitwarden as an SSH key item
  ("SSH key · jotavare · WSL laptop").

```bash
ssh-keygen -t ed25519 -C "jotavare"
ssh-copy-id root@192.168.1.10   # appends the public key to /root/.ssh/authorized_keys
ssh root@192.168.1.10 hostname  # prints "pve" without a password prompt
```

Local credentials for scripts live in a `.env` at the repo root, which is
in `.gitignore` and never committed.

### Next

1. **pve → Updates → Repositories:** disable the enterprise repositories
   (PVE and Ceph), then **Add → No-Subscription**.
2. **pve → Updates → Refresh → Upgrade.** Reboot if the kernel changed.
3. **pve → System → Network:** confirm `vmbr0` has the static address.
4. Tailscale on the host, so the web UI is reachable over the tailnet only.
5. Create a dedicated user and API token for OpenTofu (`bpg/proxmox`).

### Known issue: e1000e hardware unit hang

The I219-LM (`e1000e` driver) can log `Detected Hardware Unit Hang` and
drop the link under load. The usual fix is turning off TSO/GSO offload on
the NIC. Only applied if the problem shows up.

[Back to the build log](../README.md#work-in-progress)
