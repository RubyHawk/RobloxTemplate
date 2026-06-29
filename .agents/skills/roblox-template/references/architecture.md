# Architecture reference

## Layers

- `src/shared`: serializable types, configuration, catalogs, pure calculations, remote names, theme tokens, and provider contracts.
- `src/server`: profile ownership, validation, persistence, economy, inventory, rewards, purchases, public data, and external adapters.
- `src/client`: presentation state, input, audio, loading, AFK detection, UI factories, screens, and the component gallery.
- `worker`: optional notification scheduling boundary; gameplay must remain available when it is offline.

## Data flow

Clients request an intent through a named remote. The server validates rate, type, bounds, ownership, and current state; mutates the in-memory profile; then publishes a sanitized snapshot. Clients never submit final balances or rewards.

## Profile evolution

Store one versioned profile object per player. Reconcile missing defaults and apply sequential migrations before services access it. Public profiles contain only explicitly whitelisted statistics and are stored separately.

## UI composition

Every screen, card, input, button, layout, and finite data slot exists as an editable instance under `StarterGui.TemplateUI`. The screen binder only connects actions and applies live text, images, attributes, and visibility. It never creates, clones, or destroys GuiObjects. The screen registry owns exclusivity and back navigation.

## Integration states

Each provider returns `available`, `disabled`, or `error` with a user-safe reason. Placeholder IDs are zero or empty strings and must never trigger a purchase, HTTP call, or reward.
