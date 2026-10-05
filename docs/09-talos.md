# Talos

The Kubernetes cluster: one control plane and two workers running
[Talos Linux](https://www.talos.dev/) as VMs on Proxmox, built with
OpenTofu. Sizes and IPs are in
[01. Proxmox, Planned VMs](01-proxmox.md#planned-vms).

## Design

Written before building, so each choice has its reason next to it.
Versions at the time: Talos v1.14.1, the `siderolabs/talos` OpenTofu
provider v0.12.0, Cilium v1.20.2.

### Image

Built by the [Talos Image Factory](https://factory.talos.dev/) from a
schematic that lists the extensions.

| Choice | Value | Why |
|--------|-------|-----|
| Platform | `nocloud` | Proxmox passes the static IP through cloud-init, so each node has its address from the first boot, with no DHCP phase |
| Boot | Disk image imported into Proxmox | No ISO boot and install step |
| Extensions | `qemu-guest-agent`, `iscsi-tools`, `util-linux-tools`, `tailscale` | Clean shutdown and IP reporting in Proxmox, Longhorn, tailnet access |
| Secure Boot | Off | Simpler for a proof of concept |

### VM settings

| Setting | Value | Why |
|---------|-------|-----|
| Machine, firmware | `q35`, UEFI (OVMF) | Modern defaults, recommended by Talos |
| CPU type | `host` | All CPU features, no emulation overhead; there is no other node to migrate to |
| Memory | Fixed, ballooning off | No hidden overcommit |
| Disk | VirtIO SCSI single, `iothread`, `discard=on`, `ssd=1` | Deleted blocks go back to the thin pool and the NVMe, which matters for QLC wear |
| Network | VirtIO on `vmbr0`, `firewall=1` | Turns on the per-VM firewall |
| Guest agent | On | Clean shutdown from Proxmox, IPs visible in the UI |
| Start on boot | Yes, control plane first | The cluster comes back after a host reboot |

### VM firewall

The host firewall only protects Proxmox itself
([01. Proxmox, Firewall](01-proxmox.md#firewall)). Each Talos VM gets its
own:

| Rule | Why |
|------|-----|
| `policy_in: DROP` | Nothing reaches a node unless allowed below |
| Everything from the node range `.15` to `.29` | etcd, kubelet, Cilium and trustd between nodes |
| `6443` and `50000` from the LAN, for now | The first config is applied over the LAN, before Tailscale runs on the nodes. Narrowed to the tailnet once it does |
| UDP `41641` | Tailscale direct connections; tailnet traffic reaches the node inside this |
| ICMP from the LAN | Ping |
| `ipfilter` off | Cilium answers ARP for the LoadBalancer IPs (`.50` to `.99`) through the node's NIC; with `ipfilter` on, Proxmox would drop that traffic |

Which app ports on the LoadBalancer pool are open, and to whom, is decided
together with tailnet-only access for admin UIs (Backlog).

### API access

| Item | Value |
|------|-------|
| VIP | `192.168.1.20`, the Talos built-in shared IP, used by the workers. With one control plane it is only an extra address, ready for more |
| From my devices | The control plane's tailnet name, `talos-cp-1.<tailnet>.ts.net:6443`. The VIP is LAN only, so away from home the tailnet is the only way |
| `certSANs` | `192.168.1.20`, `192.168.1.15`, and the control plane's tailnet name and IP |
| `talosconfig` | Endpoint: the control plane's tailnet name. Nodes: all four |

### Network and cluster

| Item | Value |
|------|-------|
| Hostnames | `talos-cp-1`, `talos-w-1`, `talos-w-2`. The VM ID is 100 plus the last octet of the IP: `115`, `121`, `122` (the services VM `.30` is `130`) |
| DNS | `1.1.1.1`. Tailscale does not manage DNS on the nodes, same as on the host |
| NTP | `time.cloudflare.com`, the Talos default |
| IPv6 | Router advertisements and autoconf off with machine sysctls, same as the host |
| KubeSpan | Off. All nodes share one LAN |
| CNI | `none`, and kube-proxy off: Cilium replaces both |
| Cilium devices | The LAN NIC only, never `tailscale0` |

### Tailscale on the nodes

Tailnet Lock refuses any new device until a signing node signs it
([02. Tailscale, Tailnet Lock](02-tailscale.md#tailnet-lock)). The nodes
join with a **pre-signed auth key**: reusable, tagged `tag:talos`, and
signed once with `tailscale lock sign` on `pve` or the laptop. Nodes that
use it join already trusted, which also survives rebuilds. The key is a
secret, so it lives in OpenBao.

### Cluster config

The `siderolabs/talos` OpenTofu provider generates the machine secrets,
applies the machine configs, bootstraps etcd and returns the kubeconfig
and talosconfig. All of it stays in the encrypted OpenTofu state
([05. OpenTofu, State encryption](05-opentofu.md#state-encryption)). The
`kubeconfig` and `talosconfig` files written for local use are in
`.gitignore`.

### Build order

1. The services VM with OpenBao, since the auth key and secrets live
   there, and Garage for backups.
2. Talos image and the four VMs.
3. Machine configs and bootstrap.
4. Cilium.
5. Flux.

## Build

### 1. Image

[iac/modules/talos/image.tf](../iac/modules/talos/image.tf): a
`talos_image_factory_schematic` with the four extensions gives schematic
`077514df…`; the same list always gives the same ID. Proxmox downloads
the `nocloud` qcow2 of that schematic for v1.14.2 into `local` as an
`import` file, the same way as the Debian image of the services VM.

### 2. VMs

[iac/modules/talos/vms.tf](../iac/modules/talos/vms.tf): one
`for_each` over the nodes in [iac/main.tf](../iac/main.tf), each VM
with its firewall. The disk is imported from the Talos image and grown to
its size; cloud-init gives the static IP and DNS.

The guest agent starts disabled: Talos only runs extension services once
it has a machine config, and the Proxmox provider would wait 15 minutes
for an agent that is not there yet. It is turned on after the install.

After boot the nodes wait in maintenance mode, with the extensions
already loaded:

```bash
talosctl -n 192.168.1.15 get extensions --insecure
# iscsi-tools, qemu-guest-agent, tailscale, util-linux-tools, schematic 077514df…
```

`--insecure` is only possible in maintenance mode: there are no
certificates yet. Once a node has its config, the API needs the client
certificate from `talosconfig`.

## GitOps layout

The Kubernetes manifests go in `gitops/`, read by Flux. One folder per
thing, and a separate folder that says what Flux applies and in what
order:

```text
gitops/
  flux/                 Flux itself, plus one Kustomization per folder below
  infrastructure/
    cilium/             network: the Helm release
      config/           its settings: LoadBalancer IP pool
    longhorn/
    nfs/                NFS CSI driver
      config/           the storage class for the NAS
  projects/
    immich/
```

| Folder | Holds |
|--------|-------|
| `flux/` | What Flux runs and the order: `infrastructure/longhorn` after `infrastructure/cilium`, every project after the infrastructure it needs (`dependsOn`) |
| `infrastructure/<name>/` | A cluster component: its Helm release, and its settings in `config/` next to it |
| `projects/<name>/` | An app, as at work |

Settings often use types the chart itself brings: a Cilium IP pool only
exists once Cilium is installed. Flux checks a whole folder before it
applies any of it, so a pool next to the release would block the release
too. `config/` is its own Flux step that waits for the release.

## References

- [Talos Linux documentation](https://www.talos.dev/)
- [Talos on Proxmox](https://docs.siderolabs.com/talos/v1.14/platform-specific-installations/virtualized-platforms/proxmox)
- [Talos Image Factory](https://factory.talos.dev/)
- [Talos system extensions](https://github.com/siderolabs/extensions)
- [siderolabs/talos OpenTofu provider](https://registry.terraform.io/providers/siderolabs/talos/latest/docs)
- [Cilium on Talos](https://www.talos.dev/v1.14/kubernetes-guides/network/deploying-cilium/)
- [Tailnet Lock: pre-signed auth keys](https://tailscale.com/kb/1226/tailnet-lock)

[Back to the build log](../README.md#work-in-progress)
