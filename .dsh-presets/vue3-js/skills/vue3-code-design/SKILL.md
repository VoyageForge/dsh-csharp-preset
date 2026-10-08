---
name: vue3-code-design
description: >-
  Designing Vue 3 components in plain JavaScript: `<script setup>` anatomy, the component taxonomy
  (views, feature, base UI), props/emits/v-model/slot contracts, `useXxx` composables,
  provide/inject, Pinia, feature-first project layout, and the channel-choice decision table. Use
  when creating or restructuring components, deciding where state or logic belongs, extracting a
  composable, or when the user asks about component design, composables, state, or project
  structure.
---

# Vue 3 Code and Component Design

Companion skills: `vue3-language-spec` for syntax, naming, and formatting;
`vue3-script-splitting` for when a script should be broken into separate files; `vue3-code-review`
for the checklist applied to finished code; `vue3-testing-vitest` for tests.

## The rules that matter most

1. **One component per file.** Every component is a `.vue` file named in `PascalCase`:
   `OrderSummary.vue` exports the design of `OrderSummary`. Never define two components in one
   file, and never define a component inline inside another component's `<script setup>`.
2. **`<script setup>` + Composition API only.** No Options API, no `mixins`, no `this`.
3. **Feature-first, not type-first.** Code that changes together lives together. A new screen
   goes into `features/<name>/`, not into a global `views/` and a global `components/`.
4. **Props down, events up.** A child never mutates a prop and never reaches into its parent.
   State is owned by the lowest common ancestor that needs to read it.
5. **State lives where it is used, and moves up only when a second consumer appears.** Local
   `ref` → composable → `provide/inject` → Pinia, in that order. Do not start with Pinia.
6. **Every composable is reusable in isolation.** If it needs a template or a DOM node, it is a
   component concern, not a composable concern.

## Single-file component anatomy

Fixed block order, always: `<script setup>` first, then `<template>`, then `<style>`. The
script is what a reviewer reads first, and keeping it on top makes the component's contract the
first thing visible.

```vue
<script setup>
import { computed, ref } from 'vue'
import { useOrderFilters } from '../composables/useOrderFilters.js'

// 3.3+ — name the component for devtools and recursive use. Required when the file is
// reached through a dynamic import and the name cannot be inferred.
defineOptions({ name: 'OrderList' })

// 3.4+ — a writable model replaces the props+emit pair for v-model.
const filters = defineModel('filters', { type: Object, required: true })

// Declare the full contract: type, required, default, validator.
const props = defineProps({
  orders: { type: Array, required: true },
  loading: { type: Boolean, default: false },
})

const emit = defineEmits({
  // Object form documents and validates payloads. Return false to warn on misuse.
  select: (id) => typeof id === 'string',
})

const { keyword, status } = useOrderFilters(filters)

const visible = computed(() =>
  props.orders.filter((order) => order.status === status.value),
)
</script>

<template>
  <ul class="order-list">
    <OrderListItem
      v-for="order in visible"
      :key="order.id"
      :order="order"
      @select="emit('select', order.id)"
    />
  </ul>
</template>

<style scoped>
.order-list { display: grid; gap: 0.5rem; }
</style>
```

Rules for the block:

- **`<script setup>` only.** A second plain `<script>` block is allowed only for `export`
  side-effects such as `export default { inheritAttrs: false }` — prefer `defineOptions` for
  everything it covers.
- **Macros are compiler built-ins.** `defineProps`, `defineEmits`, `defineModel`,
  `defineExpose`, `defineOptions`, `defineSlots` need no import and must not be imported.
- **Do not import components for template use in modern SFCs** — Vite resolves them. Do import
  them when they are used in the script (dynamic components, conditional rendering by variable).
- **Reactive props destructure (3.5+)** lets `const { orders, loading } = defineProps(...)` stay
  reactive. Below 3.5 destructuring props loses reactivity — use `props.orders` or `toRefs`.

## Component taxonomy

Four kinds. Naming and location follow from the kind, and mixing them up is the main source of
bloated components.

| Kind | Purpose | Location | Naming | May import |
| --- | --- | --- | --- | --- |
| **View** (route component) | One route. Composes features, owns page-level state and fetching. | `features/<f>/views/` | `OrderListView.vue` | anything below it |
| **Feature component** | Domain-aware UI used by one feature. | `features/<f>/components/` | `OrderSummary.vue` | base, composables, its feature's store |
| **Base component** | Domain-free, reusable, no knowledge of the app. | `components/base/` | `BaseButton.vue`, `BaseModal.vue` | other base components only |
| **Layout component** | App chrome: shell, nav, footer. | `components/layout/` or `layouts/` | `AppShell.vue` | base only |

A base component **never** imports a store, a router, an `api.js`, or a feature component. If it
needs domain data, it takes it as a prop. That is what makes it reusable.

