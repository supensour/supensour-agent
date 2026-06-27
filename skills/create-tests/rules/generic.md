# Generic test-generation rules

Base, language-agnostic conventions for generated tests. Language modules
(`rules/<lang>/index.md` + `types/<type>.md`) extend and override these.

## Principles

- **Minimum viable tests.** Write only enough to cover the target's behavior — uncovered lines,
  branches, and functions, plus edge/error paths. Avoid redundant or exhaustive cases that don't
  improve coverage or document a real risk.
- **Test behavior, not implementation.** Assert observable outputs/effects, not private internals.
  Refactors that preserve behavior should not break tests.
- **Arrange–Act–Assert.** One logical behavior per test. Keep arrange/act/assert visually separable.
- **Deterministic.** No dependence on wall-clock time, random seeds, network, ordering, or shared
  mutable state. Fake timers / clocks for time-dependent logic. Reset mocks between tests.
- **Names describe the scenario.** "returns 401 when token expired", not "test1" / "happy path".
- **Isolate at the right boundary.** Mock external I/O (network, DB, filesystem, clock) — not the unit
  under test. Don't mock so deep the test asserts nothing real, nor so shallow it hits real services.

## Cases to cover (per target)

- Each new/changed public function or method.
- Each branch: `if/else`, `switch`, ternary, `try/catch`, early returns, guard clauses.
- Edge inputs: `null`/`undefined`/empty, zero, negative, boundary values, max/min, empty collections.
- Error paths: thrown exceptions, rejected promises, non-2xx responses — assert the failure is handled
  as specified (status, message, fallback), not just that it throws.

## Output discipline

- Follow the **language module's** file naming + location convention exactly.
- Match the project's existing test style (framework, import order, helpers) before introducing new
  patterns — read a neighboring test first.
- A generated test must be runnable as-is: real imports, no `TODO`-only bodies, no placeholder asserts.
