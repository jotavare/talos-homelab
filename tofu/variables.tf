variable "proxmox_host" {
  description = "Proxmox address on the tailnet, from PROXMOX_HOST in the local .env."
  type        = string
}

variable "state_passphrase" {
  description = "State encryption passphrase, from SOPS through run.sh."
  type        = string
  sensitive   = true
}
