# Selected HTTP connector services

The native kernel can execute reviewed connector resources using the standard
Connections and confirmed Actions APIs. Requires ADR-187; configuration is optional.

An administrator selects actual installed services, for example:

```text
OSHAL_CONNECTOR_HTTP_SERVICES='{"jira":"https://YOUR.atlassian.net/rest/api/3","gitlab":"https://gitlab.com/api/v4"}'
```

Replace the Jira hostname with the intended account's realm. Values are HTTPS base
URLs, without secrets, query, fragment, interpolation or private-network bypass.
At most 32 selections / 32 KiB are admitted. The selected connector's YAML must
exist in OSHAL_CONNECTORS_DIR. Invalid sources stop startup before activation.

Each person then connects their account through the existing Connections flow.
Basic credentials are username:token; GitLab uses the personal access token under
the catalog's PRIVATE-TOKEN header. Existing OAuth completion uses its saved
access_token. Material stays in the kernel vault. Personal invocation scope is
linked during that explicit connection, after existing marketplace admission.
Existing accounts without the endpoint binding must reconnect. Changing a service
URL or auth shape also requires reconnection; token renewal preserves the old realm.

GET /connectors returns httpServices configuration and capabilityLinked for the
current person. Check usable own connection, not configuration alone. Standard
POST /connectors/ID/actions/OPERATION consumes a fresh X-Oshal-Confirm confirmation
from POST /confirmations and JSON arguments. Add an account query, for example `?account=work`, to bind the exact selected account; it never falls back to another one. Service metadata advertises namedAccountSelection. Select the actual supported Jira
transition ID from jira-transitions before jira-transition-issue. GitLab state
updates use gitlab-update-issue-state with projectId, issueIid and stateEvent
(provider-supported close/reopen). ServiceNow uses servicenow-update-incident-state
with sysId and the instance's reviewed state value. Do not guess state numbers.

Writes are not retried. A timeout can mean the remote change happened: read the
original record and reconcile before another attempt. A 204 is accepted with null
data. A returned remote state is not infrastructure recovery. A paginated response
has pageComplete=false; it is never presented as the entire provider inventory.

Applications own external-link direction, status mapping, conflicts and echo
suppression. The shared operation path does not implement those domain policies.
No credential, confirmation or public service configuration grants a model raw
network/cluster access. Provider health remains not-probed until an actual call.