A view **never** contains more than structure and orchestration. If a view's `<template>` exceeds
roughly 150 lines or its script owns more than one concern, extract feature components.

## Directory layout

Feature-first. An `orders` change touches one directory.

```
src/
  main.js                     # createApp, plugins, mount — the only bootstrap file
  App.vue                     # root component: layout + <RouterView>
  router/index.js             # merges each feature's routes.js
  stores/                     # ONLY stores shared by two or more features
  composables/                # ONLY composables shared by two or more features
  lib/                        # framework-agnostic helpers — no Vue imports at all
  components/
    base/                     # BaseButton.vue, BaseInput.vue, BaseModal.vue
    layout/                   # AppShell.vue, AppNav.vue
  features/
    orders/
      views/                  # OrderListView.vue, OrderDetailView.vue
      components/             # OrderSummary.vue, OrderStatusBadge.vue
      composables/            # useOrderFilters.js
      stores/                 # orders.js  (feature-owned store)
      orders.api.js           # every fetch for this feature
      routes.js               # export default [{ path, name, component: () => import(...) }]
      index.js                # the feature's public surface — other features import from here
      __tests__/
    cart/
```

Two rules keep this honest:

- **Cross-feature imports go through `features/<f>/index.js`.** Reaching into
  `features/orders/components/OrderSummary.vue` from `features/cart/` couples the two features
  to an internal file; importing from `features/orders` makes the dependency visible and
  refactorable.
- **`lib/` must not import `vue`.** Pure functions (formatting, validation, math) live there so
  they are trivially testable and reusable on the server.

## Props, emits, and models

**Props are a public API.** Declare the object form with `type`, `required`/`default`, and a
`validator` when the domain has a closed set of values. Booleans default to `false`; do not write
`default: false` for them.

```js
const props = defineProps({
  size: { type: String, default: 'md', validator: (v) => ['sm', 'md', 'lg'].includes(v) },
  order: { type: Object, required: true },
  selected: { type: Boolean, default: false },
})
```

**Never mutate a prop**, not even an object or array prop — the mutation escapes upward silently
and the parent's state changes without going through the parent. If the child needs an editable
copy, copy it into a local `ref` with `watch` based on a stable identity, or emit the change.

```js
// Wrong: mutates the parent's object.
props.order.status = 'shipped'

// Right: the child asks; the parent decides.
emit('update:status', 'shipped')
```

**Emits declare their payloads.** Prefer the object form with a validator for non-trivial
payloads, and name events in `kebab-case` in the template — `emit('orderShipped')` in script is
listened to as `@order-shipped`.

**`v-model` is the standard two-way contract.** Use `defineModel` rather than hand-writing the
`modelValue` prop plus `update:modelValue` emit.

```js
// 3.4+: writable model. `.value` reads the prop, assigning emits the update.
const model = defineModel({ type: String, required: true })

// Named and multiple models in one component.
const title = defineModel('title')
const visible = defineModel('visible', { type: Boolean, default: false })
```

Use `v-model` only for genuinely two-way, presentation-level state (input values, open/closed,
selected tab). For one-way commands, use a plain prop plus an event — a `v-model` implies the child
may write, which is the wrong implication for "please delete this".

**Expose deliberately.** `defineExpose({ focus })` is the only way a parent may call into a child,
and only for imperative actions the DOM cannot express (`focus()`, `scrollTo()`, `reset()`). Never
expose state for the parent to read — pass it down or lift it up instead.

## Slots

Default to slots for content, props for data.

```vue
<!-- BaseCard.vue -->
<script setup>
defineProps({ title: { type: String, default: '' } })
defineSlots({
  default: () => undefined,          // content
  actions: (props) => undefined,     // 3.3+: documents the slot and its props
})
</script>

<template>
  <section class="card">
    <header v-if="title || $slots.actions">
      <h2 v-if="title">{{ title }}</h2>
      <div class="card__actions"><slot name="actions" /></div>
    </header>
    <slot />
  </section>
</template>
```

- Check `$slots.name` (or `useSlots()`) before rendering an optional wrapper, so an empty
  header or footer does not leave stray margins.
- Scope slots pass data **up** to the parent's template: `<slot :order="order" />`, consumed as
  `<template #default="{ order }">`.
- Fallback content goes between the slot tags: `<slot>No orders yet</slot>`.
- Do not build a "render prop" API out of a prop that takes a function. That is a slot.

## Composables

A composable is a function whose name starts with `use` that encapsulates stateful logic behind
reactive values. It is the primary unit of reuse in Vue 3 — not a mixin, not a base class.

```js
// features/orders/composables/useOrderFilters.js
import { computed, ref } from 'vue'

export function useOrderFilters(initial = {}) {
  const keyword = ref(initial.keyword ?? '')
  const status = ref(initial.status ?? 'all')

  const isEmpty = computed(() => keyword.value.trim() === '')

  function reset() {
    keyword.value = ''
    status.value = 'all'
  }

  return { keyword, status, isEmpty, reset }
}
```

