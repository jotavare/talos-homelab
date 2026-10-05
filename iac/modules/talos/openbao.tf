resource "vault_kv_secret_v2" "cluster" {
  mount = "kv"
  name  = "talos/cluster"

  data_json = jsonencode({
    machine_secrets = yamlencode(talos_machine_secrets.this.machine_secrets)
    talosconfig     = data.talos_client_configuration.this.talos_config
    kubeconfig      = replace(talos_cluster_kubeconfig.this.kubeconfig_raw, local.endpoint, "https://${local.api}:6443")
  })
}

resource "vault_kv_secret_v2" "machine_configs" {
  mount = "kv"
  name  = "talos/machine-configs"

  data_json = jsonencode({
    for k, v in data.talos_machine_configuration.node : k => v.machine_configuration
  })
}
