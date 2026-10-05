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

### 3. Config and bootstrap

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

### The machine config

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

To read every field with its documentation, generate a throwaway config
outside the repo: `talosctl gen config test https://192.168.1.20:6443`
writes `controlplane.yaml` with a comment above each field. The node
stores its config without comments.

### Secrets and configs in OpenBao

`kv/talos/cluster` holds the machine secrets, the `talosconfig` and the
admin `kubeconfig`, written by OpenTofu
([openbao.tf](../iac/modules/talos/openbao.tf)). The state on the laptop
already has them; the copy in OpenBao means losing the laptop does not
lose the cluster. Restore on a new laptop:

```bash
bao kv get -mount=kv -field=talosconfig talos/cluster > ~/.talos/config
bao kv get -mount=kv -field=kubeconfig  talos/cluster > ~/.kube/config
```

### 4. Cilium

Flux runs as pods, and pods need a network first, so Flux cannot install
the network. OpenTofu installs Cilium once with the Helm provider
([iac/modules/cilium](../iac/modules/cilium/)); Flux takes the same
release over later.

The values live in
[gitops/infrastructure/cilium/values.yaml](../gitops/infrastructure/cilium/values.yaml),
read by OpenTofu now and by Flux later, so they exist once:

| Value | Why |
|-------|-----|
| `kubeProxyReplacement: true` | Cilium handles Services with eBPF, kube-proxy is off |
| `k8sServiceHost: localhost`, `k8sServicePort: 7445` | KubePrism, Talos' local API proxy on every node. Cilium needs the API before Services exist |
| `devices: eth0` | Never `tailscale0` |
| `cgroup.autoMount.enabled: false`, `hostRoot: /sys/fs/cgroup` | Talos mounts cgroups itself |
| `securityContext.capabilities` | The list Talos documents, without `SYS_MODULE`: Talos does not let pods load kernel modules |
| `ipam.mode: kubernetes` | Pod IPs from each node's Kubernetes pod range |
| `operator.replicas: 1` | One is enough for three nodes |

```bash
kubectl get nodes   # all Ready
kubectl -n kube-system exec ds/cilium -c cilium-agent -- cilium-dbg status --brief   # OK
```

### 5. Flux

Flux is installed by OpenTofu as the
[Flux Operator](https://fluxcd.control-plane.io/operator/) plus a
`FluxInstance` ([iac/modules/flux](../iac/modules/flux/)), both Helm
charts. The instance values are in
[gitops/flux/instance.yaml](../gitops/flux/instance.yaml):

| Item | Value | Why |
|------|-------|-----|
| Flux | `2.9.x` | The operator keeps it on the latest patch |
| Components | source, kustomize, helm, notification | No image automation yet |
| Sync | `https://github.com/jotavare/talos-homelab.git`, `main`, `gitops/flux` | The repo is public, so Flux reads it without a token. `flux bootstrap` would need a GitHub token with write access to commit its own files |

Taking Cilium over:

1. OpenTofu installed Cilium first: Flux runs in pods, and pods need the
   network.
2. Flux's `HelmRelease` has the same name, namespace and values (the same
   [values.yaml](../gitops/infrastructure/cilium/values.yaml) through a
   ConfigMap). Its first run was a Helm upgrade to revision 2 of the
   existing release, so nothing restarted.
3. OpenTofu keeps its `helm_release` with `ignore_changes = all`: it only
   matters on a fresh cluster, and never touches Cilium afterwards.

The Cilium Kustomization has `prune: false`: removing the folder by
mistake would otherwise uninstall the network of the whole cluster.

### 6. NFS storage

[gitops/infrastructure/nfs](../gitops/infrastructure/nfs/): the
[csi-driver-nfs](https://github.com/kubernetes-csi/csi-driver-nfs) chart,
then in `config/` the `nas` storage class:

| Setting | Value | Why |
|---------|-------|-----|
| Server, share | `192.168.1.11`, `/tank/k8s` | The NAS ([08. NAS](08-nas.md)) |
| `subDir` | `<namespace>/<pvc name>` | Readable folder names on the NAS instead of `pvc-<uuid>` |
| `reclaimPolicy` | `Retain` | Deleting a claim never deletes the photos |
| Mount options | `nfsvers=4.2`, `hard` | The NAS only serves 4.1 and 4.2. `hard` makes writes wait through a WiFi drop instead of failing |

Tested with a claim and a non-root pod that wrote a file, read back on the
NAS. The pod needs `runAsGroup` and `fsGroup`: the driver chowns the new
folder to the `fsGroup`, and without a matching group the write is
refused. The test volume and its folder were deleted afterwards.

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
