variable "chart_version" {
  description = "Cilium Helm chart version."
  type        = string
}

variable "values" {
  description = "Helm values, shared with the Flux HelmRelease."
  type        = string
}
