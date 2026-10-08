---
name: vue3-testing-vitest
description: >-
  Testing a Vue 3 + TypeScript project with Vitest and @vue/test-utils: happy-dom config in
  `vite.config.ts`, colocated `__tests__/*.spec.ts`, typed mount factories, testing composables
  with an effect scope, Pinia with createTestingPinia, typed mocks with `vi.mocked` and
  `vi.fn<T>()`, and type-level assertions. Use when writing or fixing unit and component tests, when
  the `vue-tsc` gate fails, or when the user asks about test structure, mocking, or coverage.
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
| Type checking | **`vue-tsc --build`** (`npm run type-check`) — a separate gate, not something Vitest does |
| Component type helpers | **`vue-component-type-helpers`** for `ComponentProps` / `ComponentExposed` |
| Accessibility assertions (optional) | `vitest-axe` |

Vitest transpiles with esbuild and **never checks types**. A fully green suite is therefore not
evidence that the project compiles; run `vue-tsc --build` (the `type-check` script) as well.

## Configuration

Vitest config stays in `vite.config.ts`. Add a `test` block and keep the import from
`vitest/config` so the config file gains the `test` key under its own types.
`vitest.config.ts` is only needed when the test environment genuinely diverges from the dev server.

```ts
// vite.config.ts
import { fileURLToPath, URL } from 'node:url'
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
    setupFiles: ['./vitest.setup.ts'],
    include: ['src/**/*.spec.ts'],
    restoreMocks: true,
    coverage: {
      provider: 'v8',
      reporter: ['text', 'html'],
      include: ['src/**/*.{ts,vue}'],
      exclude: ['src/main.ts', 'src/**/*.spec.ts'],
    },
  },
})
```

`globals: true` lets tests use `describe`/`it`/`expect`/`vi` without importing them — but in
TypeScript that also needs the ambient types, which is the one thing this flag costs:

```jsonc
// tsconfig.vitest.json — a third project reference, alongside app and node
{
  "extends": "./tsconfig.app.json",
  "include": ["src/**/__tests__/*", "env.d.ts"],
  "exclude": [],
  "compilerOptions": {
    "types": ["node", "vitest/globals"],
    "tsBuildInfoFile": "./node_modules/.tmp/tsconfig.vitest.tsbuildinfo"
  }
}
```

`tsconfig.app.json` deliberately excludes `src/**/__tests__/*`, so the test files belong to this
project and the globals are declared here rather than leaking into application code. Add
`{ "path": "./tsconfig.vitest.json" }` to the root `tsconfig.json` references so `vue-tsc --build`
covers it.

The examples below import from `'vitest'` explicitly, which needs no ambient types at all and reads
unambiguously in a `.ts` file. Prefer that; if you do rely on globals, the ESLint config must know
them too:

```js
// eslint.config.js — add to the exported array
{
  files: ['src/**/*.spec.ts'],
  languageOptions: { globals: { ...globals.node, ...globals.vitest } },
}
```

Add the gates to `package.json` so both are runnable, and run the type gate as part of `test`:

```json
"scripts": {
  "type-check": "vue-tsc --build",
  "test": "vitest run",
  "test:watch": "vitest",
  "test:all": "vue-tsc --build && vitest run"
}
```

## Layout and naming

Tests are colocated with the code they cover.

```
src/features/orders/
  components/OrderSummary.vue
  composables/useOrderFilters.ts
  stores/orders.ts
  orders.api.ts
  types.ts
  __tests__/
    OrderSummary.spec.ts
    useOrderFilters.spec.ts
    orders.store.spec.ts
```

- One spec file per subject, named after it: `OrderSummary.vue` → `OrderSummary.spec.ts`.
- `describe` names the subject; `it` names the **behavior**, in plain language: `it('emits select with the order id when a row is clicked')`.
- Given/When/Then inside the test body, separated by a blank line. One behavior per `it` — if the
  title needs "and", split it.
- **Build fixtures with a typed factory** (`function makeOrder(overrides: Partial<Order> = {}): Order`)
  rather than casting a literal with `as Order`. A factory makes the next required field a compile
  error in one place instead of a runtime surprise in every test.
- Prefer a small typed mount factory over repeating the mount options.

## Component tests

**`mount` by default; `shallowMount` only when a child is irrelevant and slow.** Shallow mounting
everywhere hides integration bugs and makes assertions about markup meaningless.

