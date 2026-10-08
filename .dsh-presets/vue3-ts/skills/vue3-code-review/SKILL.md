---
name: vue3-code-review
description: >-
  Severity-tagged review checklist for Vue 3 + TypeScript: reactivity correctness (destructuring,
  prop mutation, watch cleanup), component contract violations, type-safety findings (`any`,
  unchecked `as`, non-null assertions, unvalidated boundary data), resource leaks, performance,
  accessibility, security, and structure. Use when reviewing, refactoring, or debugging Vue
  components, when a UI misbehaves or stops updating, or when asked to review a diff or pull
  request.
---

# Vue 3 Code Review Checklist

Apply the requirements from `vue3-code-design` (structure, contracts, state placement),
`vue3-language-spec` (syntax, typing, naming, formatting, comments), and `vue3-script-splitting`
(whether a script should have been split). This skill is the ordered procedure and the failure
catalogue.

## How to review

Review in this order. A later pass on broken reactivity is wasted work.

0. **Gates first.** `npm run type-check` (`vue-tsc --build`), `npm run lint`, and
   `npm run format:check` must pass. Vitest strips types without checking them, so a green test run
   says nothing about `vue-tsc` — run the type gate yourself rather than assuming CI did.
1. **Correctness** — does it do what it claims? Read the diff against the requirement.
2. **Reactivity** — will the UI actually update? This is where Vue bugs live (§1).
3. **Lifecycle** — does anything outlive its component? (§2)
4. **Contract** — are props, emits, models, and slots honest? (§3)
5. **Type safety** — is the boundary typed, or asserted? (§4)
6. **Structure** — is it in the right place and the right size? (§5)
7. **Performance** — is anything quadratic, deep, or unmemoized? (§6)
8. **Accessibility and security** — (§7, §8)
9. **Style** — naming, formatting, comments. Prettier and ESLint already cover most of it; do not
   spend review attention on whitespace.

Report findings as a list, ordered by severity. For each: what is wrong, **why it breaks** (the
concrete failure, not the rule number), and the minimal fix. Do not rewrite files the user did not
ask you to rewrite, and do not report a style nit as a bug.

| Severity | Meaning |
| --- | --- |
| **Blocker** | Produces wrong output, crashes, or leaks. Must be fixed before merge. |
| **Major** | Works today, breaks on the next change. Fix in this change. |
| **Minor** | Maintainability or clarity. Fix or file it. |
| **Nit** | Preference. Mention once, do not press. |

## 1. Reactivity correctness

The single highest-yield pass. Every item below is a real, common failure.

| Symptom | Cause | Fix |
| --- | --- | --- |
| UI never updates after a change | `reactive()` object was destructured: `const { count } = state` | Read through the object (`state.count`), or declare with `ref` and `toRefs` |
| UI never updates after a change | A `reactive` object was replaced wholesale (`state = {...}` loses the proxy binding) | Mutate fields, or use `ref` and assign `.value` |
| UI never updates after a change | A ref was passed into a helper that reads it as a value: `isEqual(a, b)` inside `computed` | Normalize with `toValue(a)` inside the computed so the read is tracked |
| UI never updates after a change | `shallowRef` used for state whose nested fields change | `ref`, or replace the whole value deliberately |
| Child shows stale data | Prop object mutated in place (`props.items.push(x)`) | Emit; let the owner replace the array (`items.value = [...items.value, x]`) |
| Computed never recomputes | It reads a non-reactive source: `Date.now()`, a module-level plain variable, `route.params` captured once | Wrap the source in `ref`/`computed`; use `useRoute()` inside the computed |
| `watch` never fires | Source is a non-reactive value or a getter that reads nothing reactive | Watch a `computed`, a ref, or a `() => obj.field` getter |
| Infinite loop / stack overflow | A watcher mutates the state it watches | Guard the write, or convert the derivation to `computed` |
| Async `watch` writes after the source changed again | No cancellation; the older request resolved last | `AbortController` + `onWatcherCleanup` (3.5+) |
| `watchEffect` misses dependencies | Reads happen **after** an `await` — dependencies are only collected before the first await | Read reactive sources before awaiting, or use `watch` with explicit sources |
| Template shows an old value for one frame | DOM read right after a state write | `await nextTick()` before reading/measuring the DOM |
| Props destructure loses reactivity | Vue < 3.5 — `const { x } = defineProps(...)` | Use `props.x`, or `toRefs`, or upgrade to 3.5+ |

