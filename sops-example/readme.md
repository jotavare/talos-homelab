# SOPS example

A minimal working example of encrypting a secrets file with
[SOPS](https://github.com/getsops/sops) and an [age](https://github.com/FiloSottile/age)
key, the pattern this homelab plans to use for GitOps secrets.

## Files

- `.sops.yaml`: tells sops which age public key to encrypt with, and which
  files that rule applies to (matched by `path_regex`).
- `secrets.example.yaml`: the encrypted file. Safe to commit. Keys and
  structure stay readable, values are ciphertext.

The age keypair used to create this example is not committed anywhere in
this repo. Only the public key appears, in `.sops.yaml`.

## How this was made

```bash
# generate an age keypair (private key never committed)
age-keygen -o keys.txt

# .sops.yaml references the public key from keys.txt

# write a plaintext file, then encrypt in place
sops -e -i secrets.example.yaml
```

## Decrypting

Needs the matching age private key. sops looks for it in the default
location `~/.config/sops/age/keys.txt`, or wherever `SOPS_AGE_KEY_FILE`
points.

```bash
sops -d secrets.example.yaml
```

Note: sops checks the default path **in addition to** `SOPS_AGE_KEY_FILE`,
not instead of it. If a key sits in the default file it will be used even
when the env var points elsewhere.

## Editing in place

```bash
sops secrets.example.yaml
```

Opens the decrypted content in `$EDITOR`, re-encrypts on save. The file on
disk is always ciphertext, there is no plaintext copy to manage. Normal
`git add` / `git commit` / `git push` afterwards.

## Key organization

Common practice, for when this grows past a single example file.

#### Scope keys per environment, not per repo

One `.sops.yaml` per repo, with several rules routed by path. Each cluster
then only needs the private key for its own environment.

```yaml
creation_rules:
  - path_regex: clusters/prod/.*\.yaml$
    age: age1prod...,age1breakglass...
  - path_regex: clusters/staging/.*\.yaml$
    age: age1staging...,age1breakglass...
  - path_regex: .*\.yaml$
    age: age1homelab...,age1breakglass...
```

First matching rule wins, so order most specific first.

The same mechanism scopes by team instead of environment if needed
(`secrets/infra/` to platform keys, `secrets/apps/` to app keys).

#### Multiple recipients per rule

Comma-separated keys mean any one of them can decrypt. This is how a
cluster and a human both get access to the same file without sharing a
single key.

#### Keep a break-glass key

Generate one backup key, include it in every rule, store it offline (a
password manager, a hardware token, paper). It is the recovery path when a
primary key is lost or needs rotating. Without it, a lost key means the
secrets are unrecoverable.

#### One private key per identity

Each person, machine, and CI job gets its own key. Public keys go in
`.sops.yaml`, private keys never go in git:

- laptop: `~/.config/sops/age/keys.txt`, accumulating one block per key
- cluster: a Kubernetes Secret that Flux/ArgoCD mounts to decrypt at sync time
- CI: a masked variable
- break-glass: offline, on no machine

Adding or removing a recipient later means re-encrypting the affected
files:

```bash
sops updatekeys secrets.example.yaml
```

#### Isolation between keys is real

A file encrypted to one key genuinely cannot be decrypted by a different
one. What blurs it is the shared default `keys.txt`: once several keys sit
in it, that machine can open everything. That is expected for your own
laptop. For anyone else, hand over only the single key file they need.

## Real usage

For the actual homelab, the age private key would live outside git
entirely (a password manager, or mounted into the cluster as a Kubernetes
Secret for Flux/ArgoCD to use at sync time), never alongside the encrypted
files it decrypts.

## References

- [Using SOPS with Age and Git like a Pro](https://devops.datenkollektiv.de/using-sops-with-age-and-git-like-a-pro.html)
- [Configuring SOPS with multiple encryption keys in Flux](https://oneuptime.com/blog/post/2026-03-13-how-to-configure-sops-with-multiple-encryption-keys-in-flux/view)
- [A comprehensive guide to SOPS](https://blog.gitguardian.com/a-comprehensive-guide-to-sops/)
