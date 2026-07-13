# Stagewright plugin usability refresh — 2026-07-13

Stagewright's data and authoring commands were retained, but the widget shell was reorganized around four
clear tasks: **Paint**, **Routes**, **Levels**, and **Check**. The refresh does not migrate or rewrite stage
data.

## Interaction changes

- The header tabs and level form use proportional grid layouts, so controls no longer clip at the widget's
  390-pixel minimum width.
- Paint brushes are grouped into terrain, build policy, enemy traversal, and cell roles. The header explains
  the selected brush, reports the hovered cell, and reminds authors that one drag is one undo step.
- Route nodes and edges are deterministically ordered and use readable endpoint names. Route controls are
  split into **Build**, **Rules**, and **Test** panels instead of one dense command grid.
- The selected node or edge gets a contextual summary with stable ID suffix, priority, lane count, and
  predicate types. A missing **Delete edge** command was added with confirmation and undo support.
- Level settings use a responsive two-column form. Level actions are a compact two-row grid, and level rows
  display their validation health alongside stable ID suffixes.
- Validation has an error/warning summary. Selecting an issue navigates to its level, graph, node, or edge.

## Verification

- StyLua and Selene validate the strict Luau source.
- Pure/source tests compile the plugin shell and guard the responsive form and task-specific route panels.
- The built RBXM validator requires the new route panels, edge deletion, and issue-navigation markers.
- Manual Studio QA should cover narrow and wide docking, brush drag/undo, node and edge selection, route tool
  tabs, issue navigation, and plugin reload while the widget is open.
