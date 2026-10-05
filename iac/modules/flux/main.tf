resource "helm_release" "operator" {
  name             = "flux-operator"
  namespace        = "flux-system"
  create_namespace = true
  repository       = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart            = "flux-operator"
  version          = var.operator_version
  wait             = true
}

resource "helm_release" "instance" {
  name       = "flux"
  namespace  = "flux-system"
  repository = "oci://ghcr.io/controlplaneio-fluxcd/charts"
  chart      = "flux-instance"
  version    = var.operator_version
  values     = [var.instance_values]
  wait       = true

  depends_on = [helm_release.operator]
}
