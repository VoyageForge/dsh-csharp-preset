---
name: vue3-script-splitting
description: >-
  When to split a Vue 3 `<script setup lang="ts">` script into its own TypeScript file: choosing
  between a plain util, a `useXxx` composable, a Pinia store, a service, and a component; the
  triggers for extracting, and when it is premature; typing a composable's inputs with
  `MaybeRefOrGetter` and its output with a named interface. Use when a component's script has grown
  large, a second component needs the same logic, or the user asks about splitting scripts or
  composables.
---

# Splitting a Vue Script Into Separate Files (TypeScript)

Companion skills: `vue3-code-design` (component structure and contracts),
`vue3-language-spec` (TypeScript rules and style), `vue3-code-review` (the checklist).

The official guidance is one sentence long and says the important part: composables are extracted
**not only for reuse but also for code organization**, and once a component becomes "too large to
navigate and reason about", Composition API lets you organize it into smaller functions grouped by
logical concern — you can think of the extracted composables as *component-scoped services that can
talk to one another*. Everything below is that idea made operational, with the typing that
TypeScript makes non-optional.

## The rule

**Split when a concern is separable — not when a line count is exceeded.** A line count is a review
*trigger*, never the reason. A 300-line script that does one thing coherently is fine; a 90-line
script that fetches data, owns a form, drives a modal, and formats money is not.

The test that decides it is the **naming test**:

> Can you give the block a name that is not a restatement of the component's own name?

If you can say "the order-filtering concern", "the cursor-pagination concern", "the selection-modal
concern" — that is a separable concern, and it has a name, so it can have a file and a type. If the
only name you can produce is "the OrderList logic", it is not separable yet.

The second test is the **change test**:

> Would this block change for a different reason than the rest of the script?

Two independent reasons to change in one file is one too many.

In TypeScript there is a third, unusually objective test:

> **Can you write the public interface of this block without mentioning the component?**

If describing the block requires `typeof` on something local, or leaks the component's own
generated types, it is not a unit yet.

## Where the extracted code goes

Five destinations. Choosing the wrong one is the most common mistake — especially turning a pure
function into a composable.

