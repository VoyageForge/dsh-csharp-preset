---
name: vue3-code-design
description: >-
  How to design Vue 3 components in TypeScript: `<script setup lang="ts">` anatomy, type-based props
  with reactive destructure, typed emits, models and slots, `InjectionKey` provide/inject, typed
  composables and generic components, Pinia stores, and feature-first layout. Use when creating or
  restructuring a component, deciding where state or logic belongs, typing a component's public API,
  or when the user asks about component design, composables, Pinia, or project structure.
---

# Vue 3 Code and Component Design

Companion skills: `vue3-language-spec` for syntax, typing, naming, and formatting;
`vue3-script-splitting` for when a script should be broken into separate files; `vue3-code-review`
for the checklist applied to finished code; `vue3-testing-vitest` for tests.

## The rules that matter most

1. **One component per file.** Every component is a `.vue` file named in `PascalCase`:
   `OrderSummary.vue` exports the design of `OrderSummary`. Never define two components in one
   file, and never define a component inline inside another component's `<script setup>`.
2. **`<script setup lang="ts">` + Composition API only.** No Options API, no `mixins`, no `this`.
3. **Feature-first, not type-first.** Code that changes together lives together. A new screen
   goes into `features/<name>/`, not into a global `views/` and a global `components/`.
4. **Props down, events up.** A child never mutates a prop and never reaches into its parent.
   State is owned by the lowest common ancestor that needs to read it.
5. **State lives where it is used, and moves up only when a second consumer appears.** Local
   `ref` → composable → `provide/inject` → Pinia, in that order. Do not start with Pinia.
6. **Every composable is reusable in isolation.** If it needs a template or a DOM node, it is a
   component concern, not a composable concern.
7. **A type is part of the contract.** A prop, emit, model, slot, store, or composable that is not
   typed is not finished. Types describe the boundary; they never silence the compiler.

## TypeScript baseline

The project is strictly typed. Everything below inherits from that one decision. The base
configuration comes from `@vue/tsconfig`, so the project files stay thin — and the important part
is that they are **project references**, which is why the type gate is `vue-tsc --build` rather than
a plain `--noEmit` run:

```jsonc
// tsconfig.json — a solution file: no compilerOptions, only references.
{
  "files": [],
  "references": [
    { "path": "./tsconfig.node.json" },
    { "path": "./tsconfig.app.json" }
  ]
}
```

```jsonc
// tsconfig.app.json — application code
{
  "extends": "@vue/tsconfig/tsconfig.dom.json",   // strict + verbatimModuleSyntax + DOM libs
  "include": ["env.d.ts", "src/**/*", "src/**/*.vue"],
  "exclude": ["src/**/__tests__/*"],
  "compilerOptions": {
    "noUncheckedIndexedAccess": true,
    "paths": { "@/*": ["./src/*"] }
  }
}
```

`env.d.ts` at the project root carries `/// <reference types="vite/client" />`. Nothing else needs
declaring: `@vue/tsconfig/tsconfig.dom.json` sets `types: []` on purpose so Node's globals cannot
leak into browser code. See `vue3-language-spec` for the full three-file setup.

- **`strict: true` is not negotiable.** Turning off individual strictness flags to make an error go
  away is a Compiler-Error Blocker, not a fix.
- **No `any`.** If the shape is genuinely unknown, it is `unknown`, and it is narrowed before use.
  `any` disables checking for everything it touches, including code you have not written yet.
- **No non-null assertion `!` as a shortcut.** `value!` tells the compiler to stop helping. Narrow
  with a guard, an early return, or `??`. Reserve `!` for a proven invariant, with a comment saying
  what proves it.
- **No `as` casts to silence an error.** `as` is a claim, not a check. The one sanctioned shape is a
  narrowing assertion immediately after a runtime validation — and even there, prefer returning a
  typed value from a parser function.
- **Validate at the boundary.** `JSON.parse`, `await res.json()`, `localStorage.getItem`, and route
  params all arrive as `unknown`/`string`. Parse them into your types with a guard or a schema and
  hand the typed value to the rest of the app. Types stop at the process edge.
