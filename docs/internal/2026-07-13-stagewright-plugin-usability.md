# Stagewright plugin usability refresh — 2026-07-13

Stagewright's data and authoring commands were retained, but the widget shell was reorganized around four
clear tasks: **Paint**, **Routes**, **Levels**, and **Check**. The refresh does not migrate or rewrite stage
data.

## Interaction changes

- The header tabs and level form use proportional grid layouts, so controls no longer clip at the widget's
  390-pixel minimum width.
- Paint brushes are grouped into terrain, build policy, enemy traversal, and cell roles. The header explains
  the selected brush and reports the hovered cell. A normal click only selects a cell; authors must hold
  **Shift** while dragging to paint, and one modified drag remains one undo step.
- Route nodes and edges are deterministically ordered and use readable endpoint names. Route controls are
  split into **Build**, **Rules**, and **Test** panels instead of one dense command grid.
- The selected node or edge gets a contextual summary with stable ID suffix, priority, lane count, and
  predicate types. A missing **Delete edge** command was added with confirmation and undo support.
- Level settings use a responsive two-column form. Level actions are a compact two-row grid, while level rows
  remain quiet and show only identity; validation detail stays in the Check workspace.
- Validation has an error/warning summary. Selecting an issue navigates to its level, graph, node, or edge.

## Desktop workspace follow-up

The widget identity moved to `StagewrightPanelV2` so existing saved narrow docking state does not trap the
redesigned editor. It opens as a large floating Studio workspace and adapts through three widths:

- Wide: persistent stage/level browser, central editor, and contextual inspector.
- Medium: persistent stage/level browser plus the central editor.
- Compact: central editor only, with the top task navigation retained.

The Flow + Graph workspace now includes a native clickable 2D topology overview synchronized with the
existing 3D Bézier handles. Nodes use spawn/junction/goal colors; edges expose priority, conditional versus
fallback state, trace state, selection, zoom, fit, and center controls. The inspector supports node rename
and precise local XYZ editing, plus edge priority/lane/rule summaries.

Paint gained category-specific visualization, 1×1/3×3/5×5 brush sizes, reset-to-default painting, and direct
cell-error navigation. Its toolbox now replaces the level browser in Paint instead of competing with a second
brush sidebar, leaving the entire center pane for the canvas. Hover is calculated from the visible scrolling
canvas bounds so pooled cells cannot retain stale coordinates.

The graph overview now uses deterministic topology columns from spawn to goal rather than scattering cards by
their physical X/Z coordinates. The canvas clips every edge, the repeated node/edge list was removed from the
inspector, and Build controls only expose node or edge commands relevant to the current selection. The selected
level's validation count remains in the header; project-wide details remain in Check.

## Stagewright 2.3 approved workspace

The first 2.3 pass retained too much of the 2.2 shell and failed visual QA against the approved concept. The
follow-up replaces the workspace structure directly rather than treating the mockup as loose inspiration:

- The application bar is 52 pixels high and contains the Stagewright identity, stage/level breadcrumb,
  undo/redo, validation state, four workspaces, and menu in one row.
- **Flow** uses a full-height dotted topology canvas with curved selectable edges, quiet default links, a live
  minimap, bottom-right viewport controls, and the six approved primary actions: Add Node, Connect, Split Edge,
  Lanes, Condition, and Delete. These actions mutate real graph data and disable contextually.
- **Paint** uses the approved Layers rail, real color swatches, Select/Pencil/Rectangle/Fill/Eraser/Pan tools,
  coordinate headers, combined layer visualization, grid legend, zoom/fit controls, and the explicit
  **Shift + drag** safeguard. Select and Pan never mutate; rectangle and flood fill use one undo transaction.
- **Levels** is one level-overview surface with editable settings, a live miniature of the selected layered
  grid, route/build/issue metrics, and one primary Open Level action. Secondary lifecycle commands live behind
  the three-dot menu instead of occupying a permanent button block.
- **Check** has its own Validation rail, four project summary cards, a table header, navigable issue rows, and
  disabled export while blocking errors exist.

No stage payload or runtime schema changed in this UI pass. Existing stage IDs, graphs, layered cells, and
working-copy persistence remain intact.

## Verification

- StyLua and Selene validate the strict Luau source.
- Pure/source tests compile the plugin shell and guard the responsive form and task-specific route panels.
- The bootstrap keeps top-level locals below a guarded danger threshold. Studio's Luau compiler has a
  200-register ceiling and rejected an earlier build before its toolbar was created even though the pure Luau
  parser accepted the source.
- The built RBXM validator requires the new route panels, edge deletion, and issue-navigation markers.
- The local installer refuses to replace Stagewright while Studio is open; overwriting a loaded plugin can
  strand its toolbar or dock-widget registration until a full restart.
- Manual Studio QA should cover wide/medium/compact resizing, stage search, brush size and reset undo, 2D/3D
  node selection parity, exact XYZ editing, edge selection, route tabs, cell issue navigation, and plugin
  reload while the widget is open.
