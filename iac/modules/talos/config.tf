locals {
  endpoint      = "https://${var.vip}:6443"
  controlplanes = { for k, v in var.nodes : k => v if v.role == "controlplane" }
  first_cp      = keys(local.controlplanes)[0]
  installer     = "factory.talos.dev/nocloud-installer/${talos_image_factory_schematic.this.id}:${var.talos_version}"

  common = [
    yamlencode({
      machine = {
        sysctls = {
          "net.ipv6.conf.all.accept_ra"     = "0"
          "net.ipv6.conf.all.autoconf"      = "0"
          "net.ipv6.conf.default.accept_ra" = "0"
          "net.ipv6.conf.default.autoconf"  = "0"
        }
      }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "UnattendedInstallConfig"
      installer  = { image = local.installer }
      provisioning = {
        diskSelector = { match = "disk.dev_path == \"/dev/sda\"" }
      }
    }),
    yamlencode({
      apiVersion  = "v1alpha1"
      kind        = "ResolverConfig"
      nameservers = [{ address = "1.1.1.1" }]
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeNodeConfig"
      nodeIP     = { validSubnets = ["192.168.1.0/24"] }
    }),
    yamlencode({
      apiVersion = "v1alpha1"
      kind       = "KubeFlannelCNIConfig"
      "$patch"   = "delete"
    }),
  ]

  tailscale = yamlencode({
    apiVersion = "v1alpha1"
    kind       = "ExtensionServiceConfig"
    name       = "tailscale"
    environment = [
      "TS_AUTHKEY=${var.tailscale_auth_key}",
      "TS_ACCEPT_DNS=false",
    ]
  })
}

resource "talos_machine_secrets" "this" {
  talos_version = var.talos_version
}

data "talos_machine_configuration" "node" {
  for_each = var.nodes

  cluster_name     = var.cluster_name
  cluster_endpoint = local.endpoint
  machine_type     = each.value.role
  machine_secrets  = talos_machine_secrets.this.machine_secrets
  talos_version    = var.talos_version
  docs             = false
  examples         = false

  config_patches = concat(
    local.common,
    [local.tailscale],
    each.value.role == "controlplane" ? [
      yamlencode({
        machine = {
          certSANs = [var.vip, each.value.ip, "${each.key}.${var.tailnet}"]
        }
        cluster = {
          etcd = { advertisedSubnets = ["192.168.1.0/24"] }
        }
      }),
      yamlencode({
        apiVersion    = "v1alpha1"
        kind          = "KubeAPIServerConfig"
        certExtraSANs = [var.vip, each.value.ip, "${each.key}.${var.tailnet}"]
      }),
      yamlencode({
        apiVersion = "v1alpha1"
        kind       = "KubeProxyConfig"
        enabled    = false
      }),
      yamlencode({
        apiVersion = "v1alpha1"
        kind       = "Layer2VIPConfig"
        name       = var.vip
        link       = "eth0"
      }),
    ] : []
  )
}

resource "talos_machine_configuration_apply" "node" {
  for_each = var.nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.node[each.key].machine_configuration
  node                        = each.value.ip
  endpoint                    = each.value.ip

  depends_on = [proxmox_virtual_environment_vm.node]
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.nodes[local.first_cp].ip
  endpoint             = var.nodes[local.first_cp].ip

  depends_on = [talos_machine_configuration_apply.node]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for k, v in local.controlplanes : v.ip]
  nodes                = [for k, v in var.nodes : v.ip]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.nodes[local.first_cp].ip
  endpoint             = var.nodes[local.first_cp].ip

  depends_on = [talos_machine_bootstrap.this]
}