Also flag:

- **`computed` with side effects.** A computed must be pure and synchronous. Writing to a ref,
  firing a request, or logging inside it runs at unpredictable times.
- **A `watch` used where `computed` belongs.** If the callback only assigns a derived value, it is
  a `computed`; the watcher adds a render pass and a chance to desynchronize.
- **`deep: true` on a large object.** Name what actually changed and watch a narrow `computed`.
- **`reactive` for a primitive-holding value.** `ref` is the right default; use `reactive` only for
  a group of related fields that is treated as one object and never reassigned.
- **A type annotation that made a reactivity bug invisible.** `toRefs` under
  `noUncheckedIndexedAccess`, or a hand-written return type that widened a `Ref<T>`, can hide the
  fact that a read is no longer tracked. Treat a widening annotation as a reactivity finding, not a
  style one.

## 2. Lifecycle and resource ownership

Every resource created must be destroyed by the same scope. Grep the diff for each pattern below.

| Pattern | Check |
| --- | --- |
| `setInterval` / `setTimeout` | Cleared in `onUnmounted`/`onScopeDispose`, or replaced by `useTimeout`-style helper |
| `addEventListener` | Removed with the same function reference; prefer `{ once: true }` where applicable |
| `IntersectionObserver` / `ResizeObserver` / `MutationObserver` | `disconnect()` on unmount |
| `fetch` in a watcher or on mount | Accepts and aborts an `AbortController`; no state write after unmount |
| Store or external subscription | Unsubscribed (usually the returned disposer, or `onScopeDispose`) |
| Event-bus / `mitt` listener | Off on unmount — and question whether a bus is needed at all |
| `watch` registered inside another `watch` or handler | The previous watcher's stop handle is stored and called, or the watcher is created once at setup |
| `document`/`window` listener for a keydown or resize | Registered in `onMounted`, removed in `onUnmounted`, and scoped to when it is needed (e.g. only while a modal is open) |
| `<KeepAlive>`d component | Uses `onActivated`/`onDeactivated` rather than `onMounted`/`onUnmounted` for per-visit work |
| `provide`d mutable value | Exposed as `readonly()`, which for a ref is typed `Readonly<Ref<T>>`, unless consumers are meant to write |

A component that registers a listener inside an event handler rather than in setup is a **Blocker**:
each invocation stacks another listener.

## 3. Component contract

- **Props are declared, not assumed.** In TypeScript that means a named `interface Props` and
  `defineProps<Props>()` — not an inline object literal, and not a local interface that re-declares
  a domain type already available for import.
- **A closed set is a union, not a validator.** `size?: 'sm' | 'md' | 'lg'` beats
  `validator: (v) => ['sm','md','lg'].includes(v)`; keep a validator only if the value arrives from
  a source the compiler cannot see (an attribute, a CMS payload).
- **Defaults are declared once.** Reactive props destructure (3.5+) for inline defaults;
  `withDefaults` on 3.4 and below — where the docs say a mutable reference default *should* be a
  factory (`tags: () => []`), because a literal array would be shared across every instance.
- **No prop is mutated** — including object and array props. Mutating `order.status` is a
  Blocker: it changes parent state without the parent knowing.
- **Every emitted event is declared and typed** in `defineEmits`; the tuple syntax
  (`{ select: [id: string] }`) types both the `emit(...)` call and the template listener. The array
  form (`defineEmits(['select'])`) leaves every payload `any` — a Major finding in TypeScript.
- **`v-model` is used only for genuine two-way presentation state**, and is declared with
  `defineModel<T>()` rather than a hand-written prop/emit pair. A `v-model` on domain data makes the
  child a writer of business state.
