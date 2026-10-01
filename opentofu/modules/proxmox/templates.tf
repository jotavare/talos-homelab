resource "proxmox_download_file" "debian_13_cloud" {
  node_name          = "pve"
  datastore_id       = "local"
  content_type       = "import"
  url                = "https://cloud.debian.org/images/cloud/trixie/20260914-2601/debian-13-genericcloud-amd64-20260914-2601.qcow2"
  checksum           = "95e110dfcdbd0ed8a82a75ed9579802f9950cabf51a810dcc6388e81bc778188713878b9f28d583a0ea602fbf48b35996ae9ad37f584166d8fbd6489df248f53"
  checksum_algorithm = "sha512"
}
