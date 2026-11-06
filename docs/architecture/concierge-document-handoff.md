# Concierge document handoff

The product requirement is: “You can see the work. Make an easy change yourself.
Or discuss it with the embedded concierge and let it handle the update. Move
between both as you go.” This applies to the embedded concierge and to Jarvis
working through that concierge, in every application.

The application saves the visible browser draft automatically before an assistant
reads it for editing. The assistant receives that document's identity, revision
and selection, reads it through its original-owner application tools, and saves
an edit to the same document. On return, the application reads the saved result
and refreshes its own editor. The person does not press Save or Reload.

Application document operations preserve editable structure: text stays text,
layers stay layers and filters stay adjustable. Image generation remains an
explicit image operation. A layer/filter edit must not silently replace the
document with a flattened image.

The shared browser entry is `shared/ui/js/document-handoff.js`:

- `registerDocumentSession({app, prepare, refresh})` binds an application's
  existing authorized save/read functions to its visible editor.
- `beginDocumentHandoff(context)` waits for the application save before the
  conversation sends its request, and returns fresh context plus a matching
  `refresh()` operation for hand-back.
- `refreshOpenDocument({app})` refreshes the visible application after an
  approval-required tool actually succeeds.

Only visible, same-origin document windows participate. A replaced workspace is
not refreshed by an earlier handoff. A failed save prevents the assistant read.
If the person edits while the assistant is working, a conflicting refresh must
preserve the browser draft and explain the conflict. API revision guards and
original-owner permissions remain the authority for every read and edit.

The kernel fences a bounded document descriptor as page data for both a direct
concierge and Jarvis. An inline specialist receives the descriptor only when its
application owns that open document. Docking to a concierge retains its own
document context without relabelling another application's document. All
concierge entry points must display the actual approval cards their tools return.

## Verification and rollout

Source verification currently covers the shared handoff, direct concierge,
Jarvis inline and docked context, and Create, Video, Publishing Studio, PDF
Workbench and Motion Studio save/read/edit/refresh sequences through actual editor controls and PostgreSQL with row security. Create
also covers editable gray adjustment and text layers, repeated manual changes,
undo, failed saves and concurrent drafts. Video verifies delayed saves after a
project switch; Publishing applies inspector fields and flushes full operation
batches. PDF waits for actual revision jobs, retains native form/annotation data,
and fences late jobs to their original document. Historical questions retain the
visible revision; applications do not silently restore it for editing. Motion
also retains inspector fields on multiple layers, saves complete effect text whose
hidden section changed, and prevents an older draft from silently rebasing onto a
newer saved revision. Its native gray effect is rendered and remains adjustable.

Relevant source tests are `document_handoff.test.cjs`, `swarmbot_chat.test.cjs`,
`jarvis_docking.test.cjs`, `concierge_app_context.rs`, `jarvis_app_tools.rs`, and
Create's `tests/browser/create-handoff-proof.mjs`, Video's
`tests/video-document-handoff.test.mjs`, and Publishing/PDF
`tests/browser/document-handoff.test.mjs`, also used by Motion Studio (Test Lab
`document-handoff`).

The whole-product requirement remains open until every application with editable
work implements and passes its adapter's real manual → concierge → manual →
concierge round trip, through direct concierge and Jarvis, and installed
acceptance proves those same operations. A declared bot or a generic shared
handoff test does not establish an application's edit coverage. Source and
installed acceptance must be reported separately.

The rejected “Continue in another app” panel remains disabled.
