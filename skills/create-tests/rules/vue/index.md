# Vue / JS-TS test conventions (entry)

Extends `rules/generic.md`. Entry point for the `vue` language module — covers Vue 2/3 + plain JS/TS
units run under **Vitest**. Load this, then the relevant `types/<type>.md`, then any matching `cases/*`.

## Framework & tooling

- **Runner:** Vitest (`@vue/test-utils` for components). Config in `vitest.config.js` (jsdom env).
- **Assertions/mocks:** `expect`, `vi.fn()`, `vi.mock()`, `vi.spyOn()`. Globals may be enabled — match
  the project (if `globals: true`, `describe/it/expect` need no import).

## File naming & location

- **Name:** `<source-basename>.spec.ts` (prefer `.spec.ts`; `.spec.js` only to match an all-JS project).
- **Location:** mirror the source path under the test root. Common roots: `test/unit/specs/<rel>` or
  `src/**/__tests__/`. **Detect the project's actual convention** from existing specs before writing.
  - e.g. `src/composables/promo-scheme/utils.js` → `test/unit/specs/composables/promo-scheme/utils.spec.ts`

## Running + coverage (token-efficient)

Use `scripts/run-tests.sh vue <spec> --coverage <source>` (wraps the command below). Scoped coverage is
~8× faster than whole-repo:

```bash
npm run test:unit -- run <test-file> --coverage --coverage.include="<source-file>"
# multiple: space-separate test files; repeat --coverage.include per source file
```

Don't re-run after every edit — run once to verify the final result / check coverage.

> Check whether coverage is on by default in the project's vitest/vite config (grep `coverage:`
> `vite.config.*` `vitest.config.*`). If `coverage.enabled: true` is set, coverage still collects even
> when the CLI omits `--coverage` — and with `coverage.all: true` it instruments the whole
> `coverage.include` glob (often all of `src/**`), not just the file under test. So a plain pass/fail
> sanity run pays the full whole-repo coverage cost. When you don't need coverage numbers yet, pass
> `--coverage=false` explicitly — never rely on omitting the flag to mean "off." (`vue_run_tests` in
> `scripts/lib/lang-vue.sh` already does this when called without a source file.)

## Coverage goals

- **100%** on utility functions and composables.
- Components: cover all **props**, emitted **events**, and **computed** properties; plus edge cases and
  error handling where relevant.
- Minimum viable — add only what's needed to hit the goal unless a case is critical.

## Async

- Use `flushPromises` from `@vue/test-utils` to await async updates / promise callbacks — not ad-hoc
  `await Promise.resolve()` chains. Use `await wrapper.vm.$nextTick()` for reactivity flushes.
- `vi.useFakeTimers()` for debounce/throttle/`setTimeout` logic.

## References

- Test types: [types/unit.md](types/unit.md)  (integration: later)
- Cases: [cases/handling-rejected-promises.md](cases/handling-rejected-promises.md)
