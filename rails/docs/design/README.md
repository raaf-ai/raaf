# Design sources

The dashboard is implemented from the **RAAF Console** design canvas
(claude.ai project `d865e78e-08ae-496d-b952-540164c70276`), not from the
ProspectsRadar design system. That distinction matters: the ProspectsRadar
project (`6e9f12f2-…`) contains only ProspectsRadar's own screens, and building
from it produces the wrong layout.

| File in the canvas | Status here |
|---|---|
| `PHLEX_COMPONENTS.md` | The component inventory this library follows. Namespace `RAAF::Rails::Ui`. |
| `Shell.dc.html` | Implemented — `Ui::Organisms::PageShell` + `Sidebar`. |
| `RAAF Console.dc.html` | Screens: Overview, Agents, Agent detail, Errors, Cost & usage. Copy kept here. |
| `RAAF Tracing.dc.html` | Screens: Traces, Spans, Search, Flows, Tools, Trace detail. Copy kept here. **All six implemented.** |
| `RAAF Continuous.dc.html` | Screens: Policies, Policy, **Policy edit**, Queue, Results, Health. Copy kept here. Policies, Policy, Queue and Health implemented. |
| `RAAF Eval.dc.html` | Screens: Datasets, Dataset, Experiments, Experiment, **Experiment edit**, Prompts, Prompt, Feedback. Copy kept here. Only the edit screen is implemented. |

Read them with the `DesignSync` tool (`method: "get_file"`, that project id).

## Screen inventory, from the canvas

**Console** — `Overview` (KPI row, Agent health grid, Failing now, Live runs),
`Agents` (table), `Agent detail` (header + Configuration / Evals tabs),
`Errors` (error groups), `Cost & usage` (breakdown by model and agent).

**Tracing** — `Traces`, `Spans`, `Search`, `Flows` (topology / pipeline /
single trace path), `Tools`, `Trace detail` (span waterfall + inspector).

## Design constants

Kind colours (`KindBadge` owns this mapping, nothing else):

| kind | background | ink |
|---|---|---|
| agent | `rgb(0 154 204 / 16%)` | `#6fd2f0` |
| llm | `rgb(139 92 246 / 16%)` | `#c4b1fb` |
| tool | `rgb(17 170 100 / 16%)` | `#7ee0ae` |
| handoff | `rgb(245 158 11 / 16%)` | `#f3c37b` |
| guardrail | `rgb(59 130 246 / 16%)` | `#a8c7fb` |
| pipeline | `rgb(255 255 255 / 10%)` | `#d1d5db` |

Health tones: ok `#11aa64` / text `#7ee0ae`; warn `#f59e0b` / `#f3c37b`;
bad `#ef4444` / `#ff8f8f`. The three bases are `var(--raaf-success)`,
`var(--raaf-warning)` and `var(--raaf-danger)` under the health dialect's
names, so `warn` and `warning` are the same amber by construction.

Components speak one tone vocabulary — `accent` / `success` / `warning` /
`danger`. The health dialect survives in the token names and in the components
that still tint by it (`Mono`, `Bar`, the meters, the waterfall); the KPI tile
does not know it, and a screen crossing from one to the other does so at its
own call site.

## Designed column sets

Taken from `RAAF Tracing.dc.html` and implemented in `TracesTable` /
`SpansList` / `SpansIndex`. The design uses fluid `minmax(0, Nfr)` tracks
throughout, which is why `Organisms::DataGrid` supports fractional weights.

**Traces** — Workflow 1.9 · Status 0.8 · Spans 1.1 · Duration 0.7 ·
Tokens 0.7 · Cost 0.75 · Started 0.7

**Spans** — Span 1.7 · Kind 1.1 · Trace 0.85 · Duration 0.55 · Tokens 0.75 ·
Status 0.75 · Start 0.7

Templates for the Tracing screens, and where each one now lives:

| Template | Implemented in |
|---|---|
| Tools grid `repeat(auto-fill, minmax(268px, 1fr))` | `organisms/tool_registry.css` → `.raaf-tools` |
| Search workbench `minmax(0, 220px) minmax(0, 1fr)` | `organisms/search_workbench.css` → `.raaf-wb-split` |
| Trace detail `minmax(0, 1.25fr) minmax(0, 1fr)` | `organisms/trace_detail.css` → `.raaf-trace-split` |
| Flows topology `minmax(0, 1fr) 40px minmax(0, 1.15fr) 40px minmax(0, 1fr)` | `organisms/topology.css` → `.raaf-topo` |

## Where the design and the data disagree

The canvas is drawn against a tidy five-agent workflow. Three places needed a
decision the design does not make, and each one is commented at the code:

- **Topology with 38 source agents.** The designed rank is a column of four.
  `TopologyGraph` draws the busiest `RANK_LIMIT` per rank and prints what it
  left out, rather than rendering a 3,000px column or silently truncating.
- **Pipeline steps.** The design shows a pipeline's *declared* steps; the trace
  store has no declared structure, so the Flows tab shows share-of-wall-clock
  instead and is titled "Pipeline heat" to say so.
- **Payload keys.** The design's payload is `system` / `tool arguments` /
  `tool result`. RAAF's processors actually write `agent.system_instructions`,
  `agent.initial_user_prompt` and `agent.final_agent_response`; both shapes are
  checked in `TraceDetail::PAYLOAD_SECTIONS`.

## What rendering the screens turned up

Every screen above had been verified structurally — a 200 and the expected
markup — but never looked at. Rendering them found two bugs that only show on a
screen, both fixed:

- **Every tool collapsed into its namespace.** `SpanRecord#display_name` fell
  back to `extract_readable_name`, which matched the first capitalised word, so
  `run.workflow.custom.Ecosystem::TedClient.search` became `Ecosystem`. The
  Tools registry groups by that name, so four tools showed as two cards and each
  card's p95 averaged unrelated tools. It now keeps the whole constant path.
  Pinned by `span_record_display_name_spec.rb`, which also pins the pipeline
  label staying short on purpose.
- **Half-translated timestamps.** `time_ago_in_words` is localised, so on this
  Dutch host app a hardcoded `" ago"` suffix produced "ongeveer 1 maand ago".
  `BaseComponent#time_ago` now builds the phrase in English, matching the rest
  of the dashboard's chrome. The `continuous/` components still do it the old
  way and will read the same way on a non-English host.

Two things that look like bugs on screen and are not:

- **Flows is empty on the default 24h window.** There are no `agent`/`tool`
  spans in the last day and no `handoff` spans at all, so the empty states are
  honest. Pass `start_time` to widen the window when checking the components.
- **A trace header disagreeing with its own waterfall.** On `trace_849e5397…`
  the header reads 16.7s and the waterfall 1415.7s. The trace row's `ended_at`
  is stamped before its spans finish; each number is faithful to its own source,
  and the waterfall is the true extent. That is a tracer lifecycle issue, not a
  rendering one.

Unrelated and still broken: `/raaf/tracing/costs` raises
`uninitialized constant RAAF::Tracing::CostManager::TraceRecord`
(`tracing/lib/raaf/cost_manager.rb:132`, and again at 454 and 480 — its
siblings all write `::RAAF::Tracing::TraceRecord`). Nothing links there; the
sidebar's Cost & usage points at `/raaf/dashboard/costs`, which works.

## The banner the design does not have

The Tracing screens opened on a gradient banner carrying an eyebrow, the page
title and a sentence of description. The canvas has none: `RAAF Tracing.dc.html`
contains no banner on any of its six screens — the only `linear-gradient` in the
file is a 3px connector in the topology — and every screen begins on its own
content, because the shell's topbar already carries `Tracing / <title>`.

So the banner spent roughly a tab's height repeating what was two lines above
it. Removed from all six. The four screens that hung actions off it —
Export JSON, Clear all, Refresh, All traces, and the Spans view toggle — keep
them in `.raaf-page-actions`, a right-aligned row. `HeroHeader` stays in the
library, and on the style guide, because it is still the right component for a
page that genuinely leads with one.

Trace detail lost the most: its banner held the workflow name and trace id.
The name is now the page title and "Trace" the crumb, which is where the design
puts them, and the id was already in the trace bar directly underneath.

## Making the range control real

The topbar's `1h / 24h / 7d / 30d` was decorative. `PageShell` renders it as
inert `<button>`s unless given a `range_href`, and nothing passed one — so on
Flows, whose default window is usually empty, the page offered no way to widen
it and read as unimplemented.

