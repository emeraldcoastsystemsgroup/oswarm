# Configuration reference

The kernel is configured entirely through environment variables. Technical identifiers keep
the `OSHAL_` prefix (the kernel's internal name); the product is oswarm. On Docker Compose the
public values live in `.env` (as `OSWARM_*` settings the Compose file maps onto these variables)
and the secrets in `runtime.env`; on Kubernetes they are the config map and the secret.

Values marked *image default* are set in the image and only need changing for an unusual
layout. Nothing here is required beyond the first table.

## Required

| Variable | Meaning |
|---|---|
| `OSHAL_POSTGRES` | PostgreSQL connection string (`postgresql://user:password@host:5432/database`). `OSHAL_POSTGRES_URL` is read too. |
| `OSHAL_VAULT_KEY` | 64 hex characters (32 bytes). Seals every credential people connect. Losing it loses them; keep it with your backups. |
| `OSHAL_ADMIN_TOKEN` | The operator's static bearer token for the API. 64 hex characters. |
| `OSHAL_ADMIN_SUBJECT` | The administrator's sign-in name, the one `oshald init-password` sets the password for. |

## Listener and identity

| Variable | Meaning |
|---|---|
| `OSHAL_BIND` | Address the HTTP listener binds. *Image default* `0.0.0.0:38788` (inside the container). |
| `OSHAL_PUBLIC_URL` | The URL people open, used for links and provider callbacks. Set it to the https URL of your reverse proxy. |
| `OSHAL_DEPLOYMENT` | Deployment profile: `home`, `team` or `enterprise` (`demo` for throwaway installations). It changes defaults, not features. |
| `OSHAL_LANDING_PATH` | Same-origin path a signed-in person lands on instead of the default. |
| `OSHAL_DEFAULT_TIMEZONE` | IANA timezone for schedules and summaries when a person has not set one. |
| `OSHAL_OIDC_ISSUER` and the provider settings | Sign-in with an identity provider; see [operations/oidc.md](operations/oidc.md). |
| `OSHAL_MOCK_IDENTITY` | `false` in every real installation. |
| `OSHAL_ASSISTANT_ORB_FILE` | A PNG, WebP or JPEG of at most 512 KiB that replaces the assistant's orb image. |

## Storage (durable state)

All of these sit under `/var/lib/oshal`, the `kernel_state` volume on Compose and the state claim
on Kubernetes.

| Variable | Meaning |
|---|---|
| `OSHAL_PACKAGE_DIR` | Installed packages. |
| `OSHAL_PACKAGE_DATA_DIR` | Per-package lasting data. |
| `OSHAL_APPLICATION_FILES_DIR` | Files people upload into applications. |
| `OSHAL_COMPANION_ARTIFACT_DIR` | Artifacts the assistant produces. *Image default.* |
| `OSHAL_JOURNAL_PATH` | The mesh journal (one writer; the file is why there is one kernel replica). *Image default.* |
| `OSHAL_LEDGER_SPILL_PATH` | Cost ledger recovery journal when the database is unavailable. *Image default.* |
| `OSHAL_CAREER_DATA_DIR` | Data for the Career applications. |

## Application catalogs (read-only)

| Variable | Meaning |
|---|---|
| `OSHAL_APPLICATIONS_DIR` | The staged public catalog (`/opt/oshal/applications`). An absent directory is an empty catalog and is reported in the boot notes. |
| `OSHAL_APP_PRIVATE_DIR` | An optional second catalog of applications you do not publish. |
| `OSHAL_ADDITIONAL_APPLICATIONS_DIRS` | Further catalog directories, colon separated. |
| `OSHAL_PLATFORM_DIR` | The browser platform the image ships (`/app/platform`). *Image default.* |
| `OSHAL_CONNECTORS_DIR` | The connector catalog the image ships (`/app/connectors`). *Image default.* |

## Package runtimes

| Variable | Meaning |
|---|---|
| `OSHAL_PACKAGE_RUNTIME` | The Node executable applications run on. *Image default* `/usr/bin/node`. An absolute path is used as given; a bare name is searched on `PATH` and then in the system locations. |
| `OSHAL_BRIDGE_RUNNER` | The package bridge. *Image default* `/app/bridge/runner.js`. |
| `OSHAL_PACKAGE_NODE_MODULES` | The pinned Node dependencies shipped in the image. |
| `OSHAL_PACKAGE_PYTHON_PATH` | The pinned Python packages shipped in the image. |

## Inference

| Variable | Meaning |
|---|---|
| `OSHAL_FLEET_PROVIDER`, `OSHAL_FLEET_MODEL` | The default provider and model for the fleet. `noop` / `noop-1` answers nothing and costs nothing; people add real connections in Connections after signing in. |
| `OSHAL_OPENAI_API_KEY`, `OSHAL_ANTHROPIC_API_KEY` | Default keys for those providers, when you prefer an installation-wide key over per-person connections. |
| `OSHAL_INFERENCE_CONFIG` | A JSON declaration of the available APIs, models, prices and the failover chain. |
| `OSHAL_INFERENCE_TIMEOUT_MS` | Per-call ceiling for inference requests. |
| `OSHAL_INFERENCE_LOCAL_ENDPOINTS` | JSON list of local model endpoints the inference client may call, each with its URL prefix and the exact addresses it resolves to; anything undeclared is refused. See [security/sandbox.md](security/sandbox.md). |
| `OSHAL_INFERENCE_NETWORK` | The Docker network local model services share, when the kernel joins one. |
| `OSHAL_COST_ESTIMATE_PER_MTOK_IN`, `OSHAL_COST_ESTIMATE_PER_MTOK_OUT` | Reference rates (USD per million tokens) used to budget zero-priced calls. |

## Image generation

| Variable | Meaning |
|---|---|
| `OSHAL_IMAGE_PROVIDER` | Unset or `none` means no image generation; `comfyui` drives a ComfyUI server. |
| `OSHAL_IMAGE_COMFYUI_URL`, `OSHAL_IMAGE_COMFYUI_WAKE_URL` | The server and an optional wake endpoint; both must match an `OSHAL_IMAGE_LOCAL_ENDPOINTS` declaration. |
| `OSHAL_IMAGE_LOCAL_ENDPOINTS` | JSON list of permitted image endpoints, same shape as the inference list. |
| `OSHAL_IMAGE_COMFYUI_MODEL`, `OSHAL_IMAGE_COMFYUI_TEXT_ENCODER`, `OSHAL_IMAGE_COMFYUI_VAE` | Model file names. |

## Workspace and editor

| Variable | Meaning |
|---|---|
| `OSHAL_WORKSPACE_ROOT` (with `WORKSPACE_ROOT`, `WORKSPACE_DIR`, `SHARED_WORKSPACE_ROOT`) | The shared workspace directory on the workspace claim (Kubernetes). |
| `OSHAL_CODE_SERVER_URL` | The editor bridge URL when the optional code-server is deployed. |

## Compose settings (`.env`)

| Setting | Maps to |
|---|---|
| `OSWARM_IMAGE` | The kernel image. |
| `OSWARM_PROJECT` | The Compose project name. |
| `OSWARM_BIND_ADDRESS`, `OSWARM_PORT` | The host side of the port mapping. |
| `OSWARM_PUBLIC_URL` | `OSHAL_PUBLIC_URL` |
| `OSWARM_DEPLOYMENT` | `OSHAL_DEPLOYMENT` |
| `OSWARM_FLEET_PROVIDER`, `OSWARM_FLEET_MODEL` | `OSHAL_FLEET_PROVIDER`, `OSHAL_FLEET_MODEL` |
| `OSWARM_KERNEL_CPUS`, `OSWARM_KERNEL_MEMORY`, `OSWARM_POSTGRES_MEMORY` | Container ceilings. |
| `OSWARM_APPARMOR_PROFILE` | The AppArmor profile the kernel container runs under on Linux. |