- **`import type` for type-only imports.** With `verbatimModuleSyntax`, a value-imported-but-
  unused-as-value symbol is a build error, and a type-only import that survives into the bundle is
  a wasted module edge.
- **`vue-tsc --build` is the type gate** (`npm run type-check`). Vitest and the dev server strip
  types without checking them, so a green test run is not evidence that the types are sound.
- **Types live next to what they describe.** A feature's types go in `features/<f>/types.ts`; only
  domain types shared by two or more features move to `src/types/`. Never re-declare a domain type
  locally just to avoid an import.

## Single-file component anatomy

Fixed block order, always: `<script setup lang="ts">` first, then `<template>`, then `<style>`. The
script is what a reviewer reads first, and keeping it on top makes the component's contract the
first thing visible.

```vue
<script setup lang="ts">
import { computed } from 'vue'
import type { Order, OrderFilters } from '../types'
import { useOrderFilters } from '../composables/useOrderFilters'

// 3.3+ — name the component for devtools and recursive use. Required when the file is
// reached through a dynamic import and the name cannot be inferred.
defineOptions({ name: 'OrderList' })

interface Props {
  orders: Order[]
  loading?: boolean
}

// 3.5+ — type-based declaration plus reactive props destructure, which also supplies
// defaults. The destructured names stay reactive.
const { orders, loading = false } = defineProps<Props>()

// 3.3+ — tuple syntax. Each key is an event, each tuple is its payload.
const emit = defineEmits<{
  select: [id: string]
}>()

// 3.4+ — writable model. The generic is the model's type.
const filters = defineModel<OrderFilters>('filters', { required: true })

const { keyword, status } = useOrderFilters(filters)

const visible = computed<Order[]>(() =>
  orders.filter((order) => order.status === status.value),
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

- **`lang="ts"` on `<script setup>`**, and the interface at the top of the block, above the macros
  that use it. Declaration order is what a reader follows even though types are hoisted.
- **`<script setup>` only.** A second plain `<script>` block is allowed only for `export`
  side-effects such as `export default { inheritAttrs: false }` — prefer `defineOptions` for
  everything it covers.
- **Macros are compiler built-ins.** `defineProps`, `defineEmits`, `defineModel`,
  `defineExpose`, `defineOptions`, `defineSlots` need no import and must not be imported. Their
  type arguments are compile-time only and are erased from the build.
- **Do not import components for template use in modern SFCs** — Vite resolves them. Do import
  them when they are used in the script (dynamic components, conditional rendering by variable).
- **Reactive props destructure (3.5+)** lets `const { orders, loading } = defineProps<Props>()` stay
  reactive, and is the preferred way to declare defaults. Below 3.5 destructuring props loses
  reactivity — use `props.orders`, `toRefs`, or `withDefaults`.
- **Type-only imports use `import type`**, so `verbatimModuleSyntax` stays satisfiable and no
  runtime import is emitted for something that only exists in the type system.

## Component taxonomy

Four kinds. Naming and location follow from the kind, and mixing them up is the main source of
bloated components.

| Kind | Purpose | Location | Naming | May import |
| --- | --- | --- | --- | --- |
| **View** (route component) | One route. Composes features, owns page-level state and fetching. | `features/<f>/views/` | `OrderListView.vue` | anything below it |
| **Feature component** | Domain-aware UI used by one feature. | `features/<f>/components/` | `OrderSummary.vue` | base, composables, its feature's store |
| **Base component** | Domain-free, reusable, no knowledge of the app. | `components/base/` | `BaseButton.vue`, `BaseModal.vue` | other base components only |
| **Layout component** | App chrome: shell, nav, footer. | `components/layout/` or `layouts/` | `AppShell.vue` | base only |

A base component **never** imports a store, a router, an `api.ts`, a domain type, or a feature
component. If it needs domain data, it takes it as a prop — a base component that imports the
`Order` type is no longer domain-free. That is what makes it reusable.

A view **never** contains more than structure and orchestration. If a view's `<template>` exceeds
roughly 150 lines or its script owns more than one concern, extract feature components.

## Directory layout

Feature-first. An `orders` change touches one directory.

```
src/
  main.ts                     # createApp, plugins, mount — the only bootstrap file
  App.vue                     # root component: layout + <RouterView>
  env.d.ts                    # /// <reference types="vite/client" />
  types/                      # domain types shared by 2+ features: Order, Customer
  router/index.ts             # merges each feature's routes.ts
  stores/                     # ONLY stores shared by two or more features
  composables/                # ONLY composables shared by two or more features
  lib/                        # framework-agnostic helpers — no Vue imports at all
  components/
    base/                     # BaseButton.vue, BaseInput.vue, BaseModal.vue
    layout/                   # AppShell.vue, AppNav.vue
  features/
    orders/
      types.ts                # feature-local types, DTOs, and filter shapes
      views/                  # OrderListView.vue, OrderDetailView.vue
      components/             # OrderSummary.vue, OrderStatusBadge.vue
      composables/            # useOrderFilters.ts
      stores/                 # orders.ts  (feature-owned store)
      orders.api.ts           # every fetch for this feature
      routes.ts               # export default [...] satisfies RouteRecordRaw[]
      index.ts                # the feature's public surface — other features import from here
      __tests__/
    cart/
