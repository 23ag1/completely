# Input validation

Validate at every system boundary. Never trust external data — user input, API responses,
file contents, env, queue messages.

- Validate **before** processing, with a schema (zod / pydantic / json-schema), not ad-hoc ifs.
- Fail fast with a clear message naming the offending field.
- Parse, don't just check: turn raw input into a typed, known-good value at the edge, then the
  core works only with valid types.
- Enforce limits (length, range, count) to bound blast radius.
- **Front:** validate for UX, but never rely on it for safety. **Back:** the server re-validates
  everything — the client is untrusted.
