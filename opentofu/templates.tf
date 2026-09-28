resource "proxmox_download_file" "debian_13_lxc" {
  node_name          = "pve"
  datastore_id       = "local"
  content_type       = "vztmpl"
  url                = "http://download.proxmox.com/images/system/debian-13-standard_13.6-1_amd64.tar.zst"
  checksum           = "4c0c27ca6ceab5ef0b84db57825a00f26157ef1854bafe97297813e1cbe8ecb8cc9c453cab6b3b0efe1ba193a50c47ece1e41d950e411b8730b835b71e9e754b"
  checksum_algorithm = "sha512"
}

resource "proxmox_download_file" "debian_13_cloud" {
  node_name          = "pve"
  datastore_id       = "local"
  content_type       = "import"
  url                = "https://cloud.debian.org/images/cloud/trixie/20260914-2601/debian-13-genericcloud-amd64-20260914-2601.qcow2"
  checksum           = "95e110dfcdbd0ed8a82a75ed9579802f9950cabf51a810dcc6388e81bc778188713878b9f28d583a0ea602fbf48b35996ae9ad37f584166d8fbd6489df248f53"
  checksum_algorithm = "sha512"
}
