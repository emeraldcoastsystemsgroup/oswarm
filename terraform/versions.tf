# oswarm on an existing Kubernetes cluster: provider requirements.
terraform {
  required_version = ">= 1.6.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }
}

# The cluster is named explicitly, never taken from whatever context is current.
provider "kubernetes" {
  config_path    = var.kubeconfig
  config_context = var.kube_context
}