| What you are extracting | Destination | Naming |
| --- | --- | --- |
| **Pure, stateless logic** — formatting, parsing, validation, math, sorting, building a query string. No `ref`, no lifecycle, no `watch`. | Plain module in `lib/` (or the feature's own folder). **Not a composable.** | `format-currency.ts` → `formatCurrency()` |
| **Stateful, reactive logic** — owns `ref`s over time, registers watchers or lifecycle hooks, manages a side effect. | Composable | `useOrderFilters.ts` → `useOrderFilters()` |
| **State shared by unrelated parts of the app, or that must outlive navigation** | Pinia store | `orders.ts` → `useOrdersStore()` |
| **Data access for one domain** — endpoints, request shaping, response parsing | Service module beside the feature | `orders.api.ts` |
| **A visual unit with its own template** — the logic and the markup belong together | A component | `OrderSummary.vue` |
| **Types, constants, injection keys** | A plain module, one concern per file | `order-status.ts`, `order-context.ts` |

The stateless/stateful line is the one that matters most. Vue's own docs draw it: a date formatter
encapsulates **stateless logic** and belongs with lodash and date-fns; tracking a mouse position
encapsulates **stateful logic** and belongs in a composable. Wrapping pure functions in a
`useFormatters()` composable adds a function call, a `return` object, a fabricated type, and a false
implication that there is state — and it is a **Major** review finding.

```ts
// Wrong — pure functions wearing a composable costume.
export function useFormatters() {
  const formatDate = (date: Date): string => new Intl.DateTimeFormat('en-US').format(date)
  const formatCurrency = (n: number): string =>
    new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(n)
  return { formatDate, formatCurrency }
}

// Right — plain utilities with real signatures.
// lib/formatters.ts
export function formatDate(date: Date): string {
  return new Intl.DateTimeFormat('en-US').format(date)
}

export function formatCurrency(amount: number): string {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amount)
}
```

Note the side effect of getting this right: the `lib/` versions have honest signatures, so a caller
cannot pass a string where a `Date` belongs. The composable version hid that behind a `return`
object.

## When to split — the triggers

Any one of these is sufficient. More than two and the script is overdue.

**Correctness and testing**

1. **The same logic is needed by a second consumer** — another component, or another composable.
   The second consumer is the only honest proof that an abstraction is real; a first consumer alone
   is a guess.
2. **You cannot test the logic without mounting the whole component.** Mounting a component to test
   a filter function means the function lives in the wrong place.
3. **The same reactive lifecycle is needed twice** — the same `watch` + cleanup + state group.
4. **The type of the block depends on the component.** If its signature needs a local `type` that
   only makes sense inside that component, extract the *type* first and see whether the logic
   follows it out of the file.

**Structure**

5. **The script has more than one reason to change.** Data loading and table filtering change for
   different reasons.
6. **The script reads as clearly separable phases.** Data fetching → search and filter → sort →
   selection → modal control. Four phases is four composables.
7. **A block has a name** (the naming test above) — even if it is used exactly once. This is the
   documented "extract for organization, not just reuse" case.
8. **A `watch` and the state it maintains are far apart in the file.** Their distance is the bug;
   split them together.

**Size — review triggers, not laws**

**No official Vue documentation states a line-count threshold.** The docs say only that components
become "too large to navigate and reason about". The numbers below are review triggers, useful as a
signal that a concern is hiding, never as a rule to obey:

| Signal | Threshold | What it usually means |
| --- | --- | --- |
| `<script setup>` length | ~200 lines | More than one concern |
| `<template>` length | ~150 lines | Extract child components, not composables |
| Component prop count | ~7 | The component is doing too much, or props should be grouped into one object type |
| Distinct `watch`/`watchEffect` calls | ~3 | Several independent reactive concerns |
| Single function length | ~40 lines | Extract helpers, then group them |
| Nesting depth | 3 levels | Guard clauses, or split the branches |
| `ref`s declared at the top level | ~10 | Unrelated state is being kept in one place |

When a threshold is crossed, **find the concern** before extracting. Extracting by line count
produces a composable named `useOrderListPart2`.

You can enforce the line budget mechanically instead of arguing about it. `eslint-plugin-vue`
(v9.15.0+) ships an opt-in rule, `vue/max-lines-per-block`, which is unlimited unless you configure
it — so silence from a default `recommended` config means the rule is not running:

```js
// eslint.config.js — a defensible starting budget
'vue/max-lines-per-block': ['warn', {
  script: 200,
  template: 150,
  skipBlankLines: true,
}],
```

Treat a `warn` here as "go find the concern", not "cut the file in half".

### The other axis: splitting the component

Splitting the *script* and splitting the *component* are different operations, and the second is
often what is actually needed. Extract a child component — not a composable — when:

- the component owns **both** orchestration/state and substantial presentational markup for several
  sections;
- it has **three or more distinct UI sections** (a filter bar, a list, a detail panel, a footer);
- a **template block repeats** or could become reusable (a row, a card, a list entry);
- the thing you want to reuse is **logic and layout together** — the official rule is: use a
  composable when reusing pure logic, use a component when reusing both logic and visual layout.

The two axes combine well. A list view typically ends up as a thin route view plus a filter-bar
component, a list component, an item component, and two or three typed composables behind them. Do
the component split first when the markup is the problem, and the composable split first when the
state is. Note that splitting a component also splits its types, so extract the shared domain types
into the feature's `types.ts` before you fan out — otherwise every child imports its props type from
a sibling, and the dependency graph becomes circular.

**Cross-cutting**

9. **The component mixes server data and UI state.** Data fetching belongs in a service module or a
   composable; the local UI flag does not belong next to it.
10. **The logic is needed in a second frame** — the same behaviour on a page and inside a modal, or
    in a mobile and a desktop variant.
11. **The script imports more than about five modules of its own.** A long import list is a list of
    concerns.

## When NOT to split

Extraction is not free: it adds a file, an import, an interface, an exported type, and a place for
the reader to jump to. Do not pay that cost without a reason.

- **One consumer, and no prospect of a second.** Wait for the second consumer. Premature abstraction
  is more expensive to undo than duplication.
- **The whole script is under ~30 lines.** There is nothing to organize yet.
- **The block needs the component instance.** `emit`, template refs, `defineExpose`, props and slots
  are component concerns. A "composable" that takes an `emit` function or reaches for
  `getCurrentInstance()` is a component pretending to be a function.
- **The interface would be worse than the code.** If extracting means passing six arguments, the
  block is not a cohesive unit — either group them into one options interface *and* split along a
  different seam, or leave it.
- **It would become a one-line composable.** `useFullName(first, last)` returning one `computed` is
  a worse `computed`, and a worse type.
- **The component is a thin presentational wrapper.** A `BaseButton` has no logic to extract.
- **The only motive is the line count.** See above.

## Where the file lives

Extraction answers "what is it"; location answers "who may use it". Both matter.

```
src/
  lib/                        # pure, framework-free. NEVER imports vue.
    formatters.ts
    parse-query.ts

  composables/                # shared by two or more features
    useEventListener.ts
    useMediaQuery.ts

  stores/                     # shared by two or more features
    session.ts

  features/
    orders/
      composables/            # private to this feature
        useOrderFilters.ts
        useOrderSelection.ts
      orders.api.ts           # data access for this feature
      types.ts                # Order, OrderStatus, OrderFilters
      order-status.ts         # runtime constants derived from those types
      views/OrderListView.vue
      components/
```

Rules:

- **A feature-private composable stays in the feature** until a second feature needs it. Moving it
  to `src/composables/` early creates a shared surface with one consumer.
- **`lib/` never imports `vue`.** If the extracted function needs `ref`, it is a composable. This is
  the single most useful structural line in the codebase, because `lib/` is then trivially testable
  without a Vue environment.
- **One concern per file.** `useOrderFilters.ts` does not also export `useOrderSorting`.
- **A composable's filename matches its export**: `useOrderFilters.ts` exports `useOrderFilters`.
- **A service module is per domain**, not per endpoint: `orders.api.ts`, not `get-orders.ts`.
- **Types live where the domain lives**, and are imported with `import type` so they never survive
  into the bundle. A type used by two features belongs in the feature that owns the domain, and the
  other feature imports it from there.

## How to split — procedure

Mechanical, in this order. Doing it out of order is how reactivity gets lost.

1. **Name the concern.** If you cannot, stop — see the naming test.
2. **Write the public interface first.** Decide the input type and the return type before moving any
   body code; that is the whole advantage of doing this in TypeScript.
3. **Create the file** in the right destination (table above).
4. **Move the state**: every `ref`/`reactive`/`computed` the concern owns, with the code that writes
   them.
5. **Move the watchers and lifecycle hooks with the state they touch.** A `watch` in the component
   that writes the composable's state is the classic broken extraction.
6. **Move the cleanup into the composable**, so it owns its own lifecycle: `onScopeDispose()` (or
   `onUnmounted()`) inside the composable, not in the component.
7. **Make the inputs explicit parameters** with a named options interface when there is more than
   one or two.
8. **Return a plain object of refs**, typed by an exported interface — never a `reactive` object.
9. **Update the component** to call the composable and destructure what it needs.
10. **Keep the template contract unchanged.** A refactor that also changes the template is two
    changes; do them separately.
11. **Run `vue-tsc --build` and the tests.** The type checker is the extraction's safety net; the
    tests are its payoff.

### Inputs: `MaybeRefOrGetter<T>` and `toValue()`

Vue exports `MaybeRef<T>` and `MaybeRefOrGetter<T>` (3.3+). A composable that may be called from
more than one place should accept all three shapes — a raw value, a ref, or a getter — and document
that in its signature.

```ts
import { ref, toValue, watchEffect, type MaybeRefOrGetter, type Ref } from 'vue'

export function useFetch<T>(url: MaybeRefOrGetter<string>): {
  data: Ref<T | null>
  error: Ref<Error | null>
} {
  const data = ref<T | null>(null)
  const error = ref<Error | null>(null)

  watchEffect(() => {
    // toValue() inside the effect: a ref or getter argument is tracked here.
    const target = toValue(url)
    data.value = null
    error.value = null
    fetch(target)
      .then((response) => response.json() as Promise<T>)
      .then((json) => { data.value = json })
      .catch((cause: unknown) => {
        error.value = cause instanceof Error ? cause : new Error(String(cause))
      })
  })

  return { data, error }
}

// All three call forms type-check and behave reactively:
// useFetch<Order[]>('/api/orders')
// useFetch<Order[]>(urlRef)
// useFetch<Order[]>(() => `/api/orders/${props.id}`)
```

`toValue()` called *outside* an effect reads once and tracks nothing — that is the bug this pattern
exists to avoid. `MaybeRefOrGetter` makes it impossible for a caller to get this wrong silently.

### Outputs: a named return interface

In JavaScript a composable's return shape lives in the reader's head. In TypeScript it is the
contract, and it should be named whenever it is not trivial:

```ts
export interface UseOrderFiltersReturn {
  keyword: Ref<string>
  status: Ref<OrderStatus>
  visible: ComputedRef<Order[]>
  isEmpty: ComputedRef<boolean>
  reset: () => void
}

export function useOrderFilters(
  orders: MaybeRefOrGetter<Order[]>,
  initial: Partial<OrderFilters> = {},
): UseOrderFiltersReturn {
  /* … */
}
```

Vue's convention still applies: return a **plain, non-reactive object of refs**, so the caller can
destructure and keep reactivity. Do not return a `reactive()` object — it breaks destructuring in
the caller and its inferred type is not the type you wrote.

### Generic composables

When the logic is genuinely parameterized by a type, make the composable generic rather than typing
it as `unknown` and casting at every call site:

```ts
export function useSelection<T extends { id: string }>(items: MaybeRefOrGetter<T[]>) {
  const selectedId = ref<string | null>(null)
  const selected = computed<T | null>(
    () => toValue(items).find((item) => item.id === selectedId.value) ?? null,
  )

  function select(item: T): void { selectedId.value = item.id }
  function clear(): void { selectedId.value = null }

  return { selectedId, selected, select, clear }
}
```

The `T extends { id: string }` constraint is what makes `.id` legal inside the body while keeping
the caller's own type on the way out.

### Immutable state with explicit actions

For state that must not be mutated from outside, return `readonly()`, so the compiler enforces what
was previously a comment. The declared signature is
`readonly<T extends object>(target: T): DeepReadonly<UnwrapNestedRefs<T>>`, and because
`UnwrapNestedRefs<T> = T extends Ref ? T : UnwrapRefSimple<T>` leaves a ref alone, a
`Ref<CartItem[]>` comes back as `DeepReadonly<Ref<CartItem[]>>` — i.e.
`Readonly<Ref<DeepReadonly<CartItem[]>>>`. Both `items.value = [...]` and
`items.value.push(...)` are then type errors:

```ts
import { computed, readonly, ref } from 'vue'

export function useCart() {
  const items = ref<CartItem[]>([])
  const total = computed(() =>
    items.value.reduce((sum, item) => sum + item.price * item.quantity, 0),
  )

  function addItem(product: Product, quantity = 1): void { /* … */ }
  function removeItem(productId: string): void { /* … */ }

  return { items: readonly(items), total, addItem, removeItem }
}
```

### Injection keys

The one thing that must leave a component even in a small refactor: a `provide`/`inject` key. It
belongs in its own module so both sides import the same typed symbol.

```ts
// features/orders/order-context.ts
import type { InjectionKey, Ref } from 'vue'

export interface OrderContext {
  orders: Readonly<Ref<Order[]>>
  reload: () => Promise<void>
}

// The key carries the type, so provide() and inject() cannot disagree.
export const OrderContextKey: InjectionKey<OrderContext> = Symbol('order-context')
```

```ts
// the provider
import { provide, readonly } from 'vue'
import { OrderContextKey } from '../order-context'

provide(OrderContextKey, { orders: readonly(orders), reload: load })

// the consumer — typed, and it throws instead of returning undefined
import { inject } from 'vue'
import { OrderContextKey, type OrderContext } from '../order-context'

export function useOrderContext(): OrderContext {
  const context = inject(OrderContextKey)
  if (context === undefined) {
    throw new Error('useOrderContext() must be called under an OrderContext provider')
  }
  return context
}
```

## The contract an extracted composable must satisfy

An extracted unit is a small module with a public API. Hold it to the same standard as a component:

1. **Named `useXxx`** (the official convention), file named after the export.
2. **Called only in `setup()` / `<script setup>`, and synchronously.** These are the only contexts
   where Vue can determine the active instance, required to register lifecycle hooks and to dispose
   watchers on unmount. `<script setup>` is the one place you may call one *after* an `await`,
   because the compiler restores the instance context.
3. **Owns its cleanup.** Timers, listeners, observers, subscriptions, in-flight requests — released
   by the composable, not by its caller.
4. **SSR-safe.** DOM access happens in `onMounted` (or later), never in the composable body.
5. **No hidden globals.** No module-level mutable state. If two calls need to share state, that state
   is a store — not a module-scope `ref` and not a module-scope `let`.
6. **Returns refs, not values.** A returned plain value is frozen at call time and silently wrong;
   TypeScript will happily let you return it, so this is a review item, not a compiler error.
7. **Explicit inputs**, typed with `MaybeRefOrGetter<T>` where reactivity may come from the caller.
8. **A named return type** once the shape stops being obvious.
9. **Reusable in isolation.** If it needs a template, it is a component.
10. **Documented with JSDoc**, including whether inputs may be refs or getters.

## Worked example

A view that does four things, before and after.

```vue
<!-- BEFORE: ~180 lines of script, four concerns, untestable without mounting -->
<script setup lang="ts">
import { computed, onMounted, ref, watch } from 'vue'
import { formatCurrency } from '@/lib/formatters'
import type { Order, OrderStatus } from '../types'

const orders = ref<Order[]>([])
const loading = ref(false)
const error = ref<Error | null>(null)
const keyword = ref('')
const status = ref<OrderStatus>('all')
const selectedId = ref<string | null>(null)
const isModalOpen = ref(false)

const visible = computed(() => orders.value
  .filter((o) => status.value === 'all' || o.status === status.value)
  .filter((o) => o.customer.toLowerCase().includes(keyword.value.trim().toLowerCase())))

const selected = computed(() => orders.value.find((o) => o.id === selectedId.value) ?? null)
const totalLabel = computed(() =>
  formatCurrency(visible.value.reduce((sum, o) => sum + o.total, 0)))

function openModal(id: string): void { selectedId.value = id; isModalOpen.value = true }
function closeModal(): void { isModalOpen.value = false }

async function load(): Promise<void> {
  loading.value = true
  error.value = null
  try {
    const response = await fetch('/api/orders')
    orders.value = (await response.json()) as Order[]
  } catch (cause) {
    error.value = cause instanceof Error ? cause : new Error(String(cause))
  } finally {
    loading.value = false
  }
}

watch(keyword, () => { /* debounce a search later */ })
onMounted(load)
</script>
```

```vue
<!-- AFTER: the view declares which concerns it uses; each concern is typed and testable alone -->
<script setup lang="ts">
import { useOrders } from '../composables/useOrders'
import { useOrderFilters } from '../composables/useOrderFilters'
import { useOrderSelection } from '../composables/useOrderSelection'
import { useCurrencyTotal } from '../composables/useCurrencyTotal'

// Data
const { orders, loading, error, load } = useOrders()

// Search / filter — takes `orders` so the two concerns stay decoupled
const { keyword, status, visible } = useOrderFilters(orders)

// Selection + modal
const { selected, isModalOpen, openModal, closeModal } = useOrderSelection(orders)

// Presentation-only derivation
const { totalLabel } = useCurrencyTotal(visible)
</script>
```

The component's template did not change at all, and every new call site is inferred from the
composable's declared return type. That is the sign of a clean extraction.

## Over-extraction — the failure modes

| Anti-pattern | Why it is worse than not splitting | Fix |
| --- | --- | --- |
| `useUtils()`, `useHelpers()`, `useCommon()` | A grab-bag that becomes a second god object and re-couples everything | Split by concern, or make them plain `lib/` functions |
| A composable per one-line `computed` | Adds a file, an import, a type, and an indirection for no reduction in complexity | Leave it in the component |
| `useOrderList()` — the whole script renamed | No seam was found; the file count went up and clarity went down | Apply the naming test; find the real concerns |
| Composable that takes `emit` or a component ref | A component concern; it will only ever work in one place | Keep it in the component, or make it a child component |
| Composable with 6+ positional parameters | The interface is harder to read than the code was | One options interface, *and* reconsider the seam |
| Composable reading module-level mutable state | Hidden singleton; call sites silently share state; tests interfere | A store, or make it a parameter |
| `lib/` module importing `vue` | Destroys the framework-free layer | Move it to `composables/` |
| Splitting data fetching from its error handling | The error state has no owner | One composable or service per resource owns both |
| Extracting the template into a composable via a render function | Composables do not render | A component |
| One file exporting several unrelated `useXxx` | Filename lies; imports pull in code you did not want | One concern per file |
| Typing the composable's inputs as `any` to make the split easy | The split hid the design problem instead of exposing it; nothing is checked at the seam | Name the type, or find the real seam |
| A `type` declared in the composable but describing the component's domain | The type belongs to the domain, so the composable does not own its own API | Move the type to the feature's `types.ts` and import it |

## Checklist

Before finishing an extraction, confirm:

- [ ] The concern has a name that is not a restatement of the component's name.
- [ ] Its public interface is written out — inputs and return type — and the component is not
      mentioned in either.
- [ ] It went to the right destination — plain module, composable, store, service, or component.
- [ ] `lib/` files still do not import `vue`.
- [ ] The composable owns the cleanup for everything it creates.
- [ ] It is called synchronously in `<script setup>` (or `setup()`).
- [ ] Inputs accept refs/getters/values as `MaybeRefOrGetter<T>` and normalize with `toValue()`
      inside an effect.
- [ ] It returns a plain object of refs, typed by a named interface where the shape is non-obvious.
- [ ] No `any`, no non-null assertion `!`, and no `as` cast was introduced at the seam.
- [ ] The component's template is unchanged.
- [ ] `vue-tsc --build` passes and the extracted logic has tests.