`RAAF::Rails::TimeRange` now owns the range: the four labels, the selected
value, the URL builder, and `parse_time_range`. Three controllers had their own
copy of that method (tracing, dashboard, continuous), which is exactly why the
control could be wired on one screen and dead on the next. The continuous
console keeps its own week-long default by overriding `default_range`.

Wired on Flows and on Overview / Performance / Cost & usage / Errors — the
screens whose whole content is drawn from the window. Traces, Spans and Tools
still render the pills inert: they filter by explicit start/end fields instead,
and a pill that changed the URL without changing the rows would be worse than
one that plainly does nothing.

Two details this turned up:

- The range travels in the URL, so a chosen window survives a link and a
  refresh, and `range_href` keeps every other parameter — switching the range
  on the Flows path tab does not drop the trace you were looking at.
- The Overview's Start/End fields were hardcoded to 24h, so picking 7d and
  pressing Apply filter silently narrowed the window back. They now open on the
  window actually in effect, and the form carries the range forward.

## Traces, against the canvas

The column set recorded above was wrong, and the comment above `COLUMNS` said
it came from the canvas. The design's header is eight columns, and the first is
the one that was missing:

`Trace 1.1 · Workflow 1.7 · Status 0.85 · Spans 0.55 · Duration 0.75 ·
Tokens 0.75 · Cost 0.7 · Started 0.8`

The trace id leads because it is what you copy into a log search, and because
the workflow name repeats down its column in runs — a table of forty
`LinkedinDma::PeriodicSyncJob` rows with no id tells you nothing about which
one you are looking at. It is printed in the accent, which `Atoms::Mono` gained
a `:accent` tone for rather than any call site hardcoding a colour.

The filter also diverged. The design is a single glass strip — the active
workflow as a chip, status pills, the count — and the screen had a five-field
form (search, workflow, status, start time, end time) above a row of four
headline counts. Both are gone, replaced by `Molecules::FilterBar`, which
already had that exact shape. The counts it dropped are the ones the Overview
carries; "Failed 60" as a number you cannot click says less than a Failed pill
that filters the table.

Two things fell out of that:

- The two date fields were the only way to narrow this screen by time, so the
  window now comes from the topbar range and applies always. **This changes the
  default**: Traces used to list everything and now opens on the last 24h,
  which is what the range control has been claiming all along.
- `FilterBar` hardcoded its query field to `name="q"` while this controller
  reads `params[:search]`, so the search box would have done nothing. The name
  is now a parameter, and the bar carries the chips' filters as hidden fields
  so submitting a search does not drop the status you had selected.

`time_ago` gained one special case: "less than a minute ago" was long enough to
wrap the Started column onto a second line, and it is also the vaguest of the
phrases. It now reads "just now".

## Trace detail, against the canvas

Already faithful — the trace bar, the `1.25fr / 1fr` split, the waterfall's
shared scale and per-row tokens, the Payload / Error / Tokens & cost / Raw
tabs, the veil and the backtrace are all as drawn. Two notes:

- The banner removal cost it the workflow name and trace id. The name is now
  the page title with "Trace" as the crumb, which is where the design puts
  them, and the id was already in the bar beneath.
- **The design's inspector shows a per-span cost; the data has none.** Only
  `TraceRecord` carries a cost, so the meta row shows duration, model, tokens
  and status instead. Printing the trace's cost against a single span would be
  wrong, and this is the fourth place where the canvas assumes a field RAAF's
  processors do not write.

## Spans, against the canvas

The same two problems as Traces, plus a missing column.

The recorded weights were wrong again. The design's seven columns are:

`Span 1.9 · Kind 0.8 · Trace 1.1 · Duration 0.7 · Tokens 0.7 · Status 0.75 ·
Start 0.7`

**Tokens was not implemented at all** — the screen had six columns. On a screen
whose whole subject is LLM and tool calls, the column saying what a call cost
in tokens is not an ornament. Status is also right-aligned in the design, and
the Trace column is the trace id in the accent; it had been showing the
workflow name, which repeats down the column and is usually the thing you
filtered by to get there.

The filter was the same five-field form Traces had. The design filters this
screen by kind, on a rail of pills that each carry a dot in the kind's colour
and their own count — the count is the reason to click one, so a chip without
it is a guess. Now `Molecules::FilterBar` with `Atoms::Chip`, which gained a
`dot:` for it.

Two things that keeps honest:

- The dot resolves through `KindBadge.resolve`, now public, so the alias table
  (`response`→llm, `chat`→llm, unknown→pipeline) is not repeated. The dot's six
  colour rules live in `kind_badge.css` beside the badge's, which is still the
  only file where a kind becomes a colour. `component` and `job` are not among
  the design's six kinds and correctly fall back to the neutral pipeline dot.
- The counts are taken with every filter applied **except** kind, so the chips
  read as facets: clicking "tool" must not make the other kinds report zero.
  That is what the `except:` parameter on `filter_spans` is for.

Left alone: the Hierarchy / List toggle, which the design does not have. It
predates this work, the tree is genuinely useful on a 137-span trace, and the
kind rail now carries through both views.

`Molecules::FilterForm` is now unreferenced — Traces and Spans were its only
two call sites. Left in place rather than deleted; it is still the right
component for a screen that needs an explicit date range.

## The Spans header, second pass

The kind rail was right but it was not what the screen opened on. Above it sat
a full glass panel — three icons explaining root, parent and child spans, a
sentence about the chevrons, and the Expand all / Collapse all buttons. The
design opens straight on the rail.

The card is gone. Its two real controls moved into the actions row and now
appear only in the hierarchy view, where they mean something. The explanation
went with it: the tree marks are legible without a key, and a legend taller
than the rows it describes is not paying for its space. `raaf-tree-legend`,
`-item` and `-note` were removed from `tree.css` with it; `raaf-tree-mark`
stays, because `TreeCell` still draws it on every row.

## A degenerate trace is not a broken screen

A trace detail opened on `trace_8e395a94…` looks nothing like the canvas, and
the screen is not at fault: that trace is one `AiEvaluationMetricsJob` span,
23ms, no payload. The waterfall draws its single bar and the inspector says
"No payload captured", both correctly.

Most recent traffic here is single-span background jobs, so picking a trace at
random — which is what a probe script does — usually lands on one. The screens
that show the design's shape need a trace with structure:
`trace_9a2c7171702fc5030cc6b5944c0d107c` (122 spans, a redacted payload) is the
one to check against. This is the same reason Flows reads as empty on its
default window, and it is worth knowing before concluding a screen is wrong.

## Search, against the canvas

Closer to the design than the other screens were. The query panel, the Try
chips, the `220px | 1fr` split, the checkbox facets with counts, and the hit
cards — kind chip, name, meta, and a snippet with an accent left border keyed
to the hit's status — were all already there and already right.

Two gaps:

- **The query's cost.** The design's bar reads `148 hits · 240ms`; this one
  showed only the hit count. Now timed around the search itself rather than the
  whole request, so the number describes the query and not the rendering.
- **A third facet.** The design draws three groups and this had two. Which
  third is not specified, so the choice is ours: workflow, the axis Traces
  already filters by, which makes a search narrow the same way a listing does.
  Spans carry a `trace_id` rather than a workflow, so it joins.

### What the timing immediately exposed

`execution expired` took **3.8 seconds** to return two hits. The search
predicate is `span_attributes::text ILIKE '%…%'` (plus `events::text`), an
unindexed sequential scan over casted JSON: roughly one second per pass over
17k spans, and the page made four passes — count, kind, status, workflow.

Folding the three facet queries into one grouped query took it to **2.1s** with
identical counts. That is the part this work was responsible for; the rest is
structural.

**Still outstanding, and not fixed here:** about two seconds of every search is
the leading-wildcard ILIKE, which no ordinary index can serve. The fix is a
`pg_trgm` GIN index on the searched expressions, or a generated tsvector column
— a migration and an extension, which is a database decision rather than a
screen one. Worth doing before this table grows: the cost is linear in span
count, and 17k spans is small.

The visible timing is the useful part of the finding. It was invisible before
precisely because the design's one small label was missing.

### The empty state in the facet column

