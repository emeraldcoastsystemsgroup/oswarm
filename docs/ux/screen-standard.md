# Kernel screen standard (as-built)

> Some commands and paths below refer to tooling in the kernel source, which is not part of this repository; they describe how the kernel behaves, not files you will find here.

The rules every kernel-served screen follows: the operator shell (`/admin`), the native screens
compiled into the kernel (`crates/api/src/*.html`: Users, Application access, App Loader, Jobs,
Connections, Files, Security Center, Eval Wall, AI Test Lab, Help, Run Trace, Search, Devices, Sign
in, Guest, Workspace chat) and the platform pages the kernel ships (`platform/src/pages/cockpit`,
`config-admin`, `swarm-admin`, `workflow-studio`). The experiences (Nexus, Orbit, Studio, Commons,
Home) have their own grammar and skins (`platform/src/experience`) and are out of scope here.

The kit that implements these rules is served by the kernel itself:

| Asset | Served at | What it gives a screen |
| --- | --- | --- |
| `crates/api/src/kernel_screen.css` | `/ui/kernel/screen.css` | Page anatomy, glass surfaces, stat tiles, cards, forms, buttons, tables, phone layout |
| `crates/api/src/kernel_table.js` | `/ui/kernel/table.js` | Sortable headers, value-aware sorting, numeric alignment, phone stacking labels |

## 1. One palette: the portal themes

- A screen paints only with the framework theme tokens (`--bg-primary`, `--bg-card`, `--border-color`,
  `--text-primary`, `--accent-primary`, `--status-*`, `--glass-*`, `--card-shadow`, ...). A hex colour
  may appear only as the fallback inside `var(--token, #hex)`.
- The predefined cockpit themes are the palette catalog: midnight, daylight, ocean, sakura, forest,
  gray, black, light-blue, aurora, graphite, amber, plus the opaque Workspace paper theme. A screen
  links `/shared/ui/css/surface-themes.css` and runs `/shared/ui/js/surface-theme.js`; the active
  theme is the person's saved cockpit theme, and **midnight when nothing is saved**. A screen never
  hardcodes its own dark or light palette.
- Native controls follow the theme's `color-scheme`; a screen does not override it.

## 2. Glass is the surface

- Every raised surface (card, tile, dialog, sticky header) is a glass panel: a translucent gradient
  from `--bg-card`, a 1px `--glass-border` line, `--card-shadow` with an inset top highlight, and
  `backdrop-filter: blur(var(--glass-blur)) saturate(140%)`.
- The page background carries the theme's `--accent-glow` as two soft radial washes behind the panels,
  fixed to the viewport, so the blur has depth to show. A flat solid background with blurred panels
  is the "fallen flat" look this standard replaces.
- Workspace is the one opaque theme on purpose (`--glass-blur: 0px`, white cards); the kit degrades
  to paper there without a screen doing anything.
- **Store applications and platform pages get the same finish automatically.** The theme bootstrap
  every themed page loads (`/shared/ui/js/surface-theme.js`) also loads the portal's glass layer
  (`/shared/ui/js/surface-glass.js` + `/shared/ui/css/surface-glass-auto.css`): any rounded container
  painted with the theme's card colour (`var(--bg-card)`) is marked `data-oshal-glass` and raised as a
  glass panel, and the accent glow is painted behind the page when nothing else paints there. The
  contract for an application is therefore unchanged: paint cards with `--bg-card`, borders with
  `--border-color`, and the portal makes them glass in every theme. A page that must keep its own
  finish puts `data-no-glass` on the bootstrap script or on `<html>`; one element opts out with
  `data-no-glass`.

## 3. Page anatomy

```
<body>
  <main class="ks-page">                     max-width 1200px, 24px gutter (16px on a phone)
    <header class="ks-head">                 breadcrumb · h1 · lede on the left, actions on the right
    <div class="ks-tiles">…</div>            stat tiles: label, value, hint (auto-fit, min 180px)
    <section class="ks-card">                one topic per card; .ks-card-head holds h2 + actions
      <div class="table-scroll">…</div>      a data table lives inside a scroll wrap
    </section>
```

