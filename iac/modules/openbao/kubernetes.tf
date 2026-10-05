resource "vault_jwt_auth_backend" "kubernetes" {
  path                   = "kubernetes"
  type                   = "jwt"
  bound_issuer           = var.k8s_issuer
  jwt_validation_pubkeys = [var.k8s_service_account_public_key]
}

resource "vault_policy" "external_secrets" {
  name   = "external-secrets"
  policy = file("${path.module}/policies/external-secrets.hcl")
}

resource "vault_jwt_auth_backend_role" "external_secrets" {
  backend         = vault_jwt_auth_backend.kubernetes.path
  role_name       = "external-secrets"
  role_type       = "jwt"
  user_claim      = "sub"
  bound_subject   = "system:serviceaccount:external-secrets:external-secrets"
  bound_audiences = ["openbao"]
  token_policies  = [vault_policy.external_secrets.name]
  token_ttl       = 600
}
