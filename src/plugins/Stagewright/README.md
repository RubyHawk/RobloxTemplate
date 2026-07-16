# Stagewright plugin architecture

`GridPlatformEditPlugin.server.luau` is the composition root. It owns plugin
lifecycle, application state, page wiring, and calls into focused modules. New
domain logic or reusable UI primitives should not be added to the bootstrap.

## Modules

- `ProjectStore.luau`: project persistence, working-copy mutations, and undo
  recordings.
- `AuthoringArea.luau`: transient Studio authoring model and 3D selection.
- `WorldPathView.luau`: world-path canvas rendering and input.
- `RouteOverview.luau`: route-logic graph rendering and input.
- `UI/Theme.luau`: shared color and sizing tokens. Change visual language here.
- `UI/Factory.luau`: small, reusable plugin controls.
- `UI/Toolbar.luau`: vector icons and toolbar selection styles.
- `Graph/Operations.luau`: graph mutations such as connect, split, lanes, and
  handle smoothing. It has no UI, persistence, or Workspace dependency.
- `Graph/PredicateFields.luau`: predicate input parsing and trace-context
  parsing. It has no UI or persistence dependency.
- `Shared/`: schema, validation, serialization, baking, migration, and runtime
  math shared with tests or gameplay code.

## Dependency direction

```text
bootstrap / views -> UI
bootstrap / views -> ProjectStore
bootstrap -> Graph
Graph -> Shared
ProjectStore -> Shared
UI -> Theme
```

Modules never require bootstrap. Graph modules never require UI,
`ProjectStore`, or Workspace. UI modules never require graph or persistence.
This keeps styling changes independent from route behavior and project data.

## Mutation flow

UI callback -> bootstrap controller -> `ProjectStore.mutate()` -> graph or grid
operation -> render refresh.

All authored data lives in versioned project payload. Workspace objects are
transient previews. Expensive preview/build work must happen only on explicit
preview or build actions, not every pointer movement.

## Where changes belong

- Colors, fonts, spacing, control states: `UI/`.
- Route topology or lane behavior: `Graph/` and `Shared/`.
- Canvas interaction: `WorldPathView.luau` or `RouteOverview.luau`.
- Persistence, undo, migrations: `ProjectStore.luau` and `Shared/`.
- Page composition only: bootstrap.
