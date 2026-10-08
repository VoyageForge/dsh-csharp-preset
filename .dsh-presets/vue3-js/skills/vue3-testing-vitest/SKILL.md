---
name: vue3-testing-vitest
description: >-
  Testing Vue 3 in plain JavaScript: Vitest, @vue/test-utils, happy-dom config, colocated
  `__tests__/*.spec.js` layout, mounting with plugins and stubs, querying by role instead of
  internals, asserting on emitted events, flushing async updates, testing composables in an effect
  scope, Pinia with createTestingPinia, mocking with vi.mock, and the anti-patterns. Use when
  writing or fixing tests, when setting up Vitest, or when asked about test structure, mocking, or
  coverage.
---

# Testing a Vue 3 Project with Vitest

Companion skills: `vue3-code-design` and `vue3-language-spec` — tests follow the same naming and
style rules as the code under test.

## Toolchain

| Concern | Choice |
| --- | --- |
| Runner, assertions, mocking, coverage | **Vitest** |
| Component mounting | **`@vue/test-utils`** |
| DOM | **`happy-dom`** (faster; switch to `jsdom` only if a specific API is missing) |
| Store | **`@pinia/testing`** |
| Accessibility assertions (optional) | `vitest-axe` |

## Configuration

If `vite.config.js` already exists, add a `test` block and keep the import from `vitest/config` so
the type-free config still gains the `test` key. `vitest.config.js` is only needed when the test
environment genuinely diverges from the dev server.

```js
// vite.config.js
import { fileURLToPath } from 'node:url'
import { defineConfig } from 'vitest/config'
import vue from '@vitejs/plugin-vue'

export default defineConfig({
  plugins: [vue()],
  resolve: {
    alias: { '@': fileURLToPath(new URL('./src', import.meta.url)) },
  },
  test: {
    environment: 'happy-dom',
    globals: true,
    setupFiles: ['./vitest.setup.js'],
    include: ['src/**/*.spec.js'],
    restoreMocks: true,
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html'],
      include: ['src/**/*.{js,vue}'],
      exclude: ['src/main.js', 'src/**/*.spec.js'],
    },
  },
})
```

`globals: true` lets tests use `describe`/`it`/`expect`/`vi` without importing them; the ESLint
config must then declare the Vitest globals for test files:

```js
// eslint.config.js — add to the exported array
{
  files: ['src/**/*.spec.js'],
  languageOptions: { globals: { ...globals.node, ...globals.vitest } },
}
```

## Layout and naming

Tests are colocated with the code they cover.

```
src/features/orders/
  components/OrderSummary.vue
  composables/useOrderFilters.js
  stores/orders.js
  orders.api.js
  __tests__/
    OrderSummary.spec.js
    useOrderFilters.spec.js
    orders.store.spec.js
```

- One spec file per subject, named after it: `OrderSummary.vue` → `OrderSummary.spec.js`.
- `describe` names the subject; `it` names the **behavior**, in plain language: `it('emits select with the order id when a row is clicked')`.
- Given/When/Then inside the test body, separated by a blank line. One behavior per `it` — if the
  title needs "and", split it.
- Prefer a small factory (`function mountSummary(props = {})`) over repeating the mount options.

## Component tests

**`mount` by default; `shallowMount` only when a child is irrelevant and slow.** Shallow mounting
everywhere hides integration bugs and makes assertions about markup meaningless.

```js
import { describe, expect, it, vi } from 'vitest'
import { mount } from '@vue/test-utils'
import OrderSummary from '../OrderSummary.vue'

function mountSummary(props = {}) {
  return mount(OrderSummary, {
    props: { order: { id: 'o-1', total: 1250, status: 'paid' }, ...props },
  })
}

describe('OrderSummary', () => {
  it('formats the total as currency', () => {
    const wrapper = mountSummary()

    expect(wrapper.get('[data-testid="total"]').text()).toBe('$12.50')
  })

  it('emits select with the order id when the row is clicked', async () => {
    const wrapper = mountSummary()

    await wrapper.get('button').trigger('click')

    expect(wrapper.emitted('select')).toEqual([['o-1']])
  })
})
```

Mount options worth knowing:

| Option | Use |
| --- | --- |
| `props` | Initial props; change later with `await wrapper.setProps({ ... })` |
| `global.plugins` | Pinia, router, i18n, a component library |
| `global.stubs` | Replace a heavy or irrelevant child: `{ OrderChart: true }` |
| `global.mocks` | Replace a global property such as `$t` or `$route` |
| `global.provide` | Supply a `provide`/`inject` context under test |
| `global.directives` | A custom directive used by the template |
| `attachTo` | Append to the document — required for focus, `document.activeElement`, and real layout |
| `slots` | Render slot content: `{ actions: '<button>Save</button>' }` |

## Querying

Query what the user perceives, not what the implementation happens to be.

