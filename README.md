# Homelab

I am rebuilding my homelab on [Talos](https://www.talos.dev/), an
immutable, API-managed Kubernetes OS, instead of a general-purpose Linux
distro running Kubernetes on top.

At work I already run Kubernetes on RKE2, GKE and AKS. This is not my
first homelab either, so the point here is not to learn Kubernetes from
scratch. The point is to learn the parts I do not touch at work: Talos
itself, and around it, open source tools or tools I have not used
professionally. New and open source tools are preferred, but it is not a
hard rule: when something I already know is still the best fit, it stays.

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
  <img src="diagrams/overview.png" alt="Homelab overview: ISP router, Wi-Fi access point and a Proxmox host running the Talos VMs and an OpenBao container, with admin access from a laptop or phone only over Tailscale">
  <br>
  <sub><b>Overview.</b> One flat LAN, Talos VMs bridged onto it, management over Tailscale only.</sub>
</p>

<p align="center">
  <img src="diagrams/proxmox.png" alt="Proxmox host plan: 32 GB of RAM split between the host, an OpenBao LXC container, one control plane and three workers on the vmbr0 bridge, and the NVMe split into VM and LXC disks, ISOs and swap">
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
| `192.168.1.30` to `.49` | Static | Services outside the cluster (OpenBao `.30`) and other lab machines |
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
| Object storage | MinIO, Google Cloud Storage, Azure Blob Storage | **Garage** / **SeaweedFS** / **RustFS** / **Ceph** |
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
| Secrets store | Vault or OpenBao as a cluster of three on dedicated machines, auto-unsealed by a cloud key service | One OpenBao container on the same host, unsealed by hand after a reboot. Survives a cluster rebuild, not the loss of the host |
| OpenTofu state | Remote backend with locking and versioning (S3, GCS, Azure Blob) | Encrypted state file in git, no locking. Fine for one person on one laptop; old states stay in git history ([details](docs/05-opentofu.md#state-encryption)) |
| Backups | Proxmox Backup Server on a separate machine, plus a copy off site | Proxmox Backup Server as a VM on the same host until there is a second machine. It protects against mistakes, not against losing the host |

## Work in progress

The build, step by step, in the order it was done. One page per phase,
with the tools, the options chosen and why.

| Phase | Covers |
|-------|--------|
| [01. Proxmox](docs/01-proxmox.md) | Install USB, install, post-install, planned VMs |
| [02. Tailscale](docs/02-tailscale.md) | Account, laptop, Proxmox host, hardening |
| [03. Ansible](docs/03-ansible.md) | Proxmox host configuration as a playbook |
| [04. Secrets](docs/04-secrets.md) | SOPS and age for bootstrap secrets, OpenBao outside the cluster |
| [05. OpenTofu](docs/05-opentofu.md) | Proxmox user and token, project, state encryption, OpenBao container |
| [06. Talos](docs/06-talos.md) | Design: image, VM settings, firewall, API access, Tailscale |

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

- [ ] Run the Ansible compliance checks on a schedule (a timer on the
      laptop or CI with a Tailscale runner), so drift shows up without a
      manual run.

### Tailscale

- [ ] Sync `tailscale/policy.hujson` to the tailnet from git (GitOps).
- [ ] Let's Encrypt certificate (`*.home.<domain>`) for the Proxmox web
      UI, instead of the self-signed one.

### Repository

- [ ] Security audit pipeline in CI: secret scanning of every push and
      the full history, plus linting of the config files, before anything
      reaches the public repo.

### Before Talos

- [ ] Tailnet-only access for app admin UIs on the LoadBalancer pool
      (subnet router, `tailscale serve` or per-VM firewall), before any UI
      goes live.
- [ ] Lockout and upgrade runbook: etcd snapshot before every upgrade,
      copied off the host.
- [ ] OpenBao container configured by Ansible: OpenBao, Tailscale with
      `tag:openbao`, init and unseal by hand, Raft snapshots copied off the
      host.
- [ ] External Secrets Operator in the cluster, reading from OpenBao.
- [ ] Tailscale tags `tag:openbao` and `tag:talos`, grants to `tcp:8200`.
- [ ] Cloudflare API token for DNS-01, limited to DNS edits on the lab
      domain.
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