With no query there are no facets, so `.raaf-wb-split` had a single child — and
a two-track `220px | 1fr` grid puts a single child in the first track. Both the
"Search the trace store" prompt and every no-results message rendered into a
220px column against the left edge.

`.raaf-wb-split--bare` now gives the results the whole width when there is
nothing to stand beside.

Worth noting how this survived: the split collapses to one column at 860px, and
the only wide-viewport look at this screen had a query in it. Checking a screen
means checking its empty state too, at a width where the desktop grid applies.

## The actions bar, and reading Shell.dc.html at last

`Shell.dc.html` had never been read here — only the two screen files were kept
locally, and the shell was implemented from the screens' surroundings. Reading
it settles what the header is:

- crumb over title, on the left
- the `1h / 24h / 7d / 30d` pill group
- a live toggle, labelled **Live** / **Paused**
- the ⌘K search affordance and the avatar
- then `<main style="padding:24px; display:flex; flex-direction:column; gap:20px">`
  holding the screen's content **directly**

Nothing sits between that header and the screen. The strip these screens
carried — Hierarchy / List, Expand all, Export JSON, Clear all — was invented
here, and it is the second header this console grew that no design has.

It is gone from all four screens that had it. The controls were not dropped;
each moved onto the thing it acts on, which is where a reader looks for it:

| Screen | Where its actions live now |
|---|---|
| Spans | the span table's card header, with the view toggle and Expand/Collapse |
| Traces | the traces table's card header (`TracesTable` now owns them, not the page) |
| Tools | `Recent calls` panel header, via `Panel`'s own `action:` link |
| Trace detail | the end of the trace bar, in `.raaf-trace-bar-actions` |

`.raaf-page-actions` is now unused. It stays in `layout.css` — a screen with a
genuinely page-level action will want it — but no Tracing screen has one.

### Two more things Shell.dc.html says that this does not

Neither is a header, and neither is fixed here; both are worth knowing:

- The live toggle reads **Live** / **Paused**. This says "Auto-refresh on".
- The design's sidebar has no **Performance** item under Monitor, and its
  Tracing group ends with **Trace detail** where this has **Timeline**.

## The traces footer

The design closes the table section with
`Showing 12 of 12,480` on the left and `prev` / `next` on the right, inside the
section. Three things differed:

- **Wording.** It read `1–25 of 481`. Now `Showing 1–25 of 481`. The range is
  kept over the design's bare count, because on page 12 "showing 25" says
  nothing about where you are.
- **Thousands separators.** The design has them and this did not; `1215` reads
  wrong at a glance where `1,215` does not. Applied to the footer and to the
  filter strip's trace count.
- **A "Last updated: 2026-09-06 12:33:09" line** below the card, in no design.
  Removed, along with the method behind it — the shell's live toggle is what
  says whether the page is current. Its Stimulus target was already guarded by
  `hasLastUpdatedTarget`, so the controller is unaffected.

### Two the design would have me remove, left in and flagged

Both are cases where following the mock would cost something real, so they are
noted rather than done:

- **Numbered page links.** The design draws only `prev` / `next`. With 49 pages
  of traces, prev/next alone means 48 clicks to reach the end; a mock showing
  two pills is likely shorthand rather than a decision to make the last page
  unreachable.
- **The filter strip's search field.** The design's strip is workflow chip,
  status pills and count only. The search box arrived when the five-field form
  was removed, and dropping it now would leave no way to search traces at all.

## The Traces table has no title bar

Correcting the previous entry. Removing the page-actions bar moved those
buttons into a card header on the table — which the design also does not have.
Its traces section opens directly on the column-header row:

```
<section …>
  <div style="display:grid; grid-template-columns:…">Trace|Workflow|Status|…</div>
  rows…
```

No title, no controls. Refresh, Export JSON and Clear all traces are gone from
the page. Nothing at the route level changed: `/raaf/tracing/traces.json` still
serves the export, and `POST /raaf/tracing/traces/destroy_all` still clears.
Both Stimulus targets (`refreshButton`, `lastUpdated`) were already guarded by
`has…Target`, so the dashboard controller is unaffected.

The lesson from three rounds of this: relocating chrome the design does not
have is not the same as removing it. Each move made the page smaller without
making it match.

### What still exists here that the canvas does not

Not changed — listed so the next pass does not have to rediscover them:

- **Spans** carries the same card header this one just lost: a `Span hierarchy`
  title with the view toggle, Expand/Collapse, Export and Clear. The design's
  spans section opens on its column header too.
- **Tools** is, in the design, *only* the auto-fill card grid. The entire
  `Recent calls` panel beneath it is an addition — though `Spans?kind=tool`
  answers the same question.
- **Trace detail** has `All traces` / `Export JSON` on its trace bar; the
  design's bar is id, status and stats.
- **Numbered page links** and the **filter strips' search fields**, as noted
  above.

## Clearing the rest of what the canvas does not have

Done in one pass, after the Traces title bar:

| Removed | Was |
|---|---|
| Spans' card header | `Span hierarchy` title with Export, Clear, Expand all, Collapse all |
| Tools' `Recent calls` panel | a whole span table under the card grid; the design's Tools screen is the grid alone |
| Trace detail's bar actions | `All traces` / `Export JSON` on the trace bar |
| Numbered page links | a windowed page list between prev and next |
| Both filter strips' search fields | added when the five-field forms went |

Nothing moved anywhere this time. Routes are untouched:
`/raaf/tracing/spans.json`, `/raaf/tracing/traces.json`, `<trace path>.json` and
both `destroy_all` posts all still work; the console just no longer offers
buttons for them. Individual tool calls are still listed — `Spans?kind=tool`
is the screen built for it. Text search is still on the Search screen, which
the topbar's ⌘K points at.

`Pagination` lost `WINDOW`, `pages` and `page_link` with the numbered list.
Expand all / Collapse all are gone but the per-row chevrons still work, so a
tree can still be opened and closed.

### The one thing kept, and why

**Spans' Hierarchy / List switch.** Not chrome — it is the only way into one of
the two views, and deleting it would delete the tree. It is now the same
underline tab pair Flows uses for its three views, which is the design's own
pattern for switching what a screen shows, rather than a control tucked into a
header the design does not have.

## The live control says Live again

`PageShell#live_toggle` had been rendering `Live` / `Paused` with an `is-live`
class all along — correct against `Shell.dc.html`, and correctly styled by
`app_shell.css`. The inline `auto-refresh` controller in `BaseLayout` then
overwrote both on connect:

```js
el.textContent = this.enabledValue ? "Auto-refresh on" : "Auto-refresh off"
el.classList.toggle("raaf-status-pip--live", this.enabledValue)
```

So the served markup was right for one frame. `raaf-status-pip--live` belonged
to a status pip this control stopped being, and was defined nowhere — the
green treatment on screen came from `is-live` surviving on the element, not
from that class. The controller now writes the label and class the shell
served, and the button toggles Live ⇄ Paused as the design's does.

Everything else in the header already matched: the crumb and title, the range
pills (mono, `5px 12px`, pill radius, `glass-white-12` when active), the ⌘K
search affordance and the avatar.

## The subheader is a glass strip on Traces

Between the shell's header and the table, the design sets the Traces filter row
on its own panel — `padding:12px 14px; border-radius:14px; surface-glass;
1px border` — while the Spans kind rail sits bare on the page background. Ours
was bare on both, so the Traces pills floated with nothing holding them.

`FilterBar` gained `panel:`, false by default, and Traces passes it. Both
screens now match their own design rather than sharing one treatment. The chip
group inside it already matched: `padding:3px`, pill radius, `glass-white-5`,
1px border.

**Still missing from that strip:** the design's first element is a workflow
filter chip — a funnel icon and `workflow:Discovery::Pipeline` — set to
`min-width:200px; flex:1` so it fills the row. Ours renders a workflow chip
only when a workflow filter is already applied, and since the five-field form
went there is no way to *set* one from the page; `?workflow=` still works.
Restoring it means choosing a control the design only shows in its filtered
state, so it is noted rather than guessed at.

### The workflow filter, built

The strip now opens with it, as the design does: a funnel, `workflow:` and the
scope the table is under, filling the row beside the status pills and the count.

The design only ever draws it filtered, so the control was ours to choose.
`Molecules::ScopeFilter` is the chip with a `<select>` wearing it — the whole
thing is a GET form that applies on change. Chips were the obvious alternative
and do not survive the data: this console has **54 distinct workflow names**.

