variable "talos_version" {
  description = "Talos release for the image and the machine configs."
  type        = string
}

variable "nodes" {
  description = "Talos nodes by hostname. The VM ID is 100 plus the last octet of the IP."
  type = map(object({
    role   = string
    ip     = string
    cores  = number
    memory = number
    disk   = number
    data   = optional(number, 0)
  }))
}

variable "cluster_name" {
  description = "Kubernetes cluster name."
  type        = string
}

variable "vip" {
  description = "Shared IP for the Kubernetes API on the control planes."
  type        = string
}

variable "tailnet" {
  description = "MagicDNS suffix of the tailnet, for the API certificates."
  type        = string
}

variable "tailscale_auth_key" {
  description = "Reusable tag:talos auth key, pre-signed for Tailnet Lock."
  type        = string
  sensitive   = true
}
