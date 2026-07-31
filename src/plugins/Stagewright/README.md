# Stagewright plugin architecture

`GridPlatformEditPlugin.server.luau` is the composition root. It owns plugin
lifecycle, application state, page wiring, and calls into focused modules. New
domain logic or reusable UI primitives should not be added to the bootstrap.

## Modules

- `ProjectStore.luau`: project persistence, working-copy mutations, and undo
  recordings.
- `AuthoringArea.luau`: transient Studio authoring model and 3D selection.
- `Controllers/WorldPathController.luau`: world-path view lifecycle and options,
  wired to semantic mutation adapters from the composition root.
- `Controllers/WorldPathEditSession.luau`: pure begin/apply/commit/cancel
  coordination for one world-path gesture, with no Roblox service dependency.
- `Controllers/PaintRouteDragSession.luau`: pure route-canvas pointer and undo
  lifecycle; it composes the shared drag reducer and owns no graph or UI state.
- `Controllers/PaintStrokeSession.luau`: pure cell-paint transaction and gesture
  lifecycle for pencil, erase, rectangle, and fill tools. It snapshots brush
  settings and owns no GUI, brush catalog, or project-store dependency.
- `WorldPathView.luau`: world-path canvas rendering and pointer input; it does
  not own persistence or undo.
- `RouteOverview.luau`: route-logic graph rendering and input.
- `UI/AppShell.luau`: dock-widget chrome and responsive page layout.
- `UI/HeaderController.luau`: stage selector, project menu, and history actions.
- `UI/Theme.luau`: shared color and sizing tokens. Change visual language here.
- `UI/Factory.luau`: small, reusable plugin controls.
- `UI/Toolbar.luau`: vector icons and toolbar selection styles.
- `UI/PaintAppearance.luau`: semantic cell colors and glyphs. It contains no
  canvas input or project mutation.
- `Paint/Brushes.luau`: pure brush catalog and bounded cell-area mutation. It
  contains no UI, persistence, or Workspace dependency.
- `Stage/Settings.luau`: pure level-setting parsing and transactional grid
  resize rules. It preserves in-bounds cell data and reports truncation first.
- `Graph/Operations.luau`: graph mutations such as connect, split, lanes, and
  handle smoothing. It has no UI, persistence, or Workspace dependency.
- `Waves/Model.luau`: pure enemy-type, wave-set, and endless-growth mutations.
  Growth parsing validates through `Shared/StageSchema`, and its preview calls
  the runtime `TowerDefenseWaves` math so the designer cannot drift from the
  server. It has no UI, Workspace, or rig-folder dependency.
- `Waves/RigCatalog.luau`: live discovery of the mob Models under
  `ReplicatedStorage.Template.EnemyRigs`. It powers the designer's mob picker
  only; authored data stores the rig name, never a live instance reference.
- `Graph/PredicateFields.luau`: predicate input parsing and trace-context
  parsing. It has no UI or persistence dependency.
- `Validation/IssueModel.luau`: pure issue counting, filtering, grouping, and
  ordering. It has no UI or persistence dependency.
- `Shared/`: schema, validation, serialization, baking, migration, and runtime
  math shared with tests or gameplay code.

## Dependency direction

```text
bootstrap -> controllers / views / UI
bootstrap -> ProjectStore
controllers -> views / Shared
bootstrap -> Graph
bootstrap -> Paint
bootstrap -> Stage
bootstrap -> Validation
Graph -> Shared
ProjectStore -> Shared
UI -> Theme
```

Modules never require bootstrap. Graph modules never require UI,
`ProjectStore`, or Workspace. Paint modules never require UI, persistence, or
Workspace. UI modules never require graph or persistence. This keeps styling
changes independent from route behavior and project data.

## Mutation flow

UI callback -> focused controller -> injected bootstrap adapter ->
`ProjectStore` transaction -> graph or grid operation -> render refresh.

All authored data lives in versioned project payload. Workspace objects are
transient previews. Expensive preview/build work must happen only on explicit
preview or build actions, not every pointer movement.

## Where changes belong

- Colors, fonts, spacing, control states: `UI/`.
- Route topology or lane behavior: `Graph/` and `Shared/`.
- Canvas interaction: `WorldPathView.luau` or `RouteOverview.luau`.
- Persistence, undo, migrations: `ProjectStore.luau` and `Shared/`.
- Page composition only: bootstrap.