Three things it gets right that are worth keeping if it is ever rebuilt:

- The options are every workflow the store knows, not the ones on the current
  page. A filter that only offers what is already on screen cannot find what
  is not.
- The scope lives in the URL, so a filtered table is a link.
- `carry:` re-emits status and range as hidden fields, so changing the workflow
  keeps the rest of the filter — verified: from
  `?workflow=UsageLimitCheckJob&range=30d`, picking another workflow lands on
  `?workflow=IndicatorDigestJob&range=30d`.

Applying on change needed one line of JavaScript rather than an inline
`onchange`, so the markup carries no script and nothing depends on the host's
CSP: `AutoSubmitController` in `BaseLayout`, registered as `auto-submit`.

## Spans is one flat list

The Hierarchy / List tabs are gone, and with them the tree. The design's spans
section is a flat table: rows carry no indent, no node mark, and the first
column is headed `Span`, not `Span hierarchy`. Keeping a switch the design does
not have — after removing it from the card header, then rebuilding it as tabs —
was the last of the "relocate rather than remove" moves.

Nothing is lost that the console cannot answer better elsewhere. Parent/child
belongs to **one** run, and a trace's waterfall draws exactly that on a shared
time scale; interleaving 18,000 spans from every trace into one tree was
answering a question nobody asks in that order. Clicking a row still opens the
span, and the span page still links its trace.

Removed with it: `hierarchy?` and its branches through the row renderer,
`depth_of`, `children?`, `row_classes`, `row_data`, `relation_label`,
`child_count_label`, `mark_for`, `icon_for`, the `view` parameter, and the
controller's call to `organize_spans_hierarchically`. The ~95-line inline
expander script in `BaseLayout` — `toggleChildren`, the collapsed-state
initialiser and their console logging, shipped on every page — went too;
verified afterwards that the module script still parses, the Stimulus
controllers still register, and the console is clean.

**Left in place deliberately:** `Molecules::TreeCell`, `tree.css` and
`organize_spans_hierarchically`. All three are now unreferenced, but
`app/components/RAAF/rails/ui/` is untracked, so deleting the molecule cannot
be undone from git. They are inventory, not wiring — say the word and they go.

## Badges, not one rail

The two chip groups are drawn differently and had been sharing one treatment.

- **Traces status filters** sit inside a single pill container —
  `gap:6px; padding:3px; border-radius:999px; glass-white-5; 1px border` — with
  the chips bare inside it. That is what `.raaf-chip-rail` already was.
- **Spans kind filters** are *separate badges*: `gap:8px` between them, each
  carrying its own `1px` border, background and `999px` radius. No container.

Ours put the kind filters inside the grouped rail, so eight kinds read as one
continuous bar instead of eight things you can click. `FilterBar` gained
`grouped:`, true by default, and Spans passes false for
`.raaf-chip-rail--loose`: no shared container, and each chip takes the border
and background the design gives it.

The dot and count inside each badge were already right.

The first attempt at this looked unchanged, and the reason is worth keeping:
`.raaf-chip-rail--loose` was written *above* `.raaf-chip-rail` in the file.
Both are single-class selectors, so specificity ties and the later rule wins —
the base kept re-applying its border, padding and background over the variant.
A modifier has to follow the thing it modifies. Verified from computed style
rather than by eye: the loose rail reports `border-width: 0px`,
`background: rgba(0,0,0,0)`, `padding: 0px`, `gap: 8px`, and the Traces rail
still reports `1px`, `rgba(255,255,255,0.05)`, `3px`.

## Continuous · Policies

`RAAF Continuous.dc.html` had never been read here either — the local notes did
not list it. It is now in `docs/design/` beside the other two.

The screen was still the original Tailwind markup: a white card on a grey page,
`text-gray-900`, Preline buttons, inside a console that is dark everywhere else.
Rebuilt on the library, from the design:

- **Headline stats** — `repeat(auto-fit, minmax(180px,1fr))`, each card a label
  with its icon opposite, a 24px mono value and a note. `Organisms::MetricGrid`
  already had that shape — it has since converged into `Organisms::StatGrid`.
  Counted over every policy, not the filtered page: the headline says what the
  system is doing, and a filter should not move it.
- **Filter rail** — All / Active / Paused with the count opposite, plain pills
  on the page. This is the third chip treatment in the canvas, so `FilterBar`'s
  two axes are now independent: `grouped:` for the shared container (Traces has
  one), `outlined:` for per-chip borders (Spans has them). Policies has neither.
- **Table** — `Policy 2.2 · Agent 1.4 · Scorers 1.5 · Sample 0.6 · Status 0.8 ·
  Last run 0.85`, the last three right-aligned.

Two molecules the design needed and the library did not have:

| Component | For |
|---|---|
| `Molecules::TitleMeta` | a name over a quieter line — the policy and what triggers it, in one column |
| `Molecules::TagList` | short mono labels in a cell; the scorers a policy runs, capped at three with a `+n` |

`StatusBadge` gained `active` and `paused`. A policy is not a run, but it reads
on the same pill, and that class owns the only status-to-colour mapping.

Two things worth noting about the data path:

- **Last run** comes from one grouped `maximum(:created_at)` over the page's
  policies, not a lookup per row.
- **No range is passed to the layout**, so the topbar pills stay inert here.
  The list is not filtered by time, and a pill that navigates without changing
  the rows is worse than one that plainly does nothing.

While wiring it: `Continuous::BaseController` had a `default_range` override
but no longer included `RAAF::Rails::TimeRange` — the earlier extraction left
it stranded. Nothing called `parse_time_range` there, so nothing was broken;
the include is back, and the 7-day default means something again.

## Continuous · one policy

Also still the original Tailwind: `p-6`, `lg:grid-cols-3`, `text-gray-900`, a
details block, an evaluators block, matching spans, recent results, a stats
sidebar and an actions sidebar. Rebuilt to the design's three parts:

1. **Header panel** — the name, its description on a `68ch` measure, the status
   pill and a mono meta line, with three figures opposite: today's count, the
   average score, and the share that came back good.
2. **`1.4fr / 1fr` split** — the scorers beside the configuration. Each scorer
   is its check, its average score and a bar; the configuration is
   label-and-value rows on a fixed 112px label column.
3. **Composite score · 30 days** — one bar per day, coloured by score.

Actions are gone, as on Traces: View queue, View results, Analytics, Edit,
Duplicate and Delete. Every route still works — this is the same trade already
made for Export and Clear, and the same offer stands.

### Two sections the data cannot fill

Both are the canvas assuming a field RAAF does not store — the fourth and fifth
instances of that in this console:

- **Weights and thresholds.** The design gives every scorer a weight and draws
  a threshold marker on its bar. Every evaluator's `config` is `{}`; neither
  number exists. The bar shows the score alone rather than inventing a line to
  measure it against.
- **Alert routing.** The design lists where a breach is sent. `EvaluationPolicy`
  has no alerting columns at all, so the section is omitted rather than drawn
  empty.

A day with no evaluations draws as a stub, not a zero-height bar: a policy that
did not run is not a policy that scored nothing, and at a glance the two would
read the same.

Two Phlex traps this screen hit, both worth knowing before writing another
component on `Tracing::BaseComponent`:

- **`format` is not `Kernel#format`.** Phlex resolves element methods by name,
  so `format("%.2f", x)` raises `wrong number of arguments (given 2, expected
  0)`. The operator form, `"%.2f" % x`, is the one that survives.
- **`tokens` is a `Ui::Base` helper**, not available here. The tracing base
  component builds its class lists plainly.

## Overview

The design is the KPI row and then a `1.72fr / 1fr` split — agent health beside
Failing now and Live runs. Two blocks on the screen were in neither:

- **The Start time / End time form** with Apply filter and Reset. Once the
  topbar's range began driving this screen, it was a second and much larger
  control for the same window, sitting between the KPIs and the content. Gone,
  along with `window:`/`params:` on the component and the fields' defaults —
  the ones that used to silently narrow a 7d view back to 24h.
- **The Top workflows table.** It ranked the same agents the health grid above
  it already shows, by the same numbers. Gone with `success_rate_badge`.

