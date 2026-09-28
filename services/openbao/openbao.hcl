ui            = true
disable_mlock = true
cluster_addr  = "https://127.0.0.1:8201"

storage "raft" {
  path    = "/openbao/data"
  node_id = "openbao"
}

listener "tcp" {
  address         = "0.0.0.0:8200"
  cluster_address = "127.0.0.1:8201"
  tls_disable     = true
}
