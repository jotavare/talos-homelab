locals {
  endpoint      = "https://${var.vip}:6443"
  controlplanes = { for k, v in var.nodes : k => v if v.role == "controlplane" }
  first_cp      = keys(local.controlplanes)[0]
  api           = "${local.first_cp}.${var.tailnet}"
  installer     = "factory.talos.dev/nocloud-installer/${talos_image_factory_schematic.this.id}:${var.talos_version}"

  patches = "${path.root}/../talos"
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
  docs             = true
  examples         = true

  config_patches = concat(
    [
      templatefile("${local.patches}/common.yaml", { installer = local.installer }),
      templatefile("${local.patches}/tailscale.yaml", { auth_key = var.tailscale_auth_key }),
    ],
    each.value.role == "controlplane" ? [
      templatefile("${local.patches}/controlplane.yaml", {
        vip      = var.vip
        ip       = each.value.ip
        hostname = each.key
        tailnet  = var.tailnet
      }),
      ] : [
      file("${local.patches}/worker.yaml"),
    ]
  )
}

resource "talos_machine_configuration_apply" "node" {
  for_each = var.nodes

  client_configuration        = talos_machine_secrets.this.client_configuration
  machine_configuration_input = data.talos_machine_configuration.node[each.key].machine_configuration
  node                        = each.value.ip
  endpoint                    = local.api

  depends_on = [proxmox_virtual_environment_vm.node]
}

resource "talos_machine_bootstrap" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.nodes[local.first_cp].ip
  endpoint             = local.api

  depends_on = [talos_machine_configuration_apply.node]
}

data "talos_client_configuration" "this" {
  cluster_name         = var.cluster_name
  client_configuration = talos_machine_secrets.this.client_configuration
  endpoints            = [for k, v in local.controlplanes : "${k}.${var.tailnet}"]
  nodes                = [for k, v in var.nodes : v.ip]
}

resource "talos_cluster_kubeconfig" "this" {
  client_configuration = talos_machine_secrets.this.client_configuration
  node                 = var.nodes[local.first_cp].ip
  endpoint             = local.api

  depends_on = [talos_machine_bootstrap.this]
}