Non-negotiable conventions:

- **Return a plain object of refs**, not a `reactive` object. Destructuring a returned `reactive`
  loses reactivity; returned refs survive destructuring. Name the returned refs explicitly —
  never `return { ...toRefs(state) }` when the set is small enough to list.
- **Never return a `reactive` object from a composable** for the same reason.
- **Accept refs and plain values.** Normalize with `toValue()` so `useX(route.params.id)` and
  `useX(idRef)` both work, and wrap reads in `computed`/`watch` so they track.
- **Own the cleanup of everything it creates.** Timers, `addEventListener`, `IntersectionObserver`,
  store subscriptions, and in-flight requests are all removed in `onScopeDispose`.
- **Accept an `options` object with an optional `immediate` / `watch` flag** rather than making
  every caller wrap it in `watchEffect` by hand.
- **Only call composables at the top level of `setup()`** (or inside another composable). Calling
  one inside a callback detaches its lifecycle hooks from the component.

```js
import { onScopeDispose, toValue, watch } from 'vue'

export function usePolling(fetcher, intervalMs) {
  const data = ref(null)
  let timer = null

  async function tick() {
    data.value = await toValue(fetcher)()
  }

  function start() {
    stop()
    timer = setInterval(tick, intervalMs)
    tick()
  }

  function stop() {
    if (timer !== null) {
      clearInterval(timer)
      timer = null
    }
  }

  // Runs when the owning component unmounts OR an outer effectScope stops.
  onScopeDispose(stop)

  return { data, start, stop }
}
```

Cross-feature composables go in `src/composables/`; feature-private ones stay in the feature.

## provide / inject

Use it to skip intermediate components in a **subtree** — a form passing context to deeply nested
fields, a table passing row actions to cells. Do not use it as a global store; it is scoped to the
component subtree and invisible to anyone outside it.

```js
// provider — features/orders/composables/orderContext.js
import { inject, provide } from 'vue'

const OrderContextKey = Symbol('order-context')

export function provideOrderContext(context) {
  provide(OrderContextKey, context)
}

export function useOrderContext() {
  const context = inject(OrderContextKey)
  if (context === undefined) {
    throw new Error('useOrderContext() must be called under a provideOrderContext() provider')
  }
  return context
}
```

- **The key is a `Symbol`**, stored once in a module, never a bare string — string keys collide
  silently across libraries.
- **Pair every `provide` with a `useXxx()` reader** that throws a descriptive error when the value
  is missing. Never sprinkle raw `inject('someKey')` through components.
- **Provide a `ref` when the value changes**, and mark it `readonly()` if consumers must not write to it.

## State: where it belongs

Choose the lowest rung that works, and move up only when a second consumer actually appears.

| Situation | Use |
| --- | --- |
| Used by one component only | `ref` / `reactive` inside that component |
| Used by a component and its children | Props down, events up |
| Used by siblings under one parent | Lift to the parent |
| Reused logic across components, no shared instance | Composable |
| Deep subtree, one provider, form/table context | `provide` / `inject` |
| Shared across unrelated features, survives navigation, needs devtools | Pinia |

**Never use a global store for state that dies with a page.** A route's filter state belongs to
the view or the query string, not to a store that outlives it.

### Pinia

Use setup stores — they read like a composable and match the rest of the codebase.

```js
// features/orders/stores/orders.js
import { computed, ref } from 'vue'
import { defineStore } from 'pinia'
import { fetchOrders } from '../orders.api.js'

export const useOrdersStore = defineStore('orders', () => {
  const items = ref([])
  const loading = ref(false)
  const error = ref(null)

  const count = computed(() => items.value.length)

  async function load() {
    loading.value = true
    error.value = null
    try {
      items.value = await fetchOrders()
    } catch (cause) {
      error.value = cause
    } finally {
      loading.value = false
    }
  }

  return { items, loading, error, count, load }
})
```

Store rules:

- **One store per feature concern**, named after the noun it owns (`orders`, `cart`, `session`).
  Not one store per entity type, and never one giant `useAppStore`.
- **A store holds state and the actions that change it.** No DOM access, no `window`, no template
  concerns, no router navigation inside a getter. Navigate in the component or in a route guard.
- **Server data caching is not the same as client state.** If the project uses TanStack Query or
  similar, keep fetched server data there and keep the store for client-owned state.
- **Destructure with `storeToRefs`.** `const { items } = useOrdersStore()` loses reactivity;
  `const { items } = storeToRefs(useOrdersStore())` keeps it. Actions can be destructured directly.
- **Reset on logout / workspace switch.** Provide an explicit `$reset`-equivalent action in setup
  stores (setup stores have no built-in `$reset`).
