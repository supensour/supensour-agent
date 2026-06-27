# Vue review rules

Extends `generic.md` for Vue.js / Nuxt / Quasar projects. Covers Vue 2 (Options API) and Vue 3 (Composition API).

## Security (Vue-specific)

- [ ] No `v-html` with unsanitized user input — XSS vector
- [ ] No dynamic component names from user input (`:is="userInput"`)
- [ ] No `eval()` or `new Function()` with user-controlled strings
- [ ] Route guards enforce auth — no client-only auth checks without server validation
- [ ] Sensitive data not in Vuex/Pinia state accessible from devtools
- [ ] No secrets in `.env` files bundled into client code

## Architecture (Vue-specific)

- [ ] Components: single responsibility — no mixing fetch, logic, presentation
- [ ] Composables extract reusable logic — no duplicating reactive patterns across components
- [ ] Props typed (TypeScript or PropType) with required/default
- [ ] Events typed + documented — `defineEmits` with type signatures
- [ ] Provide/inject used sparingly — prefer props/emits for parent-child
- [ ] Store (Vuex/Pinia): actions for async, mutations/state for sync — no API calls in components directly (unless thin wrapper)
- [ ] Route-level code splitting with dynamic imports for heavy views
- [ ] Shared types in dedicated files, not inline in components

## Performance (Vue-specific)

- [ ] No reactive data that needn't be reactive — use `shallowRef` or raw objects for large read-only datasets
- [ ] `v-for` always has `:key` bound to stable unique identifier — not array index for mutable lists
- [ ] Computed properties over methods for derived state (caching)
- [ ] No expensive computation in templates — move to computed
- [ ] `v-if` vs `v-show` used correctly — `v-if` for rare toggles, `v-show` for frequent
- [ ] Large lists use virtual scrolling, not 1000+ DOM nodes
- [ ] Watchers have cleanup — no leaked intervals, event listeners, subscriptions
- [ ] `onUnmounted` / `beforeDestroy` cleans up side effects

## Code quality (Vue-specific)

- [ ] Composition API preferred for new code in Vue 3 — Options API only in legacy
- [ ] `ref()` vs `reactive()` used consistently
- [ ] Template refs typed correctly (`ref<HTMLInputElement | null>(null)`)
- [ ] No mixing `this.$refs` with Composition API `ref()`
- [ ] Slots named descriptively, scoped slots typed
- [ ] Component file naming: PascalCase for SFC, consistent with project convention
- [ ] No business logic in lifecycle hooks — extract to composables
- [ ] i18n: no hardcoded user-facing strings — use translation keys

## Test coverage (Vue-specific)

- [ ] Component tests: mount/shallowMount, test props → rendered output
- [ ] Component tests: user interactions emit correct events with correct payloads
- [ ] Composable tests: test reactive behavior, not implementation
- [ ] Store tests: actions, getters, mutations tested in isolation
- [ ] Use `flushPromises` from `@vue/test-utils` for async assertions
- [ ] `vi.useFakeTimers()` for debounce/throttle/setTimeout logic
