# Security

Before any commit touching input, auth, or data:

- **No secrets in code.** Use env / a secret manager; validate required secrets exist at startup.
- **Injection:** parameterized queries (never string-built SQL); escape/encode output (XSS);
  never pass untrusted input to a shell.
- **AuthN/AuthZ:** verify identity and check permission on every protected action, server-side.
- **CSRF** protection on state-changing requests; **rate-limit** public endpoints.
- **Errors** must not leak stack traces, secrets, or internal structure to clients.
- **Dependencies:** run an audit (`npm audit` / `pip-audit`); a secret scan (`gitleaks`); a
  static check (`semgrep` / `bandit`) before relying on "looks fine".
- If you find a security issue: stop, fix it before continuing, rotate any exposed secret.
