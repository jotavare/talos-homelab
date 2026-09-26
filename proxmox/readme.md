# Proxmox host

The physical machine the Talos cluster runs on, and how it was set up.

## Why a hypervisor under Talos

Talos can run on bare metal, but this homelab starts with a single mini
PC. One machine as one Talos node cannot show the things worth learning:
etcd quorum, a node failing, rolling upgrades. Running Talos as VMs on
[Proxmox VE](https://www.proxmox.com/en/products/proxmox-virtual-environment/overview)
turns one box into a multi-node cluster.

Proxmox also has a mature OpenTofu provider
([bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest)),
and Talos has an official one
([siderolabs/talos](https://registry.terraform.io/providers/siderolabs/talos/latest)).
Between them the VMs, machine configs and cluster bootstrap can all be
declared in this repo.

## Hardware

| Component | Detail |
|-----------|--------|
| Model     | HP Pro Mini 400 G9 |
| CPU       | Intel Core i5-12500T, 6 cores / 12 threads, 35 W |
| RAM       | 32 GB DDR4-3200 (2 x 16 GB, both slots used, max 64 GB) |
| Storage   | Intel 670p 512 GB NVMe |
| Network   | Intel I219-LM gigabit, single port, no Wi-Fi |
| GPU       | Intel UHD Graphics 770 (integrated) |

Why it fits:

- **Performance cores only.** The i5-12500T has no efficiency cores, which
  avoids the scheduling quirks mixed-core 12th/13th gen chips can cause
  under a hypervisor. 35 W is fine to leave running 24/7.
- **32 GB is enough for a real cluster.** Proxmox takes 1 to 2 GB. That
  leaves room for three control-plane VMs at 2 to 4 GB each plus two or
  three workers at 4 to 6 GB each.
- **All Intel hardware**, supported by the stock Proxmox kernel.

Known limits:

- **Storage is the tight resource.** 512 GB is fine to start. It gets
  tight once workers need persistent volumes (Longhorn, OpenEBS or
  similar) or once ISOs and backups pile up.
- **Single NIC.** Everything goes through one port, so the I219-LM quirk
  below matters.

## Install media

Proxmox VE 9.2, written to a 32 GB USB stick with
[Rufus](https://rufus.ie/) 4.15 in **DD image mode**.

1. Download the ISO from the
   [Proxmox downloads page](https://www.proxmox.com/en/downloads) and
   check its SHA256 against the published one. On Windows:
   ```powershell
   Get-FileHash .\proxmox-ve_9.2-1.iso
   ```
2. In Rufus, pick the USB stick under Device and the ISO under Boot
   selection. Partition scheme, target system and file system go grey.
   That is expected: Rufus is treating the ISO as a raw disk image, so
   those settings do not apply.
3. Click START. If asked, choose **Write in DD Image mode**, not ISO mode.
4. Afterwards Windows may say the drive needs formatting. Cancel, do not
   format. A DD-written stick is not readable by Windows.

Notes:

- DD mode wipes the whole stick. This one previously had
  [Ventoy](https://www.ventoy.net/), which can boot the Proxmox ISO
  directly, but DD mode is what Proxmox recommends and the most reliable.
  Running Ventoy2Disk again restores Ventoy afterwards.
- Proxmox VE supports Secure Boot since 8.1, so it can stay on.
- On this HP, F9 at power-on opens the boot menu, F10 the BIOS.

## Post-install checklist

To do once Proxmox is installed:

- [ ] Switch to the `pve-no-subscription` repository (no paid
      subscription here).
- [ ] Apply the I219-LM offload workaround (below) before relying on the
      network.
- [ ] Put the web UI (port 8006) behind Tailscale only.

#### I219-LM hardware unit hang

Under heavy traffic the I219-LM can log `Detected Hardware Unit Hang` and
briefly drop the link. The usual workaround is turning off segmentation
offload on the physical interface, as a `post-up` line in
`/etc/network/interfaces`:

```
post-up ethtool -K eno1 tso off gso off
```

The interface name may differ; check with `ip link`. Worth doing from the
start: a flapping single NIC is painful to debug when everything,
including the management UI, goes through it.

#### Management UI stays off the internet

The Proxmox web UI and API control every VM on the host. It is never
exposed publicly, only reachable over the tailnet. This repo being public
makes that more important, not less: the layout of the setup is visible
to anyone.

## Log

- **2026-09-26**: Picked the HP Pro Mini 400 G9 as the host. Wrote the
  Proxmox VE 9.2 installer to USB with Rufus in DD mode.