Added, because the design has it and the component already supported it:
**a sparkline on every agent card.** `AgentHealthGrid` renders
`Molecules::Sparkbars` whenever a tile carries `:series`; nothing had ever
passed one. It is one query for the whole grid, bucketed into 18 columns in
Ruby — `date_trunc` cannot divide an arbitrary window into a fixed number of
columns, and the window here is whatever the topbar says.

**Still missing:** the design puts a delta beside each KPI figure — `+12%`
against the previous period. Nothing computes a previous period, so the cards
show the figure and its note alone rather than a made-up trend.

## Span detail — a screen the canvas does not have

There is no span-detail design. The Tracing canvas stops at Trace detail, and
the Shell's own nav ends at "Trace detail" too. So this screen was built from
the design's vocabulary rather than invented:

- the **trace bar** idiom for identity — the span id, its status and its
  figures, exactly as a trace announces itself;
- **`Organisms::SpanInspector`**, which is already how the *designed* trace
  screen shows one span: Payload / Error / Tokens & cost / Raw, the tab a URL
  parameter so a link can land on the tab that explains the span;
- beside it, what a trace's inspector has no room for — every attribute, and
  the span's place in its trace (trace, workflow, parent, children, start).

Payload sections come from `TraceDetail::PAYLOAD_SECTIONS`, the same constant
the trace screen reads, so a span does not describe itself differently
depending on which page you opened it from.

### The per-kind deep dives are not converted

About **4,000 lines** across `agent_span_component` (1,376),
`pipeline_span_component` (620), `llm_span_component` (373),
`guardrail_span_component` (346), `tool_span_component` (269),
`search_span_component` (233) and `handoff_span_component` (204) are still the
original light-theme markup. They carry real content — agent configuration,
context variables, tool schemas — so they are kept, inside a card, for the
kinds that have one.

**The generic fallback is not.** For a `job` or `component` span it printed
"Unknown Span Type", then repeated the id, name, kind, status and workflow the
frame above already shows — in white-on-white, because the page around it is
dark now. Skipped via `DEDICATED_KINDS`: nothing is lost, because it said
nothing this page does not.

Converting the seven per-kind components is the remaining work here, and it is
one kind at a time rather than one change.

## Policy form — another screen the canvas did not have

> **Stale as of the September re-pull.** `RAAF Continuous.dc.html` now carries
> a full policy `isEdit` screen, and `RAAF Eval.dc.html` an experiment one. The
> paragraph below describes why this form was invented, which is still how it
> is built; it is no longer true that no design exists for it. Rebuilding it
> against the canvas is open work — see "Re-pulling the canvases" at the end.

No form appeared in any of the three canvases when this was written: no `new`,
no `edit`, no `<form>` anywhere. So, like the span page, this follows the
library the designed screens are built from rather than inventing a look —
cards per section, `Molecules::Field` for every label and hint, and the shared
input classes.

What did **not** change: every field name, every `id`, and every Stimulus
target and action. The check picker still posts
`evaluation_policy[check_configs][…]`, `evaluator-toggle` still reveals a
check's settings when it is ticked, and the `hidden` class it flips is the one
`layout.css` already defines. Verified in the browser rather than by reading:
ticking an unselected check reveals its config row, and every already-selected
row has its config visible.

Structure now: **Basics** (name, description, active) · **Checks** (the picker,
grouped per agent) · **Limits and retention** · **Advanced** · actions.

### The input atoms were built for a light theme

`.raaf-input` sets `color: var(--raaf-gray-900)` on a pale background — the
file says so plainly: *"the design's default is the light form surface;
`--glass` is the dark-surface variant the tracing dashboard uses"*. Nothing had
ever used them, so nobody had noticed. A first pass with the bare classes gave
dark text on a dark card and a white textarea, because `raaf-textarea` and
`raaf-select` are shape-only modifiers meant to sit on top of `raaf-input`.

Every field here now carries `raaf-input raaf-input--glass`, plus the shape
modifier where it applies. Worth knowing before the next form: the bare classes
are the light-theme ones, and on this console they are always wrong.

## The inspector's tabs

The span and trace pages both open on `SpanInspector`, and its Payload / Error
/ Tokens & cost / Raw switcher was a segmented control: a 24px pill group,
`12px 28px` padding, and a **green** fill on the active tab. That appears in no
canvas. The design draws these as a row of small pills —

```
gap:2px · padding:6px 11px · border-radius:8px · 12px/600
active: glass-white-12 on #fff · inactive: transparent on muted
```

— inside the bordered strip `.raaf-inspector-tabs` already provided.

Rather than add a third variant, the **base** `.raaf-tabs` became this. The
canvas has exactly two tab treatments and no more: this row, and the underline
Flows uses for its three views. The segmented look was a pre-library leftover
with no call site outside the inspector and one style-guide demo, so nothing
was preserved by keeping it.

Checked from computed style rather than by eye, on both pages that use it:
active tab reports `rgba(255,255,255,0.12)`, `8px`, `6px 11px`. And on Flows,
whose underline overrides are more specific and come later in the file, the
active tab still reports a transparent background, a teal bottom border and no
radius — the change did not leak into it.

## A span opens its trace

The design has no span screen, and it does more than omit one: on Spans, in
Search, and in the failing-now list, **every row calls `goScreen("trace")`**.
A span is always read inside the run it belongs to.

That is the better answer, not just the drawn one. A span alone can say it took
16.3s and returned ok; the waterfall around it says what ran before it, what it
was waiting on, and whether 16.3s was the whole trace or a tenth of it.

`BaseComponent#trace_span_path` now builds
`/raaf/tracing/traces/<trace>?span=<span>`, and every span row goes through it:
Spans (both list components), Search hits, error signatures, the slowest-spans
table, and the Flows path. The trace screen already selected a span from that
parameter, so nothing new was needed at the far end.

`SpanRecord.error_signatures` gained `trace_id` beside its `span_id` — without
it the errors table would have fallen back to the span page silently, which is
the kind of miss that looks like it works.

**The span page is still there**, and is where a span with no trace goes. It is
also the only home for the per-kind deep dives — agent configuration, tool
schemas, guardrail detail — which the trace inspector has no room for. Nothing
links to it from a listing any more, so if those deep dives matter, the trace
inspector needs a way through to it. That is a real loose end, not a finished
decision.

## What is still on the old UI

Measured, not remembered: each page fetched and its rendered markup counted for
light-theme classes (`text-gray-`, `bg-white`, `rounded-md`, `space-y-`,
`grid-cols-` …). Converted screens score 0 — the single hit they all show is a
string inside an inline Stimulus script, not markup.

**Converted:** Overview · Agents · Performance · Errors · Cost & usage ·
Traces · Spans · Search · Flows · Tools · Trace detail · Continuous Policies
(list, detail, form) · the span page's frame.

**Still the original markup**, worst first:

| Page | Legacy blocks rendered |
|---|---|
| Continuous → Results (`results_list`, `result_show`) | 120 |
| Span detail, for kinds with a deep dive | 100 |
| Continuous → Evaluators (`evaluator_list`, `evaluator_show`) | 91 |
| Continuous → Analytics (`analytics_dashboard`) | 42 |
| Continuous → Queue (`queue_list`, `queue_show`) | 41 |
| Replays (index, new, show, status + an ERB partial) | 13 |
| Timeline | 10 |
| Eval → Datasets, Experiments, Prompts, Feedback scores | 8 each, **empty** |

The Eval numbers understate the work badly: every one of those pages is showing
an empty state, so their tables and forms have never rendered. Twelve
components sit behind them (`dataset_*`, `experiment_*`, `prompt_*`,
`feedback_*`) totalling several hundred lines of unexercised light-theme markup.

The single biggest lump is the per-kind span components — about **4,000 lines**
across `agent_span_component` (1,376), `pipeline` (620), `llm` (373),
`guardrail` (346), `tool` (269), `search` (233), `handoff` (204),
`dialogue_display`, plus `span_detail_base` (857). They are why an agent span's
page still scores 100 where a job span's scores 0.

Also still there, and the reason any of this renders at all:
`BaseLayout` loads **Tailwind from a CDN** (line 69) and **Preline** (line
1209). Neither can go until the list above is empty — and the CSP note in the
host app exists specifically because of them.

## The experiment editor — the canvas's only form

`RAAF Eval.dc.html` was empty when this file first recorded it. It now carries
eight screens, and this is the first one built: `isEdit`, reached from the
"Edit experiment" button on the experiment screen.

