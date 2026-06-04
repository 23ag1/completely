# Task template — the worker-contract shape for `bd create`

Each field closes one silent-failure class. `cmp lint` FAILs any open task missing
acceptance, design, or metadata.write_zone.

```bash
bd create "<imperative goal, one line>" -t task -p <0-3> \
  --acceptance "<observable, testable: what proves it is done>" \
  --design     "<approach / why; link the spec section>" \
  --metadata   '{"write_zone":["path/or/glob", "..."], "verify":"<command>", "stop_rules":"return blocked if <...>"}' \
  -l "<labels>"
```

- **acceptance** → stops "I said it's done". **design** → stops aimless work.
- **metadata.write_zone** → stops touching a sibling's files. **verify** → the proof command.
- **stop_rules** → return `blocked` (never a silent stub) on ambiguity/scope/can't-build-full.
