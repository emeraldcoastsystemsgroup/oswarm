# oswarm on an existing Kubernetes cluster.
#
# Every workload is read from the Kubernetes templates in ../install/kubernetes, the same files
# the manual procedure applies, and changed only where an installation differs: the namespace,
# the storage, the image pull, the secrets, and the optional database, administrator and catalog
# steps. The release values (image digest, catalog commit and checksum, PostgreSQL digest) are
# read from the installers, so this module never names a second copy of them.

locals {
  templates = "${path.module}/../install/kubernetes"
  sources = {
    for name in ["namespace", "configmap", "endpoints", "pvc", "deployment", "service", "code-server"] :
    name => [for doc in split("\n---\n", file("${local.templates}/${name}.yaml")) : yamldecode(doc) if trimspace(doc) != ""]
  }

  catalog_commit = coalesce(var.catalog_commit, regex("CATALOG_COMMIT_DEFAULT=\"([0-9a-f]{40})\"", file("${path.module}/../install/install.sh"))[0])
  catalog_sha256 = coalesce(var.catalog_sha256, jsondecode(file("${local.templates}/tools.lock.json")).catalogArchiveSha256)
  postgres_image = regex("image: (postgres:[0-9a-z.-]+@sha256:[a-f0-9]{64})", file("${path.module}/../install/docker/compose.yaml"))[0]

  kernel_source    = local.sources["deployment"][0]
  kernel_container = local.kernel_source.spec.template.spec.containers[0]
  image            = coalesce(var.image, local.kernel_container.image)
  revision         = var.image == null ? regex("REVISION=([a-f0-9]{40})", file("${path.module}/../install/docker/image-release.env"))[0] : null
  in_cluster_db    = nonsensitive(var.postgres_url == null)
  generate_admin   = nonsensitive(var.admin_password == null)
  pull_secrets     = length(var.image_pull_secrets) == 0 ? null : [for name in var.image_pull_secrets : { name = name }]
  labels           = { "app.kubernetes.io/part-of" = "oshal", "app.kubernetes.io/managed-by" = "terraform" }
  in_namespace     = { namespace = var.namespace }
}

# ----- namespace, configuration and secrets ---------------------------------------------------

resource "kubernetes_manifest" "namespace" {
  manifest = merge(local.sources["namespace"][0], {
    metadata = merge(local.sources["namespace"][0].metadata, { name = var.namespace })
  })
}

resource "kubernetes_manifest" "config" {
  for_each = {
    config = merge(local.sources["configmap"][0], {
      metadata = merge(local.sources["configmap"][0].metadata, local.in_namespace)
      data = { for key, value in merge(local.sources["configmap"][0].data, {
        OSHAL_DEPLOYMENT = var.deployment_profile
        OSHAL_PUBLIC_URL = var.public_url
      }) : key => value if value != null }
    })
    endpoints = { for key, value in merge(local.sources["endpoints"][0], {
      metadata = merge(local.sources["endpoints"][0].metadata, local.in_namespace)
      # An empty data map reads back as null, so it is sent only when there is an endpoint.
      data = length(merge(local.sources["endpoints"][0].data, var.endpoints)) == 0 ? null : merge(local.sources["endpoints"][0].data, var.endpoints)
    }) : key => value if value != null }
  }
  manifest   = each.value
  depends_on = [kubernetes_manifest.namespace]
}

resource "random_id" "admin_token" {
  byte_length = 32
}

# Seals every credential people connect. Losing it loses them: back it up (output vault_key).
resource "random_id" "vault_key" {
  byte_length = 32
}

resource "random_password" "postgres" {
  count   = local.in_cluster_db ? 1 : 0
  length  = 40
  special = false
}

resource "random_password" "administrator" {
  count   = local.generate_admin ? 1 : 0
  length  = 24
  special = false
}

locals {
  postgres_url   = local.in_cluster_db ? "postgresql://postgres:${random_password.postgres[0].result}@oshal-postgres:5432/oshal" : var.postgres_url
  admin_password = local.generate_admin ? random_password.administrator[0].result : var.admin_password
}

resource "kubernetes_secret_v1" "kernel" {
  metadata {
    name      = "oshal-kernel-secret"
    namespace = var.namespace
    labels    = local.labels
  }
  data = {
    OSHAL_ADMIN_TOKEN   = random_id.admin_token.hex
    OSHAL_VAULT_KEY     = random_id.vault_key.hex
    OSHAL_POSTGRES      = local.postgres_url
    OSHAL_ADMIN_SUBJECT = var.admin_subject
  }
  depends_on = [kubernetes_manifest.namespace]
}