- **Emits carry the minimal payload** — an id, not the whole object; the parent owns the lookup.
- **Slots are declared with `defineSlots`** and checked before rendering their wrapper
  (`v-if="$slots.actions"`), so optional regions do not leave empty chrome.
- **A `provide`/`inject` key is an `InjectionKey<T>`** in its own module, paired with a throwing
  `useXxx()` reader. An untyped `Symbol` key forces an `as` at every consumer — see §4.
- **`defineExpose` exposes actions, never state**, and the exposed surface is what consumers read
  through `ComponentExposed<typeof Child>`.
- **`defineOptions({ name })`** is present for components reached through dynamic import, so
  devtools and `<KeepAlive :include>` can identify them.
- **`inheritAttrs`** is intentional. With multiple root nodes, `$attrs` is not applied
  automatically — bind it explicitly (`v-bind="$attrs"`) or acknowledge that it is dropped.
- **Base components import nothing domain-aware** — no store, no router, no api module, and no
  domain type.

## 4. Type safety

Types are a contract with the next person to change this file. Every item below trades that contract
for a moment of quiet from the compiler.

| Symptom | Cause | Fix |
| --- | --- | --- |
| A signature accepts anything | `any` in a parameter, return, or generic default | Name the real type; `unknown` plus narrowing if it is genuinely unknown |
| An error is suppressed | `@ts-ignore` (hides the line and every error after it) | Fix the type; if truly unavoidable, `// @ts-expect-error -- <reason>` on the exact next line |
| A wrong shape compiles | `as SomeType`, and especially `as unknown as SomeType` | Validate at the boundary and return a typed value from a parser |
| A crash on a nullable value | Non-null assertion `!` used to end the complaint | Narrow with a guard, early return, or `??`; keep `!` only for a proven invariant, with a comment saying what proves it |
| Payload is `any` in the handler or listener | `defineEmits(['select'])` array form | `defineEmits<{ select: [id: string] }>()` |
| Two names for one domain shape | A local `interface Props { order: { ... } }` restating `Order` | Import the domain type; the local interface holds only what differs |
| Every value is `any` and nothing is checked | `Record<string, any>` as a data shape | A real interface, or `Record<string, unknown>` plus narrowing at each use |
| Enums leak runtime code and narrow poorly | `enum` for a closed set | `as const` object + `keyof typeof`, or a union of string literals |
| `Object.keys()` is `string[]` and indexing fails | The compiler cannot infer the keys | Type the object, or iterate `Object.entries` with a typed record |
| Server data is trusted blindly | `JSON.parse(raw) as Order[]`, `await res.json() as Order` | Parse and validate (schema or hand-written guard), then return the typed value |
| `catch (cause)` is treated as `Error` | `catch` binds `unknown` under `strict` | Narrow with `cause instanceof Error` before reading `.message` |
| A composable's return type is wider than reality | A hand-written annotation, or `ref([])`/`ref(null)` without a generic | Let inference work; annotate the ref itself (`ref<Order[]>([])`, `ref<Order \| null>(null)`) |

Also flag:

- **A missing return type on an exported non-composable function.** Inference is fine for a
  composable, whose returned object is its API; an exported helper (`formatOrder`, `parseFilters`,
  an api function) should say what it returns, or a later edit silently widens it.
- **`as` inside a template or a computed to make a prop fit.** The mismatch is real; fix the prop
  type or narrow properly.
- **`@ts-expect-error` with no reason, or on a line that no longer errors.** An unused
  `@ts-expect-error` is itself an error under some configs and a lie in all of them.
- **A type assertion in a test that hides a production mismatch.** `as unknown as Order` in a spec
  means the fixture and the real shape have already diverged.
- **`any` in an event handler's parameter**, which silently disables checking for the whole
  handler body.
- **Optional chaining used to paper over a type that should have been non-optional** — or the
  reverse: a `?.` chain long enough to suggest the invariant is wrong.
- **`// eslint-disable` or a suppression comment with no reason.** Same rule as `@ts-expect-error`.

## 5. Structure

- **One component per file.** Two components in one `.vue` file is a Major finding: no devtools
  entry, no isolated test, no meaningful file name.
