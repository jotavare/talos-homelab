# Proxmox

The physical host: from an empty mini PC to a running Proxmox VE.

## Why a hypervisor under Talos

Talos can run on bare metal, but this homelab starts with a single mini
PC. One machine as one Talos node cannot show the things worth learning:
several nodes, a node failing, rolling upgrades. Running Talos as VMs on
Proxmox VE turns one box into a multi-node cluster.

Proxmox also has a mature OpenTofu provider
([bpg/proxmox](https://registry.terraform.io/providers/bpg/proxmox/latest)),
and Talos has an official one
([siderolabs/talos](https://registry.terraform.io/providers/siderolabs/talos/latest)).
Between them the VMs, machine configs and cluster bootstrap can all be
declared in this repo.

## Why this hardware fits

Specs are in the [Hardware section](../README.md#hardware) of the readme.

- **Performance cores only.** The i5-12500T has no efficiency cores, which
  avoids the scheduling quirks mixed-core 12th and 13th gen chips can cause
  under a hypervisor. 35 W is fine to leave running 24/7.
- **32 GB is enough for a real cluster.** Proxmox takes 1 to 2 GB, leaving
  room for a control plane and three workers (see [Planned VMs](#planned-vms)).
- **All Intel hardware**, supported by the stock Proxmox kernel.

Known limits:

- **Storage is the tight resource.** 512 GB of QLC is fine to start. It
  gets tight once workers need persistent volumes (Longhorn or similar) or
  once ISOs and backups pile up, and QLC wears faster under heavy writes.
- **Single NIC.** Everything, management included, goes through one port.

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
IPv4. The installer keeps IPv6 auto-configuration on, though, so it is
turned off after the install (see [Network check](#network-check)).

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

Web UI, user `root`, realm **Linux PAM**. The certificate warning and the
"no subscription" popup are expected.

| | Before the firewall | Now |
|--|--|--|
| Web UI | `https://192.168.1.10:8006` | `https://pve.<tailnet>.ts.net:8006` |
| SSH | `ssh root@192.168.1.10` | `ssh root@pve.<tailnet>.ts.net` |

Since the [firewall](#firewall), management only answers over the tailnet
([02. Tailscale](02-tailscale.md)). At home the tailnet path still goes
straight over the LAN.

- **Root password:** replaced the one set in the installer with a long
  random one from the password manager (Bitwarden, item
  "Proxmox VE · pve · root"). Changed under **Datacenter → Permissions →
  Users → root → Password**.
- **Web UI 2FA:** TOTP for `root@pam` (**Datacenter → Permissions → Two
  Factor → Add → TOTP**), scanned into an authenticator app, plus a set of
  one-time **recovery keys** (**Add → Recovery Keys**) stored in Bitwarden
  with the login, plus a printed copy kept offline. The login page now asks for a code after the password.
- **SSH key login:** an Ed25519 key generated on the admin laptop, with
  the private key backed up in Bitwarden as an SSH key item
  ("SSH key · jotavare · WSL laptop").

```bash
ssh-keygen -t ed25519 -C "jotavare"
ssh-copy-id root@192.168.1.10   # appends the public key to /root/.ssh/authorized_keys
ssh root@192.168.1.10 hostname  # prints "pve" without a password prompt
```

`authorized_keys` also holds an `ssh-rsa` key: the host's own root key,
which Proxmox adds itself. It is expected.

The key was installed while the LAN was still open, which is why the
commands above use `192.168.1.10`. With the key in place, SSH password
login is turned off for root:
[proxmox/ssh/10-hardening.conf](../proxmox/ssh/10-hardening.conf), copied
to `/etc/ssh/sshd_config.d/`. A drop-in survives upgrades better than
editing `sshd_config`, and it wins because the `Include` line sits at the
top of the main file (first value wins). The same drop-in also allows at
most 3 attempts per connection (`MaxAuthTries 3`), gives 20 seconds to log
in, turns off X11 forwarding, and drops dead sessions after about 10
minutes (`ClientAliveInterval 300`, `ClientAliveCountMax 2`). TCP
forwarding stays on, for SSH tunnels.

```bash
sshd -t && systemctl reload ssh      # validate, then reload; open sessions stay up
ssh root@pve.<tailnet>.ts.net hostname                       # key: works
ssh -o PubkeyAuthentication=no root@pve.<tailnet>.ts.net     # Permission denied (publickey)
```

What the tools need, such as the host's tailnet address, lives in
OpenBao ([04. Secrets](04-secrets.md)).
Passwords that no script uses stay only in Bitwarden.

### Repositories and upgrade

Proxmox 9 keeps its apt sources as deb822 `.sources` files in
`/etc/apt/sources.list.d/`. After the install:

- `pve-enterprise.sources` and `ceph.sources`: the paid enterprise
  repositories, set to `Enabled: false` (no subscription here).
- `debian.sources`: Debian trixie main, updates and security. Left as is.

Added the free no-subscription repository, the same file that
**pve → Updates → Repositories → Add → No-Subscription** creates:

```
# /etc/apt/sources.list.d/proxmox.sources
Types: deb
URIs: http://download.proxmox.com/debian/pve
Suites: trixie
Components: pve-no-subscription
Signed-By: /usr/share/keyrings/proxmox-archive-keyring.gpg
```

No Ceph no-subscription repository: Ceph is not in use.

Then upgraded and rebooted, since the upgrade brought a new kernel:

```bash
apt update
apt full-upgrade
reboot
```

Check afterwards:

```bash
pveversion       # pve-manager/9.2.20, running kernel 7.0.14-19-pve
apt list --upgradable   # empty
```

### Automatic security updates

Debian security fixes install on their own every day through
`unattended-upgrades`. Everything else stays manual:

- **Proxmox packages** (`pve-no-subscription`): Proxmox asks for
  `apt full-upgrade`, and a plain unattended upgrade can leave them half
  upgraded. Run the upgrade above by hand from time to time.
- **Debian point releases**: also by hand, together with the Proxmox
  upgrade.
- **Reboots**: never automatic. A new kernel waits for a planned reboot.
- **Tailscale**: not covered here. It updates itself, see
  [02. Tailscale](02-tailscale.md#proxmox-host).

```bash
apt install unattended-upgrades
```

The settings live in one drop-in,
[`proxmox/apt/52unattended-upgrades-local`](../proxmox/apt/52unattended-upgrades-local),
copied to `/etc/apt/apt.conf.d/`. It turns on the daily run, limits the
allowed origins to `trixie-security` (the Debian default also allows
point releases), turns off automatic reboots and mails root only when an
upgrade fails. Root's mail goes out through the notification system (see
[Email notifications](#email-notifications)). The package's own
`20auto-upgrades` sets the same two `APT::Periodic` lines; the drop-in is
the one kept in the repo.

Check it:

```bash
unattended-upgrade --dry-run --debug 2>&1 | grep "Allowed origins"
# Allowed origins are: origin=Debian,codename=trixie-security,label=Debian-Security
less /var/log/unattended-upgrades/unattended-upgrades.log   # what ran
```

### Email notifications

Proxmox sends every alert (upgrade failures, disk health, backups)
through its notification system, and root's local mail goes there too
(`/root/.forward` pipes it to `proxmox-mail-forward`). Out of the box the
only target is `mail-to-root`, which hands mail to the local postfix.
With no relay, that mail never leaves the host or lands in spam.

Added an SMTP target that sends through a Gmail account with an app
password. The recipient is a Proton address. Proton itself only allows
SMTP sending on paid plans with a custom domain, so it only receives.

In **Datacenter → Notifications**:

| Field | Value |
|-------|-------|
| Endpoint name | `gmail` |
| Server | `smtp.gmail.com`, TLS, port `465` |
| Username, from address | the Gmail address |
| Password | a Gmail [app password](https://myaccount.google.com/apppasswords), kept in Bitwarden |
| Recipient | `root@pam` (its email is the Proton address) |

Then **Notification Matchers → `default-matcher`**: target `gmail`
instead of `mail-to-root`. The password is stored apart from the rest, in
`/etc/pve/priv/notifications.cfg`, readable by root only.

Check both paths, the test button and root's local mail:

```bash
# Notifications → gmail → Test, then:
printf "Subject: pve root mail test\n\ntest\n" | sendmail root
```

Both should arrive in the Proton inbox.

### Disk health alerts

The only disk is an Intel 670p, a QLC NVMe. QLC wears faster than other
flash, so its health is worth watching. `smartmontools` comes with
Proxmox and `smartd` already runs, but the default rule scans every disk,
USB sticks included, and never runs a self-test.

Starting point, from `smartctl -a /dev/nvme0`:

| Field | Value |
|-------|-------|
| Temperature | 44 C idle, drive warning at 83 C, critical at 88 C |
| Percentage used | 2% |
| Available spare | 100%, drive alarm below 10% |
| Health | PASSED, critical warning `0x00`, no media errors |

Replaced `/etc/smartd.conf` with a single rule for the NVMe,
[`proxmox/smartd/smartd.conf`](../proxmox/smartd/smartd.conf):

```
/dev/nvme0 -a -W 5,70,80 -s (S/../.././02|L/../../6/03) -m root -M exec /usr/share/smartmontools/smartd-runner
```

- `-a`: health, new error log entries and the drive's critical warning,
  which covers spare below its threshold and "reliability degraded".
- `-W 5,70,80`: log a 5 C jump, log above 70 C, mail above 80 C.
- `-s`: short self-test daily at 02:00, long self-test Saturday at 03:00.
- `-m root`: mail root, which goes out through
  [Email notifications](#email-notifications).

Tested the mail path once with `-M test`, which sends a test mail on
start, then restarted with the real config:

```bash
sed "s|-M exec|-M test -M exec|" /etc/smartd.conf > /tmp/smartd-test.conf
smartd -q onecheck -c /tmp/smartd-test.conf   # test mail arrives
systemctl restart smartd
journalctl -u smartd   # "Monitoring ... 1 NVMe devices"
smartctl -l selftest /dev/nvme0   # self-test results
```

`smartd` has no threshold for "percentage used", so an early wear warning
waits for the monitoring stack.

### Network check

After the reboot the bridge still has its static address, on the pinned
interface name:

```
# /etc/network/interfaces
iface nic0 inet manual

iface vmbr0 inet static
	address 192.168.1.10/24
	gateway 192.168.1.1
	bridge-ports nic0
```

The address is static on the host itself (`inet static`, no DHCP client
running), and `.10` sits outside the router's DHCP pool (`.100` to
`.254`), so no reservation on the router is needed.

IPv6 on `vmbr0` is link-local only (`fe80::`), but the kernel still had
`accept_ra` and `autoconf` on. If the router ever starts announcing an
IPv6 prefix, the host would pick up a public address that bypasses the
static IPv4 plan. Turned off with
[`proxmox/sysctl/90-ipv6-no-autoconf.conf`](../proxmox/sysctl/90-ipv6-no-autoconf.conf),
copied to `/etc/sysctl.d/`:

```bash
sysctl --system
sysctl net.ipv6.conf.vmbr0.accept_ra net.ipv6.conf.vmbr0.autoconf   # both 0
ip -6 addr show vmbr0   # only fe80::
```

This only covers the host. Talos VMs get the same settings in their own
machine config. `tailscale0` keeps its tailnet IPv6 address, which
Tailscale assigns itself.

### Firewall

Only the tailnet can reach the management ports of the host. Config in
[proxmox/firewall/](../proxmox/firewall/), copied to
`/etc/pve/firewall/cluster.fw` and `/etc/pve/nodes/pve/host.fw`.

With the firewall on, Proxmox automatically allows the web UI (`8006`),
SSH (`22`), console (`5900-5999`) and SPICE (`3128`) from the
**management** IP set, and it always adds `local_network` to that set.
`local_network` is auto-detected as the LAN (`192.168.1.0/24`), so turning
the firewall on alone keeps the LAN open. Overriding the alias is what
closes it:

- `local_network` alias set to the tailnet range `100.64.0.0/10`.
- `management` IP set: the tailnet ranges only, IPv4 `100.64.0.0/10` and
  IPv6 `fd7a:115c:a1e0::/48`. MagicDNS answers with both addresses, so
  without the IPv6 range a client that tries IPv6 first gets dropped and
  has to fall back to IPv4.
- `policy_in: DROP`, `policy_out: ACCEPT`.
- Host rules: Tailscale direct connections (`udp/41641`) and ping from the
  LAN, for troubleshooting.

Enabled with a dead-man switch, working over the tailnet SSH session so
blocking the LAN could not cut it:

```bash
systemd-run --unit=fw-deadman --on-active=5min /usr/sbin/pve-firewall stop
# set enable: 1 in cluster.fw, then
pve-firewall restart && pve-firewall status
# tests pass, so keep it on
systemctl stop fw-deadman.timer
```

| Path | Result |
|------|--------|
| tailnet → `:8006`, `:22` | allowed |
| LAN → `:8006`, `:22`, `:111` | blocked |
| LAN → ping | allowed |
| Tailscale | still direct over the LAN, not relayed |
| `pve` → internet (apt) | allowed |

These rules protect the Proxmox host only. Traffic to the VMs on
`vmbr0` goes through a separate firewall per VM (`firewall=1` on the VM's
network card plus its own `<vmid>.fw`). Until that is set up, a VM's ports
are open to the whole LAN.

Two trade-offs, accepted on purpose:

- **Single node only.** Proxmox also uses `local_network` to allow
  cluster traffic (corosync) between nodes. With the alias pointing at the
  tailnet, a second Proxmox node on the LAN could not join. Adding one
  means putting the LAN back in `local_network`, or adding explicit
  corosync rules (`udp/5405-5412`) for the new node.
- **Outbound is open** (`policy_out: ACCEPT`). The host needs apt, DNS,
  NTP, Tailscale (coordination and DERP) and SMTP, and a tight outbound
  list breaks every time one of those changes address. The cost: a
  compromised host could send data anywhere. Inbound is what the firewall
  guards here.

### Unused services

`rpcbind` (port `111`, on every interface) comes enabled with Proxmox but
is only needed to mount NFSv3 storage on the host. There is no NFS here,
so it is off, even though the firewall already dropped the port:

```bash
systemctl disable --now rpcbind.socket rpcbind
# back on, if a NAS is ever mounted on the host over NFSv3:
systemctl enable --now rpcbind.socket rpcbind
```

NFSv4 storage does not need it, and neither do Talos VMs mounting NFS
themselves: they use their own network stack.

What still listens (`ss -tulpn`):

| Port | Service | Reachable from |
|------|---------|----------------|
| `22` | SSH | tailnet only (firewall) |
| `8006` | Web UI (`pveproxy`) | tailnet only (firewall) |
| `3128` | SPICE proxy | tailnet only (firewall) |
| `udp/41641` | Tailscale direct connections | anywhere, WireGuard authenticated |
| `25`, `85`, `323` | Postfix, `pvedaemon`, chrony | localhost only |

### Why no fail2ban

[fail2ban](https://github.com/fail2ban/fail2ban) watches login logs and,
after too many failures from one IP (say 5 in 10 minutes), adds a
firewall rule that blocks that IP for a while. It exists to slow down
password guessing from the internet. On this host there is nothing for it
to catch:

| What fail2ban stops | Why it cannot happen here |
|---------------------|---------------------------|
| Internet bots guessing SSH passwords | SSH only answers the tailnet, and only takes keys |
| Password guessing on the web UI | Tailnet only, and needs the password plus TOTP |
| Someone on the LAN trying logins | The firewall drops LAN traffic to `22` and `8006` |

To even reach a login prompt, an attacker already has to be in the
tailnet, which means one of my own devices is compromised (Tailnet Lock
stops new devices from joining). Banning that device's tailnet IP after
a few failures would come too late to matter.

It would also cost something:

- One more daemon to configure and keep updated.
- Its own firewall rules next to `pve-firewall`, which can clash.
- A way to lock myself out, for example a script retrying with a stale
  key bans my own laptop.

Brute-force protection comes back once something in the cluster is
exposed to the internet through an ingress, and it lives in the cluster,
not on the nodes:

- Talos nodes cannot run fail2ban at all: no package manager, no SSH, no
  shell. Their only way in is the Talos API, which takes a client
  certificate (mTLS), so there is no password to guess. On a distribution
  like RKE2 on Ubuntu, the host has SSH and packages, so fail2ban on the
  node still makes sense there.
- Istio, Cilium and Envoy Gateway block fixed IP ranges and rate limit
  requests, but none of them bans an IP after repeated failures.
- [CrowdSec](https://www.crowdsec.net/) does. Its agent runs as pods and
  reads ingress logs, adds a shared list of known attacker IPs, and a
  bouncer in the ingress (Envoy `ext_authz`) enforces the bans.
- Envoy Gateway rate limits and the SSO's own account lockout cover the
  rest.

### Lockout recovery

The physical console (keyboard and monitor on the host) is the way back in
for every lock added here. It needs only the root password: no network, no
2FA, no SSH key.

| Locked out of | Fix |
|---------------|-----|
| Everything over the network (firewall) | Console: `pve-firewall stop`, fix the rules, then `pve-firewall start` |
| Web UI 2FA (lost authenticator) | Use one of the recovery keys from Bitwarden in place of the code |
| Web UI 2FA, recovery keys lost too | Console: `pveum user tfa delete root@pam` removes 2FA, then set it up again |
| SSH (lost key) | Console, or the web UI shell: add a new public key to `/root/.ssh/authorized_keys` |
| Tailscale down | Console: `tailscale status`, `systemctl restart tailscaled`; or `pve-firewall stop` to reach the UI from the LAN |

### Container backups

A snapshot is not a backup. Proxmox snapshots of a container sit in the
same thin pool on the same NVMe, so they are only for rolling back a bad
upgrade. A backup job writes a full, compressed copy of each container as
a separate file.

| Setting | Value |
|---------|-------|
| Job | `daily-containers`, in `/etc/pve/jobs.cfg` |
| Guests | `130`, the services VM |
| When | Every day at 03:00. With `repeat_missed`, a run missed because the host was off starts at the next boot |
| Mode | `snapshot`: the guests keep running, OpenBao stays unsealed |
| Where | `local` (`/var/lib/vz/dump`), `zstd` |
| Retention | The last 5: each new backup removes the oldest. About 1.5 GB each, 7.5 GB in all |

The first run, still with two LXC containers, took 11 seconds and wrote
under 600 MB. Failures go to the default
notification matcher, so they arrive by email.

The job is managed by OpenTofu
([05. OpenTofu, Backup job](05-opentofu.md#backup-job)), with the one
extra privilege it needs limited to `local`.

Restore, into a new ID so the original keeps running:

```bash
ls /var/lib/vz/dump/
pct restore 9130 /var/lib/vz/dump/vzdump-lxc-130-<date>.tar.zst --storage local-lvm
```

The backups are on the same disk as the containers: they cover a mistake
or a broken container, not a dead drive. The Talos VMs are left for
Proxmox Backup Server (Backlog).

### Web UI certificate

The web UI at `https://pve.home.<domain>:8006` has a Let's Encrypt
certificate, so browsers trust it with no warning. The name points at the
host's tailnet IP, so it only opens over the tailnet. Proxmox renews it
itself, from its daily update timer. How it is set up (Cloudflare DNS,
the ACME account, plugin and certificate) is in
[05. OpenTofu, DNS and certificates](05-opentofu.md#dns-and-certificates).

## Ansible

The steps above that can run unattended are also an Ansible playbook:
see [03. Ansible](03-ansible.md).

## NIC hang

The onboard Intel I219-LM (`e1000e` driver) hung while the cluster pulled
large images and Longhorn installed:

```text
e1000e 0000:00:1f.6 nic0: Detected Hardware Unit Hang
```

262 times in nine minutes. The host kept running but lost the network, so
from outside it looked frozen: no ping, and `pve-desktop` on the same LAN
showed its ARP entry as `INCOMPLETE`. A short press of the power button
shut it down cleanly, which is how `journalctl -b -1` still had the
messages.

It is a known `e1000e` problem with TCP segmentation offload under load.
The fix is to let the CPU segment instead of the card: `tso off gso off`,
applied by Ansible now and on every boot with a `post-up` line on `nic0`
in `/etc/network/interfaces`. The extra CPU work is negligible at 1 Gbit.

## Planned VMs

The plan for the Talos VMs and the services VM, drawn
before they exist. It changes if the numbers turn out wrong once the
cluster runs.

![Proxmox host plan: 32 GB of RAM split between the host, the services VM and the planned control plane and three workers on the vmbr0 bridge, and the NVMe split into VM disks, ISOs and swap](../diagrams/proxmox.png)

| VM | vCPU | RAM | Disk | IP |
|----|------|-----|------|----|
| Control plane `talos-cp-1` | 2 | 4 GB | 32 GB | `192.168.1.15` |
| Workers `talos-w-1`, `talos-w-2` | 4 each | 8 GB each | 80 GB each | `192.168.1.21`, `.22` |
| Services VM (OpenBao, Caddy, Tailscale) | 2 | 1.5 GB | 32 GB | `192.168.1.30` |
| Kubernetes API VIP | | | | `192.168.1.20` |
| Cilium LoadBalancer pool | | | | `192.168.1.50` to `.99` |

- **RAM:** 2.5 GB stays with the host, 1.5 GB goes to the services VM
  and 20 GB to the Talos VMs, which leaves about 6 GB free for a third
  worker or another VM. No overcommit, so a busy VM never pushes the host
  into swap. The first plan had three workers, 28 GB in all: over what
  the host has once Proxmox and the services VM are counted.
- **vCPU:** 10 on 12 threads. CPU overcommit is fine, the VMs are rarely
  all busy at once.
- **Disk:** 192 GB of the 348 GB `local-lvm` thin pool, leaving room for
  snapshots and more VMs. `local` (96 GB) keeps the Talos image.
- **API VIP:** with a single control plane the VIP is not needed yet, but
  pointing clients at it from day one means a second or third control
  plane can join later without new certificates or kubeconfigs.
- **OpenBao and Garage outside the cluster:** the cluster depends on its
  secrets, and its backups cannot live in it, so both run on the services
  VM and survive a cluster rebuild. See [07. Services VM](07-services.md).

**Why one control plane and not three.** Production clusters run three
control planes, so etcd keeps quorum when one fails, and that is the
right way to replicate production. This homelab runs one on purpose:

- It is a proof of concept. Nothing critical runs here.
- All VMs share one physical host, so three control planes would not
  survive a hardware failure anyway.
- Every GB saved on control planes goes to workers, and the goal is to
  run a lot of apps.
- This is the only server available to test on for now.

The trade-off: if the control plane VM breaks, the cluster API is down
until it is restored from an etcd snapshot. Workloads that are already
running keep running. Going to three control planes later is a matter of
adding two VMs behind the same VIP.

## Next

1. [05. OpenTofu](05-opentofu.md): the VMs as code.

## References

- [Proxmox VE downloads](https://www.proxmox.com/en/downloads)
- [Prepare installation media](https://pve.proxmox.com/wiki/Prepare_Installation_Media)
- [Rufus](https://rufus.ie/)
- [Package repositories](https://pve.proxmox.com/wiki/Package_Repositories)
- [Network configuration](https://pve.proxmox.com/wiki/Network_Configuration)
- [Firewall](https://pve.proxmox.com/wiki/Firewall)
- [User management and two-factor authentication](https://pve.proxmox.com/wiki/User_Management)
- [Unattended upgrades (Debian wiki)](https://wiki.debian.org/UnattendedUpgrades)
- [Notifications](https://pve.proxmox.com/wiki/Notifications)
- [smartd.conf manual](https://manpages.debian.org/trixie/smartmontools/smartd.conf.5.en.html)
- [fail2ban](https://github.com/fail2ban/fail2ban) and [CrowdSec](https://www.crowdsec.net/)

[Back to the build log](../README.md#work-in-progress)
