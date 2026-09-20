# Homelab v-next (Talos)

Planning notes for the next homelab iteration, built on Talos Linux.

## Goal

Rebuild the homelab on [Talos](https://www.talos.dev/), an immutable,
API-managed Kubernetes OS, instead of a general-purpose Linux distro
running k8s on top.

## Core stack (candidates)

- **Kubernetes**: orchestration
- **Talos**: the node OS itself
- **Tailscale** / **Headscale**: mesh networking / overlay VPN
  (Headscale as the self-hosted control-plane alternative to Tailscale's)
- **WireGuard**: underlying tunnel protocol for the above
- **Ansible**: bootstrapping / config management for anything outside Talos's own API-driven model
- **Forgejo**: self-hosted git
- **OpenTofu**: infra as code (Terraform fork)
- **OpenBao**: secrets management (Vault fork)
- **Garage** / **SeaweedFS**: S3-compatible object storage
- **RustFS**: evaluate as a storage layer, compare against Garage/SeaweedFS

## Networking

- Tailscale Kubernetes Operator: exposes cluster services over the tailnet
  - [Kubernetes Operator overview](https://tailscale.com/kb/1236/kubernetes-operator)
  - [API server proxy](https://tailscale.com/kb/1437/kubernetes-operator-api-server-proxy)
- Consider Headscale if going fully self-hosted instead of Tailscale's managed control plane

## Secrets

- Evaluate **SOPS** for encrypting secrets committed to git (GitOps-friendly secret management)
- Compare against OpenBao for anything needing dynamic secrets / a running service
- Working example: [sops-example/](sops-example/)

## Open questions

- Can Talos run **fully in-memory** (diskless boot)? Understand how that actually works before committing to it as a design constraint.

## References

- [Talos + Tailscale walkthrough (YouTube)](https://www.youtube.com/watch?v=3VpOYn_GfAY)
- [ironicbadger/infra](https://github.com/ironicbadger/infra): reference homelab infra repo
- [ironicbadger/k8s](https://github.com/ironicbadger/k8s): reference k8s config repo
