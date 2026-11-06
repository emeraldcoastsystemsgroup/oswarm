# oswarm on an existing Kubernetes cluster: every setting, with the release's values as defaults.

variable "kubeconfig" {
  description = "Path to the kubeconfig file that reaches the cluster."
  type        = string
  default     = "~/.kube/config"
}

variable "kube_context" {
  description = "The kubeconfig context to install into. Required, so an apply never lands on whichever cluster happens to be current."
  type        = string
}

variable "namespace" {
  description = "Namespace for the kernel, its claims and (when in-cluster) its database. Created by this module."
  type        = string
  default     = "oshal-kernel"
}

variable "image" {
  description = "Kernel image. Null uses the release image pinned by tag and digest in install/kubernetes/deployment.yaml."
  type        = string
  default     = null
}

variable "image_pull_secrets" {
  description = "Names of existing docker-registry Secrets in the namespace, for a private mirror of the image. The published image needs none."
  type        = list(string)
  default     = []
}

variable "storage_class" {
  description = "StorageClass for every claim. Null uses the cluster's default class."
  type        = string
  default     = null
}

variable "state_access_mode" {
  description = "Access mode of the kernel state claim. ReadWriteOncePod keeps one writer of the file journal; use ReadWriteOnce where the storage driver is not CSI."
  type        = string
  default     = "ReadWriteOncePod"

  validation {
    condition     = contains(["ReadWriteOncePod", "ReadWriteOnce"], var.state_access_mode)
    error_message = "state_access_mode must be ReadWriteOncePod or ReadWriteOnce."
  }
}

variable "storage_sizes" {
  description = "Sizes of the state, workspace, applications and (in-cluster) database claims."
  type = object({
    state        = optional(string, "20Gi")
    workspace    = optional(string, "5Gi")
    applications = optional(string, "20Gi")
    database     = optional(string, "10Gi")
  })
  default = {}
}

variable "deployment_profile" {
  description = "Kernel deployment profile: home, team or enterprise. It changes defaults, not features."
  type        = string
  default     = "enterprise"

  validation {
    condition     = contains(["home", "team", "enterprise"], var.deployment_profile)
    error_message = "deployment_profile must be home, team or enterprise."
  }
}

variable "public_url" {
  description = "The https URL people open, served by your own TLS-terminating ingress. Null leaves it unset."
  type        = string
  default     = null
}

variable "admin_subject" {
  description = "The administrator's sign-in name."
  type        = string
  default     = "admin"

  validation {
    condition     = can(regex("^[A-Za-z0-9._-]{1,64}$", var.admin_subject))
    error_message = "admin_subject must be 1-64 letters, digits, dot, underscore or dash."
  }
}

variable "admin_password" {
  description = "The administrator's first password, 12 to 1024 bytes. Null generates one (output administrator_password). Set once; the kernel never resets an existing password."
  type        = string
  default     = null
  sensitive   = true

  validation {
    condition     = var.admin_password == null || (length(var.admin_password) >= 12 && length(var.admin_password) <= 1024)
    error_message = "admin_password must be 12 to 1024 characters."
  }
}

variable "postgres_url" {
  description = "PostgreSQL 16 URL (postgresql://user:password@host:5432/database). Null runs a PostgreSQL in the namespace on its own claim."
  type        = string
  default     = null
  sensitive   = true
}

variable "apparmor" {
  description = "Whether the eligible nodes load the oshal-bwrap AppArmor profile. Set false only for nodes without AppArmor; namespaces, seccomp and capability limits stay."
  type        = bool
  default     = true
}

variable "stage_catalog" {
  description = "Stage the public application catalog on the applications claim before the kernel starts."
  type        = bool
  default     = true
}

variable "catalog_commit" {
  description = "Full commit of the public catalog to stage. Null uses the commit the installers pin."
  type        = string
  default     = null
}

variable "catalog_sha256" {
  description = "SHA-256 of that commit's tarball. Null uses the value the installers pin; set it with catalog_commit."
  type        = string
  default     = null
}

variable "endpoints" {
  description = "Independently deployed endpoints the kernel may use (OSHAL_VLLM_URL, OSHAL_OLLAMA_URL, OSHAL_TTS_URL and the other keys in install/kubernetes/endpoints.yaml)."
  type        = map(string)
  default     = {}
}

variable "kernel_resources" {
  description = "Kernel container requests and limits. Null keeps the template's (500m/1Gi requested, 12 CPUs/32Gi limit)."
  type = object({
    requests = map(string)
    limits   = map(string)
  })
  default = null
}

variable "editor" {
  description = "Add the code-server editor on the shared workspace claim, reachable only by port-forward."
  type        = bool
  default     = false
}
