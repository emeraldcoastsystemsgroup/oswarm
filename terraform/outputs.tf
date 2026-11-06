# What an operator needs after apply. The sensitive values print only with terraform output -raw.

output "namespace" {
  description = "The namespace the kernel runs in."
  value       = var.namespace
}

output "image" {
  description = "The kernel image the Deployment runs."
  value       = local.image
}

output "catalog_commit" {
  description = "The public catalog commit staged on the applications claim (null when staging is off)."
  value       = var.stage_catalog ? local.catalog_commit : null
}

output "administrator" {
  description = "The administrator's sign-in name."
  value       = var.admin_subject
}

output "administrator_password" {
  description = "The administrator's first password: terraform output -raw administrator_password."
  value       = local.admin_password
  sensitive   = true
}

output "vault_key" {
  description = "OSHAL_VAULT_KEY, which seals every connected credential. Keep a copy outside the cluster: terraform output -raw vault_key."
  value       = random_id.vault_key.hex
  sensitive   = true
}

output "open" {
  description = "A first look without an ingress."
  value       = "kubectl --context ${var.kube_context} -n ${var.namespace} port-forward service/oshal-kernel-service 38788:38788, then open http://127.0.0.1:38788/login"
}