1. **By role or accessible name** — `wrapper.get('button')`, `wrapper.get('[role="dialog"]')`,
   `wrapper.findAll('li')`.
2. **By visible text** — `wrapper.get('button').text()`, or `findAll` plus a text filter.
3. **By `data-testid`** as the escape hatch when no stable semantic hook exists.
4. **Never by CSS class**, and never `wrapper.vm.someInternal`.

Add `data-testid` deliberately in the component when a test needs a stable hook. That is a
legitimate reason to touch production markup; asserting on `.card__title--large` is not.

Useful accessors: `find`/`findAll` (empty wrapper, no throw), `get`/`getAll` (throws when missing —
prefer these, the failure message is better), `exists()`, `text()`, `html()`, `attributes()`,
`classes()`, `isVisible()`.

**Avoid `wrapper.vm`.** Reading or writing component internals couples the test to the
implementation and breaks on every refactor. The two acceptable uses are `wrapper.vm.$el` (rare) and
invoking a method exposed through `defineExpose`.

## Interactions and async

Vue updates the DOM asynchronously. Anything that changes state must be awaited.

```js
await wrapper.get('input').setValue('shipped')   // sets value + triggers input
await wrapper.get('form').trigger('submit')      // triggers the event
await wrapper.setProps({ loading: true })
await nextTick()                                 // after a direct state change
await flushPromises()                            // resolve pending promises (fetch, etc.)
```

`trigger` returns `nextTick()`, so `await` on it is enough for the immediate update. For anything
that crosses a promise boundary — a `fetch`, a `setTimeout`, a store action — use
`flushPromises()` from `@vue/test-utils`, or `vi.waitFor(() => expect(...))` when the number of
ticks is unknown.

```js
import { flushPromises, mount } from '@vue/test-utils'
import { vi } from 'vitest'
import { fetchOrders } from '../orders.api.js'
import OrderListView from '../views/OrderListView.vue'

// Mock the module at the top level; Vitest hoists this above the imports.
vi.mock('../orders.api.js', () => ({ fetchOrders: vi.fn() }))

it('renders the orders returned by the API', async () => {
  fetchOrders.mockResolvedValue([{ id: 'o-1', total: 100 }])

  const wrapper = mount(OrderListView, { global: { plugins: [router] } })
  await flushPromises()

  expect(wrapper.findAll('[data-testid="order-row"]')).toHaveLength(1)
  expect(fetchOrders).toHaveBeenCalledOnce()
})
```

## Emitted events

`wrapper.emitted(name)` returns an array of argument arrays. That is the contract between child and
parent, so assert on it rather than on internal state.

```js
expect(wrapper.emitted('select')).toEqual([['o-1']])
expect(wrapper.emitted('select')).toHaveLength(1)
expect(wrapper.emitted()).toHaveProperty('select')
```

Also assert the **absence** of an event for a guard clause: `expect(wrapper.emitted('select')).toBeUndefined()`.

## Testing composables

A composable must run inside an effect scope so its lifecycle hooks and `onScopeDispose` behave as
they do in a component. Use a small helper rather than mounting a throwaway component.

```js
// src/test-utils/with-setup.js
import { effectScope } from 'vue'

/**
 * Run a composable inside a detached effect scope.
 *
 * @param {Function} composable - Called with no arguments inside the scope.
 * @returns {[unknown, () => void]} The composable's result and a function that stops the scope.
 */
export function withSetup(composable) {
  let result
  const scope = effectScope()
  scope.run(() => {
    result = composable()
  })
  return [result, () => scope.stop()]
}
```

```js
import { describe, expect, it } from 'vitest'
import { withSetup } from '@/test-utils/with-setup.js'
import { useOrderFilters } from '../useOrderFilters.js'

describe('useOrderFilters', () => {
  it('filters by keyword case-insensitively', () => {
    const [filters] = withSetup(() => useOrderFilters())

    filters.keyword.value = 'ACME'

    expect(filters.isEmpty.value).toBe(false)
  })

  it('clears the timer when the scope stops', () => {
    const [polling, stop] = withSetup(() => usePolling(fetcher, 1000))
    const clearSpy = vi.spyOn(globalThis, 'clearInterval')

    polling.start()
    stop()

    expect(clearSpy).toHaveBeenCalled()
  })
})
```

Always test the **cleanup** path of a composable that creates a resource. That is the failure a
component test will never catch and production will.

## Stores

**Unit-test the store directly** with a fresh Pinia. Do not mount a component to test store logic.