- **Do not store component instances, DOM nodes, or class instances** in a store — use `markRaw`
  only as a last resort and never for reactive data.

## Side effects and lifecycle

| Need | Use | Note |
| --- | --- | --- |
| Derived value from other reactive state | `computed` | Cached, no side effects, synchronous |
| React to a specific source and act | `watch(source, cb)` | Lazy by default; `immediate: true` to run once now |
| React to whatever was read in a callback | `watchEffect(fn)` | Use when dependencies are dynamic/unlistable |
| Run after DOM update | `watchPostEffect` / `nextTick()` | `watch` with `{ flush: 'post' }` |
| Register on mount | `onMounted` | DOM is available; the only place to touch `ref` elements |
| Clean up on unmount | `onUnmounted` / `onScopeDispose` | Timers, listeners, observers, abort controllers |

- **Prefer `computed` over `watch` for derived data.** A `watch` that writes to another ref for
  display purposes is a `computed` in disguise and introduces an extra render pass.
- **Never make the `watch` callback `async` directly** if you need cleanup — the returned promise
  is ignored. Use `onWatcherCleanup` (3.5+) or an `AbortController` captured in the closure.
- **Never mutate watched state inside its own watcher** without a guard; it is an infinite loop.
- **`watch` on a `reactive` object is deep by default**; on a `ref` holding an object it is not.
  Pass `{ deep: true }` deliberately, and prefer watching a `computed` of the specific fields.

```js
import { onWatcherCleanup, watch } from 'vue'

// 3.5+: cancel the previous request when the source changes or the scope stops.
watch(
  () => props.orderId,
  async (id) => {
    const controller = new AbortController()
    onWatcherCleanup(() => controller.abort())
    detail.value = await fetchOrder(id, { signal: controller.signal })
  },
  { immediate: true },
)
```

## Routing boundaries

- **Every route component is lazily imported**: `component: () => import('./views/OrderListView.vue')`.
  Only the shell and the landing route are eager. See `vue3-lazy-loading` for chunk strategy,
  prefetching, `defineAsyncComponent`, and component-library on-demand import.
- **Route params are strings.** Convert and validate in the view (or in a `props` route option with
  a cast function) before using them as an id.
- **Data fetching belongs to the view or to a route guard**, never to a base component. Use
  `onBeforeRouteUpdate` to refetch when only the param changed — the component is reused and
  `onMounted` will not fire again.
- **Do not navigate from inside a store.** Return the result and let the caller navigate, or use a
  guard. Navigation inside an action makes the store untestable and surprising.
- Keep `useRoute()` for reading and `useRouter()` for writing; do not store either in Pinia.

## Performance by design

- **`v-memo`** for expensive subtrees in a long list that rarely change.
- **`shallowRef`** for large, replaced-wholesale structures (maps, charts, big arrays) — it avoids
  deep reactivity on every nested field.
- **`markRaw`** for third-party instances (map, editor, chart) that must never become reactive.
- **Virtualize** lists beyond a few hundred rows (`vue-virtual-scroller`, `@tanstack/vue-virtual`).
  Never render 5,000 DOM nodes and rely on `v-if`.
- **`KeepAlive`** for tab-like navigation where remounting is the cost; pair it with
  `onActivated`/`onDeactivated` instead of `onMounted`/`onUnmounted` for that state.
- **`defineAsyncComponent`** for heavy, rarely used widgets (editors, charts) with a loading and
  error component.

## Anti-patterns

| Anti-pattern | Why it breaks | Do instead |
| --- | --- | --- |
| Mutating a prop | Silent parent mutation; Vue warns on direct prop writes only for primitives | Emit, or `v-model` |
| `const { items } = store` | Reactivity lost | `storeToRefs(store)` |
| `return reactive({...})` from a composable | Reactivity lost on destructure | Return refs |
| Two components in one `.vue` file | Untestable, unsearchable, no devtools entry | One component per file |
| Options API or `mixins` alongside `<script setup>` | Two mental models; mixin collisions are invisible | Composition API + composable |
| `v-if` and `v-for` on the same element | `v-if` is evaluated first and cannot see the loop variable | `<template v-for>` wrapping, or filter in `computed` |
| `:key="index"` on a mutable list | Wrong reuse of DOM and component state | Stable domain id |
| Business logic in a base component | Destroys reusability | Move to the feature or a composable |
| `provide`/`inject` as a global store | Invisible coupling, breaks outside the subtree | Pinia |
| Watch chains (`A` watches `B` watches `C`) | Order-dependent, one extra render per hop | Derive with `computed` |
| Global store for ephemeral UI state | Leaks across navigations and sessions | Local `ref` |
| Emitting an event with the whole object when an id suffices | Couples child to parent internals | Emit the minimal payload |
