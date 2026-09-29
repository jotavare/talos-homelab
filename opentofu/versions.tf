terraform {
  required_version = ">= 1.12.0"

  required_providers {
    proxmox = {
      source  = "bpg/proxmox"
      version = "~> 0.114"
    }
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "~> 5.26"
    }
    vault = {
      source  = "hashicorp/vault"
      version = "~> 5.12"
    }
  }

  backend "s3" {
    bucket                      = "opentofu-state"
    key                         = "homelab/terraform.tfstate"
    profile                     = "garage"
    region                      = "garage"
    use_path_style              = true
    use_lockfile                = true
    skip_credentials_validation = true
    skip_region_validation      = true
    skip_requesting_account_id  = true
    skip_metadata_api_check     = true
    skip_s3_checksum            = true
  }

  encryption {
    key_provider "openbao" "transit" {
      key_name = "opentofu-state"
      token    = trimspace(file(pathexpand("~/.vault-token")))
    }
    method "aes_gcm" "openbao" {
      keys = key_provider.openbao.transit
    }
    state {
      method   = method.aes_gcm.openbao
      enforced = true
    }
    plan {
      method   = method.aes_gcm.openbao
      enforced = true
    }
  }
}
