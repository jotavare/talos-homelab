# Homelab

A single-server homelab running Kubernetes on
[Talos Linux](https://www.talos.dev/), an immutable, API-managed OS, as
VMs on Proxmox. Built step by step and written down as it happens.

**Why.** I already run Kubernetes at work on RKE2, GKE and AKS, and this
is not my first homelab. This one is for what I do not touch at work:
Talos itself, and open source tools I have not used professionally. When
something I already know is still the best fit, it stays.

**Why public.** On purpose: to practise security in the open. Secrets
live in three places:

- **This repo**, encrypted with [SOPS](https://github.com/getsops/sops)
  and age: only the secrets that solve a chicken-and-egg problem, needed
  before OpenBao exists, and a few private settings. Next to them sits an
  encrypted OpenTofu state.
- **OpenBao**: app secrets and everything else the cluster needs.
- **My Bitwarden**: personal credentials and recovery keys, never here.

The infrastructure is only reachable over a private tailnet. If you
manage to decrypt anything, or find something that should not be public,
please tell me through a [private security report](.github/SECURITY.md).

## Goals

- **Learn Talos**: API and machine configs only, no SSH.
- **Try new tools**: open source over what I use at work, unless clearly worse.
- **Fully public**: every config, decision and dead end, reverted ones too.
- **No exposed secrets**: passwords, keys and tokens encrypted or kept out of git.
- **Private management**: admin interfaces only over the tailnet.
- **Reproducible**: rebuild everything from this repo, VMs included.
- **GitOps**: git is the source of truth, changes land as commits and apply themselves.
- **Automation**: nothing done by hand twice.
- **Diagrams**: show how host, VMs, network and secrets connect.

## Diagrams

<p align="center">
  <img src="diagrams/overview.png" alt="Homelab overview: ISP router, Wi-Fi access point and a Proxmox host running the Talos VMs and the OpenBao and Garage containers, with admin access from a laptop or phone only over Tailscale">
  <br>
  <sub><b>Overview.</b> One flat LAN, Talos VMs bridged onto it, management over Tailscale only.</sub>
</p>

<p align="center">
  <img src="diagrams/proxmox.png" alt="Proxmox host plan: 32 GB of RAM split between the host, the OpenBao and Garage LXC containers, one control plane and three workers on the vmbr0 bridge, and the NVMe split into VM and LXC disks, ISOs and swap">
  <br>
  <sub><b>Proxmox.</b> Planned split of RAM and disk between the host, OpenBao, one control plane and three workers. Production needs three control planes for etcd quorum; one is used here to leave more room for apps (<a href="docs/01-proxmox.md#planned-vms">why</a>).</sub>
</p>

<p align="center">
  <img src="diagrams/tailscale.png" alt="Tailscale traffic: direct over the LAN at home, direct over the internet when away, DERP relay as a fallback, coordination server for keys and policy only">
  <br>
  <sub><b>Tailscale.</b> At home, direct over the LAN. Away from home, direct over the internet, with a relay as fallback (<a href="docs/02-tailscale.md#how-traffic-flows">how</a>).</sub>
</p>

## Hardware

The host and the home network it sits on.

### Proxmox host

| Component | Detail |
|-----------|--------|
| Model | HP Pro Mini 400 G9 |
| CPU | Intel Core i5-12500T, 6 cores / 12 threads, 35 W |
| RAM | 32 GB DDR4-3200 (2 x 16 GB, both slots used, max 64 GB) |
| Storage | Intel 670p 512 GB NVMe (QLC) |
| Network | Intel I219-LM gigabit, single port, no Wi-Fi |
| GPU | Intel UHD Graphics 770 (integrated) |

### Network

| Device | Detail |
|--------|--------|
| Router | ISP-provided, gateway and DHCP server |
| Access point | Cudy router running OpenWrt 25.12, DHCP disabled |

LAN `192.168.1.0/24`:

| Range | Type | Use |
|-------|------|-----|
| `192.168.1.1` | Static | ISP router |
| `192.168.1.2` | Static | Access point |
| `192.168.1.10` | Static | Proxmox |
| `192.168.1.11` to `.19` | Static | Talos control plane |
| `192.168.1.20` | Static | Kubernetes API VIP |
| `192.168.1.21` to `.29` | Static | Talos workers |
| `192.168.1.30` to `.49` | Static | Services outside the cluster (services VM `.30`, Garage `.40`) and other lab machines |
| `192.168.1.50` to `.99` | Static | Cilium LoadBalancer pool |
| `192.168.1.100` to `.254` | Dynamic (DHCP) | Phones, laptops and other clients |

## Core stack

What I already know, from work, earlier homelabs or elsewhere, and what
this homelab uses instead. `/` separates alternatives, `+` means used
together.

### Infrastructure

| Area | Already used | Candidate |
|------|--------------|-----------|
| Hypervisor | vSphere, XCP-ng, Proxmox VE | **Proxmox VE** |
| Kubernetes | GKE, AKS, RKE2 | **Talos** |
| IaC | Terraform | **OpenTofu** |
| Config management | Ansible | **Ansible** |
| Remote access | Cloudflare Tunnel | **Tailscale** / **Headscale** |
| Containers outside the cluster | Docker, Docker Compose | **Docker Compose** in a VM |
| Reverse proxy outside the cluster | Traefik | **Caddy** / **Nginx Proxy Manager** |

### Delivery

| Area | Already used | Candidate |
|------|--------------|-----------|
| Git and CI/CD | GitHub, GitLab, Jenkins, Azure DevOps | **Forgejo** / **Gitea** |
| GitOps | Argo CD | **Flux** |
| Container registry | JFrog Artifactory, Nexus | **Harbor** / **Zot** |
| Dependency updates | Renovate | **Renovate** |

### Cluster Components

| Area | Already used | Candidate |
|------|--------------|-----------|
| CNI | Canal (Calico + Flannel) | **Cilium** |
| Service mesh | Istio | **Cilium** |
| Load balancer | kube-vip, GKE and AKS cloud load balancers | **Cilium** / **MetalLB** |
| Ingress | Traefik, Istio | **Envoy Gateway** / **Cilium** |
| Certificates | cert-manager, step-ca, Traefik ACME, Istio CA (mTLS) | **cert-manager** + **step-ca** |
| Autoscaling | KEDA | **KEDA** |

### Security

| Area | Already used | Candidate |
|------|--------------|-----------|
| SSO | Authentik, Keycloak | **Kanidm** / **Zitadel** / **Authelia** |
| Secrets | HashiCorp Vault | **OpenBao** (outside the cluster) + **External Secrets Operator** + **SOPS** + **age** (bootstrap) |
| Policy | Kyverno | **Kyverno** / **OPA Gatekeeper** / **Kubewarden** |
| Runtime security | Falco | **Falco** / **Tetragon** |
| Brute-force protection | None | **CrowdSec** + **Envoy Gateway** rate limits |
| Vulnerability scanning | Trivy | **Trivy** / **Grype** |
| SBOM | CycloneDX, Dependency-Track | **Syft** + **Dependency-Track** |

### Storage and Data

| Area | Already used | Candidate |
|------|--------------|-----------|
| Block storage | local-path-provisioner, GKE and AKS managed disks | **Longhorn** |
| Object storage | MinIO, Google Cloud Storage, Azure Blob Storage | **Garage** (outside the cluster) |
| Databases | Postgres, managed cloud and on-prem | **CloudNativePG** |
| Backup | Cloud-managed Postgres backups | **Velero** + **Talos etcd snapshots** + **Proxmox Backup Server** |

### Observability

| Area | Already used | Candidate |
|------|--------------|-----------|
| Metrics | Prometheus | **VictoriaMetrics** |
| Logs | Loki | **VictoriaLogs** |
| Traces | Tempo, OpenTelemetry | **Jaeger** / **VictoriaTraces** |
| Dashboards | Grafana | **Grafana** / **Perses** |

## POC trade-offs

This is a proof of concept on a single server, with nothing critical on
it. Where the production way does not fit one box, the right way is
written down and the homelab knowingly does something simpler.

| Area | Production way | Here, and why |
|------|----------------|---------------|
| Control plane | Three control planes, so etcd keeps quorum when one fails | One, to leave RAM for apps. All VMs share one host anyway ([details](docs/01-proxmox.md#planned-vms)) |
| Control plane size | Enough RAM for headroom, 8 GB or more | 4 GB, tight for etcd, the API server and the Cilium agent. Watch memory and take RAM from a worker if needed |
| Block storage | Longhorn with three replicas on separate nodes and disks | Longhorn anyway, but every replica lands on the same QLC NVMe: no real redundancy, and more writes on a drive that wears fast. Use one replica per volume |
| Secrets store | Vault or OpenBao as a cluster of three on dedicated machines, auto-unsealed by a cloud key service | One OpenBao in the services VM on the same host, unsealed by hand after a reboot. Survives a cluster rebuild, not the loss of the host |
| OpenTofu state | Remote backend with locking and versioning (S3, GCS, Azure Blob) | Encrypted state file in git, no locking. Fine for one person on one laptop; old states stay in git history ([details](docs/05-opentofu.md#state-encryption)) |
| Object storage | Several nodes with replication, versioning and object lock, plus a copy off site | One Garage container on the same host, one copy of each object, no versioning. Survives a cluster rebuild, not the loss of the host or the drive ([details](docs/06-object-storage.md#limits)) |
| Backups | Proxmox Backup Server on a separate machine, plus a copy off site | A daily backup job for the containers to `local` now, Proxmox Backup Server as a VM on the same host later. Both protect against mistakes, not against losing the host ([details](docs/01-proxmox.md#container-backups)) |

## Work in progress

The build, step by step, in the order it was done. One page per phase,
with the tools, the options chosen and why.

| Phase | Covers |
|-------|--------|
| [01. Proxmox](docs/01-proxmox.md) | Install USB, install, post-install, planned VMs |
| [02. Tailscale](docs/02-tailscale.md) | Account, laptop, Proxmox host, hardening |
| [03. Ansible](docs/03-ansible.md) | Proxmox host configuration as a playbook |
| [04. Secrets](docs/04-secrets.md) | SOPS and age, OpenBao container set up and unsealed |
| [05. OpenTofu](docs/05-opentofu.md) | Proxmox user and token, project, state encryption, OpenBao container |
| [06. Object storage](docs/06-object-storage.md) | Garage container for backups: design, OpenTofu, Ansible role |
| [07. Services VM](docs/07-services.md) | Docker Compose stack with OpenBao, Caddy and Tailscale; OpenBao moved in from its container |
| [08. Talos](docs/08-talos.md) | Design: image, VM settings, firewall, API access, Tailscale |

## Backlog

Things skipped for now or not to forget. Removed once they land in a
phase page.

### Proxmox host

- [ ] Back up `/etc/pve` off the host (firewall, users, 2FA, VM configs).
- [ ] Interim NVMe wear alert: a daily cron job that reads "percentage
      used" with `smartctl` and mails through the notification target.
- [ ] NVMe wear alert in the monitoring stack, replacing the cron job.
- [ ] QLC wear budget: etcd, metrics and log retention, database WAL and
      Longhorn all write to the same drive. Keep retention short and
      check "percentage used" monthly at first.
- [ ] UPS with NUT for a clean shutdown on power loss.
- [ ] Test the web UI over tailnet IPv6 from a phone.

- [ ] OpenTofu and Ansible: reach Proxmox as `pve.home.<domain>` with
      certificate checks on, instead of the tailnet IP with
      `insecure = true`.
- [ ] Run the Ansible compliance checks on a schedule (a timer on the
      laptop or CI with a Tailscale runner), so drift shows up without a
      manual run.

### Tailscale

- [ ] Sync `tailscale/policy.hujson` to the tailnet from git (GitOps).

### Repository

- [ ] Security audit pipeline in CI: secret scanning of every push and
      the full history, plus linting of the config files, before anything
      reaches the public repo.
- [ ] Break-glass age key kept offline, plus separate age keys for Flux
      and CI, added as recipients with `sops updatekeys`.

### Before Talos

- [ ] Move Garage into the services stack, then remove container `140`
      and its Ansible role ([07. Services VM](docs/07-services.md)).
- [ ] Remove the protected final backup of the OpenBao container once the
      services VM has run for a while.
- [ ] Rotate what is due in the rotation table
      ([04. Secrets, Rotation](docs/04-secrets.md#rotation)).
- [ ] Update the overview and Proxmox diagrams for the services VM.
- [ ] Tailnet-only access for app admin UIs on the LoadBalancer pool
      (subnet router, `tailscale serve` or per-VM firewall), before any UI
      goes live.
- [ ] Lockout and upgrade runbook: etcd snapshot before every upgrade,
      copied off the host.
- [ ] Optional: daily OpenBao Raft snapshot to Garage, on top of the
      container backup. Portable into any OpenBao and restores the data
      without rolling back the container.
- [ ] Optional: Garage as an OCI image container (Proxmox 9.1+), fully in
      OpenTofu with no Ansible role, once OCI containers leave tech preview
      and the config file can be supplied without a bind mount.
- [ ] Copy the Garage buckets off the host, encrypted, most likely to
      Cloudflare R2 (10 GB free), or to a second machine once there is one.
- [ ] Restore test: the OpenBao container backup restored under a new ID
      with its network off, unsealed, then deleted.
- [ ] OpenBao configuration in OpenTofu (`hashicorp/vault` provider), in
      its own project `opentofu/openbao/` with its own encrypted state:
      policies (moved out of Ansible), auth methods (import `userpass`),
      `kv-v2`, later Kubernetes auth. OpenTofu logs in with my own
      short-lived `userpass` token. Init, unseal and my password stay
      manual.
- [ ] External Secrets Operator in the cluster, reading from OpenBao.
- [ ] Flux bootstrap: which git remote and which credential.
- [ ] PBS VM sizing: RAM, vCPU and a datastore disk.
- [ ] Rollout order: core platform first (Cilium, Flux, cert-manager,
      storage, metrics), then one app at a time while watching RAM.
- [ ] Brute-force protection (CrowdSec) for anything exposed to the
      internet through an ingress.

## Open questions

- Can Talos run **fully in-memory** (diskless boot)? Understand how that actually works before committing to it as a design constraint.

## References

General inspiration and reference repos. Links for a specific phase live
at the end of its page in [docs/](docs/).

- [Talos + Tailscale walkthrough (YouTube)](https://www.youtube.com/watch?v=3VpOYn_GfAY)
- [ironicbadger/infra](https://github.com/ironicbadger/infra): reference homelab infra repo
- [ironicbadger/k8s](https://github.com/ironicbadger/k8s): reference k8s config repo