It is also the first form in any of the four canvases. The policy form had to
invent its look from the library because no design existed; this one has one,
so the measurements come from the canvas and the atoms come from the library.
Nothing in `Atoms::Input`, `Select`, `Textarea`, `Toggle` or `Button` was
restyled to make it fit.

Structure: **Identity** · **Run configuration** · **Scorers** ·
**Schedule & alerts** in a column, beside a sticky `320px` rail carrying
Pending changes, Next run and the three actions.

### Where the values go, on a database that is already running

`raaf_experiments` has columns for name, description, dataset, agent, model and
provider. It has none for temperature, max turns, concurrency, timeout, the
scorers, or the schedule — that is most of what this screen edits.

They go into `configuration` and `metadata`, the two jsonb columns the table
already ships, so an installation that is already running gains the screen
without a migration. `Experiment::SETTINGS`, `#setting`, `#scorers`,
`#schedule` and `#tags` are the only readers of that shape, and
`ExperimentsController#experiment_update_params` the only writer. Keys the
screen does not edit survive the round trip untouched.

This is the opposite call from the one made twice on the continuous screens,
where a section the data could not fill was dropped. The difference is that
those were *readings* — a weight to draw a threshold marker against, a channel
a breach was already being sent to — and inventing them would have described
something that never happened. These are *declarations*: the record of what
this experiment is configured to be, which is exactly what an editor is for.

### What the engine does not act on yet

`ExperimentEngine` builds its agent from what the caller passes it and takes
scoring as a block. It reads `configuration` nowhere. So temperature, max
turns, concurrency, timeout, the scorer weights and the schedule are the
experiment's declared configuration and not instructions the engine already
follows.

The screen is written not to claim otherwise: "Next run" reports only the
dataset's item count, how many scorers are enabled, the trigger and when the
experiment last completed. The design's fourth row there is an estimated cost;
nothing prices a dataset before it runs, so it is not drawn.

Making the engine honour these is the next piece of work, and it is engine work
rather than screen work.

### Scorers come from the registry the policies already use

The picker lists checks from `EvaluatorDiscovery` — the same call
`Continuous::PoliciesController` makes, keyed the same way (`evaluator/check`).
An experiment and a policy therefore weight the same named scorers, and a newly
registered evaluator appears on both screens at once.

A scorer the experiment has never saved starts switched off with no weight.
Picking one up is a decision; a default weight would quietly make every
registered scorer count. The weights total in the card header is a judgement
and not a constraint — a set that does not total 1.0 still saves, and the total
just says so in the warn tone. Only enabled scorers are counted, so switching
one off cannot make a valid set look wrong.

### The diff rail

Every editable control carries `data-diff-label` and the value it was loaded
with, and the `experiment-edit` Stimulus controller compares each field against
its own `data-diff-initial`. No second copy of the record is kept in the page
for it to compare against, which is also why "Revert to saved" needs no server
round trip.

Four things that had to be got right, each found by driving the rendered page
rather than by reading it:

- **`form_with` must be given `scope: :experiment`.** The model is
  `RAAF::Eval::Models::Experiment`, so without it every field posts as
  `raaf_eval_models_experiment[…]` while the controller reads
  `params[:experiment]`, and every `<label for>` points at an id that does not
  exist. The existing `ExperimentForm` still has this bug on `create`.
- **A radio group's initial is the *saved* value, on every radio in it.** Each
  radio carrying its own label meant a checked radio always matched itself, and
  the group could never report a change.
- **Two Stimulus targets on one element is a space-separated list**, not two
  hash keys — merging them drops one. The cron field is both `cron` and
  `field`, and with the keys merged it silently stopped being `cron`, so
  changing the trigger no longer disabled it.
- **A `<select>` is tracked by its option's text**, because that is what the
  diff shows. Revert therefore restores it by matching that text, not by
  assigning it as the value — which would clear the selection instead.

One locale detail, the same class of bug as the half-translated timestamps
above: a `type="number"` input renders in the reader's locale, so `0.0` reads
as `0,0` on this Dutch host. An untouched scorer's weight is an Integer zero
for that reason.

### Converting the rest — progress

Working down the table above, worst first.

**Done: Continuous → Results** (120 → 0). Now the filter strip and a
`DataGrid` on `Agent 1.3 · Evaluator 1.5 · Field 1.1 · Status 0.7 · Score 0.6 ·
Span 0.8 · Created 0.8`. Two things the old page had and did not use: the
controller already computed `@agents` and `@summary` and passed neither, so the
agent picker is now a `ScopeFilter` like the one on Traces, and the count is
the real total rather than the page's size. The status filter also read
`params[:agent_name]` while the controller filters on `params[:agent]` — a
mismatch that had been quietly doing nothing.

**Done: Continuous → Evaluators** (91 → 0). A `DataGrid` with the same columns
it had. "no policy" stays a worded badge rather than a zero, which was already
the right call.

`StatusBadge` gained a **`warned`** state, amber. Results carry their own
verdicts — good / average / bad / error — and `average` had been borrowed onto
the running pill, so a finished evaluation rendered as "**Running**". It now
reads "Average" in amber, and the badge keeps its position as the only place a
status becomes a colour.

**Still to do:** Continuous Analytics (42) and Queue (41) · the per-kind span
components (~4,000 lines) · Replays (13) · Timeline (10) · the whole Eval
section (12 components, all currently behind empty states).

## The manual run that went missing

`PolicyShow` took `matching_spans:` and `recent_results:` and rendered neither.
The controller still computed both — `PolicySpanLookup.recent_for` on every
request — so the queries ran and the results were dropped on the floor.

`MatchingSpansPanel` is what that first one feeds: the newest spans a policy
would grade, each with a button that grades it now. Losing it mattered more
than losing the action row, because it is not navigation. A check whose trigger
mode is **Manual** runs from a button and nowhere else, and with the panel gone
the only remaining button was on the Evaluation tab of an *agent* span's detail
page — reachable only by someone who had already gone looking for a span the
policy happens to match. From the policy, where a threshold was just changed,
there was no way to try it.

The panel is back, below the trend so the designed order is untouched, and
converted to the library — it was still the original light-theme Tailwind, so
dropping it in unchanged would have been a white card on a dark page. Only the
markup moved: the two grouped queries, the five-minute staleness bound on
`section-refresh`, the worst-verdict-first summary, and the `data-turbo="false"`
form with its `return_to` all behave as they did.

It renders even when nothing matches. Its empty state explains that a span
counts only once it has recorded an agent response, and an absent panel reads
as an absent feature — which is exactly how this went missing in the first
place.

`POST /raaf/tracing/spans/:id/evaluate` was never touched: it queues
`EvaluationJob` with `force: true, manual: true`, which runs every check the
policy declares regardless of the sampling counter and exempt from the daily
cap.

`recent_results` is still computed and still unrendered. `RecentResultsPanel`
is the component for it and is also unconverted; the policy's results are
reachable at `/raaf/continuous/results`, so that one is a display gap rather
than a lost capability.

**Done: Continuous → Analytics** (42 → 0) and **Queue** (41 → 0).

Analytics lost its two chart panels. They were placeholders for a `d3-chart`
Stimulus controller that is registered nowhere, behind the words *"Chart will
be rendered with D3.js"* — a promise the console cannot keep, and worse dark
than light. What is left is the filter strip, four figures and the model table.

Converting it surfaced three things that were wrong underneath:

- **`good_rate` was always 0%.** It counted `status: 'passed'`, and evaluators
  write good / average / bad / error. There has never been a `passed`. It now
  reads 33.3% on this data, agreeing with the six Good of eighteen on Results.
- **The model table could never populate.** Its query lived only in the
  `model_comparison_data` JSON endpoint and was never put in `@overview_stats`,
  so the page always showed "No model data". One `model_comparison_rows` now
  feeds both, and the table has rows.
- **Total cost was never computed** at all. It sums `metrics->>'cost'` now.
  It still reads "—" here, correctly: every recorded cost is 0.

Queue rows carry Retry and Cancel, so the row is deliberately **not** a link —
a `button_to` form inside an anchor is invalid and its recovery is not worth
relying on. The identifying cell links instead. Two components came out of it:
`Atoms::Link` for a link inside a row that is not one, and
`Molecules::RowActions` for the controls at the end of it. `RowActions` is the
only component in the library that includes a Rails helper, because a
state-changing action has to POST and `button_to` is what carries the token.

