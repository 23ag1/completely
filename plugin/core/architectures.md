# Architecture presets

When `/completely:init` asks "what architecture?", offer these. If the user doesn't know, pick the
recommended default for their stack and explain why in one line. Record in `completely.toml [architecture]`.

## Frontend
- **FSD (Feature-Sliced Design)** — *recommended default* for non-trivial React/Vue apps. Layers
  `app → pages → widgets → features → entities → shared`; imports flow one way (down). Scales,
  kills circular deps, clear ownership.
- **Feature-based** — group by feature folder; simpler, good for small/medium apps.
- **Atomic design** — for component-library / design-system-heavy UIs.

## Backend
- **Modular monolith (bounded contexts)** — *recommended default*. One deployable; each module
  exposes a public `service`, hides its repository/models; split to services later only if needed.
  Most of the microservices benefit, little of the ops cost.
- **Layered (controller → service → repository)** — classic, fine for CRUD-heavy apps.
- **Hexagonal / ports & adapters** — when you must swap infra (DB, queues) or test in isolation.

## How init uses this
1. Detect stack. 2. Offer matching presets, recommended first. 3. If unsure → choose recommended +
state the trade-off. 4. Write the choice to `completely.toml` and note it in `CLAUDE.md` so future
work conforms.
