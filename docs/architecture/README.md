# Architecture

Design documents for the native kernel and the applications it hosts.

| Document | What it answers |
| --- | --- |
| [jarvis-conversation-policy.md](./jarvis-conversation-policy.md) | When the assistant answers in the conversation, hands a request to an application's bot, or queues a ticket. |
| [connector-http-services.md](./connector-http-services.md) | How reviewed connector resources execute through native original-person Actions. |
| [package-egress.md](./package-egress.md) | How a sandboxed application reaches the network: declared hosts, kernel-held connector credentials, the fenced transport. |
| [concierge-document-handoff.md](./concierge-document-handoff.md) | How an application's visible document is saved, read and edited by the embedded concierge or Jarvis, and refreshed on return. |
