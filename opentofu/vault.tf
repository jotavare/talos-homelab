resource "vault_mount" "kv" {
  path    = "kv"
  type    = "kv"
  options = { version = "2" }
}

resource "vault_auth_backend" "userpass" {
  type = "userpass"
}

resource "vault_policy" "admin" {
  name   = "admin"
  policy = file("${local.files}/openbao/policies/admin.hcl")
}

resource "vault_generic_endpoint" "admin_user" {
  path                 = "auth/${vault_auth_backend.userpass.path}/users/jotavare"
  ignore_absent_fields = true
  disable_delete       = true

  data_json = jsonencode({
    token_policies = [vault_policy.admin.name]
    token_ttl      = 28800
    token_max_ttl  = 86400
  })
}
