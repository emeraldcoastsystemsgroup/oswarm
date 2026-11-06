# Application YAML is the dependency authority

Declare an application's prerequisites in its `oshal-app.yaml`. The kernel reads those declarations for installation, reactivation, runtime admission and composite-role resolution. Application names and dependency lists do not belong in controller-specific or screen-specific fallback tables.

```yaml
dependencies:
  required:
    apps: [documents]
    tools: [documents-render]
    bots:
      - app: documents
        name: document-assistant
    connectors: []
  optional:
    apps: [music]
    tools: []
    bots: []
    connectors: []
```

This is a schema example, not a declaration that those example providers are installed. `apps` identifies packages; each bot reference names its owning package and exact bot name. Required bot owners must also appear in `required.apps`. Optional bot owners must appear in either declared application list. Public tool names resolve to the provider's current declaration. Dependencies reference the provider; they do not copy its code, persona, model configuration or credentials. Kernel capabilities belong in `uses`.

Required applications include their transitive required applications and group members. Missing or inactive required applications block execution. A required bot must still exist in its declared active provider, and a required tool must still be publicly exported by an active provider. These checks run again before reactivation, lazy runtime loading and each package call. A provider reload can therefore block an already loaded consumer until the required export returns. Failed activation preserves the prior lifecycle state. Missing optional components do not block the required application.

Bulk reload (`POST /api/packages/reload`) discovers both configured application directories (`OSHAL_APPLICATIONS_DIR` and `OSHAL_APP_PRIVATE_DIR`) before applying the same prerequisite order used at boot. Sources in `OSHAL_APPLICATIONS_DIR` retain precedence over same-named sources in `OSHAL_APP_PRIVATE_DIR`, reported in `shadowedPackages`. Cyclic candidates are refused before publication; their previous serving versions remain intact, while independent candidates may still refresh. Partial failures are returned explicitly and recorded as structured reload diagnostics.

Installation prerequisites and user permission assignments are distinct parts of the same application contract. `authorization.roleTemplates` in the application YAML declares the exact roles to assign across the application and its components. The linked authorization catalog defines what each named role permits. One composite assignment expands all required components; it refuses if any required application lacks an explicit role mapping. It does not guess a role from the application's name. Optional components enter the assignment only when expressly selected. Individual roles remain available for advanced administration.

The native Application access UI reads that same plan. An administrator selects a user and composite role, sees required component roles read-only, and applies one assignment. Dependencies do not require separate manual checkboxes. Explicit denial, expiry, changed source/catalog contracts and removal of an assignment remain authorization boundaries; dependency availability alone does not grant access.

The parser also preserves the existing flat mapping and array forms for compatibility. These do not invent missing application owners, optional selections or authorization mappings. Declared connector constraints restrict eligible connector identifiers; they neither provision a credential nor establish that a particular user's connection is ready.

## Verification and delivery boundary

The dependency lifecycle regression (`crates/oshald/tests/dependency_lifecycle.rs`) uses temporary application YAML, genuine kernel admission, the real package lifecycle coordinator and HTTP router. An owned in-process handler counts dispatches so a refusal must also prove that application code did not run. The unchanged baseline fails all four cases: transitive inactive prerequisite on reactivation, removed required bot, withdrawn/private required tool, and an inactive tool provider named by the supported legacy flat form. The corrected loader passes those cases and recovery after the provider returns. Absent optional application/tool/bot declarations remain accepted throughout.

The bulk reload regression (`crates/oshald/tests/bulk_reload_dependencies.rs`) sends real administrative HTTP requests against owned temporary repositories. It proves cross-repository transitive ordering, denial of ordinary-user reload, consistent source precedence and preservation of healthy versions when a replacement batch introduces a cycle. All three original cases fail on unchanged source and pass with the combined discovery plan. This is lifecycle evidence, not execution of application business handlers.

This fixture does not execute a model or certify a full original application.

## Add-ons: `extends` shares the base application's data

Package SQL is namespaced per package (`pkg:<name>:<table>`), so a package that extends
another's business process, such as an add-on over another application, would
otherwise read and write tables of its own that hold none of the rows it was written for.
An add-on names the application whose data namespace it shares:

```yaml
dependencies: { apps: [example-app] }
extends: example-app
```

The named application must be a required dependency, must be installed, and must not itself
extend another: add-ons do not chain, and a chained package's routes are refused as
`package_rejected`. With `extends`, the add-on's SQL statements, declared schema and migrations
run in the base's namespace in the caller's own scope, so the add-on reads the base's rows and
the base sees the add-on's tables. Migration receipts are kept as `<package>:<id>` there, so two
applications' `001-*` files never collide. Uninstalling the add-on removes nothing from the
base's namespace. A package that merely depends on another keeps its own namespace.

Proof: `crates/packages/src/addon_namespace.rs` (declaration rules) and
`crates/oshald/tests/addon_shared_data.rs` (a base, an add-on, a mere dependant and a chained
add-on through the real router and SQL adapter).
