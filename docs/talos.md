# Talos

The Kubernetes cluster's operating system and nodes: one control plane
and two workers running [Talos Linux](https://www.talos.dev/) as VMs on
Proxmox, built with OpenTofu. Sizes and IPs are in
[Proxmox, Planned VMs](proxmox.md#planned-vms). What runs on top is in
[Platform](platform.md), [GitOps](gitops.md) and [Immich](immich.md).

![Talos: OpenTofu builds one machine config per node from the machine secrets, the Talos defaults and the patches in talos/, applies it to the three VMs booted from the Image Factory image with five extensions, bootstraps etcd on talos-cp-1, and keeps the admin configs, the full configs and the Tailscale auth key in OpenBao](../diagrams/talos.png)

## Design

Written before building, so each choice has its reason next to it, and
updated after the build where reality differed. Versions: Talos v1.14.2
(Kubernetes v1.37), the `siderolabs/talos` OpenTofu provider v0.12.0,
Cilium v1.20.2.

### Image

Built by the [Talos Image Factory](https://factory.talos.dev/) from a
schematic that lists the extensions.

| Choice | Value | Why |
|--------|-------|-----|
| Platform | `nocloud` | Proxmox passes the static IP through cloud-init, so each node has its address from the first boot, with no DHCP phase |
| Boot | Disk image imported into Proxmox | No ISO boot and install step |
| Extensions | `qemu-guest-agent`, `iscsi-tools`, `util-linux-tools`, `tailscale`, `i915` | Clean shutdown and IP reporting in Proxmox, Longhorn, tailnet access, the Intel GPU driver and firmware |
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
([Proxmox, Firewall](proxmox.md#firewall)). Each Talos VM gets its
own:

| Rule | Why |
|------|-----|
| `policy_in: DROP` | Nothing reaches a node unless allowed below |
| Everything from the node range `.15` to `.29` | etcd, kubelet, Cilium and trustd between nodes |
| No `6443` or `50000` from the LAN | The first config went over the LAN, before Tailscale ran on the nodes. Afterwards OpenTofu, `talosctl` and `kubectl` moved to `talos-cp-1.<tailnet>.ts.net`, and the LAN rules were removed. Tailnet traffic arrives inside UDP `41641` and the node's own `tailscale0`, so the Proxmox firewall never sees it |
| UDP `41641` | Tailscale direct connections; tailnet traffic reaches the node inside this |
| ICMP from the LAN | Ping |
| `ipfilter` off | Cilium answers ARP for the LoadBalancer IPs (`.50` to `.99`) through the node's NIC; with `ipfilter` on, Proxmox would drop that traffic |

Nothing on the LAN reaches the LoadBalancer pool: no rule allows it. The
Gateway's `192.168.1.51` is announced on the LAN, but apps are reached
only through its tailnet proxy
([9. Secrets, certificates and the Gateway](platform.md#secrets-certificates-and-the-gateway)).

### API access

| Item | Value |
|------|-------|
| VIP | `192.168.1.20`, the Talos built-in shared IP, used by the workers. With one control plane it is only an extra address, ready for more |
| From my devices | The control plane's tailnet name, `talos-cp-1.<tailnet>.ts.net:6443`. The VIP is LAN only, so away from home the tailnet is the only way |
| `certSANs` | `192.168.1.20`, `192.168.1.15`, and the control plane's tailnet name and IP |
| `talosconfig` | Endpoint: the control plane's tailnet name. Nodes by LAN IP, reached through the control plane's API |

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
([Tailscale, Tailnet Lock](tailscale.md#tailnet-lock)). The nodes
join with a **pre-signed auth key**: reusable, tagged `tag:talos`, made
by OpenTofu and signed once with `tailscale lock sign` on `pve`. Nodes that
use it join already trusted, which also survives rebuilds. The key is a
secret, so it lives in OpenBao.

### Cluster config

The `siderolabs/talos` OpenTofu provider generates the machine secrets,
applies the machine configs, bootstraps etcd and returns the kubeconfig
and talosconfig. All of it stays in the encrypted OpenTofu state
([OpenTofu, State encryption](opentofu.md#state-encryption)) and in
OpenBao. The files for local use are written outside the repo, to
`~/.kube/config` and `~/.talos/config`.

### Build order

As it was done:

1. Image from the Image Factory, the three VMs, machine configs and
   bootstrap, Tailscale on every node: this page.
2. Cilium, installed by OpenTofu, then Flux taking it over:
   [Platform](platform.md#cilium) and [GitOps](gitops.md#flux-install).
3. NFS storage on the NAS and Longhorn on a data disk per worker:
   [Platform](platform.md#nfs-storage).
4. CloudNativePG and Immich: [Immich](immich.md).
5. External Secrets, cert-manager, the Tailscale operator and the Cilium
   Gateway: [Platform](platform.md#secrets-certificates-and-the-gateway).

The services VM with OpenBao came before all of it: the secrets and the
nodes' auth key live there.

## Image

[iac/modules/talos/image.tf](../iac/modules/talos/image.tf): a
`talos_image_factory_schematic` with the five extensions gives schematic
`3db570be…`; the same list always gives the same ID. Adding `i915` changed
it from `077514df…`. Proxmox downloads
the `nocloud` qcow2 of that schematic for v1.14.2 into `local` as an
`import` file, the same way as the Debian image of the services VM.

A new schematic only changes the installer in the machine config. A
running node keeps its image until it is upgraded to the new installer.
`talosctl upgrade` drains the node through the Kubernetes API at the VIP,
which the firewall only opens to the tailnet, so the drain is done with
`kubectl` and the upgrade runs without its own:

```bash
kubectl drain talos-w-2 --ignore-daemonsets --delete-emptydir-data
talosctl -n 192.168.1.22 upgrade --drain=false --wait \
  --image factory.talos.dev/nocloud-installer/<schematic>:v1.14.2
kubectl uncordon talos-w-2
```

Only `talos-w-2` runs the `i915` image so far, since only it has the GPU.
The others pick it up with their next upgrade.

## VMs

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
# i915, iscsi-tools, qemu-guest-agent, tailscale, util-linux-tools, schematic 3db570be…
```

`--insecure` is only possible in maintenance mode: there are no
certificates yet. Once a node has its config, the API needs the client
certificate from `talosconfig`.

## Config and bootstrap

[iac/modules/talos/config.tf](../iac/modules/talos/config.tf):

| Resource | Does |
|----------|------|
| `talos_machine_secrets` | The cluster's CAs, tokens and etcd encryption key, once. Kept only in the encrypted state |
| `talos_machine_configuration` (data) | One config per node: the generated defaults plus the patches below |
| `talos_machine_configuration_apply` | Sends it to the node in maintenance mode; the node installs and reboots |
| `talos_machine_bootstrap` | Starts etcd on `talos-cp-1`, once |
| `talos_cluster_kubeconfig`, `talos_client_configuration` | The admin `kubeconfig` and `talosconfig`, as sensitive outputs |

Talos 1.14 splits the machine config into many small documents
(`UnattendedInstallConfig`, `ResolverConfig`, `KubeNodeConfig`,
`KubeProxyConfig`, ...). The old `machine.install`,
`machine.network.nameservers` and `machine.kubelet.nodeIP` fields are
rejected next to them (`.machine.install is already set in v1alpha1
config`), so the patches target the documents. They are plain Talos
YAML in [talos/](../talos/), filled in by OpenTofu with `templatefile`:
[common.yaml](../talos/common.yaml) for every node,
[controlplane.yaml](../talos/controlplane.yaml) for control planes, and
[tailscale.yaml](../talos/tailscale.yaml) with the auth key.

| Patch | Nodes | Why |
|-------|-------|-----|
| `UnattendedInstallConfig`: the Image Factory installer of the schematic, disk `/dev/sda` | All | Upgrades keep the extensions. The disk selector must be repeated, a patch replaces the document's `provisioning` |
| `ResolverConfig`: `1.1.1.1` | All | Same DNS as the host |
| `KubeNodeConfig`: node IP from `192.168.1.0/24` | All | With Tailscale on the node, the kubelet could pick the tailnet address |
| `KubeFlannelCNIConfig` with `$patch: delete` | All | No default CNI, Cilium comes next |
| `machine.sysctls` | All | IPv6 router advertisements and autoconf off |
| `ExtensionServiceConfig` `tailscale`: the pre-signed key, `TS_ACCEPT_DNS=false` | All | Joins the tailnet as `tag:talos` without a manual signature |
| `KubeProxyConfig`: `enabled: false` | Control plane | Cilium replaces kube-proxy. The document only exists on control planes |
| `KubeAPIServerConfig.certExtraSANs`, `machine.certSANs` | Control plane | The VIP, the LAN IP and the tailnet name are valid for the API and Talos API |
| `cluster.etcd.advertisedSubnets` | Control plane | etcd peers on the LAN, not the tailnet |
| `Layer2VIPConfig`: `192.168.1.20` on `eth0` | Control plane | The shared API address |

The patches were tried first with `talosctl gen config --config-patch`
and `talosctl validate --mode metal`, which caught the last two errors
before any apply.

The tailnet key is a `tailscale_tailnet_key` in OpenTofu (reusable,
`tag:talos`, pre-authorized), signed once on `pve` with
`tailscale lock sign` and stored signed in OpenBao `kv/talos`. Every node
joined the tailnet on its first boot.

The configs for local use are written outside the repo:

```bash
cd iac
tofu output -raw talosconfig > ~/.talos/config
tofu output -raw kubeconfig  > ~/.kube/config
talosctl -n 192.168.1.15 get members   # all three, LAN, tailnet and VIP addresses
kubectl get nodes                      # three nodes, NotReady until there is a CNI
```

The guest agent was turned on afterwards, which made Proxmox reboot each
VM once. All three answer `qm agent <id> ping`.

## The machine config

Each node does run on one big YAML file, its machine config: 29 documents
and about 320 lines for the control plane. It is not in the repo because
it holds the cluster's private keys and tokens. It is built at plan time
from two parts:

| Part | Where |
|------|-------|
| The secrets | `talos_machine_secrets`, in the encrypted state and in OpenBao `kv/talos/cluster` |
| Everything else | The Talos defaults plus the patches in [talos/](../talos/), in git |

So the repo holds only what differs from the defaults. The full file is on
each node, in its encrypted `STATE` partition, read through the API:

```bash
talosctl -n 192.168.1.15 get machineconfig -o yaml   # contains secrets, do not paste it anywhere
```

The configs are generated with Talos' own documentation (`docs` and
`examples` on), a comment above each field, the same file
`talosctl gen config` writes. The node keeps only a few of those
comments, so the full commented file of each node is also stored in
OpenBao by OpenTofu:

```bash
bao kv get -mount=kv -field=talos-cp-1 talos/machine-configs   # contains secrets
```

## Secrets and configs in OpenBao

`kv/talos/cluster` holds the machine secrets, the `talosconfig` and the
admin `kubeconfig`, written by OpenTofu
([openbao.tf](../iac/modules/talos/openbao.tf)). The state on the laptop
already has them; the copy in OpenBao means losing the laptop does not
lose the cluster. Restore on a new laptop:

```bash
bao kv get -mount=kv -field=talosconfig talos/cluster > ~/.talos/config
bao kv get -mount=kv -field=kubeconfig  talos/cluster > ~/.kube/config
```

## References

- [Talos Linux documentation](https://www.talos.dev/)
- [Talos on Proxmox](https://docs.siderolabs.com/talos/v1.14/platform-specific-installations/virtualized-platforms/proxmox)
- [Talos Image Factory](https://factory.talos.dev/)
- [Talos system extensions](https://github.com/siderolabs/extensions)
- [siderolabs/talos OpenTofu provider](https://registry.terraform.io/providers/siderolabs/talos/latest/docs)
- [Tailnet Lock: pre-signed auth keys](https://tailscale.com/kb/1226/tailnet-lock)

[Back to the build log](../README.md#docs)
