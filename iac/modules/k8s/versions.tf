terraform {
  required_providers {
    kubernetes = {
      source = "hashicorp/kubernetes"
    }
    tailscale = {
      source = "tailscale/tailscale"
    }
    vault = {
      source = "hashicorp/vault"
    }
  }
}
