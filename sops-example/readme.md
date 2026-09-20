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

Needs the matching age private key, referenced via `SOPS_AGE_KEY_FILE` or
placed at the default `age/keys.txt` location sops looks for.

```bash
SOPS_AGE_KEY_FILE=/path/to/keys.txt sops -d secrets.example.yaml
```

## Editing in place

```bash
SOPS_AGE_KEY_FILE=/path/to/keys.txt sops secrets.example.yaml
```

Opens the decrypted content in `$EDITOR`, re-encrypts on save.

## Real usage

For the actual homelab, the age private key would live outside git
entirely (a password manager, or mounted into the cluster as a Kubernetes
Secret for Flux/ArgoCD to use at sync time), never alongside the encrypted
files it decrypts.