- **`<script setup lang="ts">` and Composition API only.** A `mixins` option, an Options API
  component, or a `lang="js"` script block in the diff is a Blocker for consistency: two mental
  models in one codebase.
- **The view orchestrates; it does not implement.** If a view's script owns fetching, filtering,
  formatting, and a modal, extract.
- **Size.** A `<template>` over ~150 lines, a `<script setup>` over ~200 lines, or a component with
  more than ~7 props is a signal to split — split along responsibility, not arbitrarily.
- **Feature-first placement.** A new global `components/` entry for something only one feature uses
  is misplaced. Cross-feature imports go through `features/<f>/index.ts`. A domain type used by two
  features belongs in `src/types/`, not duplicated in each.
- **`lib/` stays framework-free.** Any `import ... from 'vue'` in `lib/` is a Major finding.
- **State is on the lowest rung that works.** A Pinia store for state that dies with the route, or
  for a single component's UI flag, is a Major finding.
- **`provide`/`inject` uses an `InjectionKey<T>`** and ships with a throwing `useXxx()` reader. A
  bare `Symbol` key is a Major finding in TypeScript — it forces a cast at every consumer.
- **No prop drilling through three or more layers** — that is `provide`/`inject` or a store.
- **No barrel files inside a feature** other than `index.ts`, and no `export *` that hides what a
  module offers.

## 6. Performance

- **Lists over a few hundred rows are virtualized**, not merely `v-if`-filtered.
- **`:key` is a stable domain id.** Index keys on a reorderable or filterable list are a Major
  finding: they reuse the wrong component instance and its local state.
- **No new object/array literal passed as a prop in a template** (`:config="{ a: 1 }"`,
  `:items="orders.filter(...)"`). Each render creates a new identity, defeating memoization and
  invalidating child props. Hoist to a `computed` or a module constant — and type that constant, so
  the hoisted object keeps the prop's type.
- **`computed` is not doing O(n²) work** inside a render path, and is not re-sorting on every access
  when the sort order did not change.
- **`watch` is not `deep` on a large tree**, and does not fire per keystroke without debouncing.
- **`v-if` vs `v-show` chosen deliberately**: `v-if` for rarely shown expensive subtrees,
  `v-show` for frequently toggled cheap ones.
- **Route components are lazily imported**; heavy widgets (editors, charts, maps) use
  `defineAsyncComponent`.
- **Third-party instances are `markRaw`ed** so Vue does not make a chart or map deeply reactive.
- **Large immutable data uses `shallowRef`** (typed `ShallowRef<T>`).
- **Imports are narrow.** `import { debounce } from 'lodash-es'`, never `import _ from 'lodash'`;
  no whole-library imports for one helper.
- **Type-only imports use `import type`.** A plain `import` of a type used only in annotations is a
  Major finding under `verbatimModuleSyntax`: it fails the build, or drags a value module into the
  bundle for nothing.
- **`v-memo` on expensive repeated subtrees** in long lists, keyed by the fields that matter.
- **DOM measurement happens in `onMounted` or after `nextTick`**, never during setup.

## 7. Accessibility

| Check | Finding |
| --- | --- |
| Interactive element | `@click` on a `<div>`/`<span>` without `role`, `tabindex="0"`, and a keydown handler — use `<button>` |
| Form input | Every input has an associated `<label for>` or `aria-label` |
| Image | Every `<img>` has meaningful `alt` (or `alt=""` when decorative) |
| Async status | Loading and error states announced via `aria-live="polite"` / `role="status"` |
| Modal | Focus moves in on open, is trapped while open, and returns to the trigger on close; `Esc` closes |
| Icon-only button | Has an accessible name (`aria-label` or visually hidden text) |
| Color | State is not conveyed by color alone — add text or an icon |
| Heading order | `<h1>`–`<h6>` are sequential and not chosen for size |
| Keyboard | Every pointer interaction has a keyboard equivalent; focus is visible (`:focus-visible` styled) |

## 8. Security

- **`v-html` is a Blocker** unless the content is sanitized with DOMPurify at the boundary and a
  comment records why. The lint rule `vue/no-v-html` exists for this reason.
