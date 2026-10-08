---
name: vue3-script-splitting
description: >-
  When to split logic out of a Vue 3 `<script setup>` into its own file in plain JavaScript: the
  decision table for choosing a util, a `useXxx` composable, a Pinia store, a service, or a
  component; when to extract and when not to; the extraction procedure; the composable contract; and
  the over-extraction anti-patterns. Use when a script has grown large, when a second component
  needs the same logic, or when asked about splitting scripts, extracting composables, or component
  size.
---

# Splitting a Vue Script Into Separate Files

Companion skills: `vue3-code-design` (component structure and contracts),
`vue3-language-spec` (syntax, naming, formatting), `vue3-code-review` (the checklist).

The official guidance is one sentence long and says the important part: composables are extracted
**not only for reuse but also for code organization**, and once a component becomes "too large to
navigate and reason about", Composition API lets you organize it into smaller functions grouped by
logical concern — you can think of the extracted composables as *component-scoped services that can
talk to one another*. Everything below is that idea made operational.

## The rule

**Split when a concern is separable — not when a line count is exceeded.** A line count is a
review *trigger*, never the reason. A 300-line script that does one thing coherently is fine; a
90-line script that fetches data, owns a form, drives a modal, and formats money is not.

The test that decides it is the **naming test**:

> Can you give the block a name that is not a restatement of the component's own name?

If you can say "the order-filtering concern", "the cursor-pagination concern", "the selection-modal
concern" — that is a separable concern, and it has a name, so it can have a file. If the only name
you can produce is "the OrderList logic", it is not separable yet.

The second test is the **change test**:

> Would this block change for a different reason than the rest of the script?

Two independent reasons to change in one file is one too many.

## Where the extracted code goes

Five destinations. Choosing the wrong one is the most common mistake — especially turning a pure
function into a composable.

