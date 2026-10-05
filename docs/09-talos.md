# Talos

The Kubernetes cluster: one control plane and two workers running
[Talos Linux](https://www.talos.dev/) as VMs on Proxmox, built with
OpenTofu. Sizes and IPs are in
[01. Proxmox, Planned VMs](01-proxmox.md#planned-vms).

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
| No `6443` or `50000` from the LAN | The first config went over the LAN, before Tailscale ran on the nodes. Afterwards OpenTofu, `talosctl` and `kubectl` moved to `talos-cp-1.<tailnet>.ts.net`, and the LAN rules were removed. Tailnet traffic arrives inside UDP `41641` and the node's own `tailscale0`, so the Proxmox firewall never sees it |
| UDP `41641` | Tailscale direct connections; tailnet traffic reaches the node inside this |
| ICMP from the LAN | Ping |
| `ipfilter` off | Cilium answers ARP for the LoadBalancer IPs (`.50` to `.99`) through the node's NIC; with `ipfilter` on, Proxmox would drop that traffic |

Nothing on the LAN reaches the LoadBalancer pool: no rule allows it. The
Gateway's `192.168.1.51` is announced on the LAN, but apps are reached
only through its tailnet proxy
([9. Secrets, certificates and the Gateway](#9-secrets-certificates-and-the-gateway)).

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
([02. Tailscale, Tailnet Lock](02-tailscale.md#tailnet-lock)). The nodes
join with a **pre-signed auth key**: reusable, tagged `tag:talos`, made
by OpenTofu and signed once with `tailscale lock sign` on `pve`. Nodes that
use it join already trusted, which also survives rebuilds. The key is a
secret, so it lives in OpenBao.

### Cluster config

The `siderolabs/talos` OpenTofu provider generates the machine secrets,
applies the machine configs, bootstraps etcd and returns the kubeconfig
and talosconfig. All of it stays in the encrypted OpenTofu state
([05. OpenTofu, State encryption](05-opentofu.md#state-encryption)) and in
OpenBao. The files for local use are written outside the repo, to
`~/.kube/config` and `~/.talos/config`.

### Build order

As it was done, each step a section below:

1. Image from the Image Factory.
2. The three VMs, waiting in maintenance mode.
3. Machine configs and bootstrap, Tailscale on every node.
4. Cilium, installed by OpenTofu.
5. Flux, taking Cilium over.
6. NFS storage on the NAS.
7. Longhorn on a data disk per worker.
8. CloudNativePG and Immich.
9. External Secrets, cert-manager, the Tailscale operator and the Cilium
   Gateway.

The services VM with OpenBao came before all of it: the secrets and the
nodes' auth key live there.

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

The configs are generated with Talos' own documentation (`docs` and
`examples` on), a comment above each field, the same file
`talosctl gen config` writes. The node keeps only a few of those
comments, so the full commented file of each node is also stored in
OpenBao by OpenTofu:

```bash
bao kv get -mount=kv -field=talos-cp-1 talos/machine-configs   # contains secrets
```

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

### 7. Longhorn

Block storage for databases and anything that should not sit on NFS over
WiFi. Two parts:

**A data disk per worker.** Talos 1.14 no longer has kubelet extra
mounts; the way to give Longhorn its own place is a `UserVolumeConfig`.
The 80 GB system disk was already all `EPHEMERAL`, so each worker got a
second 50 GB disk (`scsi1`, the `data` field in
[iac/main.tf](../iac/main.tf)), hot-plugged without a reboot.
[talos/worker.yaml](../talos/worker.yaml) formats it as XFS and Talos
mounts it at `/var/mnt/longhorn`:

```bash
talosctl -n 192.168.1.21 get volumestatus u-longhorn   # disk, ready, /dev/sdb, 54 GB
```

**Longhorn through Flux**, in
[gitops/infrastructure/longhorn](../gitops/infrastructure/longhorn/):

| Value | Why |
|-------|-----|
| Namespace labelled `pod-security ... privileged` | Longhorn's managers need host access; the cluster default is `baseline` |
| `defaultDataPath: /var/mnt/longhorn` | The user volume above |
| `defaultReplicaCount: 1`, `defaultClassReplicaCount: 1` | Every replica would land on the same NVMe anyway (README trade-offs) |
| `persistence.defaultClass: true` | Claims without a storage class get Longhorn; the NAS is asked for by name, `nas` |
| CSI sidecars and UI at one replica | Saves RAM on a two-worker cluster |
| `preUpgradeChecker.jobEnabled: false` | The checker job does not work with Flux' Helm upgrades |

Longhorn runs on the workers only: the control plane keeps its
`NoSchedule` taint.

The install was also what exposed the `pve` NIC hang
([01. Proxmox, NIC hang](01-proxmox.md#nic-hang)).

### 8. CloudNativePG and Immich

[CloudNativePG](https://cloudnative-pg.io/) runs Postgres as a
Kubernetes resource: a `Cluster` gets its pods, volumes, users and
backups from the operator in
[gitops/infrastructure/cnpg](../gitops/infrastructure/cnpg/).

[Immich](https://immich.app/) v3 needs Postgres with the VectorChord
extension. Its chart recommends exactly this setup, and
[gitops/projects/immich](../gitops/projects/immich/) follows it:

| File | What |
|------|------|
| `database.yaml` | A one-instance `Cluster` on Longhorn (5 Gi), Postgres 18, with the VectorChord extension mounted as an image (`vchord-scratch`) and loaded at start. A `Database` resource creates the extensions Immich uses |
| `library.yaml` | The photo library, a claim on the `nas` storage class: the files live on `pve-desktop` in `/tank/k8s/immich/immich-library` |
| `database/secret.yaml` | An `ExternalSecret` with the database user and password from OpenBao `kv/k8s/immich-database`. CloudNativePG applies it to the `app` role through `managed.roles` and follows changes (`cnpg.io/reload`) |
| `repository.yaml`, `release.yaml` | The Immich chart from its OCI registry, with Valkey on, the library claim, and the database credentials from that secret. CloudNativePG's own generated `immich-database-app` is not used |
| `route.yaml` | The `HTTPRoute` for `immich.home.<domain>` on the Gateway |
| `config.yaml` | Immich's settings as a file (`IMMICH_CONFIG_FILE`): the external address and login through Pocket ID. An `ExternalSecret` template renders it: Flux fills `${DOMAIN}`, External Secrets the OIDC client from `kv/k8s/immich-oauth`. With a config file the settings page is read-only, git is the source. A change needs `kubectl -n immich rollout restart deploy/immich-server` |

| Data | Where | Why |
|------|-------|-----|
| Photos and videos | NAS, NFS over WiFi | Large, written once, read often; fine at WiFi speed |
| Postgres | Longhorn on the worker data disks | A database over NFS on WiFi is slow and can corrupt |
| Machine learning cache, Valkey | `emptyDir` | Rebuilt on restart |

The Flux step `immich` waits for `cnpg`, `longhorn` and `nfs-config`
([gitops/flux/projects.yaml](../gitops/flux/projects.yaml)).

Immich runs in two Flux steps: `immich-database` first, then `immich`.
With one step, the server started before the `Database` resource had
created the extensions and crashed on `permission denied to create
extension "vector"`. The namespace, the database `Cluster` and the library
claim carry `kustomize.toolkit.fluxcd.io/prune: disabled`, so moving or
deleting files in git never deletes the photos or the database.

The admin account was created through the Immich API with a generated
password, kept in OpenBao `kv/immich`.

Every setting was read back from `/api/system-config` and compared with
the defaults. Changed in [config.yaml](../gitops/projects/immich/config.yaml):

| Setting | Value | Why |
|---------|-------|-----|
| `server.externalDomain` | `https://immich.home.<domain>` | Share links and the mobile app get the right address |
| `oauth` | Pocket ID, button "Login with Pocket ID", no auto-register | Same login as OpenBao and Proxmox; only users that already exist can log in |
| `passwordLogin` | on | Fallback while Pocket ID is new |
| `server.publicUsers` | off | Users do not see the list of all users |
| `newVersionCheck` | off | Versions are pinned in git; no calls to GitHub, as for Pocket ID |
| `storageTemplate` | on, `{{y}}/{{y}}-{{MM}}-{{dd}}/{{filename}}` | Files on the NAS by date with their own names, readable over SMB and easy to back up. The template braces are escaped in the `ExternalSecret`, which also uses `{{ }}` |

Kept as they are:

| Setting | Default | Note |
|---------|---------|------|
| `backup.database` | every night at 02:00, keep 14 | Immich dumps its own database to `library/backups`, which is on the NAS: a database copy outside the cluster already |
| `machineLearning` | CLIP `ViT-B-32__openai`, faces `buffalo_l`, OCR | The small models, enough for 8 GB workers |
| `ffmpeg.accel` | disabled | No GPU |
| `map` | tiles from `tiles.immich.cloud` | The browser fetches map tiles from Immich's servers |
| `trash` | 30 days | |


### 9. Secrets, certificates and the Gateway

Apps are reached the way they would be in a company cluster: one Gateway,
one `HTTPRoute` per app, certificates from cert-manager, secrets from the
secret store. Nothing outside the cluster changes for a new app except
its DNS name.

```text
laptop (tailnet) -> gateway.<tailnet>.ts.net (Tailscale proxy pod)
                 -> Cilium Gateway "home" (TLS, *.home.<domain>)
                 -> HTTPRoute -> immich-server
```

| Part | Where | Does |
|------|-------|------|
| External Secrets Operator | [infrastructure/external-secrets](../gitops/infrastructure/external-secrets/) | Copies OpenBao secrets into Kubernetes Secrets. The `openbao` `ClusterSecretStore` logs in with the operator's service-account token |
| OpenBao login for the cluster | [iac/modules/openbao/kubernetes.tf](../iac/modules/openbao/kubernetes.tf) | A JWT login (`auth/kubernetes`) that checks tokens against the cluster's service-account public key, taken from the Talos secrets. OpenBao never calls the cluster. The role accepts only `external-secrets/external-secrets`, audience `openbao`, policy read-only on `kv/k8s/*` and `kv/config` |
| `cluster-settings` | Made by OpenTofu in `flux-system` | `DOMAIN` and `TAILNET` for Flux' `postBuild` substitution, so manifests say `${DOMAIN}` and the public repo never holds the domain |
| cert-manager | [infrastructure/cert-manager](../gitops/infrastructure/cert-manager/) | The `letsencrypt` `ClusterIssuer`, DNS-01 through Cloudflare with the token from `kv/k8s/cert-manager` |
| Gateway API CRDs | [infrastructure/gateway-api](../gitops/infrastructure/gateway-api/) | Upstream `standard-install.yaml` v1.6.1, vendored: Flux does not fetch remote files |
| Cilium Gateway | [infrastructure/gateway](../gitops/infrastructure/gateway/) | `GatewayClass` `cilium`, the wildcard certificate `*.home.<domain>`, and the `Gateway` `home` with one HTTPS listener. Its Service gets `192.168.1.51` on the LAN and is exposed on the tailnet |
| Tailscale operator | [infrastructure/tailscale](../gitops/infrastructure/tailscale/) | Watches Services with `tailscale.com/expose`: the Gateway becomes the tailnet device `gateway` |
| DNS | [iac/modules/dns](../iac/modules/dns/) | `cluster_apps` in [iac/main.tf](../iac/main.tf) point at the Gateway's tailnet IP, read from the Tailscale API |

Things found on the way:

- Pods already reach OpenBao: the nodes route `100.x` through their own
  Tailscale and masquerade pod traffic, and `tag:talos` may reach
  `tag:services:443`.
- The Cilium chart did not create the `GatewayClass`, so it is in git.
- Turning on Gateway support also needs the Cilium operator restarted:
  `rollOutCiliumPods` only restarts the agents, and they wait for CRDs the
  operator registers.
- Cilium's values ConfigMap carries `reconcile.fluxcd.io/watch: Enabled`,
  so a change upgrades the release at once instead of within 30 minutes.
- The Gateway proxy needed a Tailnet Lock signature
  ([02. Tailscale](02-tailscale.md#devices-made-by-the-kubernetes-operator)).

Adding an app: its folder in `projects/`, an `HTTPRoute` with
`<name>.home.${DOMAIN}`, and its name in `cluster_apps`.

## GitOps layout

The Kubernetes manifests go in `gitops/`, read by Flux. One folder per
thing, and a separate folder that says what Flux applies and in what
order:

```text
gitops/
  flux/                 Flux itself, plus one Kustomization per folder below
  infrastructure/
    gateway-api/        Gateway API CRDs
    cilium/             network: the Helm release
      config/           LoadBalancer IP pool, L2 announcements
    external-secrets/   the operator
      config/           the OpenBao store
    cert-manager/
      config/           the Let's Encrypt issuer and its token
    tailscale/          the operator and its OAuth secret
    gateway/            GatewayClass, wildcard certificate, Gateway
    longhorn/
    cnpg/
    nfs/                NFS CSI driver
      config/           the storage class for the NAS
  projects/
    immich/
      database/         namespace and Postgres, applied first
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

### How Kustomize and Flux work here

For someone used to Argo CD and Helm:

| Argo CD and Helm | Here |
|------------------|------|
| A root `Application` that applies other `Application`s | The `FluxInstance` syncs `gitops/flux/`, which holds a Flux `Kustomization` per folder |
| An `Application` per folder | A Flux `Kustomization`: `cilium`, `longhorn`, `immich`, ... |
| Sync waves | `dependsOn` between Flux `Kustomization`s |
| A Helm chart | A `HelmRelease`, still Helm, for every third-party app |
| Templates and values for our own manifests | Plain YAML. The only variable is `${DOMAIN}` (and `${TAILNET}`), filled by Flux from `cluster-settings` (`postBuild.substituteFrom`) |

Two things share the name:

| | `kustomization.yaml` | Flux `Kustomization` |
|-|----------------------|----------------------|
| Tool | Kustomize, built into `kubectl` | Flux |
| Answers | Which files make up this folder, and generators such as the ConfigMap from Cilium's `values.yaml` | When and in what order the folder is applied, and whether it is healthy |
| Where | In every folder | `gitops/flux/infrastructure.yaml`, `gitops/flux/projects.yaml` |

The cycle, with the intervals in use:

| What | Interval | Effect |
|------|----------|--------|
| Fetch from GitHub (`GitRepository`) | 1 min | A push shows up within a minute; `reconcile.fluxcd.io/requestedAt` skips the wait |
| Each step (`Kustomization`) | 10 min | Applies at once on a new commit, and re-applies every 10 min, which undoes manual changes |
| Waiting for a dependency (`retryInterval`) | 1 min | A step whose dependency is not ready checks again every minute |
| Helm charts (`HelmRelease`) | 30 min | Upgrade when the chart or values change. Cilium's values ConfigMap has `reconcile.fluxcd.io/watch: Enabled`, so it applies at once |
| Chart indexes (`HelmRepository`) | 1 h | New chart versions show up |

`wait: true` makes a step ready only once what it applied is healthy.
`prune: true` deletes from the cluster what was deleted from git, except
objects with `kustomize.toolkit.fluxcd.io/prune: disabled`: the Immich
namespace, database and photo library. The Cilium step has `prune: false`:
deleting its folder by mistake would take the network down.

## References

- [Talos Linux documentation](https://www.talos.dev/)
- [Talos on Proxmox](https://docs.siderolabs.com/talos/v1.14/platform-specific-installations/virtualized-platforms/proxmox)
- [Talos Image Factory](https://factory.talos.dev/)
- [Talos system extensions](https://github.com/siderolabs/extensions)
- [siderolabs/talos OpenTofu provider](https://registry.terraform.io/providers/siderolabs/talos/latest/docs)
- [Cilium on Talos](https://www.talos.dev/v1.14/kubernetes-guides/network/deploying-cilium/)
- [Tailnet Lock: pre-signed auth keys](https://tailscale.com/kb/1226/tailnet-lock)

[Back to the build log](../README.md#work-in-progress)
