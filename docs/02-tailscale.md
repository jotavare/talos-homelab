# Tailscale

Remote admin access to the homelab over a WireGuard mesh, with no ports
opened on the router.

## Why Tailscale

- **Free** for this use: the Personal plan covers 6 users, unlimited user
  devices and 50 tagged devices.
- **End-to-end encrypted** with WireGuard. Private keys never leave the
  devices, and connections are outbound only, so nothing new is exposed to
  the internet.
- **What is trusted:** Tailscale's coordination server decides which
  devices join the tailnet and sees metadata (devices, connection times),
  never traffic. Tailnet Lock removes the ability to add devices without a
  signature from one of our own nodes.
- **Headscale** (self-hosted coordination server) stays a later
  experiment. Moving to it only means re-joining the devices.

## Where it runs

Directly on each node that needs remote access, not as a subnet router:

| Node | How |
|------|-----|
| Proxmox host | `tailscaled` on the Debian base system |
| Admin laptop | Tailscale Windows app (WSL shares its network) |
| Phone | Tailscale Android app |
| Talos VMs | Tailscale system extension, in the Talos phase |

## Account and devices

- **Account:** signed in with GitHub, which has 2FA enabled. Whoever
  controls that login controls the tailnet.
- **Laptop:** Tailscale Windows app. WSL goes
  through the Windows network, so commands run in WSL reach the tailnet
  too.
- **Phone:** Tailscale Android app, for access away from home.
- **MagicDNS** is on, so every device gets a name under
  `<tailnet>.ts.net`.

Key expiry stays **on** for the laptop and phone: a lost device loses
access on its own.

## Proxmox host

Installed from Tailscale's official apt repository, in the same deb822
format as the Proxmox one. Signing key fingerprint:
`2596 A99E AAB3 3821 893C 0A79 458C A832 957F 5868`.

```bash
curl -fsSL https://pkgs.tailscale.com/stable/debian/trixie.noarmor.gpg \
  -o /usr/share/keyrings/tailscale-archive-keyring.gpg
```

```
# /etc/apt/sources.list.d/tailscale.sources
Types: deb
URIs: https://pkgs.tailscale.com/stable/debian
Suites: trixie
Components: main
Signed-By: /usr/share/keyrings/tailscale-archive-keyring.gpg
```

```bash
apt update && apt install tailscale
tailscale up --hostname=pve   # prints a login URL, approved in the browser
```

Then, in the [admin console](https://login.tailscale.com/admin/machines),
**⋯ → Disable key expiry** on `pve`. A server should not drop off the
tailnet when its key expires (180 days by default).

Check from the laptop:

```bash
tailscale status                          # pve listed with a 100.x address
curl -sk -o /dev/null -w '%{http_code}\n' https://pve.<tailnet>.ts.net:8006   # 200
```

The web UI is now at `https://pve.<tailnet>.ts.net:8006` from any device on
the tailnet.

## Useful commands

| Command | What it does |
|---------|--------------|
| `tailscale status` | Devices on the tailnet, their IPs, and whether traffic is flowing |
| `tailscale ip -4` | This device's tailnet IPv4 address |
| `tailscale ping pve` | Pings over the tailnet and says whether the path is direct or via a DERP relay |
| `tailscale netcheck` | NAT type, UDP reachability and latency to each DERP region |
| `tailscale whois 100.x.y.z` | Which device and user own a tailnet IP |
| `tailscale up --hostname=NAME` | Joins the tailnet (first time) or changes settings |
| `tailscale down` | Disconnects without logging out |
| `tailscale logout` | Leaves the tailnet; the device must be approved again |
| `tailscale set --hostname=NAME` | Changes one setting without re-running `up` |
| `tailscale version` | Client version |
| `tailscale debug prefs` | The current settings in full |
| `systemctl status tailscaled` | The daemon on Linux |
| `journalctl -u tailscaled -f` | Follow the daemon's logs |

`tailscale ping` is the one to reach for first when something is slow:
"via DERP" means traffic is relayed rather than direct.

## Hardening

1. Enable Tailnet Lock once the laptop and `pve` have joined.
2. Access rules so only the admin laptop reaches `:8006`, `:6443` and
   `:50000`.
3. Proxmox firewall so `:8006` is no longer open to the whole LAN.

## References

- [What is Tailscale](https://tailscale.com/kb/1151/what-is-tailscale)
- [Pricing](https://tailscale.com/pricing)
- [Install on Linux](https://tailscale.com/kb/1031/install-linux)
- [Key expiry](https://tailscale.com/kb/1028/key-expiry)
- [Tailnet Lock](https://tailscale.com/kb/1226/tailnet-lock)
- [Access control (ACLs)](https://tailscale.com/kb/1018/acls)
- [MagicDNS](https://tailscale.com/kb/1081/magicdns)
- [HTTPS certificates](https://tailscale.com/kb/1153/enabling-https)
- [Headscale](https://github.com/juanfont/headscale)

[Back to the build log](../README.md#work-in-progress)