- Headings: one `h1` per screen; `h2` per card; a kicker (`.ks-kicker`) above the `h1` names the area.
- Actions sit right-aligned in the head or card head, never scattered between paragraphs. One primary
  button per card.
- Explanatory prose is a one-line lede or a muted help line under a control. Longer explanations go to
  Help (`/api/help`), not onto the screen.

## 4. Data is a table, and every table sorts

- Anything with more than one row and more than one attribute is a `<table>` with a `<thead>`:
  never a bullet list, a run of paragraphs, a `<pre>` dump or "label: value" lines inside a box.
- The table sits in `.table-scroll` (or carries `data-sortable`), which makes every header a sort
  control: click to sort ascending, click again for descending, `aria-sort` reflects the state, and
  the arrow shows it. Numbers, sizes (`120.5 MB`), percentages, durations and dates sort as values,
  not as text, and columns whose cells are all numeric align right.
- The header stays visible while the body scrolls (sticky inside `.table-scroll`).
- At 600px and under a table marked `stack-on-phone` renders each row as labelled lines; the kit
  writes the `data-label` from the header, so a screen marks the table and does nothing else.
- No word is split across lines; only an identifier (`code`) may break anywhere.
- An empty table says what would be there ("No jobs returned for this view."), inside the table's
  place, in muted text; a refused read says what to do.

## 5. Forms line up

- `form.ks-form` is a grid of fields (`.ks-field`: `<label>` above its control), auto-fit columns of
  at least 220px, one gap size. Every control is the same height, full width of its field, with the
  theme's focus ring. A help line is `.ks-help` under the control.
- Buttons: `.ks-btn` (glass), `.ks-btn-primary` (accent fill, `--text-on-accent` ink),
  `.ks-btn-danger`. The primary action is the last control in the row.

## 6. States

- Loading, empty and refusal lines use `role="status"` and the muted style; an error line uses
  `.ks-error` (status-error ink). A refusal names the fix ("Sign in, then open …").
- Nothing on a screen is a button that performs no action.

## 7. Phone

- 412×915 shows no horizontal scroll; touch targets are at least 44px tall; inputs are 16px so the
  phone does not zoom; the actions row wraps.

## 8. Proof before shipping

- Screenshot every changed screen at 1280×800 and 412×915 and look at it. The live sweep
  `ops/audit/kernel_screens_live_sweep.cjs` captures every kernel screen on a running kernel.
- The browser audit `ops/audit/kernel_screen_standard_browser.cjs` renders the shipped screen files
  over an owned fixture server and checks this standard (theme link and kit link present, no raw hex
  outside fallbacks, every data table sortable with value-aware order, numeric columns right-aligned,
  no horizontal scroll at 412px, no split words). `ops/ci_local.py` runs it as the
  `kernel-screen-standard-browser-audit` step.
- `crates/api/src/kernel_table.test.cjs` pins the sort semantics (`node --test`).
- All three are registered in the AI Test Lab on the server through the platform's Jarvis declaration
  (`platform/swarm-apps/jarvis-test-lab.yaml`), so `/api/test-lab/app` lists them with their runner,
  prerequisites and side effects.
- Sign in (`/login`) and the guest page are self-contained by design: they load no admitted asset before
  a session exists, so they keep their own small palette and are outside the kit.

## Applying the standard to a screen

1. `<html lang="en" data-theme="midnight">`; in `<head>`, in this order:
   `surface-themes.css`, `/ui/kernel/screen.css?v=<asset version>`, the screen's own `<style>`,
   `surface-theme.js`, `/ui/kernel/table.js?v=<asset version>` (defer).
2. Delete the screen's copies of body/typography/button/table/tile rules; keep only what is specific to
   the screen.
3. Wrap the content in `main.ks-page`, put the title block in `header.ks-head`, tiles in `.ks-tiles`,
   each topic in `section.ks-card`, every table in `.table-scroll`, and mark wide tables
   `stack-on-phone`.
4. Turn lists of records into tables; turn scattered inputs into a `form.ks-form` grid.
5. Add the screen to the browser audit's screen list and take the two screenshots.
