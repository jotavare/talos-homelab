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
| Talos VMs | Tailscale system extension, in the Talos phase |

## Account and laptop

1. Tailscale account, signed in with GitHub, with 2FA enabled on the GitHub
   account.
2. Tailscale app on Windows, logged in to the same account.

## Proxmox host

1. Add Tailscale's apt repository for Debian trixie and install
   `tailscale`.
2. `tailscale up --hostname=pve`, approve the login in the browser.
3. Disable key expiry for `pve` in the admin console, so the server does
   not drop off the tailnet after 180 days.
4. Check the web UI over the tailnet: `https://pve.<tailnet>.ts.net:8006`.

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
