variable "talos_version" {
  description = "Talos release for the image and the machine configs."
  type        = string
}

variable "nodes" {
  description = "Talos nodes by hostname. The VM ID is 100 plus the last octet of the IP."
  type = map(object({
    role   = string
    ip     = string
    cores  = number
    memory = number
    disk   = number
  }))
}
