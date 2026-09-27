variable "proxmox_host" {
  description = "Proxmox address on the tailnet, from secrets/env.sops.yaml through run.sh."
  type        = string
}

variable "state_passphrase" {
  description = "State encryption passphrase, from SOPS through run.sh."
  type        = string
  sensitive   = true
}
