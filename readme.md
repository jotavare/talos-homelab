# Homelab v-next (Talos)

Planning notes for the next homelab iteration, built on Talos Linux.

## Goal

Rebuild the homelab on [Talos](https://www.talos.dev/), an immutable,
API-managed Kubernetes OS, instead of a general-purpose Linux distro
running k8s on top.

This is an experiment. It is not the first homelab here, but it
deliberately uses Talos and tools not used day to day at work, to learn
them properly. Everything is public, so the repo doubles as a record of
how it was built, including dead ends and decisions that were reverted.

## Hardware

A single mini PC running Proxmox VE, with the Talos nodes as VMs on top.
Specs, install steps and a build log: [proxmox/](proxmox/)

## Core stack (candidates)

- **Kubernetes**: orchestration
- **Talos**: the node OS itself
- **Proxmox VE**: hypervisor on the physical host, Talos nodes run as VMs
- **Tailscale** / **Headscale**: mesh networking / overlay VPN
  (Headscale as the self-hosted control-plane alternative to Tailscale's)
- **WireGuard**: underlying tunnel protocol for the above
- **Ansible**: bootstrapping / config management for anything outside Talos's own API-driven model
- **Forgejo**: self-hosted git
- **OpenTofu**: infra as code (Terraform fork)
- **SOPS** + **age**: encrypted secrets in git, the starting point (see Secrets)
- **OpenBao**: secrets management (Vault fork), deferred, not needed at the start
- **Garage** / **SeaweedFS**: S3-compatible object storage
- **RustFS**: evaluate as a storage layer, compare against Garage/SeaweedFS

## Networking

- Tailscale Kubernetes Operator: exposes cluster services over the tailnet
  - [Kubernetes Operator overview](https://tailscale.com/kb/1236/kubernetes-operator)
  - [API server proxy](https://tailscale.com/kb/1437/kubernetes-operator-api-server-proxy)
- Consider Headscale if going fully self-hosted instead of Tailscale's managed control plane

## Secrets

Working example: [sops-example/](sops-example/)

#### The question that decides the tool: who needs the secret?

**A Kubernetes app needs it.** Nextcloud, Immich, Forgejo and friends.
Off-the-shelf software that reads an env var or a mounted file, and just
needs a `Secret` object to exist in the cluster. **This is almost all of
this homelab.**

**A program on a laptop needs it during development.** Code being written
locally that needs an API key.

These are different problems with different tools. Nearly everything here
is the first case.

#### Tools for the first case

All three do the same job, get a Kubernetes Secret into the cluster, from
different sources.

**SOPS + age**: encrypt a Secret manifest, commit the ciphertext to git.
Flux/ArgoCD holds the age private key in-cluster and decrypts at apply
time. The secret lives in git, encrypted. Nothing extra to run.

**OpenBao + External Secrets Operator (ESO)**: run OpenBao as a service.
Secrets live in its storage, never in git. Git holds only a pointer
("fetch `database/password`, make a Secret called `nextcloud-db`") and ESO
does the fetching. **ESO writes a plain, static Kubernetes Secret, so
off-the-shelf apps work fine with this.** They never know OpenBao exists.

**Sealed Secrets**: ciphertext in git like SOPS, but encrypted to the
cluster itself. Noted so it is not a surprise when it comes up; SOPS is
more flexible.

#### OpenBao is not a layer under SOPS, it is an alternative to it

Easy to get confused here. OpenBao is not something SOPS uses. They are
two different answers to the same question. Seeing OpenBao listed as a
SecretSpec provider does not change that (see below).

#### SOPS vs OpenBao, honestly

|                              | SOPS + age          | OpenBao                    |
|------------------------------|---------------------|----------------------------|
| Extra service to run         | none                | yes, must stay up + backed up |
| Where secrets live           | in git, encrypted   | in OpenBao's storage       |
| Works with off-the-shelf apps| yes                 | yes, via ESO               |
| Rotating a secret            | edit, commit, push  | API call, no git change    |
| Dynamic / leased credentials | no                  | yes                        |
| Audit log of every access    | no, just git history| yes                        |
| Fine-grained access policies | no                  | yes                        |
| Bootstrap problem            | none                | real, see below            |

Reasons SOPS goes first:

- **Bootstrap.** OpenBao starts *sealed* and something must unseal it after
  every restart. That usually means unseal keys stored SOPS-encrypted in
  git anyway, or a cloud KMS (external dependency), or unsealing by hand
  after every reboot. In a homelab where nodes reboot, this is what bites.
- **Availability coupling.** If OpenBao is down or sealed, ESO cannot
  refresh secrets, and a cluster-wide restart brings nothing up until
  OpenBao is up first. SOPS has no such ordering dependency.
- **Backups.** OpenBao's storage holds the only copy. Lose it without a
  backup and the secrets are gone. With SOPS every git clone is a backup.

Reasons OpenBao is genuinely better, once those are handled: rotation
without a git commit, a real audit log, secrets never touching git even
encrypted, dynamic credentials, per-app policies.

#### Plan

Start with **SOPS + age** only. Add OpenBao later if rotation, audit
trails, or keeping secrets out of git becomes a concrete need.

The common pattern using both, which falls out of the bootstrap problem:

- **SOPS + age** for bootstrap-critical secrets, the ones needed before
  anything else exists: cluster join tokens, OpenBao's own unseal key,
  ESO's credentials for talking to OpenBao.
- **OpenBao + ESO** for application secrets once the cluster is running.

Something has to hold the key that unlocks OpenBao, and that something is
usually SOPS. So SOPS is needed either way.

#### SecretSpec: evaluated, not adopted

[SecretSpec](https://github.com/cachix/secretspec) (Cachix, the devenv
people) separates *what secrets an app needs* (a committed
`secretspec.toml`) from *where values come from* (30+ providers: 1Password,
Vault, OpenBao, keyring, SOPS, age, and so on). Its SOPS and age providers
arrived in 0.17.0, not 0.18 as a widely seen video title claims. Latest is
0.20.0.

It solves the second case above, feeding secrets to a program being
developed, and it does that well. It does not fit this homelab:

- **No cluster-side component.** No controller, no reconciliation loop. The
  core primitive is `secretspec run -- command`, a laptop and CI thing.
- **Its Kubernetes provider is the inverse of what is needed here.** It uses
  local kubectl credentials to *read* values already in the cluster,
  mangled into `secretspec--{project}--{profile}--{key}`.
- **Its SOPS provider looks up individual values**, where GitOps encrypts
  whole manifests. Its age provider is flat dotenv, not Kubernetes YAML.

Maturity as of 2026-09: repo about 14 months old, still 0.x, ~1.5k stars
but only ~4k recent crates.io downloads and ~1.6k npm monthly. Early
adopter territory, weekly releases with 0.x churn.

Worth revisiting only if applications get developed against this cluster
and a single manifest describing their needs becomes useful. Its age
provider reuses the same keys, so adopting it later would not mean a
second key hierarchy.

## Open questions

- Can Talos run **fully in-memory** (diskless boot)? Understand how that actually works before committing to it as a design constraint.

## Use of AI

AI (Claude) helps with documentation, diagrams and commit messages in this
repo. Decisions, hardware and the actual build are done by hand.

## References

- [Talos + Tailscale walkthrough (YouTube)](https://www.youtube.com/watch?v=3VpOYn_GfAY)
- [ironicbadger/infra](https://github.com/ironicbadger/infra): reference homelab infra repo
- [ironicbadger/k8s](https://github.com/ironicbadger/k8s): reference k8s config repo
