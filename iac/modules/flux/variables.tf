variable "operator_version" {
  description = "Flux Operator and flux-instance chart version."
  type        = string
}

variable "instance_values" {
  description = "Values of the flux-instance chart: Flux version, components and the Git sync."
  type        = string
}