- **Never bind user input to `:href` / `:src` / `:action` unvalidated** — `javascript:` URLs
  execute. Allowlist the scheme.
- **`target="_blank"` requires `rel="noopener noreferrer"`** (or `noopener` alone for same-origin).
- **`innerHTML`, `outerHTML`, `insertAdjacentHTML`, and `document.write`** are banned; use the
  template or a text node.
- **No secrets in client code.** Anything bundled is public — API keys, tokens, internal URLs. Flag
  any credential reaching `src/`, including one read through `import.meta.env`.
- **Tokens in `localStorage` are XSS-exposed.** If they are there, confirm the app has no
  `v-html` and a strict CSP; prefer httpOnly cookies when the backend allows it.
- **Authentication is enforced server-side.** A route guard is UX, not security — flag any
  authorization decision made only in the client.
- **A type annotation is not validation.** `const body = (await res.json()) as LoginResponse` on a
  credential path is a security finding, not merely a §4 one.

## 9. Style and language

Delegated to `vue3-language-spec`; check only what tools do not catch.

- **`npm run type-check`, `npm run lint`, and `npm run format:check` pass.** If they do not, that is
  the first finding — and `vue-tsc` is the one a green Vitest run does not cover.
- **Naming** follows the convention table in the language spec — especially `handleXxx` for
  handlers, `onXxx` only for callback props, `is`/`has` prefixes on booleans, and no `_` prefixes.
  Type names are `PascalCase`; a props interface is `Props` inside its component and a descriptive
  name (`OrderContext`, `UseOrderFiltersOptions`) when exported.
- **`v-for` always has `:key`**, and `v-if` is never on the same element as `v-for`.
- **Template expressions are simple.** Anything with more than one operator belongs in a `computed`.
- **Comments** are present and explain *why*; TSDoc (`/** */` with `@param`, `@returns`,
  `@example`) on exported functions, composables, and non-obvious types; every `eslint-disable` and
  `@ts-expect-error` carries a reason; no commented-out code.
- **SFC block order** is `<script setup lang="ts">`, `<template>`, `<style>`, and macro order is
  `defineOptions`, `defineProps`, `defineEmits`, `defineModel`, `defineSlots`, with `defineExpose`
  last. The `interface Props` sits at the top of the script block, above the macros that use it.
- **No `console.log`** in committed code; `console.warn`/`console.error` are acceptable for real
  diagnostics.
- **No dead code**: unused imports, unused refs, unreachable branches, unused CSS classes, and
  exported types nothing imports.

## Review output

```
## Findings

**Blocker — src/features/cart/CartSummary.vue:42**
`items.push(next)` mutates the parent's array through the prop. The parent's `computed` never sees
the change and the total goes stale.
→ Emit `add`, and let the owner assign a new array: `items.value = [...items.value, next]`.

**Major — src/features/orders/orders.api.ts:18**
`return (await res.json()) as Order[]` asserts a shape nothing validated. A renamed server field
compiles cleanly and produces `undefined` totals at runtime.
→ Parse the payload into `Order[]` (a guard or a schema) and return the parsed value.

**Major — src/features/orders/views/OrderListView.vue:18**
The `watch` callback is `async` and starts a request per keystroke; the last response to arrive
wins, so the list can show results for a previous keyword.
→ Debounce the source, and abort the previous request with an `AbortController` released in
`onWatcherCleanup`.

**Minor — src/features/orders/components/OrderRow.vue:7**
`:config="{ compact: true }"` creates a new object each render, so `OrderRow` re-renders on every
parent update.
→ Hoist to a module constant typed as `RowConfig`.

**Minor — src/features/orders/stores/orders.ts:9**
`const items = ref([])` infers `Ref<never[]>`; the array cannot be filled without an edit here.
→ `ref<Order[]>([])`.

## Not changed
Everything else in the diff follows the design and style rules. `vue-tsc`, lint, and format all
pass.
```

Order findings by severity, cite `file:line`, and state the concrete failure. When a finding is a
judgment call rather than a defect, say so — do not dress a preference as a bug.