```

Two rules keep this honest:

- **Cross-feature imports go through `features/<f>/index.ts`.** Reaching into
  `features/orders/components/OrderSummary.vue` from `features/cart/` couples the two features
  to an internal file; importing from `features/orders` makes the dependency visible and
  refactorable.
- **`lib/` must not import `vue`.** Pure functions (formatting, validation, math) live there so
  they are trivially testable and reusable on the server.

No `*.vue` shim is needed: `vue-tsc` understands `.vue` imports. `env.d.ts` exists for the Vite
client types, not for the SFC.

## Props, emits, and models

**Props are a public API, and in TypeScript they are declared as a type.** Define a named interface
in the component (or import the shared one), not an inline object literal.

```ts
interface Props {
  size?: 'sm' | 'md' | 'lg'
  order: Order
  selected?: boolean
  tags?: string[]
}

const { size = 'md', order, selected = false, tags = [] } = defineProps<Props>()
```

- **A union of string literals replaces the runtime `validator`.** `'sm' | 'md' | 'lg'` is checked
  at every call site, which is strictly better than a validator that only warns in development.
- **The type is a compile-time constraint, not runtime validation.** Vue can infer some runtime
  prop types from the declaration, but a union of literals is erased. When a prop value originates
  outside your code — a route param, a server payload, an untyped plugin — validate it where it
  enters and pass the validated value down.
- **Defaults with reactive props destructure (3.5+) are written inline**, as above, and a mutable
  reference default is written directly — `tags = []` is created per instance.
- **On 3.4 and below, `withDefaults` is the only way to declare defaults, and a mutable reference
  default MUST be a factory function** — a shared array or object would leak between instances:

```ts
// Vue 3.4 and below — no reactive props destructure, so withDefaults carries the defaults.
const props = withDefaults(defineProps<Props>(), {
  size: 'md',
  selected: false,
  tags: () => [],   // factory, NOT `[]` — withDefaults would share one array
})

// `props` is needed because the destructure above is unavailable.
props.order.status
```

**Never mutate a prop**, not even an object or array prop — the mutation escapes upward silently
and the parent's state changes without going through the parent. `readonly` on the type would say
so, but Vue's props are mutable by construction, so the rule is discipline plus review.

```ts
// Wrong: mutates the parent's object.
order.status = 'shipped'

// Right: the child asks; the parent decides.
emit('update:status', 'shipped')
```

**Emits declare their payloads with the tuple syntax (3.3+).** The payload type is then checked at
the `emit(...)` call site and the listener is typed in the template.

```ts
const emit = defineEmits<{
  select: [id: string]
  'update:status': [status: OrderStatus]
}>()