```ts
import { describe, expect, it } from 'vitest'
import { mount } from '@vue/test-utils'
import type { ComponentProps } from 'vue-component-type-helpers'
import OrderSummary from '../OrderSummary.vue'
import { makeOrder } from './factories'

// `ComponentProps` reads the props type straight off the component, so the
// factory cannot drift from the component's real contract.
function mountSummary(props: Partial<ComponentProps<typeof OrderSummary>> = {}) {
  return mount(OrderSummary, {
    props: { order: makeOrder(), loading: false, ...props },
  })
}

describe('OrderSummary', () => {
  it('formats the total as currency', () => {
    const wrapper = mountSummary({ order: makeOrder({ total: 1250 }) })

    expect(wrapper.get('[data-testid="total"]').text()).toBe('$12.50')
  })

  it('emits select with the order id when the row is clicked', async () => {
    const wrapper = mountSummary({ order: makeOrder({ id: 'o-1' }) })

    await wrapper.get('button').trigger('click')

    expect(wrapper.emitted('select')).toEqual([['o-1']])
  })
})
```

`mount` infers the props type from the component, so a misspelled prop or a wrong type is a
compile error at the call site. That inference is lost when the component is held in a variable
typed as the generic `Component` — keep the concrete type (`mount<typeof OrderSummary>(...)`) or
import the component directly.

Mount options worth knowing:

| Option | Use |
| --- | --- |
| `props` | Initial props; change later with `await wrapper.setProps({ ... })` |
| `global.plugins` | Pinia, router, i18n, a component library |
| `global.stubs` | Replace a heavy or irrelevant child: `{ OrderChart: true }` |
| `global.mocks` | Replace a global property such as `$t` or `$route` |
| `global.provide` | Supply a `provide`/`inject` context under test — pass a real `InjectionKey<T>` |
| `global.directives` | A custom directive used by the template |
| `attachTo` | Append to the document — required for focus, `document.activeElement`, and real layout |
| `slots` | Render slot content: `{ actions: '<button>Save</button>' }` |

## Querying

Query what the user perceives, not what the implementation happens to be.

1. **By role or accessible name** — `wrapper.get('button')`, `wrapper.get('[role="dialog"]')`,
   `wrapper.findAll('li')`.
2. **By visible text** — `wrapper.get('button').text()`, or `findAll` plus a text filter.
3. **By `data-testid`** as the escape hatch when no stable semantic hook exists.
4. **Never by CSS class**, and never `wrapper.vm.someInternal`. Under TypeScript the last one is
   worse than usual: `wrapper.vm` is typed as the component's instance, so reaching into a `ref`
   or a private helper with an `as` cast is a type-safety finding as well as a coupling one.

Add `data-testid` deliberately in the component when a test needs a stable hook. That is a
legitimate reason to touch production markup; asserting on `.card__title--large` is not.

Useful accessors: `find`/`findAll` (empty wrapper, no throw), `get`/`getAll` (throws when missing —
prefer these, the failure message is better), `exists()`, `text()`, `html()`, `attributes()`,
`classes()`, `isVisible()`.

**Avoid `wrapper.vm`.** Reading or writing component internals couples the test to the
implementation and breaks on every refactor. The two acceptable uses are `wrapper.vm.$el` (rare) and
invoking a method exposed through `defineExpose` — and that second one is typed automatically when
the component's `defineExpose` surface is used through `ComponentExposed<typeof Child>`.

## Interactions and async

Vue updates the DOM asynchronously. Anything that changes state must be awaited.

```ts
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

```ts
import { flushPromises, mount } from '@vue/test-utils'
import { expect, it, vi } from 'vitest'
import { fetchOrders } from '../orders.api'
import OrderListView from '../views/OrderListView.vue'
import { makeOrder } from './factories'

// Mock the module at the top level; Vitest hoists this above the imports.
// The factory-free form automocks and keeps the module's real types, which is
// what makes `vi.mocked` below recover a fully typed mock.
vi.mock('../orders.api')

const mockedFetchOrders = vi.mocked(fetchOrders)