**Remaining:** per-kind span components (~4,000 lines) · Continuous Queue
detail, Result detail, Evaluator detail · Replays (13) · Timeline (10) · the
Eval section (12 components, behind empty states).

## Re-pulling the canvases

Both canvases changed after the screens above were built, and one of the
changes contradicted a claim recorded here — which is the reason this section
exists.

`RAAF Eval.dc.html` was recorded as **empty**. It now carries eight screens.

`RAAF Continuous.dc.html` was read once and recorded as having no controls at
all. A grep over the local copy found three `onClick`s, all navigation, and
that is what the policy screen's "actions are gone" trade was justified against.
The current file has nine, and the policy screen carries an **Edit policy**
button: `bi-sliders2` tinted cyan, between the name block and the three
figures, pinned to the top of a header that wraps. `Atoms::Button` at `:sm` is
already that treatment — glass-white-8 on a hairline border, 600 weight — so
`PolicyShow` sets only the placement, and `.raaf-policy-head-edit` is two
properties and the icon tint.

**Check the remote copy before reasoning from the local one.** A local `.dc.html`
is a snapshot, and a claim of the form "the design does not have X" ages badly.

Still open from the re-pull, neither started:

- **The policy edit screen** (`isEdit`, lines 152–340). It has a `toggleStatus`
  control in its header and a `save` / `revert` / `cancel` rail, the same shape
  as the experiment editor. `Continuous::PolicyForm` predates it and is built
  from the library instead.
- **The other continuous screens.** Queue and Health are built (below). Results
  is drawn and unimplemented, and is the one item the sidebar still renders as a
  "soon" placeholder.

## One policy, one agent

The policy form offered all 100 checks across 17 agents. A policy matches spans
by a single `agent_name`, so all but one agent's checks are unusable — and
worse than unusable: picking across two agents used to set `agent_name` to
`"AgentA, AgentB"`, a name no span carries. The policy saved, looked
configured, and evaluated nothing, for ever, silently.

The Checks card now opens with the agent it watches, and shows that agent's
checks alone. Switching agent reveals the new group and clears the old one's
ticks, because a selection kept across a switch is exactly how the two-agent
state was reached. `reject_cross_agent_checks` refuses the save with a message
if anything still gets past the form.

### Two bugs found on the way, both worse than the first

**The edit form never pre-selected a policy's own checks.** The picker names a
check `field:specific_evaluator` — `confidence_scores:consistency`, because one
field can be graded several ways — while a policy stores only the field, with
the chosen evaluator recorded beside it in `check_specific_evaluators`. The two
were compared directly, so nothing ever matched: **every policy opened with
every box unticked, and saving it dropped every check it had.** All five
lookups (`check_selected?`, trials, sample_every_n, consistency mode, trigger
mode) carried the same flaw and now share one `stored_check` finder, which
matches on the field and honours the recorded evaluator.

**The agent could not be found by name either.** The registry groups checks by
class path (`Ai::Agents::Dmu::Classification`); a policy stores the RAAF agent
name (`StakeholderClassificationAgent`). Comparing them never matches, so the
form opened on whichever agent happened to be first. The chosen agent is now
derived from the checks the policy actually has ticked, which is the only link
between the two vocabularies that holds.

A first version of the Stimulus controller cleared non-matching groups on
`connect`, which — with the wrong agent selected — silently unticked the saved
check on page load. It now only reveals on connect and clears on an actual
change. Worth remembering: a redraw that mutates form state is a data loss
wearing a redraw's clothes.

## Queue — reading the job backend instead of RAAF's own table

The Queue screen was a "soon" placeholder in the sidebar even though
`QueueController` and `QueueList` both existed. They read
`EvaluationQueueItem`, which is the wrong table for this question.

`EvaluationQueueItem` records what RAAF *decided* to run and carries a status
RAAF writes. SolidQueue holds what a worker will *actually* pick up. The two
part company the moment a worker dies mid-run — which is why
`StaleJobCleanupJob` exists at all, and why the matching-spans panel bounds its
wait at five minutes rather than trusting a "running" row. A queue screen is
for the second question, so the screen now reads SolidQueue.

`Continuous::JobQueue` owns every one of those reads and is the only place the
SolidQueue schema is known. Two things worth keeping in mind about it:

- **The scope is the queue name.** RAAF's jobs declare `raaf_evaluations`,
  `raaf_evaluations_low` and `raaf_maintenance`, so the prefix is the filter
  and a host application's own jobs never appear. `LIKE 'raaf_%'` would be a
  bug — `_` is a single-character wildcard in SQL — so the match escapes it.
- **SolidQueue is the host's choice, not a RAAF dependency.** Every method
  returns empty when it is not the adapter, and the screen says so plainly
  rather than raising.

### Three columns the design draws that RAAF cannot fill

The canvas queues *batches* of spans against eight workers. RAAF enqueues one
job per span per policy.

- **Spans per batch** is therefore always 1. The column carries the number that
  does vary: how many checks the job will run.
- **A progress bar on each in-flight job.** SolidQueue reports nothing between
  claimed and finished. A bar drawn from elapsed time would read as progress
  and be a guess, so the row carries elapsed alone.
- **Estimated cost per row.** Nothing prices an evaluation before it runs — the
  same call the experiment editor's "Next run" makes.

The design's "Oldest wait" card also pairs its figure with an SLO. No target is
stored, so the card reports the wait and what it is the age of.

### Median wait is not measurable; latency is

The design's rail asks for median and p95 *wait*. SolidQueue deletes the
claimed row when a job finishes, so the moment a finished job started running
is gone — the split between waiting and running cannot be reconstructed after
the fact, only watched live.

The rail reports enqueue-to-finish and calls it **latency**, which is the
honest half of the question. "Oldest wait" is exact, because that job is still
in the ready table.

### One section the design does not have

**Failed.** The canvas draws a healthy queue and has nowhere for failures. On
a real one they are the rows that matter most: this database has two, both
`ArgumentError: wrong number of arguments (given 3, expected 0; required
keywords: span_id, policy_id)` — an older positional `perform_later` signature.
Both current call sites pass keywords, so those are historical rather than a
live fault, and the screen is how you would find that out.

### A bug the screen turned up

`QueueController#retry` and `#retry_failed` both enqueued
`RAAF::Eval::Continuous::EvaluationJob`, which does not exist — the class is
`RAAF::Rails::Continuous::EvaluationJob`. Every requeue raised `NameError`.
Nothing linked to those actions while the screen was a placeholder, which is
why it went unnoticed.

The JSON branch of `index` still answers with `EvaluationQueueItem` rows. It is
what `show`, `retry` and `cancel` operate on, and changing its shape would
break any caller of the endpoint.


## Health — measuring the scorers rather than the agents

Every other continuous screen reads an evaluation as a verdict on an agent.
The design's Health screen turns it round and reads the same rows as a
measurement of the evaluator: its mean, whether that mean has moved, how long
it takes, what it costs, and how much of the traffic it ever sees. A judge
whose mean drifts six percent overnight has not discovered that the fleet got
worse — and every screen that reports its verdicts will say the fleet did.

`Continuous::ScorerHealth` owns every read; `Continuous::HealthDashboard` holds
no SQL. The screen is `GET /raaf/continuous/health` in HTML. The JSON at the
same path is untouched: it is an operational health check that something may
well be polling, and it answers from RAAF's own bookkeeping rather than from
the evaluations.

### Two windows, not a thirty-day baseline

The design compares against a fixed 30-day baseline. The range control belongs
to the reader, and a 30-day baseline behind a 7-day window compares a
population with itself, so drift here is the window against **the window of
equal length immediately before it** — and the card says so rather than leaving
the reader to assume otherwise.

Drift is the *relative* move of the mean: a judge that fell from 0.87 to 0.82
lost six percent of its verdict, not five points of something.

### Three states, and which one wins

`healthy` / `drifting` / `stale`, as the design draws them, with one rule the
design does not have to make: a scorer that moved and then went quiet is both.
Drift is asked first, because it is the finding somebody has to answer;
answering "stale" there would file it under "nothing has happened lately",
which is the opposite of what happened.

Stale is silence through more than **half** the window. A quarter was tried
first and called a nightly policy stale every morning, which teaches the reader
to ignore the word.