// The call-signature form is the alternative, and the only option before 3.3:
const emitLegacy = defineEmits<{
  (e: 'select', id: string): void
  (e: 'update:status', status: OrderStatus): void
}>()
```

Name events in `kebab-case` in the template — `emit('orderShipped')` in script is listened to as
`@order-shipped`.

**`v-model` is the standard two-way contract.** `defineModel<T>()` replaces the hand-written
`modelValue` prop plus `update:modelValue` emit, and carries the type.

```ts
// 3.4+: writable model. `.value` reads the prop, assigning emits the update.
// `required: true` with no default makes `model.value` non-nullable.
const model = defineModel<string>({ required: true })

// Named and multiple models in one component. Each generic types its own model.
const title = defineModel<string>('title')
const visible = defineModel<boolean>('visible', { default: false })
```

Use `v-model` only for genuinely two-way, presentation-level state (input values, open/closed,
selected tab). For one-way commands, use a plain prop plus an event — a `v-model` implies the child
may write, which is the wrong implication for "please delete this".

**Expose deliberately, and type what you expose.** `defineExpose({ focus })` is the only way a
parent may call into a child, and only for imperative actions the DOM cannot express (`focus()`,
`scrollTo()`, `reset()`). Consumers read the exposed surface through `ComponentExposed<typeof
OrderForm>` (see *Template refs and generic components*). Never expose state for the parent to read
— pass it down or lift it up instead.

## Slots

Default to slots for content, props for data. Typed slots document the contract and type the
parent's slot props.

```vue
<!-- BaseCard.vue -->
<script setup lang="ts">
import type { Order } from '../types'

interface Props { title?: string }
const { title = '' } = defineProps<Props>()

// 3.3+ — the type names each slot and the props it passes up.
// The return type is unused; `any` is the documented idiom here.
defineSlots<{
  default: () => any
  actions: (props: { order: Order }) => any
}>()
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
  `<template #default="{ order }">` — and in TypeScript the destructured `order` is typed from
  `defineSlots`.
- Fallback content goes between the slot tags: `<slot>No orders yet</slot>`.
- Do not build a "render prop" API out of a prop that takes a function. That is a slot — and a slot
  is the only form whose props the parent's template type-checks.
- A slot type's return position is `any` by convention; do not try to type it as `VNode[]` unless a
  consumer genuinely needs the nodes.

## Composables

A composable is a function whose name starts with `use` that encapsulates stateful logic behind
reactive values. It is the primary unit of reuse in Vue 3 — not a mixin, not a base class.

```ts
// features/orders/composables/useOrderFilters.ts
import { computed, ref } from 'vue'

export interface OrderFilters {
  keyword?: string
  status?: OrderStatus
}

export function useOrderFilters(initial: OrderFilters = {}) {
  const keyword = ref<string>(initial.keyword ?? '')
  const status = ref<OrderStatus>(initial.status ?? 'all')

  const isEmpty = computed<boolean>(() => keyword.value.trim() === '')

  function reset(): void {
    keyword.value = ''
    status.value = 'all'
  }

  return { keyword, status, isEmpty, reset }
}
```

Non-negotiable conventions:

- **Return a plain object of refs**, not a `reactive` object. Destructuring a returned `reactive`
  loses reactivity; returned refs survive destructuring. Name the returned refs explicitly —
  never `return { ...toRefs(state) }` when the set is small enough to list (and `toRefs` widens
  `Ref<T>` to `Ref<T | undefined>` under strict indexing).
- **Never return a `reactive` object from a composable** for the same reason.
- **Let the return type be inferred.** Inference gives callers the exact `Ref<string>` /
  `ComputedRef<boolean>` types; a hand-written return annotation can widen them and will not narrow
  back. Annotate when the inferred type is wider than intended, or when the composable is a
  published API — importing `Ref` and `ComputedRef` from `vue` with `import type`.
