# RAAF Console UI

The dashboard's component library, implemented from the **RAAF Console** design
canvas (claude.ai project `d865e78e-08ae-496d-b952-540164c70276`) and its
`PHLEX_COMPONENTS.md` inventory. Copies of the canvas and its colour constants
are in `rails/docs/design/`.

Namespace `RAAF::Rails::Ui`, which is Zeitwerk's default for `ui/` — no
inflector needed. Live reference: **`/raaf/style_guide`**.

## Layout

```
app/components/RAAF/rails/ui/     app/assets/stylesheets/RAAF/ui/
  base.rb  stylesheet.rb            generic/    tokens, reset
  style_guide.rb                    atoms/      one file per atom
  atoms/ molecules/ organisms/      molecules/  organisms/  utilities/
```

Every component has a stylesheet of the same name. A visual change is made in
exactly one file.

## The rules that keep it DRY

- **`KindBadge` and `StatusBadge` own the only mapping from a domain value to a
  colour.** The pairs live in `tokens.css` as `--raaf-kind-*` and
  `--raaf-tone-*`. Nothing else may hardcode a status or kind colour. Both
  normalise the tracer's synonyms (`response`→llm, `ok`/`success`→completed) so
  no call site repeats that logic.
- **Every table is `Organisms::DataGrid`.** It owns the column template so a
  header and its rows cannot disagree, and derives it from each column's
  `span:` weight as `minmax(0, Nfr)` tracks. Fixed pixel columns are not
  supported — they clip the right-hand cells on narrow viewports.
- **Variants are class modifiers, never inline styles.** Components take
  symbols (`tone: :danger`, `size: :sm`) and map them onto modifier classes.
- **One KPI tile, two presentations.** `Molecules::StatCard` takes
  `layout: :corner` (icon top right, the default) or `layout: :leading` (icon
  box in front of the tile). Both carry the delta, the note and the sparkline,
  because those belong to the number and not to where the icon sits.
  `Molecules::MetricCard` is the icon-box tile it supersedes, still rendered by
  five screens until they migrate. Its tone names are already the surviving
  set, so migrating a tile is a rename and no more.
- **One tone vocabulary on the KPI tile:** `accent`, `success`, `warning`,
  `danger` — the semantic set the atoms speak, so `tone:` means the same word
  on a card, an icon and a badge. `StatCard::TONE_ALIASES` maps the health
  dialect (`ok`/`warn`/`bad`/`info`) onto it, and is the only place that
  mapping is stated. A word from neither vocabulary is dropped rather than
  passed on to the icon.
- **Dynamic values travel as CSS custom properties** — `--raaf-bar-pct`,
  `--raaf-tree-level`, `--raaf-cols`, `--raaf-spark-h` — so markup carries no
  layout arithmetic.
- **Every component accepts `class:` and arbitrary attributes**, so none needs
  forking to add a Stimulus target or a `data-` hook.
- **Every graph mark carries its own readout.** `Sparkbars` takes `tips:`
  index-aligned with its values, `MeterRow` and `StatCard` take `tip:` and
  `series_tips:`, and all of them reuse `molecules/tooltip.css` rather than a
  `title` attribute or a second tooltip mechanism. A bar's height is a
  comparison; which bucket it covers and what its share is a share *of* are
  facts only the caller has, so a component states nothing it was not told.
  A bar hangs in a full-height cell so a two-pixel stub is still hoverable.
- **Constructors never take blocks.** Phlex routes any block given to `.new`
  into `view_template`, so block-shaped arguments are keywords instead — see
  `Pagination#href` and `DataGrid#row`.

## Screens

Built: the shell, Overview, Errors, Cost & usage, Performance, Traces, Spans
(hierarchy and list), Search, Flows, Tools, Trace detail, Style guide.

`Card` splits what `flush:` used to conflate. A titled card is `--flush` for
its header strip and keeps its body padding; only a genuinely flush body also
gets `--clip`, because only a row list paints its hover fill into the rounded
corners. Clipping every titled card cut the readouts off every chart inside
one.

Not built, from the canvas: Agents and Agent detail. The inventory also still
lists `CostBreakdown`, `ExperimentsTable` and `AgentConfigPanels`.

## The Tracing components

Added with the Search, Flows, Tools and Trace detail screens. Every one is on
`/raaf/style_guide` under **Tracing**, with the data a real span rarely has.

| Class | Notes |
|---|---|
| `Organisms::SearchWorkbench` | Query bar, facets, hits. Its own classes are `raaf-wb-*`: `raaf-search` is the topbar's search widget and colliding with it collapses the workbench to 170px. |
| `Organisms::TopologyGraph` | Ranks nodes from the edges — sources, hubs, sinks — rather than taking positions. Ranks are cut at `RANK_LIMIT` busiest-first, and say what they cut. With no edges it falls back to a plain tile grid. |
| `Organisms::PipelineSteps` | `MeterRow` in its `inline:` variant, index and kind chip in the lead slot. Not a fork. |
| `Organisms::TracePath` | `PathNode` per hop, on one connector rail. |
| `Organisms::SpanWaterfall` | Takes `start_ms`/`duration_ms` and a `total_ms` window; computes the offsets so every row shares one scale. |
| `Organisms::SpanInspector` | Payload / Error / Tokens / Raw. The tab is a URL parameter, not client state. |
| `Organisms::ToolRegistry` | `auto-fill` card grid closing on a `MetricTriple`. |
| `Molecules::WaterfallRow` | Indent, bar offset and width all as custom properties. |
| `Molecules::PayloadBlock` | Blurs a masked payload and covers it with a `RedactionVeil`. Capped at 340px with its own scroll — a system prompt runs to thousands of lines. |
| `Molecules::RedactionVeil` | A `<label>` over a hidden checkbox. **The reveal is CSS only, deliberately** — a payload that stays blurred because a script failed to load is the one thing nobody can work around. |
| `Molecules::ErrorCallout` | Class, message, backtrace. The backtrace is optional, for grouped errors. |
| `Molecules::PathNode` | Rail stubs suppressed at the ends via `--first` / `--last`. |

`MeterRow` gained `inline:`, `meta:` and a block-rendered lead slot so the
pipeline screen could use it rather than fork it. The block is taken in
`view_template`, not the constructor — Phlex routes any block given to `.new`
there anyway.

The Tailwind CDN in `BaseLayout` is scaffolding for the page components not yet
converted. Remove it when the last one is done:
`grep -rl 'class: "[^"]*\(bg-\|text-gray\|px-[0-9]\)' app/components`
