---
name: vue3-code-review
description: >-
  A severity-tagged review checklist for Vue 3 code in plain JavaScript: reactivity correctness
  (reactive/ref destructuring, prop mutation, watch cleanup), component contract violations,
  resource leaks from timers, listeners, observers and in-flight requests, performance,
  accessibility, security (`v-html`, unsafe URLs), and structure. Use when reviewing, refactoring,
  or debugging Vue components, when a UI behaves unexpectedly or stops updating, or when asked to
  review a diff or pull request.
---

# Vue 3 Code Review Checklist

Apply the requirements from `vue3-code-design` (structure, contracts, state placement),
`vue3-language-spec` (syntax, naming, formatting, comments), and `vue3-script-splitting` (whether a
script should have been split). This skill is the ordered procedure and the failure catalogue.

## How to review

Review in this order. A later pass on broken reactivity is wasted work.

1. **Correctness** — does it do what it claims? Read the diff against the requirement.
2. **Reactivity** — will the UI actually update? This is where Vue bugs live (§1).
3. **Lifecycle** — does anything outlive its component? (§2)
4. **Contract** — are props, emits, models, and slots honest? (§3)
5. **Structure** — is it in the right place and the right size? (§4)
6. **Performance** — is anything quadratic, deep, or unmemoized? (§5)
7. **Accessibility and security** — (§6, §7)
8. **Style** — naming, formatting, comments. Prettier and ESLint already cover most of it; do not
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

## 2. Lifecycle and resource ownership

Every resource created must be destroyed by the same scope. Grep the diff for each pattern below.

| Pattern | Check |
| --- | --- |
| `setInterval` / `setTimeout` | Cleared in `onUnmounted`/`onScopeDispose`, or replaced by `useTimeout`-style helper |
| `addEventListener` | Removed with the same function reference; prefer `{ once: true }` where applicable |
| `IntersectionObserver` / `ResizeObserver` / `MutationObserver` | `disconnect()` on unmount |
| `fetch` in a watcher or on mount | Accepts and aborts an `AbortController`; no state write after unmount |
| Store or external subscription | Unsubscribed (usually `ctx.on`/`onScopeDispose` or the returned disposer) |
| Event-bus / `mitt` listener | Off on unmount — and question whether a bus is needed at all |
| `watch` registered inside another `watch` or handler | The previous watcher's stop handle is stored and called, or the watcher is created once at setup |
| `document`/`window` listener for a keydown or resize | Registered in `onMounted`, removed in `onUnmounted`, and scoped to when it is needed (e.g. only while a modal is open) |
| `<KeepAlive>`d component | Uses `onActivated`/`onDeactivated` rather than `onMounted`/`onUnmounted` for per-visit work |
| `provide`d mutable value | Exposed as `readonly()` unless consumers are meant to write |

A component that registers a listener inside an event handler rather than in setup is a **Blocker**:
each invocation stacks another listener.

## 3. Component contract

- **Props are declared, not assumed.** Object form with `type`; `required` or `default` for every
  prop; a `validator` for closed sets.
- **No prop is mutated** — including object and array props. Mutating `props.order.status` is a
  Blocker: it changes parent state without the parent knowing.
- **Every emitted event is declared** in `defineEmits`; payloads match what the parent listens for.
  An undeclared emit is invisible to devtools and to reviewers.
- **`v-model` is used only for genuine two-way presentation state.** A `v-model` on domain data
  makes the child a writer of business state.
- **Emits carry the minimal payload** — an id, not the whole object; the parent owns the lookup.
- **Slots are checked before rendering their wrapper** (`v-if="$slots.actions"`), so optional
  regions do not leave empty chrome.
- **`defineExpose` exposes actions, never state.** Reading child state from a parent is a design
  failure; lift the state or emit.
- **`defineOptions({ name })`** is present for components reached through dynamic import, so
  devtools and `<KeepAlive :include>` can identify them.
- **`inheritAttrs`** is intentional. With multiple root nodes, `$attrs` is not applied
  automatically — bind it explicitly (`v-bind="$attrs"`) or acknowledge that it is dropped.
- **Base components import nothing domain-aware** — no store, no router, no api module.

## 4. Structure

- **One component per file.** Two components in one `.vue` file is a Major finding: no devtools
  entry, no isolated test, no meaningful file name.
- **`<script setup>` and Composition API only.** A `mixins` option or an Options API component in
  the diff is a Blocker for consistency: two mental models in one codebase.
- **The view orchestrates; it does not implement.** If a view's script owns fetching, filtering,
  formatting, and a modal, extract.
- **Size.** A `<template>` over ~150 lines, a `<script setup>` over ~200 lines, or a component with
  more than ~7 props is a signal to split — split along responsibility, not arbitrarily.
- **Feature-first placement.** A new global `components/` entry for something only one feature uses
  is misplaced. Cross-feature imports go through `features/<f>/index.js`.
- **`lib/` stays framework-free.** Any `import ... from 'vue'` in `lib/` is a Major finding.
- **State is on the lowest rung that works.** A Pinia store for state that dies with the route, or
  for a single component's UI flag, is a Major finding.
- **`provide`/`inject` uses a `Symbol` key** and ships with a throwing `useXxx()` reader.
- **No prop drilling through three or more layers** — that is `provide`/`inject` or a store.
- **No barrel files inside a feature** other than `index.js`, and no `export *` that hides what a
  module offers.

## 5. Performance

- **Lists over a few hundred rows are virtualized**, not merely `v-if`-filtered.
- **`:key` is a stable domain id.** Index keys on a reorderable or filterable list are a Major
  finding: they reuse the wrong component instance and its local state.