it('renders the orders returned by the API', async () => {
  mockedFetchOrders.mockResolvedValue([makeOrder({ id: 'o-1', total: 100 })])

  const wrapper = mount(OrderListView, { global: { plugins: [router] } })
  await flushPromises()

  expect(wrapper.findAll('[data-testid="order-row"]')).toHaveLength(1)
  expect(mockedFetchOrders).toHaveBeenCalledOnce()
})
```

Two rules make mocks type-safe:

- **`vi.mocked(fn)` is how a mocked import is typed.** Calling `.mockResolvedValue(...)` on the raw
  imported function does not compile in TypeScript, and casting it with `as Mock` throws the types
  away. `vi.mocked` returns a mock whose implementation signature is the real function's.
- **The resolved value is checked.** `mockResolvedValue([makeOrder()])` is validated against the
  declared return type, so a fixture that stops matching the api's contract fails here rather than
  in production.

When a mock needs a specific shape rather than the whole module, pass a factory — and type it so the
fixture is checked too:

```ts
vi.mock('../orders.api', () => ({
  fetchOrders: vi.fn<() => Promise<Order[]>>(),
}))
```

## Emitted events

`wrapper.emitted(name)` returns an array of argument arrays. That is the contract between child and
parent, so assert on it rather than on internal state.

```ts
expect(wrapper.emitted('select')).toEqual([['o-1']])
expect(wrapper.emitted('select')).toHaveLength(1)
expect(wrapper.emitted()).toHaveProperty('select')
```

The declared emit payload types flow into these assertions: with
`defineEmits<{ select: [id: string] }>()`, `emitted('select')` is `[string][] | undefined`, so
comparing it to `[[42]]` is a compile error. Assert the **absence** of an event for a guard clause:
`expect(wrapper.emitted('select')).toBeUndefined()`.

## Testing composables

A composable must run inside an effect scope so its lifecycle hooks and `onScopeDispose` behave as
they do in a component. Use a small helper rather than mounting a throwaway component.

```ts
// src/test-utils/with-setup.ts
import { effectScope } from 'vue'

/**
 * Run a composable inside a detached effect scope.
 *
 * @param composable - Called with no arguments inside the scope.
 * @returns The composable's result and a function that stops the scope.
 */
export function withSetup<T>(composable: () => T): [T, () => void] {
  const scope = effectScope()
  // `run` is typed `T | undefined` because it cannot know the callback ran;
  // a guard keeps the contract honest without a non-null assertion.
  const result = scope.run(composable)
  if (result === undefined) {
    throw new Error('withSetup(): the composable returned undefined')
  }
  return [result, () => scope.stop()]
}
```

```ts
import { describe, expect, it, vi } from 'vitest'
import { withSetup } from '@/test-utils/with-setup'
import { useOrderFilters } from '../useOrderFilters'
import { usePolling } from '../usePolling'

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

The generic is what makes this worth writing: `withSetup(() => useOrderFilters())` gives a typed
`filters`, so `filters.keyword.value = 42` fails to compile instead of silently testing nothing.

Always test the **cleanup** path of a composable that creates a resource. That is the failure a
component test will never catch and production will.

## Stores

**Unit-test the store directly** with a fresh Pinia. Do not mount a component to test store logic.

```ts
import { beforeEach, describe, expect, it, vi } from 'vitest'
import { createPinia, setActivePinia } from 'pinia'
import { fetchOrders } from '../orders.api'
import { useOrdersStore } from '../stores/orders'
import { makeOrder } from './factories'

vi.mock('../orders.api')

const mockedFetchOrders = vi.mocked(fetchOrders)

describe('orders store', () => {
  beforeEach(() => {
    // A fresh Pinia per test: no state leaking between tests.
    setActivePinia(createPinia())
  })

  it('exposes the fetched orders', async () => {
    mockedFetchOrders.mockResolvedValue([makeOrder()])
    const store = useOrdersStore()

    await store.load()

    expect(store.items).toHaveLength(1)
    expect(store.loading).toBe(false)
  })

  it('records the error and clears loading when the fetch fails', async () => {
    mockedFetchOrders.mockRejectedValue(new Error('offline'))
    const store = useOrdersStore()

    await store.load()

    expect(store.error).toBeInstanceOf(Error)
    expect(store.loading).toBe(false)
  })
})
```

**Component tests use `createTestingPinia`** so store actions are stubbed by default and the test
does not hit the network.

```ts
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

`initialState` is typed loosely — it accepts a plain object, so a misspelled store id or state key
is **not** caught by the compiler and silently produces an empty store. For anything non-trivial,
seed the real store (`store.items = [makeItem()]`) after mounting with the testing pinia, or verify
the state landed before asserting on the rendered output.

## Routing

Use an in-memory history so navigation does not touch the URL bar.

```ts
import { createMemoryHistory, createRouter } from 'vue-router'
import type { RouteRecordRaw } from 'vue-router'
import OrderDetailView from '../views/OrderDetailView.vue'

const routes: RouteRecordRaw[] = [
  { path: '/orders/:id', name: 'order-detail', component: OrderDetailView },
]

