resource "vault_jwt_auth_backend" "oidc" {
  path                          = "oidc"
  type                          = "oidc"
  oidc_discovery_url            = "https://auth.home.${var.domain}"
  oidc_client_id                = var.oidc_client_id
  oidc_client_secret_wo         = var.oidc_client_secret
  oidc_client_secret_wo_version = 1
  default_role                  = "admin"
}

resource "vault_jwt_auth_backend_role" "admin" {
  backend         = vault_jwt_auth_backend.oidc.path
  role_name       = "admin"
  role_type       = "oidc"
  user_claim      = "preferred_username"
  bound_subject   = var.admin_subject
  bound_audiences = [var.oidc_client_id]
  oidc_scopes     = ["openid", "profile", "email"]
  token_policies  = [vault_policy.admin.name]
  token_ttl       = 28800
  token_max_ttl   = 86400

  allowed_redirect_uris = [
    "https://openbao.home.${var.domain}/ui/vault/auth/oidc/oidc/callback",
    "http://localhost:8250/oidc/callback",
  ]
}
