# The kernel Deployment and its Service. Two init containers run before the kernel on every
# start, and both are safe to repeat: the catalog step leaves a staged catalog alone, and the
# kernel never resets an existing administrator password. Being part of the pod (not Jobs),
# they leave nothing behind that holds the claims, so terraform destroy completes.

locals {
  # The template's container, with this installation's image, sandbox policy and resources.
  kernel_container_spec = { for key, value in merge(local.kernel_container, {
    image     = local.image
    resources = var.kernel_resources == null ? local.kernel_container.resources : var.kernel_resources
    securityContext = { for key, value in local.kernel_container.securityContext :
    key => value if var.apparmor || key != "appArmorProfile" }
  }) : key => value if value != null }

  # oshald init-password reads {"username","password"} on standard input. It refuses (exit 1,
  # "already initialized") once a password exists, which here means the step is done.
  admin_script = <<-SCRIPT
    if out="$(/usr/local/bin/oshald init-password < /run/initial-password/input.json 2>&1)"; then echo "$out"; exit 0; fi
    echo "$out"
    case "$out" in *"already initialized"*) echo "administrator password already set; left unchanged"; exit 0 ;; esac
    exit 1
  SCRIPT
  admin_container = merge({ for key, value in local.kernel_container_spec :
    key => value if !contains(["startupProbe", "livenessProbe", "readinessProbe", "ports", "args"], key) }, {
    name         = "initialize-administrator"
    command      = ["/bin/sh", "-c", local.admin_script]
    volumeMounts = concat(local.kernel_container_spec.volumeMounts, [{ name = "initial-password", mountPath = "/run/initial-password", readOnly = true }])
  })

  catalog_script = <<-SCRIPT
    set -eu
    cd /tmp
    if [ -n "$(ls -A /catalog/applications 2>/dev/null)" ]; then echo "catalog already staged; left unchanged"; exit 0; fi
    curl --fail --silent --show-error --location --retry 3 "https://codeload.github.com/emeraldcoastsystemsgroup/oshal-apps/tar.gz/$CATALOG_COMMIT" -o catalog.tar.gz
    echo "$CATALOG_SHA256  catalog.tar.gz" | sha256sum -c -
    if tar -tzvf catalog.tar.gz | grep -v '^[-d]' | grep -q .; then echo "the catalog archive holds a link or special file; refusing" >&2; exit 1; fi
    if tar -tzf catalog.tar.gz | grep -E '^/|(^|/)\.\.(/|$)' | grep -q .; then echo "the catalog archive holds an unsafe path; refusing" >&2; exit 1; fi
    rm -rf /catalog/.stage
    mkdir -p /catalog/.stage /catalog/applications
    tar -xzf catalog.tar.gz --strip-components=1 -C /catalog/.stage
    printf '{"version":1,"origin":"https://github.com/emeraldcoastsystemsgroup/oshal-apps","reference":"%s","commit":"%s","provenance":"reconstructed-from-origin","archiveSha256":"%s"}\n' "$CATALOG_COMMIT" "$CATALOG_COMMIT" "$CATALOG_SHA256" > /catalog/.stage/native-source-origin.json
    chmod -R a+rX /catalog/.stage
    cp -R /catalog/.stage/. /catalog/applications/
    rm -rf /catalog/.stage catalog.tar.gz
    echo "catalog staged at $CATALOG_COMMIT"
  SCRIPT
  catalog_container = {
    name            = "stage-catalog"
    image           = local.image
    command         = ["/bin/sh", "-c", local.catalog_script]
    env             = [{ name = "CATALOG_COMMIT", value = local.catalog_commit }, { name = "CATALOG_SHA256", value = local.catalog_sha256 }]
    resources       = { requests = { cpu = "50m", memory = "64Mi" }, limits = { cpu = "1", memory = "512Mi" } }
    securityContext = { allowPrivilegeEscalation = false, readOnlyRootFilesystem = true, capabilities = { drop = ["ALL"] }, seccompProfile = { type = "RuntimeDefault" } }
    # The kernel itself mounts this claim read-only; only this step writes to it.
    volumeMounts = [{ name = "application-bundle", mountPath = "/catalog" }, { name = "scratch", mountPath = "/tmp" }]
  }

  # The applications volume is writable at the pod level only while the catalog step needs it;
  # the kernel container's own mount of it stays read-only.
  kernel_volumes = concat([for volume in local.kernel_source.spec.template.spec.volumes : merge(volume, {
    for key, value in { persistentVolumeClaim = { claimName = try(volume.persistentVolumeClaim.claimName, "") } } :
    key => value if volume.name == "application-bundle" && var.stage_catalog
  })], [{ name = "initial-password", secret = { secretName = "oshal-initial-password", defaultMode = 288 } }])

  kernel_pod_spec = { for key, value in merge(local.kernel_source.spec.template.spec, {
    initContainers   = concat(var.stage_catalog ? [local.catalog_container] : [], [local.admin_container])
    containers       = [local.kernel_container_spec]
    volumes          = local.kernel_volumes
    imagePullSecrets = local.pull_secrets
  }) : key => value if value != null }

  kernel_annotations = { for key, value in {
    "oshal.io/application-bundle-sha256" = var.stage_catalog ? local.catalog_sha256 : "none"
    "oshal.io/catalog-commit"            = var.stage_catalog ? local.catalog_commit : null
    "oshal.io/source-revision"           = local.revision
  } : key => value if value != null }
}

# The first password, read only by the initialize-administrator step. Terraform state holds it too.
resource "kubernetes_secret_v1" "initial_password" {
  metadata {
    name      = "oshal-initial-password"
    namespace = var.namespace
    labels    = local.labels
  }
  data       = { "input.json" = jsonencode({ username = var.admin_subject, password = local.admin_password }) }
  depends_on = [kubernetes_manifest.namespace]
}

resource "kubernetes_manifest" "kernel" {
  manifest = merge(local.kernel_source, {
    metadata = merge(local.kernel_source.metadata, local.in_namespace)
    spec = merge(local.kernel_source.spec, {
      template = merge(local.kernel_source.spec.template, {
        metadata = merge(local.kernel_source.spec.template.metadata, { annotations = local.kernel_annotations })
        spec     = local.kernel_pod_spec
      })
    })
  })
  wait {
    rollout = true
  }
  timeouts {
    create = "15m"
    update = "15m"
  }
  depends_on = [kubernetes_manifest.config, kubernetes_manifest.claim, kubernetes_secret_v1.kernel, kubernetes_secret_v1.initial_password, kubernetes_manifest.postgres_deployment]
}

resource "kubernetes_manifest" "service" {
  manifest   = merge(local.sources["service"][0], { metadata = merge(local.sources["service"][0].metadata, local.in_namespace) })
  depends_on = [kubernetes_manifest.namespace]
}

resource "kubernetes_manifest" "editor" {
  for_each   = { for item in local.sources["code-server"] : "${item.kind}/${item.metadata.name}" => item if var.editor }
  manifest   = merge(each.value, { metadata = merge(each.value.metadata, local.in_namespace) })
  depends_on = [kubernetes_manifest.claim]
}