const router = createRouter({ history: createMemoryHistory(), routes })
```

- Mount the **view** with `global.plugins: [router]`, then `await router.push('/orders/o-1')` and
  `await router.isReady()`.
- Test guards as plain functions where possible — a guard that needs a mounted app is usually a
  guard doing too much.
- Assert on `router.currentRoute.value.name`, never on a rendered URL string. It is typed
  `string | symbol | undefined`, so compare it directly against the literal — do not cast it to
  `string` to quiet the compiler.
- `route.params.id` is `string | string[]`. A test that feeds it a route with a repeated segment is
  worth writing precisely because the type says the array case is real.

## Timers, mocks, and spies

- **`vi.mock(path)`** with no factory is the default for an API module: it automocks while keeping
  the module's types, and `vi.mocked(fn)` recovers a typed mock. Use a factory only when the mocked
  shape must differ from the real one, and type the factory's `vi.fn` explicitly.
- **`vi.fn<Signature>()`** for a standalone mock: `const onSubmit = vi.fn<(value: string) => void>()`.
  Without the generic the mock is `Mock<Procedure>`, its arguments are `any`, and the assertion
  proves nothing.
- **`vi.spyOn(object, 'method')`** to observe a real implementation; `restoreMocks: true` in the
  config resets them between tests.
- **`vi.useFakeTimers()`** for debounce, polling, and delay logic; always pair it with
  `vi.useRealTimers()` in `afterEach`, and advance with `vi.advanceTimersByTime(ms)` (or
  `await vi.advanceTimersByTimeAsync(ms)` when promises are involved).
- **`vi.stubGlobal('fetch', vi.fn<typeof fetch>())`** for raw `fetch` calls;
  `vi.unstubAllGlobals()` in `afterEach`. Typing the stub as `typeof fetch` keeps the response
  shape checked.
- **Never hit the real network in a test.** If an API module is not mocked, that is the bug.
- **Never `as any` a mock to make the compiler accept it.** That is the one place the type system
  was going to catch a wrong fixture; the fix is `vi.mocked` or a typed `vi.fn<...>()`.

## Type-level assertions

Vitest ships `expectTypeOf`, which fails at type-check time rather than at run time. These
assertions produce no runtime behavior, so they are checked by `vue-tsc` — the gate you already run
— and passing them is meaningful only because that gate is part of the suite.

```ts
import { expectTypeOf, it } from 'vitest'
import type { Ref } from 'vue'
import { useOrderFilters } from '../useOrderFilters'

it('exposes keyword as a mutable ref', () => {
  const { keyword } = useOrderFilters()

  expectTypeOf(keyword).toEqualTypeOf<Ref<string>>()
})
```

Use them sparingly and where a type is the actual contract: a composable's returned ref kind, a
generic component's inferred parameter, a store action's resolved type. A `.test-d.ts` file (run by
`vitest --typecheck`) is the place for assertions that must not appear in the runtime suite at all.

## What to test, and what not to

Test:

1. **Behavior with a user-visible consequence** — renders the right thing, emits the right event,
   shows an error state, disables submit while loading.
2. **Every branch** of a composable's or store's public logic, including the failure path.
3. **Cleanup** for anything that creates a resource.
4. **Boundaries** — empty list, single item, missing optional field, invalid input.
5. **Guard clauses** — the action that must NOT happen.
6. **The narrow spots in the types** — a `string | string[]` route param, a nullable field that the
   component must handle, a generic component's inference.

Do not test:

1. **Implementation details** — a ref's value, a private method, that a specific child received
   specific props (assert the rendered result instead).
2. **Vue itself** — that `v-if` hides an element, that `v-model` is two-way, that a computed caches.
3. **Third-party component libraries** — that their button calls their handler.
4. **Styling or snapshots of markup.** Snapshot tests of whole components are a maintenance tax:
   every legitimate markup change fails them, and reviewers approve the diff without reading it. If
   a snapshot is genuinely justified, keep it small and scoped.
5. **`main.ts` bootstrap.**

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
| `foo.mockResolvedValue(...)` on the raw import | Not typed as a mock; needs a cast that erases the check | `const foo = vi.mocked(fetchFoo)` |
| `as any` / `as Mock` on a mock | Throws away the one check that would catch a wrong fixture | `vi.mocked(fn)`, or `vi.fn<Signature>()` |
| Fixtures written as `{ ... } as Order` | The fixture stops matching the real type and nothing notices | A typed factory returning `Order` |
| Trusting a green `vitest run` as a type check | esbuild strips types without checking them | Run `vue-tsc --build` (`npm run test:all`) |
| `globals: true` with no `vitest/globals` in `tsconfig.json` | Tests pass at runtime and fail `vue-tsc` | Add the ambient types, or import from `'vitest'` explicitly |