| What you are extracting | Destination | Naming |
| --- | --- | --- |
| **Pure, stateless logic** — formatting, parsing, validation, math, sorting, building a query string. No `ref`, no lifecycle, no `watch`. | Plain module in `lib/` (or the feature's own folder). **Not a composable.** | `format-currency.js` → `formatCurrency()` |
| **Stateful, reactive logic** — owns `ref`s over time, registers watchers or lifecycle hooks, manages a side effect. | Composable | `useOrderFilters.js` → `useOrderFilters()` |
| **State shared by unrelated parts of the app, or that must outlive navigation** | Pinia store | `orders.js` → `useOrdersStore()` |
| **Data access for one domain** — endpoints, request shaping, response parsing | Service module beside the feature | `orders.api.js` |
| **A visual unit with its own template** — the logic and the markup belong together | A component | `OrderSummary.vue` |
| **Types, constants, injection keys** | A plain module, one concern per file | `order-status.js`, `order-context.js` |

The stateless/stateful line is the one that matters most. Vue's own docs draw it: a date formatter
encapsulates **stateless logic** and belongs with lodash and date-fns; tracking a mouse position
encapsulates **stateful logic** and belongs in a composable. Wrapping pure functions in a
`useFormatters()` composable adds a function call, a `return` object, and a false implication that
there is state — and it is a **Major** review finding.

```js
// Wrong — pure functions wearing a composable costume.
export function useFormatters() {
  const formatDate = (date) => new Intl.DateTimeFormat('en-US').format(date)
  const formatCurrency = (n) => new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(n)
  return { formatDate, formatCurrency }
}

// Right — plain utilities.
// lib/formatters.js
export function formatDate(date) {
  return new Intl.DateTimeFormat('en-US').format(date)
}
export function formatCurrency(amount) {
  return new Intl.NumberFormat('en-US', { style: 'currency', currency: 'USD' }).format(amount)
}
```

## When to split — the triggers

Any one of these is sufficient. More than two and the script is overdue.

**Correctness and testing**

1. **The same logic is needed by a second consumer** — another component, or another composable.
   The second consumer is the only honest proof that an abstraction is real; a first consumer alone
   is a guess.
2. **You cannot test the logic without mounting the whole component.** Mounting a component to test
   a filter function means the function lives in the wrong place. This trigger appears first in a
   review because it is objective.
3. **The same reactive lifecycle is needed twice** — the same `watch` + cleanup + state group.

**Structure**

4. **The script has more than one reason to change.** Data loading and table filtering change for
   different reasons.
5. **The script reads as clearly separable phases.** A typical example: data fetching → search and
   filter → sort → selection → modal control. Four phases is four composables.
6. **A block has a name** (the naming test above) — even if it is used exactly once. This is the
   documented "extract for organization, not just reuse" case.
7. **A `watch` and the state it maintains are far apart in the file.** Their distance is the bug;
   split them together.

**Size — review triggers, not laws**

**No official Vue documentation states a line-count threshold.** The docs say only that components
become "too large to navigate and reason about". The numbers below are review triggers, useful as a
signal that a concern is hiding, never as a rule to obey:

| Signal | Threshold | What it usually means |
| --- | --- | --- |
| `<script setup>` length | ~200 lines | More than one concern |
| `<template>` length | ~150 lines | Extract child components, not composables |
| Component prop count | ~7 | The component is doing too much, or props should be grouped |
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
component, a list component, an item component, and two or three composables behind them. Do the
component split first when the markup is the problem, and the composable split first when the state
is.

**Cross-cutting**

8. **The component mixes server data and UI state.** Data fetching belongs in a service module or
   a composable; the local UI flag does not belong next to it.
9. **The logic is needed in a second frame** — the same behaviour on a page and inside a modal, or
   in a mobile and a desktop variant.
10. **The script imports more than about five modules of its own.** A long import list is a list of
    concerns.

## When NOT to split

Extraction is not free: it adds a file, an import, an interface, and a place for the reader to jump
to. Do not pay that cost without a reason.

- **One consumer, and no prospect of a second.** Wait for the second consumer. Premature abstraction
  is more expensive to undo than duplication.
- **The whole script is under ~30 lines.** There is nothing to organize yet.
- **The block needs the component instance.** `emit`, template refs, `defineExpose`, props and slots
  are component concerns. A "composable" that takes an `emit` function or reaches for
  `getCurrentInstance()` is a component pretending to be a function.
- **The interface would be worse than the code.** If extracting means passing six arguments, the
  block is not a cohesive unit — either group the arguments into one options object *and* split
  along a different seam, or leave it.
- **It would become a one-line composable.** `useFullName(firstName, lastName)` returning one
  `computed` is a worse `computed`.
- **The component is a thin presentational wrapper.** A `BaseButton` has no logic to extract.
- **The only motive is the line count.** See above.

## Where the file lives

Extraction answers "what is it"; location answers "who may use it". Both matter.

```
src/
  lib/                        # pure, framework-free. NEVER imports vue.
    formatters.js
    parse-query.js

  composables/                # shared by two or more features
    useEventListener.js
    useMediaQuery.js

  stores/                     # shared by two or more features
    session.js

  features/
    orders/
      composables/            # private to this feature
        useOrderFilters.js
        useOrderSelection.js
      orders.api.js           # data access for this feature
      order-status.js         # constants + the type-ish values for this feature
      views/OrderListView.vue
      components/
```

Rules:

- **A feature-private composable stays in the feature** until a second feature needs it. Moving it
  to `src/composables/` early creates a shared surface with one consumer — the same premature cost,
  in a worse place.
- **`lib/` never imports `vue`.** If the extracted function needs `ref`, it is a composable and
  belongs in `composables/`. Enforce this in review; it is the single most useful structural line in
  the codebase, because `lib/` is then trivially testable and reusable outside Vue.
- **One concern per file.** `useOrderFilters.js` does not also export `useOrderSorting`.
- **A composable's filename matches its export**: `useOrderFilters.js` exports `useOrderFilters`.
- **A service module is per domain**, not per endpoint: `orders.api.js`, not `get-orders.js`.

## How to split — procedure

Mechanical, in this order. Doing it out of order is how reactivity gets lost.

1. **Name the concern.** If you cannot, stop — see the naming test.
2. **Create the file** in the right destination (table above).
3. **Move the state first**: every `ref`/`reactive`/`computed` the concern owns. Move them with the
   code that writes them.
4. **Move the watchers and lifecycle hooks with the state they touch.** A `watch` in the component
   that writes the composable's state is the classic broken extraction.
5. **Move the cleanup into the composable**, so the composable owns its own lifecycle:
   `onScopeDispose()` (or `onUnmounted()`) inside the composable, not in the component.
6. **Make the inputs explicit parameters.** Anything the block read from the component's scope
   becomes an argument.
7. **Return a plain object of refs** — never a `reactive` object, and never a function-only bag if
   there is state.
8. **Update the component** to call the composable and destructure what it needs.
9. **Keep the template contract unchanged.** A refactor that also changes the template is two
   changes; do them separately.
10. **Re-run the tests.** If none existed and the concern is non-trivial, this is the moment to add
    them — the extraction is what makes them cheap.

### Inputs: accept refs, getters, and plain values

A composable that will be called from more than one place should accept whatever the caller has. The
official pattern is `toValue()` — normalize a ref, a getter, or a raw value to a value — and to call
it **inside** a `watchEffect` (or to `watch` the source explicitly) so the dependency is tracked:

```js
import { ref, toValue, watchEffect } from 'vue'

export function useFetch(url) {
  const data = ref(null)
  const error = ref(null)

  watchEffect(() => {
    // toValue() inside the effect: a ref or getter argument is tracked here.
    const target = toValue(url)
    data.value = null
    error.value = null
    fetch(target)
      .then((response) => response.json())
      .then((json) => { data.value = json })
      .catch((cause) => { error.value = cause })
  })

  return { data, error }
}

// All three call forms work:
// useFetch('/api/orders')
// useFetch(urlRef)
// useFetch(() => `/api/orders/${props.id}`)
```

`toValue()` called *outside* an effect reads once and tracks nothing — that is the bug this pattern
exists to avoid.

### Outputs: always a plain object of refs

Vue's own convention: composables return a plain, non-reactive object containing refs, so the caller
can destructure and keep reactivity. Returning a `reactive()` object breaks destructuring in the
caller.

```js
// Right
const { keyword, status, reset } = useOrderFilters()
const filtered = useOrderFilters()          // keep the object when you want namespacing
const ordered = reactive(useOrderFilters()) // or unwrap refs deliberately
```

## The contract an extracted composable must satisfy

An extracted unit is a small module with a public API. Hold it to the same standard as a component:

1. **Named `useXxx`** (the official convention), file named after the export.
2. **Called only in `setup()` / `<script setup>`, and synchronously.** These are the only contexts
   where Vue can determine the active instance, which is required to register lifecycle hooks and
   to dispose watchers on unmount. `<script setup>` is the one place you may call one *after* an
   `await`, because the compiler restores the instance context.
3. **Owns its cleanup.** Anything it creates — timers, listeners, observers, subscriptions, in-flight
   requests — is released by the composable itself, not by its caller.
4. **SSR-safe.** DOM access happens in `onMounted` (or later), never in the composable body, so a
   server render does not touch `window`.
5. **No hidden globals.** It reads no module-level mutable state and writes no global. If two calls
   need to share state, that state is a store — not a module-scope `ref`.
6. **Returns refs, not values.** A returned plain value is frozen at call time and silently wrong.
7. **Explicit inputs.** No reaching into a component, no `provide`/`inject` inside unless the
   composable is deliberately the reader for a provided context.
8. **Reusable in isolation.** If it needs a template, it is a component.
9. **Documented with JSDoc** — inputs, outputs, and whether the inputs may be refs or getters.

For state that must not be mutated from outside, return `readonly()` and expose explicit actions:

```js
import { computed, readonly, ref } from 'vue'

export function useCart() {
  const items = ref([])
  const total = computed(() => items.value.reduce((sum, i) => sum + i.price * i.quantity, 0))

  function addItem(product, quantity = 1) { /* … */ }
  function removeItem(productId) { /* … */ }

  // Callers can read; only the composable's own actions can write.
  return { items: readonly(items), total, addItem, removeItem }
}
```

## Worked example

A view that does four things, before and after.

```vue
<!-- BEFORE: ~180 lines of script, four concerns, untestable without mounting -->
<script setup>
import { computed, onMounted, ref, watch } from 'vue'
import { formatCurrency } from '@/lib/formatters'

const orders = ref([])
const loading = ref(false)
const error = ref(null)
const keyword = ref('')
const status = ref('all')
const selectedId = ref(null)
const isModalOpen = ref(false)

const visible = computed(() => orders.value
  .filter((o) => status.value === 'all' || o.status === status.value)
  .filter((o) => o.customer.toLowerCase().includes(keyword.value.trim().toLowerCase())))

const selected = computed(() => orders.value.find((o) => o.id === selectedId.value) ?? null)
const totalLabel = computed(() => formatCurrency(visible.value.reduce((sum, o) => sum + o.total, 0)))

function openModal(id) { selectedId.value = id; isModalOpen.value = true }
function closeModal() { isModalOpen.value = false }

async function load() {
  loading.value = true
  error.value = null
  try {
    const response = await fetch('/api/orders')
    orders.value = await response.json()
  } catch (cause) {
    error.value = cause
  } finally {
    loading.value = false
  }
}

watch(keyword, () => { /* debounce a search later */ })
onMounted(load)
</script>
```

```vue
<!-- AFTER: the view declares which concerns it uses; each concern is testable alone -->
<script setup>
import { useOrders } from '../composables/useOrders.js'
import { useOrderFilters } from '../composables/useOrderFilters.js'
import { useOrderSelection } from '../composables/useOrderSelection.js'
import { useCurrencyTotal } from '../composables/useCurrencyTotal.js'

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

The component's template did not change at all. That is the sign of a clean extraction.

## Over-extraction — the failure modes

| Anti-pattern | Why it is worse than not splitting | Fix |
| --- | --- | --- |
| `useUtils()`, `useHelpers()`, `useCommon()` | A grab-bag that becomes a second god object and re-couples everything | Split by concern, or make them plain `lib/` functions |
| A composable per one-line `computed` | Adds a file, an import, and an indirection for no reduction in complexity | Leave it in the component |
| `useOrderList()` — the whole script renamed | No seam was found; the file count went up and clarity went down | Apply the naming test; find the real concerns |
| Composable that takes `emit` or a component ref | It is a component concern; it will only ever work in one place | Keep it in the component, or make it a child component |
| Composable with 6+ positional parameters | The interface is harder to read than the code was | One options object, *and* reconsider the seam |
| Composable that reads module-level mutable state | Hidden singleton; two call sites silently share state; tests interfere | A store, or make it a parameter |
| `lib/` module importing `vue` | Destroys the framework-free layer | Move it to `composables/` |
| Splitting data fetching and its error handling | The error state has no owner | One composable or service per resource owns both |
| Extracting the template into a composable via a render function | Composables do not render | A component |
| One file exporting several unrelated `useXxx` | Filename lies; imports pull in code you did not want | One concern per file |

## Checklist

Before finishing an extraction, confirm:

- [ ] The concern has a name that is not a restatement of the component's name.
- [ ] It went to the right destination — plain module, composable, store, service, or component.
- [ ] `lib/` files still do not import `vue`.
- [ ] The composable owns the cleanup for everything it creates.
- [ ] It is called synchronously in `<script setup>` (or `setup()`).
- [ ] Inputs accept refs/getters/values and normalize with `toValue()` inside an effect.
- [ ] It returns a plain object of refs.
- [ ] The component's template is unchanged.
- [ ] The extraction did not simply move the problem: the component's script is shorter *and*
      easier to summarize.
- [ ] Tests were added for the extracted logic — this is the payoff that justified the split.
