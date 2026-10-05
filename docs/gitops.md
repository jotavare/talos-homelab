# GitOps

How the cluster's manifests get from git to the cluster: Flux, installed
by OpenTofu, reads this public repo and applies `gitops/` in order.

![GitOps order: Flux fetches the repo and applies every Kustomization in dependsOn order, the Gateway API CRDs, then Cilium, then storage and CloudNativePG, External Secrets and the add-ons with the Intel GPU plugin from its own repo, then cert-manager, the Tailscale operator and the Gateway, and Immich last, database first](../diagrams/gitops.png)

## Flux install

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

## Layout

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
    metrics-server/     CPU and memory for kubectl top
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

## How Kustomize and Flux work here

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

- [Flux documentation](https://fluxcd.io/flux/)
- [Flux Operator](https://fluxcd.control-plane.io/operator/)
- [Flux Kustomization](https://fluxcd.io/flux/components/kustomize/kustomizations/)
- [Kustomize](https://kubectl.docs.kubernetes.io/references/kustomize/)

[Back to the build log](../README.md#docs)