- **Accept refs and plain values**, and type that parameter as `MaybeRefOrGetter<T>` (3.3+).
  Normalize with `toValue()` so `useX(route.params.id)` and `useX(idRef)` both work, and wrap reads
  in `computed`/`watch` so they track.
- **Annotate tuples that would otherwise widen.** `ref([])` infers `Ref<never[]>`, and
  `ref(null)` infers `Ref<null>`; both must be written `ref<Order[]>([])` and
  `ref<Order | null>(null)`.
- **Own the cleanup of everything it creates.** Timers, `addEventListener`, `IntersectionObserver`,
  store subscriptions, and in-flight requests are all removed in `onScopeDispose`.
- **Accept an `options` object with an optional `immediate` / `watch` flag** rather than making
  every caller wrap it in `watchEffect` by hand. Type the flags as optional booleans, not `any`.
- **Only call composables at the top level of `setup()`** (or inside another composable). Calling
  one inside a callback detaches its lifecycle hooks from the component.

```ts
import { onScopeDispose, ref, toValue } from 'vue'
import type { MaybeRefOrGetter } from 'vue'

export function usePolling<T>(fetcher: MaybeRefOrGetter<() => Promise<T>>, intervalMs: number) {
  const data = ref<T | null>(null)
  // `ReturnType<typeof setInterval>` keeps this correct in both DOM and Node typings.
  let timer: ReturnType<typeof setInterval> | null = null

  async function tick(): Promise<void> {
    data.value = await toValue(fetcher)()
  }

  function start(): void {
    stop()
    timer = setInterval(tick, intervalMs)
    void tick()   // `void` marks the deliberately un-awaited promise
  }

  function stop(): void {
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

```ts
// features/orders/composables/orderContext.ts
import { inject, provide } from 'vue'
import type { InjectionKey, Ref } from 'vue'
import type { Order } from '../types'

export interface OrderContext {
  order: Ref<Order>
  remove: (id: string) => void
}

// `InjectionKey<T>` brands the symbol with its value type, so `inject` returns
// `OrderContext | undefined` and no cast is ever needed at the consumer.
export const OrderContextKey: InjectionKey<OrderContext> = Symbol('order-context')

export function provideOrderContext(context: OrderContext): void {
  provide(OrderContextKey, context)
}

export function useOrderContext(): OrderContext {
  const context = inject(OrderContextKey)
  if (context === undefined) {
    throw new Error('useOrderContext() must be called under a provideOrderContext() provider')
  }
  return context
}
```

- **The key is a typed `Symbol`, stored once in its own module**, never a bare string — string keys
  collide silently across libraries, and an untyped key forces an `as` at every consumer.
- **`InjectionKey<T>` is what removes the cast.** With it, `inject` is typed and returns
  `T | undefined`; without it you get `unknown` and end up asserting — which the type-safety review
  will flag.
- **Pair every `provide` with a `useXxx()` reader** typed as the context interface, so the
  `undefined` check exists in exactly one place.
- **Provide a `ref` when the value changes**, and mark it `readonly()` if consumers must not write
  to it — `Readonly<Ref<T>>` in the interface makes that a compile error rather than a convention.
- **The key module must not import a component or a store**, or a type-only circular import becomes
  a runtime one.

## State: where it belongs

Choose the lowest rung that works, and move up only when a second consumer actually appears.

| Situation | Use |
| --- | --- |
| Used by one component only | `ref` / `reactive` inside that component |
| Used by a component and its children | Props down, events up |
| Used by siblings under one parent | Lift to the parent |
| Reused logic across components, no shared instance | Composable |
| Deep subtree, one provider, form/table context | `provide` / `inject` with `InjectionKey<T>` |
| Shared across unrelated features, survives navigation, needs devtools | Pinia |

**Never use a global store for state that dies with a page.** A route's filter state belongs to
the view or the query string, not to a store that outlives it.

### Pinia

Use setup stores — they read like a composable and match the rest of the codebase. The store's type
is inferred from the setup function, so `defineStore` takes no generic.

```ts
// features/orders/stores/orders.ts
import { computed, ref } from 'vue'
import { defineStore } from 'pinia'
import type { Order } from '../types'
import { fetchOrders } from '../orders.api'

