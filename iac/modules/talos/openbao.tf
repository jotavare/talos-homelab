resource "vault_kv_secret_v2" "cluster" {
  mount = "kv"
  name  = "talos/cluster"

  data_json = jsonencode({
    machine_secrets = yamlencode(talos_machine_secrets.this.machine_secrets)
    talosconfig     = data.talos_client_configuration.this.talos_config
    kubeconfig      = talos_cluster_kubeconfig.this.kubeconfig_raw
  })
}
