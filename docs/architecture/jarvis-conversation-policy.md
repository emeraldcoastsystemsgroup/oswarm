# Jarvis conversation policy: work happens in the conversation, tickets on request

**Audience:** engineers and agents changing the assistant turn (`crates/api/src/jarvis_*.rs`), an
application's concierge declaration, or the native shell's assistant affordances.

**Why this exists:** the assistant persona files every build, create or multi-step request as a
"complex" hand-off, and the kernel used to turn each one into a background `task` ticket. A person
who wanted to build something with the assistant could not interact with it: every answer was
"on it, I'll report back". This document records the kernel rule that replaced that behaviour and
where it is enforced, so the rule is not re-derived from the persona text.

## The rule

1. **A hand-off stays in the conversation unless background work was asked for.** A `create`
   directive is queued as a ticket only when the directive carries `"background": true`, the
   person's own words ask for it (`asks_for_background` in `jarvis_api.rs`: "in the background",
   "queue it", "file a ticket", ...), or the directive names an explicit queue (`kind`) or the
   platform lane (`platform`).
2. **An owned hand-off is answered now by the owning application's bot**, whatever its complexity.
   Ownership is scored from declared vocabularies (`jarvis_routing.rs`): the persona file's
   `routing_keywords`, the manifest bot entry's `routingKeywords` (ADR-083), bot `capabilities`
   and tool `routingTags`. Owners are the applications that run a workflow for the request and the
   applications that only converse through a declared bot (`chatBot`, else the first bot). The
   specialist sees the conversation so far (`history`), runs with its own tools under the caller's
   authority. The reply's `bot` stays the assistant (the outer conversation is still Jarvis's);
   the specialist is named in a `continueWith` block (`app`, `name`, `bot`, `botId`, `selector`,
   `deepLink`) so the client can keep talking to it on its own screen.
3. **A complex hand-off nobody owns is kept in the conversation.** The assistant is run once more
   with a kernel instruction that its proposal was not queued and that it must continue here; the
   continuation's prose replaces the acknowledgement and its tool calls join the reply. The reply
   lists what was kept under `keptInConversation`. A second proposal from the continuation is
   dropped, never queued.
4. **A simple hand-off nobody owns still takes the `request` lane.** It is a lookup the assistant
   cannot do itself; its result is delivered back into the same conversation on the next turn.
5. **Explicit background work is unchanged.** A workflow owner receives it as its own ticket type;
   a conversational owner never claims a ticket, so such work takes the generic lane unclaimed.

A model's call to a tool it was never given refuses the turn (a kernel contract several guards
pin). For the assistant alone, whose persona names tools the native kernel does not provide, the
turn is run once more with the kernel's tool rule ("not available in this conversation; answer
without it") before anything reaches the person.

The assistant is told the rule on every turn: `jarvis_turn.rs` fills `HANDOFF_RULE` into the
prompt's task slot through `TurnFacts.instructions` (kernel-authored text, never caller data),
only when the resolved target is the assistant itself.

## Where it is enforced

| Concern | Code |
| --- | --- |
| Directive shape and the person's explicit request | `crates/api/src/jarvis_api.rs` (`HandoffDirective.background`, `asks_for_background`) |
| Inline, kept or queued | `crates/api/src/jarvis_app_lane.rs` (`stays_in_conversation`, `Lane { answers, remaining, kept }`) |
| Owner scoring and conversational owners | `crates/api/src/jarvis_routing.rs`, `crates/packages/src/persona_routing.rs` |
| Continuation and the reply contract | `crates/api/src/jarvis_turn.rs` (`act`, `continue_in_conversation`, `respond`) |
| Queue routing of background work | `crates/api/src/jarvis_handoffs.rs` |
| Prompt task slot | `crates/oshald/src/turn_runner.rs` (`prompt`) |

## The concierge on application screens

`GET /api/ui/profile?name=<app>` returns the application's declared bots (`bots`, each with a
`selector`), its concierge (`chatAgent`: the manifest `chatBot`, else the first bot), a local
`assistant` route when declared, and the `ribbon` flags `hideChatPanel`, `hideAssistant`,
`hideStatusBar` and `defaultView`, both at the top level and inside `profile` for the retained
cockpit (`crates/api/src/ui_applications.rs`). The native shell renders them as the concierge
panel beside the application screen (`shell_applications.js`: `renderConcierge`, `askConcierge`),
which talks to `POST /api/swarm/bots/{selector}/ask` with one session per application and bot.

## Tests

- `crates/oshald/tests/jarvis_routing.rs`: explicit background requests reach the owning workflow;
  an owned complex request is answered now (and refused, not queued, when the application is
  unmounted); an unowned complex request is continued in the same reply and queued only when the
  person asks; a conversational application owns its request and its bot answers.
- `crates/oshald/tests/jarvis_app_tools.rs`: a complex owned request runs inline with the
  conversation so far and names its specialist; an explicitly background request is queued to the
  owning workflow without running a tool.
- `crates/oshald/tests/application_ui_access.rs`: the profile offers declared concierge bots and
  only a local assistant route.
- Unit: `jarvis_api.rs` (`asks_for_background`, directive flag), `jarvis_app_lane.rs`
  (`stays_in_conversation`), `persona_routing.rs` (manifest routing keywords).