A scorer present in the baseline and absent from the window is listed rather
than dropped. A check that stopped running is exactly the failure this table
exists to catch, and a table that omits it says everything is fine.

### Judge agreement, against the humans there actually are

The design's first card is agreement with a 250-span human audit. RAAF runs no
audit — but `FeedbackScore` is where a human verdict on a span is recorded, so
the figure is real wherever anybody has scored one, and honestly absent where
nobody has.

Human values are normalised onto 0–1 through their `FeedbackScoreDefinition`
range before being compared. A 4 on a 1–5 scale is agreement; compared raw it
reads as a rout. A value outside the range it claims is dropped rather than
clamped, since it cannot be placed on that scale at all.

### The banner is an alert first, a judge swap second

The design's banner is a judge model rolling underneath a scorer. That event is
real and computable — every evaluation records the judge models it called, so
the two windows' model sets can simply be compared — and it is the banner's
fallback. An unresolved `EvaluationAlert` outranks it, because an alert is
something a person still has to answer.

### What the cards report instead of what the design assumes

- **Cost per 1k evals**, from `metrics["evaluation_cost"]` — what the
  evaluation cost to *produce*, not what the graded span cost. Those are two
  different bills and `metrics["cost"]` is the other one. A rule-based scorer
  spends nothing and records zero, so the note says which of the two a $0.00 is.
- **Scorer latency p95** names the scorer that owns the tail. The design's note
  generalises ("llm judges dominate the tail"); which one it actually is, is a
  fact the row already holds.
- **Eval error rate** counts `error` only. `bad` is the evaluator working and
  not liking what it saw, which is the system doing its job.

### Coverage counts the population a policy could grade

The denominator is agent spans carrying a final response that an evaluation did
not itself produce — the same population `PolicySpanLookup` offers. Any larger
denominator makes a policy sampling one span in ten read as some smaller
fraction of a number that was never on offer.

One span graded by four checks is one span covered, not four.

The design tints a low percentage amber. Low coverage is usually the sampling
rate working as configured, so the only tinted row here is one at **zero** — a
policy that has graded nothing. Agents no policy names and nothing has graded
sort last and are the first thing the cut drops: that is ungoverned traffic,
which the Agents screen is the place to read.

### Recent events are the alerts, because they are what RAAF records

The design's list mixes alerts with configuration changes — a policy paused, a
sampling rate raised. A policy carries its current state and an `updated_at`,
which cannot say what changed, so there is no honest way to draw those. Alerts
are the events RAAF actually writes.

### Two bugs the screen turned up

**`AlertCheckJob` could not detect a failure spike.** It counted
`%w[failed error]`, and `ContinuousEvaluationResult` validates status to
`good` / `average` / `bad` / `error` — "failed" is vocabulary the table stopped
using. Only an evaluator *breaking* could raise the alert; a spike of bad
verdicts, which is the thing the check exists for, was never counted. It now
counts `%w[bad error]`.

**`GET /raaf/continuous/health/dashboard` always raised.** It called
`render_phlex`, which exists nowhere in this engine. Nothing linked to it, so
nobody found out. It now renders inside `BaseLayout` like every other screen —
though the panel itself is still Tailwind-era and light-themed, so it reads as
what it is: an operational panel that predates the design system, kept because
it is the HTML face of the JSON health check rather than a second health
screen.

### Two components changed rather than forked

`Molecules::StatCard` gained `series:`, which draws a `Sparkbars` between the
figure and the note — the design's health card is the console's KPI tile with
bars under the number. `Atoms::StatusBadge` learned `healthy` / `drifting` /
`stale`, since it owns the only mapping from a domain value to a colour and a
scorer's condition is one.

## One KPI tile, in three steps

The console had two KPI tiles doing the same job in different halves of
itself. `StatCard` put the icon top right, allowed a delta beside the figure
and a sparkline under it, and spoke `ok / warn / bad / info`. `MetricCard` put
an icon box on the left, had neither a delta nor a sparkline, and spoke
`accent / success / warning / danger`. Twelve screens render one or the other,
so a reader learned one KPI row on the Overview and met a different one on
Policies with no change of subject to justify it.

Swapping them in one commit would touch all twelve, so it is an expand,
migrate and contract instead. This is the expand step.

`StatCard` now takes `layout: :corner` (the default, unchanged) or
`layout: :leading`, which puts the icon in a tinted box in front of the tile.
The delta, the note and the sparkline are available to both, because they
belong to the number rather than to where the icon sits. Nothing migrated
here: every screen renders exactly what it rendered before, and `MetricCard`
is untouched.

### The tone question, settled once

The surviving vocabulary is `accent / success / warning / danger` — the
semantic set `Icon`, `IconBox` and the badges already speak, so `tone:` means
the same word wherever it appears. `MetricCard`'s tones are that set already.
The health dialect maps onto it in `StatCard::TONE_ALIASES` and nowhere else:
`ok → success`, `warn → warning`, `bad → danger`, `info → accent`. A call site
still speaking the old dialect renders identically, so the migrate step is a
rename per tile rather than a judgment call per tile.

Two colours were the same amber only because the same hex had been typed
twice. `--raaf-tone-warn` is now `var(--raaf-warning)`, and `ok` and `bad` are
aliased the same way, so the two names cannot drift apart.

A tone from neither vocabulary is dropped rather than passed on. The Feedback
screen scores a missing average `:muted`, which the card does not know but
`Atoms::Icon` does; without the guard, a word the card had just refused would
have coloured the icon behind its back.

The rename broke one thing quietly on the way. `health.css` tinted the
sparkline bars by `.raaf-stat-card--ok / --warn / --bad`, and those selectors
stopped matching the moment the card started emitting the new names — the
Health cards would have gone grey with every test still green. The rules are
renamed, and a spec now reads every stylesheet in the library and fails on any
rule still addressing a tone the card no longer emits.

### The migrate step

Every screen is now on `StatCard`, and nothing renders the tile it supersedes.
Policies, Queue, Analytics, Experiment detail, Experiment comparison and Replay
detail keep the icon-box presentation they had, declared once per row as
`StatGrid.new(layout: :leading, …)` rather than once per tile — a KPI row where
one tile carried its icon somewhere else would be a mistake rather than a
choice. `hint:` becomes `note:`, which is the same line under the same figure.

Two adapters moved with them. `render_stat_card` is what the Tailwind-era
Feedback statistics panel calls, and `Tracing::MetricCard` keeps its name and
its `color:`/`link:` arguments for anything outside this engine; both now draw
the converged tile. The style guide's Data display section had a second row of
the superseded tiles under it, which the KPI tiles section above already shows
in both presentations, so it is gone rather than migrated.

The screens already on `StatCard` moved to the surviving tone words in the same
pass: Overview, Performance, Cost & usage, Health and Feedback scores said
`ok / warn / bad / info` and now say `success / warning / danger / accent`.
Nothing about them renders differently — the aliases were already mapping those
words — which is exactly why the check for this reads source rather than HTML.

One crossing is left, deliberately. `score_tone` answers in the dialect `Mono`,
`Bar` and the meters speak, and it is the right word for every figure on the
Feedback screen except the KPI tile at the top. That tile maps it at its own
call site, so the tile's word is the semantic one without the shared helper
having to change vocabulary for the sake of one caller.

### The contract step

`Molecules::MetricCard`, `Organisms::MetricGrid` and `molecules/metric_card.css`
are deleted, and so is `StatCard::TONE_ALIASES`. The card knows the four
surviving words and nothing else, so `ok / warn / bad / info` are dropped the
way any other unrecognised word is. Nothing passes them: the two adapters that
carry a caller's own vocabulary — `render_stat_card` with its Preline colour
names, `Tracing::MetricCard` with `color:` — map onto the surviving set
themselves. One tile in the library, one tone vocabulary, one entry for it in
the style guide showing both presentations.

The two checks written for the migrate step stay, and are what stops the
console drifting back: one fails on any component naming the deleted tile, the
other on any tile method naming a retired tone. Both name the retired words
themselves now rather than reading them off the card, since the card no longer
states them anywhere.

The stylesheet is assembled by globbing `app/assets/stylesheets/RAAF/ui/*/`, so
deleting the CSS file is the whole of removing it — there is no manifest that
could be left pointing at a file that is gone.