- **No new object/array literal passed as a prop in a template** (`:config="{ a: 1 }"`,
  `:items="orders.filter(...)"`). Each render creates a new identity, defeating memoization and
  invalidating child props. Hoist to a `computed` or a module constant.
- **`computed` is not doing O(n²) work** inside a render path, and is not re-sorting on every access
  when the sort order did not change.
- **`watch` is not `deep` on a large tree**, and does not fire per keystroke without debouncing.
- **`v-if` vs `v-show` chosen deliberately**: `v-if` for rarely shown expensive subtrees,
  `v-show` for frequently toggled cheap ones.
- **Route components are lazily imported**; heavy widgets (editors, charts, maps) use
  `defineAsyncComponent`. See `vue3-lazy-loading` for the full rules.
- **Nothing above the fold is deferred.** An async component or a dynamic import in the first paint
  is a Major finding: it makes Largest Contentful Paint worse, not better.
- **Every `defineAsyncComponent` has an `errorComponent`** and a `delay`. Without the error
  component a failed load becomes an unhandled error and the wrapper stays on its loading component
  indefinitely — it renders nothing at all only when no `loadingComponent` was given either; without
  the delay the loading state flashes on fast connections.
- **`import.meta.glob` is not `eager: true`** unless every match really belongs in the current
  chunk — that flag silently cancels the lazy load.
- **No dynamic import inside a template expression or a render path.** It is re-created on every
  render and can re-fetch.
- **A UI library is not installed whole.** `app.use(ElementPlus)` plus
  `import 'element-plus/dist/index.css'` ships every component and the full stylesheet; flag it as a
  Blocker for bundle size.
- **`webpackChunkName` comments do nothing here** — Vite and Rolldown document no equivalent of
  webpack's magic comments. Name chunks through the build config instead, and check the Vite major:
  Vite 8 uses `build.rolldownOptions.output.codeSplitting`, Vite 5–7 use
  `build.rollupOptions.output.manualChunks` (whose **object** form is removed in 8).
- **Third-party instances are `markRaw`ed** so Vue does not make a chart or map deeply reactive.
- **Large immutable data uses `shallowRef`**.
- **Imports are narrow.** `import { debounce } from 'lodash-es'`, never `import _ from 'lodash'`;
  no whole-library imports for one helper.
- **`v-memo` on expensive repeated subtrees** in long lists, keyed by the fields that matter.
- **DOM measurement happens in `onMounted` or after `nextTick`**, never during setup.

## 6. Accessibility

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

## 7. Security

- **`v-html` is a Blocker** unless the content is sanitized with DOMPurify at the boundary and a
  comment records why. The lint rule `vue/no-v-html` exists for this reason.
- **Never bind user input to `:href` / `:src` / `:action` unvalidated** — `javascript:` URLs
  execute. Allowlist the scheme.
- **`target="_blank"` requires `rel="noopener noreferrer"`** (or `noopener` alone for same-origin).
- **`innerHTML`, `outerHTML`, `insertAdjacentHTML`, and `document.write`** are banned; use the
  template or a text node.
- **No secrets in client code.** Anything bundled is public — API keys, tokens, internal URLs. Flag
  any credential reaching `src/`.
- **Tokens in `localStorage` are XSS-exposed.** If they are there, confirm the app has no
  `v-html` and a strict CSP; prefer httpOnly cookies when the backend allows it.
- **Authentication is enforced server-side.** A route guard is UX, not security — flag any
  authorization decision made only in the client.

## 8. Style and language

Delegated to `vue3-language-spec`; check only what tools do not catch.

- **`npm run lint` and `npm run format:check` pass.** If they do not, that is the first finding.
- **Naming** follows the convention table in the language spec — especially `handleXxx` for
  handlers, `onXxx` only for callback props, `is`/`has` prefixes on booleans, and no `_` prefixes.
- **`v-for` always has `:key`**, and `v-if` is never on the same element as `v-for`.
- **Template expressions are simple.** Anything with more than one operator belongs in a `computed`.
- **Comments** are present and explain *why*; JSDoc on exported functions and composables; every
  `eslint-disable` carries a reason; no commented-out code.
- **SFC block order** is `<script setup>`, `<template>`, `<style>`, and macro order is
  `defineOptions`, `defineProps`, `defineEmits`, `defineModel`, `defineSlots`, with `defineExpose`
  last.
- **No `console.log`** in committed code; `console.warn`/`console.error` are acceptable for real
  diagnostics.
- **No dead code**: unused imports, unused refs, unreachable branches, unused CSS classes.

## Review output

```
## Findings

**Blocker — src/features/cart/CartSummary.vue:42**
`props.items.push(next)` mutates the parent's array through the prop. The parent's `computed`
never sees the change and the total goes stale.
→ Emit `add`, and let the owner assign a new array: `items.value = [...items.value, next]`.

**Major — src/features/orders/views/OrderListView.vue:18**
`watch` callback is `async` and starts a request per keystroke; the last response to arrive wins,
so the list can show results for a previous keyword.
→ Debounce the source, and abort the previous request with an `AbortController` released in
`onWatcherCleanup`.

**Minor — src/features/orders/components/OrderRow.vue:7**
`:config="{ compact: true }"` creates a new object each render, so `OrderRow` re-renders on every
parent update.
→ Hoist to a module constant.

## Not changed
Everything else in the diff follows the design and style rules. Lint and format both pass.
```

Order findings by severity, cite `file:line`, and state the concrete failure. When a finding is a
judgment call rather than a defect, say so — do not dress a preference as a bug.