```js
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { fetchOrders } from '../orders.api.js'
import { useOrdersStore } from '../stores/orders.js'

vi.mock('../orders.api.js', () => ({ fetchOrders: vi.fn() }))

describe('orders store', () => {
  beforeEach(() => {
    // A fresh Pinia per test: no state leaking between tests.
    setActivePinia(createPinia())
  })

  it('exposes the fetched orders', async () => {
    fetchOrders.mockResolvedValue([{ id: 'o-1' }])
    const store = useOrdersStore()

    await store.load()

    expect(store.items).toHaveLength(1)
    expect(store.loading).toBe(false)
  })

  it('records the error and clears loading when the fetch fails', async () => {
    fetchOrders.mockRejectedValue(new Error('offline'))
    const store = useOrdersStore()

    await store.load()

    expect(store.error).toBeInstanceOf(Error)
    expect(store.loading).toBe(false)
  })
})
```

**Component tests use `createTestingPinia`** so store actions are stubbed by default and the test
does not hit the network.

```js
import { createTestingPinia } from '@pinia/testing'
import { mount } from '@vue/test-utils'

const wrapper = mount(CartSummary, {
  global: {
    plugins: [
      createTestingPinia({
        createSpy: vi.fn,
        initialState: { cart: { items: [{ id: 'p-1', quantity: 2 }] } },
      }),
    ],
  },
})
```

## Routing

Use an in-memory history so navigation does not touch the URL bar.

```js
import { createMemoryHistory, createRouter } from 'vue-router'

const router = createRouter({
  history: createMemoryHistory(),
  routes: [{ path: '/orders/:id', name: 'order-detail', component: OrderDetailView }],
})
```

- Mount the **view** with `global.plugins: [router]`, then `await router.push('/orders/o-1')` and
  `await router.isReady()`.
- Test guards as plain functions where possible — a guard that needs a mounted app is usually a
  guard doing too much.
- Assert on `router.currentRoute.value.name`, not on a rendered URL string.

## Timers, mocks, and spies

- **`vi.mock(path, factory)`** for API modules. Hoisted to the top of the file, so the factory must
  not reference top-level variables — use `vi.hoisted()` when it must.
- **`vi.spyOn(object, 'method')`** to observe a real implementation; `restoreMocks: true` in the
  config resets them between tests.
- **`vi.useFakeTimers()`** for debounce, polling, and delay logic; always pair it with
  `vi.useRealTimers()` in `afterEach`, and advance with `vi.advanceTimersByTime(ms)` (or
  `await vi.advanceTimersByTimeAsync(ms)` when promises are involved).
- **`vi.stubGlobal('fetch', ...)`** for raw `fetch` calls; `vi.unstubAllGlobals()` in `afterEach`.
- **Never hit the real network in a test.** If an API module is not mocked, that is the bug.

## What to test, and what not to

Test:

1. **Behavior with a user-visible consequence** — renders the right thing, emits the right event,
   shows an error state, disables submit while loading.
2. **Every branch** of a composable's or store's public logic, including the failure path.
3. **Cleanup** for anything that creates a resource.
4. **Boundaries** — empty list, single item, missing optional field, invalid input.
5. **Guard clauses** — the action that must NOT happen.

Do not test:

1. **Implementation details** — a ref's value, a private method, that a specific child received
   specific props (assert the rendered result instead).
2. **Vue itself** — that `v-if` hides an element, that `v-model` is two-way, that a computed caches.
3. **Third-party component libraries** — that their button calls their handler.
4. **Styling or snapshots of markup.** Snapshot tests of whole components are a maintenance tax:
   every legitimate markup change fails them, and reviewers approve the diff without reading it. If
   a snapshot is genuinely justified, keep it small and scoped.
5. **`main.js` bootstrap.**

Coverage is a signal, not a target. Aim for the meaningful paths above; do not chase a percentage
by asserting that a function was called.

## Anti-patterns

| Anti-pattern | Why it hurts | Do instead |
| --- | --- | --- |
| `shallowMount` for everything | Children never render, integration bugs pass | `mount`, stub only specific heavy children |
| Asserting on `wrapper.vm.someRef` | Breaks on every refactor; tests the implementation | Assert rendered output or emitted events |
| CSS-class selectors (`.btn--primary`) | Breaks on restyling; no relationship to behavior | Role, text, or `data-testid` |
| `await` missing before `trigger`/`setValue` | Assertions run against the pre-update DOM — flaky or always green | Always `await` the interaction |
| `setTimeout` in a test to wait for an update | Flaky and slow | `flushPromises()`, `nextTick()`, `vi.waitFor()` |
| Shared wrapper across `it` blocks | State leaks; failures cascade | Mount inside each test or in `beforeEach` |
| Mocking the module under test | The test proves nothing | Mock its collaborators |
| One huge `it` covering a whole flow | First failure hides the rest | One behavior per `it` |
| Whole-component snapshots | Unread and rubber-stamped | Assert the specific values that matter |
| Testing that a component "renders" | Zero information | Assert what it renders |
| Real network in a unit test | Slow, flaky, order-dependent | `vi.mock` the API module |