export const useOrdersStore = defineStore('orders', () => {
  // Every empty/falsy initial value needs its generic, or it widens to never[]/null.
  const items = ref<Order[]>([])
  const loading = ref(false)
  const error = ref<Error | null>(null)

  const count = computed<number>(() => items.value.length)

  async function load(): Promise<void> {
    loading.value = true
    error.value = null
    try {
      items.value = await fetchOrders()
    } catch (cause) {
      // `cause` is `unknown` under strict mode; narrow before storing it.
      error.value = cause instanceof Error ? cause : new Error(String(cause))
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
- **State must be serializable.** It is devtools-visible and may be rehydrated; a class instance or
  a `Map` keyed by an object belongs in a `markRaw`ed module-level value, not in store state.
- **Server data caching is not the same as client state.** If the project uses TanStack Query or
  similar, keep fetched server data there and keep the store for client-owned state.
- **Destructure with `storeToRefs`.** `const { items } = useOrdersStore()` loses reactivity;
  `const { items } = storeToRefs(useOrdersStore())` keeps it and types it as `Ref<Order[]>`. Actions
  can be destructured directly and keep their signatures.
- **Reset on logout / workspace switch.** Provide an explicit `$reset`-equivalent action in setup
  stores (setup stores have no built-in `$reset`).
- **Do not store component instances, DOM nodes, or class instances** in a store — use `markRaw`
  only as a last resort and never for reactive data. `markRaw` preserves the type, so a
  `markRaw(new Chart(...))` stays a `Chart` and still satisfies the compiler.

### Template refs and generic components

`useTemplateRef` (3.5+) is the typed way to reach a DOM node or a child component instance.

```ts
// 3.5+ — the explicit generic always works; with @vue/language-tools 2.1 and a static
// `ref="inputEl"` on an <input>, the generic can also be inferred.
const inputEl = useTemplateRef<HTMLInputElement>('inputEl')

// A child component instance: type it from the imported component's exposed surface.
import type { ComponentExposed } from 'vue-component-type-helpers'
import OrderForm from './OrderForm.vue'

const formRef = useTemplateRef<ComponentExposed<typeof OrderForm>>('formRef')
formRef.value?.reset()
```

- `InstanceType<typeof OrderForm>` is the plain-TS form of the same thing; `ComponentExposed` is
  cleaner because it exposes only what `defineExpose` published.
- Both require `vue-component-type-helpers` in devDependencies; it ships with a `create-vue`
  TypeScript project.
- **Generic components** declare their parameter in the `generic` attribute, which requires
  `lang="ts"`:

```vue
<script setup lang="ts" generic="T extends { id: string }">
const { items, selected } = defineProps<{
  items: T[]
  selected?: T
}>()

const emit = defineEmits<{ select: [item: T] }>()

// `T` is also usable in slot types and in the template.
defineSlots<{ row: (props: { item: T }) => any }>()
</script>
```

The constraint (`T extends { id: string }`) is what makes `:key="item.id"` legal inside the
component; without it the compiler cannot know `id` exists. A default is written
`generic="T extends object = Record<string, unknown>"`. Consumers get `T` inferred from the `items`
they pass, so a mistyped row is a compile error at the call site.

### Routing boundaries

```ts
// features/orders/routes.ts
import type { RouteRecordRaw } from 'vue-router'

// `satisfies` checks the literal against the router's own type without widening it.
export default [
  {
    path: 'orders',
    name: 'order-list',
    component: () => import('./views/OrderListView.vue'),
  },
] satisfies RouteRecordRaw[]
```

- **Only the shell and the landing route are eager.** Every other route goes through
  `() => import(...)` so it lands in its own chunk. See `vue3-lazy-loading` for chunk strategy,
  prefetching, typed `defineAsyncComponent`, and component-library on-demand import.
- **Route params are `string | string[]`, not `string`.** `useRoute().params.id` must be narrowed
  or validated — passing it straight into a function that wants a `string` does not compile, and
  `as string` is the wrong fix. Use `Array.isArray(param) ? param[0] : param` plus an emptiness
  check, then hand the validated id to the fetch.
- **Route `props: true` still delivers strings.** Declaring `props` on the route record types the
  component's props, but the router does not convert `'42'` to `42`; the component converts and
  validates.
- **Data fetching belongs to the view or to a route guard**, never to a base component.
- **Do not navigate from inside a store.** Return the result and let the caller navigate, or use a
  guard. Navigation inside an action makes the store untestable and surprising.
- Keep `useRoute()` for reading and `useRouter()` for writing; do not store either in Pinia.

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
- **A generic `ref` holding `null` cannot be written later without the union.** `ref<Order | null>(null)`
  is the declaration that makes the assignment below compile.

```ts
import { onWatcherCleanup, ref, watch } from 'vue'

const { orderId } = defineProps<{ orderId: string }>()
const detail = ref<Order | null>(null)

// 3.5+: cancel the previous request when the source changes or the scope stops.
watch(
  () => orderId,
  async (id: string) => {
    const controller = new AbortController()
    onWatcherCleanup(() => controller.abort())
    detail.value = await fetchOrder(id, { signal: controller.signal })
  },
  { immediate: true },
)
```

## Performance by design

- **`v-memo`** for expensive subtrees in a long list that rarely change.
- **`shallowRef`** for large, replaced-wholesale structures (maps, charts, big arrays) — it avoids
  deep reactivity on every nested field. Its type is `ShallowRef<T>`, and only `.value` assignment
  triggers an update.
- **`markRaw`** for third-party instances (map, editor, chart) that must never become reactive. It
  returns the same type, so no cast is needed at the call site.
- **Virtualize** lists beyond a few hundred rows (`vue-virtual-scroller`, `@tanstack/vue-virtual`).
  Never render 5,000 DOM nodes and rely on `v-if`. Most virtualizers are generic over the row type,
  so `T` flows from the item array into the row slot.
- **`KeepAlive`** for tab-like navigation where remounting is the cost; pair it with
  `onActivated`/`onDeactivated` instead of `onMounted`/`onUnmounted` for that state.
- **`defineAsyncComponent`** for heavy, rarely used widgets (editors, charts) with a loading and
  error component.
- **`defineAsyncComponent` loses the component's prop types** unless the loader's return type is
  annotated; wrap the typed component (`defineAsyncComponent<typeof HeavyChart>(() => import(...))`)
  when the props matter to call sites.
- **No type-only imports that pull a value module into the bundle.** `import type` guarantees this;
  a plain `import` of a type used only in annotations is caught by `verbatimModuleSyntax`.

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
| `any` on a prop, emit, or composable parameter | The entire boundary stops being checked | Name the real type; `unknown` + narrowing if genuinely unknown |
| Inline object literal as a prop type | Duplicated, unexported, unreadable in errors | A named `interface Props` (or an imported domain type) |
| `defineEmits(['select'])` in TypeScript | Payloads are `any` at every call site and listener | Tuple syntax `defineEmits<{ select: [id: string] }>()` |
| `ref([])` / `ref(null)` with no generic | Widens to `never[]` / `null` and rejects real writes | `ref<Order[]>([])`, `ref<Order \| null>(null)` |
| A local interface that restates a domain type | Two shapes drift apart silently | Import the domain type; keep only the extra fields local |
| `as Order[]` on a fetch response | Asserts a shape nobody validated | Parse at the boundary and return the typed value |
| `value!` to end a nullable complaint | The null case still exists at runtime | Guard, early-return, or `??` |
| `// @ts-ignore` | Hides the next line's error and every error after it | Fix the type; `@ts-expect-error -- reason` when genuinely unavoidable |
| `enum` for a closed set | Emits runtime code, does not narrow well, awkward in `.d.ts` | `as const` object + `keyof typeof`, or a union of string literals |
