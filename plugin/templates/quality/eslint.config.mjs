// completely starter ESLint (flat config). No extra deps required; extend as your stack grows.
export default [
  {
    languageOptions: { ecmaVersion: "latest", sourceType: "module" },
    rules: {
      "no-unused-vars": "warn",
      "no-undef": "error",
      "eqeqeq": "warn",
      "no-var": "error",
      "prefer-const": "warn",
    },
  },
];