# ----- storage -----------------------------------------------------------------------------------

locals {
  claim_sizes = {
    "oshal-kernel-state"        = var.storage_sizes.state
    "oshal-workspace"           = var.storage_sizes.workspace
    "oshal-kernel-applications" = var.storage_sizes.applications
  }
  claims = {
    for claim in local.sources["pvc"] : claim.metadata.name => merge(claim, {
      metadata = merge(claim.metadata, local.in_namespace)
      spec = { for key, value in merge(claim.spec, {
        storageClassName = var.storage_class
        accessModes      = claim.metadata.name == "oshal-kernel-state" ? [var.state_access_mode] : claim.spec.accessModes
        resources        = { requests = { storage = local.claim_sizes[claim.metadata.name] } }
      }) : key => value if value != null }
    })
  }
}

resource "kubernetes_manifest" "claim" {
  for_each   = local.claims
  manifest   = each.value
  depends_on = [kubernetes_manifest.namespace]
}

# ----- the optional in-cluster PostgreSQL ------------------------------------------------------

resource "kubernetes_secret_v1" "postgres" {
  count = local.in_cluster_db ? 1 : 0
  metadata {
    name      = "oshal-postgres"
    namespace = var.namespace
    labels    = local.labels
  }
  data       = { POSTGRES_PASSWORD = random_password.postgres[0].result }
  depends_on = [kubernetes_manifest.namespace]
}

resource "kubernetes_manifest" "postgres" {
  for_each = { for name, item in {
    claim = {
      apiVersion = "v1", kind = "PersistentVolumeClaim"
      metadata   = { name = "oshal-postgres-data", namespace = var.namespace, labels = local.labels }
      spec = { for key, value in {
        accessModes      = ["ReadWriteOnce"]
        storageClassName = var.storage_class
        resources        = { requests = { storage = var.storage_sizes.database } }
      } : key => value if value != null }
    }
    service = {
      apiVersion = "v1", kind = "Service"
      metadata   = { name = "oshal-postgres", namespace = var.namespace, labels = local.labels }
      spec       = { selector = { app = "oshal-postgres" }, ports = [{ port = 5432, targetPort = 5432 }] }
    }
  } : name => item if local.in_cluster_db }
  manifest   = each.value
  depends_on = [kubernetes_manifest.namespace]
}

resource "kubernetes_manifest" "postgres_deployment" {
  count = local.in_cluster_db ? 1 : 0
  manifest = {
    apiVersion = "apps/v1", kind = "Deployment"
    metadata   = { name = "oshal-postgres", namespace = var.namespace, labels = local.labels }
    spec = {
      replicas = 1
      strategy = { type = "Recreate" }
      selector = { matchLabels = { app = "oshal-postgres" } }
      template = {
        metadata = { labels = { app = "oshal-postgres" } }
        spec = {
          automountServiceAccountToken = false
          securityContext              = { runAsUser = 70, runAsGroup = 70, fsGroup = 70 }
          containers = [{
            name  = "postgres"
            image = local.postgres_image
            env = [
              { name = "POSTGRES_PASSWORD", valueFrom = { secretKeyRef = { name = "oshal-postgres", key = "POSTGRES_PASSWORD" } } },
              { name = "POSTGRES_DB", value = "oshal" },
              { name = "PGDATA", value = "/var/lib/postgresql/data/pgdata" },
            ]
            resources       = { requests = { cpu = "50m", memory = "128Mi" }, limits = { cpu = "1", memory = "1Gi" } }
            securityContext = { allowPrivilegeEscalation = false, capabilities = { drop = ["ALL"] }, seccompProfile = { type = "RuntimeDefault" } }
            readinessProbe  = { exec = { command = ["pg_isready", "-U", "postgres", "-d", "oshal"] }, periodSeconds = 3 }
            volumeMounts    = [{ name = "database", mountPath = "/var/lib/postgresql/data" }]
          }]
          volumes = [{ name = "database", persistentVolumeClaim = { claimName = "oshal-postgres-data" } }]
        }
      }
    }
  }
  wait {
    rollout = true
  }
  timeouts {
    create = "10m"
    update = "10m"
  }
  depends_on = [kubernetes_manifest.postgres, kubernetes_secret_v1.postgres]
}
