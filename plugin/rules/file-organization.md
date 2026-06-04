# File organization

Many small, focused files beat few large ones. High cohesion, low coupling.

- 200–400 lines typical; 800 hard max. Extract utilities out of growing modules.
- Organize by **feature/domain**, not by type (`auth/` not `controllers/ models/ views/`).
- One responsibility per file; name it after what it does, not how.
- **Front:** a layered convention like FSD (`app/pages/widgets/features/entities/shared`) keeps
  imports one-directional. **Back:** a modular monolith with bounded contexts; a module exposes a
  public `service`, never its repository/models, to neighbours.
- Before adding a util, check `shared/` (front) / a `common`/`core` module (back) — don't duplicate.
