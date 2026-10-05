resource "helm_release" "cilium" {
  name       = "cilium"
  namespace  = "kube-system"
  repository = "https://helm.cilium.io"
  chart      = "cilium"
  version    = var.chart_version
  values     = [var.values]
  wait       = true
  timeout    = 600
}
