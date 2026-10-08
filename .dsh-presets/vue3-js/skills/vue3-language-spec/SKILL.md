---
name: vue3-language-spec
description: >-
  JavaScript coding standards for a Vue 3 project: the official Vue style guide priorities A–D,
  ES2022+ and ESM rules, naming conventions, Prettier formatting, a copy-ready ESLint flat config
  for eslint-plugin-vue, SFC block and attribute ordering, import ordering, modern syntax, async and
  error handling, and JSDoc. Use when writing or formatting JavaScript, SFCs, templates or CSS,
  when setting up ESLint/Prettier, or when the user asks about coding standards, naming, or
  linting.
---

# JavaScript Language and Coding Standards (Vue 3, plain JS)

Companion skills: `vue3-code-design` (structure and component contracts),
`vue3-script-splitting` (when to extract code into another file), `vue3-code-review` (the checklist).

**This project is plain JavaScript.** Do not add TypeScript syntax — no type annotations, no
`interface`, no `as`, no `enum`, no `satisfies`, no `<script setup lang="ts">`. Types are expressed
in JSDoc when a contract is non-obvious, and validated at the boundary (prop validators, API
response parsing). If the user explicitly asks for TypeScript, that is a project-wide decision —
confirm before mixing, and prefer the TypeScript preset instead.

## The official style guide, at a glance

Vue publishes a four-tier style guide. Rule names below are the official ones; the whole list is
authoritative and this project adopts it.

**Priority A — Essential (error prevention). Must always hold.**

| Rule | What it mandates |
| --- | --- |
| Use multi-word component names | Component names are always multi-word, except the root `App`. |
| Use detailed prop definitions | Every prop declares at least its type(s); `required`/`validator` where meaningful. |
| Use keyed `v-for` | A `key` with `v-for` is always required on components, and best practice on elements. |
| Avoid `v-if` with `v-for` | Never on the same element; filter in a `computed` or wrap in `<template v-for>`. |
| Use component-scoped styling | Every component's styles are scoped (or module/library-based); only top-level app styles may be global. |

**Priority B — Strongly Recommended. Violations must be rare and justified.**

| Rule | What it mandates |
| --- | --- |
| Component files | One component per file whenever a build step can concatenate files. |
| SFC filename casing | Filenames are always PascalCase or always kebab-case — never a mix. |
| Base component names | Base/presentational components use an app-specific prefix (`Base`, `App`, `V`). |
| Tightly coupled component names | A child that only makes sense under one parent carries the parent's name as prefix. |
| Order of words in component names | Start with the highest-level, most general word and end with descriptive modifiers. |
| Self-closing components | Content-less components self-close in SFCs; never in in-DOM templates. |
| Component name casing in templates | PascalCase in SFC templates, kebab-case in in-DOM templates. |
| Component name casing in JS/JSX | PascalCase in JS/JSX. |
| Full-word component names | Prefer full words over abbreviations. |
| Prop name casing | Declare camelCase; kebab-case only in in-DOM templates. |
| Multi-attribute elements | One attribute per line once an element has several. |
| Simple expressions in templates | Only simple expressions in templates; the rest moves to `computed`. |
| Simple computed properties | Split a complex `computed` into as many simple ones as the logic needs. |
| Quoted attribute values | Non-empty attribute values are always quoted. |
| Directive shorthands | `:`, `@`, `#` used always or never — never a mix. |

**Priority C — Recommended. Pick one and be consistent; this project's choices are in the sections
below.**

| Rule | This project's choice |
| --- | --- |
| Component/instance options order | Not applicable — `<script setup>` only. Inside the script, use the documented order in *SFC style* below. |
| Element attribute order | The official 10-group order, listed in *SFC style*. |
| Empty lines in component/instance options | One blank line between multi-line groups, once the script stops fitting on a screen. |
| SFC top-level element order | `<script>`, `<template>`, `<style>` — `<style>` last. |

**Priority D — Use with Caution.**

| Rule | What it mandates |
| --- | --- |
| Element selectors with `scoped` | Avoid element selectors in `scoped` styles; use classes (element selectors are slow). |
| Implicit parent-child communication | Props down / events up — never `$parent`, never mutating a prop. |

The style guide deliberately says nothing about semicolons, quotes, or trailing commas. Prettier
decides those (below), and they are not review topics.

## Language baseline

| Item | Value |
| --- | --- |
| ECMAScript | ES2022 or newer (`ecmaVersion: 'latest'`) |
| Modules | ESM only — `import`/`export`. No `require`, no `module.exports` |
| Target | Evergreen browsers, as configured by Vite's default build target |
| Runtime deps | Use what is already in `package.json`; do not add a dependency for something the platform provides |

## Naming

| Thing | Convention | Example |
| --- | --- | --- |
| Component file | `PascalCase.vue` | `OrderSummary.vue` |
| Component in script/template | `PascalCase`, multi-word | `<OrderSummary />` |
| View (route) component | `PascalCase` + `View` suffix | `OrderListView.vue` |
| Base component | `Base` prefix | `BaseButton.vue` |
| Child coupled to one parent | Parent name as prefix | `OrderListRow.vue`, `OrderListItem.vue` |
| Composable | `use` + `PascalCase`, file `useXxx.js` | `useOrderFilters.js` → `useOrderFilters()` |
| Pinia store | `useXxxStore`, file `xxx.js` | `stores/orders.js` → `useOrdersStore()` |
| Feature API module | `<feature>.api.js` | `orders.api.js` |
| Variables, functions, props | `camelCase` | `orderTotal`, `loadOrders()` |
| Booleans | `is` / `has` / `should` / `can` prefix | `isLoading`, `hasMore`, `canSubmit` |
| Event handler function | `handle` + `Event` | `handleSubmit`, `handleRowClick` |
| Callback **prop** | `on` + `Event` | `onSelect`, `onClose` |
| Emitted event (script) | `camelCase` | `emit('orderShipped')` |
| Emitted event (template) | `kebab-case` | `@order-shipped="..."` |
| Props in template | `kebab-case` | `:order-total="total"` |
| True constants (module scope) | `UPPER_SNAKE_CASE` | `MAX_RETRY_COUNT`, `API_BASE_URL` |
| Injection key | `XxxKey` Symbol | `const OrderContextKey = Symbol('order-context')` |
| CSS class | `kebab-case` | `.order-list__item` |
| Route `name` | `kebab-case` | `name: 'order-list'` |
| JS module file | `kebab-case` | `format-currency.js` |
| Test file | `<subject>.spec.js` in `__tests__/` | `useOrderFilters.spec.js` |

Rules that follow from the table:

- **Component names are multi-word and general-word-first.** `SearchButtonClear` reads correctly;
  `ClearSearchButton` does not. The name goes from the most general word to the most specific.
- **No underscore prefixes** for "private" members. Module-level privacy is what non-export does;
  a leading `_` on a parameter means "intentionally unused" and nothing else.
- **Name by role, not by type.** `orders` not `ordersArray`; `visibleOrders` not `filteredList`.
- **No single-letter names** except `i`/`j` loop indices in a three-line loop and `e` in a
  one-line catch. Use `error`.
- **No abbreviations** the domain does not already use. `order` not `ord`, `quantity` not `qty`,
  `configuration` may be `config` (universal). This applies to component names too.
- **Files and directories are `kebab-case`**, except `.vue` components, which are `PascalCase`
  everywhere in this project — never kebab-case in one place and PascalCase in another.

## Formatting — Prettier owns it

Formatting is not a review topic. Prettier decides, and `.prettierrc.json` is the single source.

```json
{
  "$schema": "https://json.schemastore.org/prettierrc",
  "semi": false,
  "singleQuote": true,
  "printWidth": 100,
  "trailingComma": "all",
  "arrowParens": "always",
  "endOfLine": "lf"
}
```

`.editorconfig` alongside it:

```ini
root = true

[*]
charset = utf-8
end_of_line = lf
indent_style = space
indent_size = 2
insert_final_newline = true
trim_trailing_whitespace = true
```

Consequences to accept rather than fight: no semicolons, single quotes, 100-column lines, trailing
commas everywhere, and `(arg) =>` even for a single argument. Never hand-align, never hand-wrap —
run `npm run format`.

## Linting — ESLint flat config

`eslint-plugin-vue` requires ESLint `^8.57.0 || ^9.0.0 || ^10.0.0` and Node
`^18.18.0 || ^20.9.0 || >=21.1.0`. Its flat configs are **arrays**, so they must be spread.

```js
// eslint.config.js
import js from '@eslint/js'
import pluginVue from 'eslint-plugin-vue'
import globals from 'globals'
import prettier from 'eslint-config-prettier/flat'

export default [
  { ignores: ['dist/**', 'coverage/**', 'node_modules/**'] },

  js.configs.recommended,
  ...pluginVue.configs['flat/recommended'],

  {
    files: ['**/*.{js,vue}'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: { ...globals.browser },
    },
    rules: {
      // ── language ────────────────────────────────────────────────────────
      'no-var': 'error',
      'prefer-const': 'error',
      'object-shorthand': ['error', 'always'],
      'prefer-template': 'error',
      'no-param-reassign': ['error', { props: false }],
      'no-return-await': 'error',
      'require-await': 'error',
      'no-console': ['warn', { allow: ['warn', 'error'] }],
      'no-unused-vars': ['error', { argsIgnorePattern: '^_', varsIgnorePattern: '^_' }],
      eqeqeq: ['error', 'always', { null: 'ignore' }],

      // ── Vue: enforce this project's style-guide choices ──────────────────
      'vue/component-api-style': ['error', ['script-setup']],
      'vue/block-order': ['error', { order: ['script', 'template', 'style'] }],
      'vue/define-macros-order': [
        'error',
        { order: ['defineOptions', 'defineProps', 'defineEmits', 'defineSlots'], defineExposeLast: true },
      ],
      'vue/component-name-in-template-casing': ['error', 'PascalCase'],
      'vue/v-bind-style': ['error', 'shorthand'],
      'vue/v-on-style': ['error', 'shorthand'],
      'vue/v-slot-style': ['error', 'shorthand'],
      'vue/multi-word-component-names': 'error',
      'vue/no-v-html': 'error',
      'vue/require-explicit-emits': 'error',
      'vue/no-unused-refs': 'error',
      'vue/prefer-true-attribute-shorthand': 'error',

      // ── size tripwires (opt-in: neither preset enables these) ────────────
      // A `warn` here means "go find the concern", not "cut the file in half".
      'vue/max-lines-per-block': [
        'warn',
        { script: 200, template: 150, skipBlankLines: true },
      ],
    },
  },

  // Node-context config files get Node globals instead of browser globals.
  {
    files: ['*.config.js', 'vite.config.js'],
    languageOptions: { globals: { ...globals.node } },
  },

  // Test files: Vitest globals.
  {
    files: ['src/**/*.spec.js'],
    languageOptions: { globals: { ...globals.node, ...globals.vitest } },
  },

  // Must stay last: turns off every rule Prettier already handles.
  prettier,
]
```

Notes on the config:

- `pluginVue.configs['flat/recommended']` is `strongly-recommended` plus the community defaults, and
  it arrives as an **array**, so it must be spread. Its severity is tiered: Priority A rules come in
  as `error`, Priority B/C rules as **`warn`**. Use `flat/recommended-error` if you want every rule
  at `error` instead of `warn`.
- **Nine of the `vue/*` rules configured above are opt-in.** `component-api-style`, `block-lang`,
  `define-macros-order`, `component-name-in-template-casing`, `no-unused-refs`,
  `prefer-true-attribute-shorthand`, `max-lines-per-block`, `enforce-style-attribute`, and
  `new-line-between-multi-line-property` are in no preset, so they only take effect because this
  config names them explicitly. `max-lines-per-block` in particular has **no defaults** — a block
  type you do not give a number is simply unenforced.
- **Import Prettier's config from its `/flat` subpath**: `eslint-config-prettier/flat`. The package
  root still works in an array but is rules-only and carries no `name`; `/flat` is the documented
  flat-config entry point. Either way it must be **last** — it only turns rules off.
- If you use an auto-import plugin, declare the imported Vue APIs as globals
  (`{ ref: 'readonly', computed: 'readonly', … }`) so rules like `vue/no-ref-as-operand` still work.
- `npm run lint` must pass with zero errors before work is considered done. Warnings are acceptable
  only for `no-console` and `vue/max-lines-per-block`.

```json
"scripts": {
  "dev": "vite",
  "build": "vite build",
  "preview": "vite preview",
  "lint": "eslint . --fix",
  "format": "prettier --write --cache src/",
  "format:check": "prettier --check src/",
  "test": "vitest run",
  "test:watch": "vitest"
}
```

## Syntax: prefer and avoid

| Prefer | Avoid | Why |
| --- | --- | --- |
| `const` by default, `let` when reassigned | `var` | `var` hoists and leaks out of blocks |
| `===` / `!==` | `==` / `!=` (except `== null`) | Coercion is a bug source; `== null` catches both null and undefined |
| `a?.b`, `a?.[i]`, `fn?.()` | `a && a.b && a.b.c` | Intent explicit, short-circuits nested access |
| `value ?? fallback` | `value \|\| fallback` | `\|\|` also replaces `0`, `''`, and `false` |
| `structuredClone(obj)` | `JSON.parse(JSON.stringify(obj))` | Loses `Date`, `Map`, `undefined`, and is slow |
| `Object.entries` / `Object.fromEntries` | `for...in` | `for...in` walks the prototype chain |
| `Array.isArray(x)` | `typeof x === 'object'` | Arrays are objects |
| `.at(-1)` | `.length - 1` index math | Reads better |
| `Array.prototype.toSorted` / `toReversed` (ES2023) | in-place `sort`/`reverse` on shared state | Never mutate a prop or store array in place |
| `#private` class fields | `this._private` | Real encapsulation, if a class is warranted |
| `Object.hasOwn(obj, key)` | `obj.hasOwnProperty(key)` | Works on null-prototype objects |
| Optional catch binding `catch {}` | `catch (e) {}` with unused `e` | Says nothing is needed |

**Banned outright:** `eval`, `new Function`, `with`, `arguments`, `debugger`, modifying built-in
prototypes, `document.write`, `innerHTML` assignment, and mutating an array or object that arrived
as a prop or came out of a store.

**Use a class only when there is identity plus behavior** to encapsulate (a parser, a client with
config, a state machine). Everything else is a function or a factory — this codebase is
function-first.

## Modules and imports

Import order, grouped with a blank line between groups, alphabetized inside a group:

1. `vue` core (`vue`, `vue-router`, `pinia`)
2. third-party packages
3. internal absolute alias (`@/…`)
4. relative parent (`../…`)
5. relative sibling (`./…`)
6. bare side-effect imports (`import './styles/main.css'`) — last

```js
import { computed, ref, watch } from 'vue'
import { useRoute } from 'vue-router'

import { formatCurrency } from '@/lib/format-currency'
import { useOrdersStore } from '@/features/orders'

import { useOrderFilters } from '../composables/useOrderFilters'

import './order-list.css'
```

- **Named exports for everything except a `.vue` SFC's implicit default.** `export function foo()`,
  never `export default function`. Named exports are rename-safe and greppable.
- **`@/` is the alias for `src/`** (already configured in `vite.config.js`). Use it for anything
  more than one directory up; use `./` and `../` within a feature.
- **Always include the `.js` extension in relative imports** (`'./useOrderFilters.js'`), and the
  SFC extension in component imports when imported from script.
- **No circular imports.** If `a.js` and `b.js` need each other, the shared piece belongs in a
  third module.

## Functions and control flow

- **Small and single-purpose.** Extract when a function needs a comment to explain a section.
  Roughly: over ~40 lines, or more than three levels of nesting, is too much.
- **Early returns over nested `if`.** Guard clauses first, happy path last, minimum indentation.
- **Maximum three parameters.** Beyond that, take one options object and destructure it.
- **Pure by default.** A function that computes returns; a function that mutates says so in its
  name (`applyFilters`, `resetForm`).
- **No boolean parameters.** `createOrder(true)` is unreadable — use an options object.
- **Prefer `for...of` over `forEach`** when you need `await`, `break`, or `continue`. `forEach`
  cannot await and cannot be exited.
- **Split complex computeds** (style guide B13). One `computed` per derivation; compose them.

```js
// Guard clauses, happy path last.
export function resolveDiscount(order, membership) {
  if (!order) return 0
  if (order.total <= 0) return 0
  if (!membership?.active) return 0

  return order.total * membership.discountRate
}
```

## Async

- **`async`/`await` over `.then()` chains.** One `await` per operation, `try/catch` for failure.
- **Never leave a promise unhandled.** Every call returns, `await`s, or explicitly handles with
  `.catch()`. In Vue, an `async` lifecycle hook or event handler that rejects produces an unhandled
  rejection the user never sees.
- **Run independent work in parallel**, sequentially only when order or dependency requires it.

```js
// Right: independent requests start together.
const [orders, customers] = await Promise.all([fetchOrders(), fetchCustomers()])

// Right: one failure should not discard the successes.
const results = await Promise.allSettled(tasks)
const succeeded = results.filter((r) => r.status === 'fulfilled').map((r) => r.value)

// Right: sequential because each step depends on the previous one.
const order = await fetchOrder(id)
const invoice = await createInvoice(order)

// Wrong: sequential for no reason — two round trips instead of one.
const orders = await fetchOrders()
const customers = await fetchCustomers()
```

- **Cancellation is explicit.** Pass an `AbortController` signal into `fetch`, and abort it when
  the component unmounts or the watched source changes. A request that outlives its component
  writes to dead state or races a newer one.
- **Never `await` inside a `computed` or a getter.** Computeds are synchronous; fetching there
  makes rendering order-dependent.
- **Debounce and throttle at the boundary**, not inside the view: a `useDebouncedRef` composable or
  a `lodash-es` helper wrapping the input, never a bare `setTimeout` inside a template handler.

## Errors

- **Throw `Error` (or a subclass), never a string or an object literal.** Only `Error` carries a
  stack.
- **Catch only what you can handle.** An empty `catch {}` that swallows a real failure is worse
  than letting it propagate.
- **Preserve the cause** when wrapping: `throw new Error('Failed to load orders', { cause })`.
- **Distinguish expected from unexpected.** A 404 on a detail route is expected and becomes UI
  state; a 500 is unexpected, is logged, and surfaces as a generic failure.
- **Never log and rethrow the same error** — that produces duplicate noise. Either handle it or let
  it bubble.

```js
export async function fetchOrders({ signal } = {}) {
  const response = await fetch('/api/orders', { signal })
  if (!response.ok) {
    throw new Error(`Failed to load orders: ${response.status} ${response.statusText}`)
  }
  return response.json()
}
```

In a component, an expected failure becomes state, not an exception that escapes:

```js
const error = ref(null)

async function load() {
  error.value = null
  try {
    orders.value = await fetchOrders()
  } catch (cause) {
    error.value = cause instanceof Error ? cause.message : 'Failed to load orders'
  }
}
```

## Comments and JSDoc

**Every non-trivial file, component, composable, and exported function gets comments.** The comment
explains *why* — the constraint, the workaround, the domain rule — not *what* the next line does.
`// increment i` is noise; `// The API returns cents; the UI works in dollars` is a comment.

- **JSDoc on exported functions and composables**, documenting the contract. The project is
  untyped, so this is the only machine-readable contract there is.

```js
/**
 * Filter an order list by a keyword and a status.
 *
 * @param {Array<Order>} orders - Orders to filter; not mutated.
 * @param {{ keyword?: string, status?: string }} [filters] - Filter criteria.
 * @returns {Array<Order>} A new array containing the matching orders.
 * @example
 * const visible = filterOrders(orders, { status: 'paid' })
 */
export function filterOrders(orders, filters = {}) { /* … */ }
```

- **Component `<script setup>` gets a block comment** above the macros stating the component's
  responsibility and its contract, unless the component is trivial.
- **`// TODO(name): what and why`** for deferred work. A `TODO` without an owner and a reason is
  not allowed.
- **`// eslint-disable-next-line rule -- reason`** whenever a rule is suppressed. A bare disable is
  not allowed.
- **Comment every regular expression, non-obvious arithmetic, and magic number** at the point of
  definition.
- **Delete commented-out code.** Version control remembers it.

## SFC, template, and CSS style

**Block order is fixed** (style guide C4): `<script setup>`, then `<template>`, then `<style>`. The
script is what a reviewer reads first, and keeping it on top makes the component's contract the
first thing visible.

**Inside `<script setup>`**, use this order: imports, macros (`defineOptions`, `defineProps`,
`defineEmits`, `defineModel`, `defineSlots`), local state, computeds, watchers, functions,
lifecycle hooks, `defineExpose`. Optionally one blank line between those groups.

**Element attribute order** is the official 10-group order (style guide C2). Within one element:

1. `is`
2. `v-for`
3. conditionals and loops state: `v-if`, `v-else-if`, `v-else`, `v-show`, `v-cloak`
4. render modifiers: `v-pre`, `v-once`
5. `id`
6. `ref`, `key`
7. `v-model`
8. every other attribute and binding (props, `class`, `style`, plain attributes)
9. `v-on` handlers
10. `v-html`, `v-text`

```vue
<template>
  <OrderListRow
    v-for="order in visibleOrders"
    :key="order.id"
    ref="rowEl"
    :order="order"
    :selected="order.id === selectedId"
    class="order-list__row"
    @select="handleSelect(order.id)"
  />
</template>
```

Read that tag top to bottom: `v-for` (2), `key` and `ref` (6), then the ordinary props and `class`
(8), then the handler (9). Note what is *not* there — a `v-if`. Filtering `visibleOrders` in a
`computed` is how Priority A is satisfied while keeping attribute order intact.

Other template rules:

- **Shorthand `:` and `@` and `#`, always** (style guide B15) — `v-bind="object"` and
  `v-on="handlers"` keep their full form because the shorthand has no meaning there.
- **One attribute per line** as soon as an element has more than two attributes or the tag exceeds
  100 characters (B11).
- **Self-close content-less components**: `<BaseIcon name="plus" />` (B6).
- **Always quote non-empty attribute values** (B14).
- **`:key` on every `v-for`**, bound to a stable domain id — never the index (A3).
- **No complex expressions in the template** (B12). Anything with more than one operator, a ternary
  chain, or a function call that allocates goes into a `computed`.
- **No `v-html`.** If HTML must be rendered, sanitize it with DOMPurify at the boundary and record
  why in a comment; the lint rule is there for a reason.
- **PascalCase component tags** in SFC templates (B7); kebab-case only inside `in-DOM` templates,
  which this project does not use.

CSS rules:

- **`<style scoped>` is the default** (style guide A5). Only `src/assets/styles/` may be unscoped,
  for resets, design tokens, and app-wide typography.
- **Use class selectors, not element selectors, in `scoped` styles** (style guide D1) — element
  selectors in scoped styles compile to attribute selectors and are slow. `.order-list > li` breaks
  the moment the markup changes; put the class on the `li`.
- **Reach into a child with `:deep()`, and only when the child is not yours.** Prefer a prop or a
  CSS custom property; `:deep()` is a coupling you should be able to justify in a comment.
- **Theme through CSS custom properties** (`var(--color-surface)`) rather than hard-coded colors
  sprinkled through components.
- **No `!important`** outside a documented third-party override.
- **Class naming**: `block__element--modifier` (BEM) for components with more than a couple of
  elements; a single descriptive kebab-case class for small ones. Keep names scoped to the
  component — `.card` inside `OrderCard.vue` should really be `.order-card`.

## Definition of done for any change

1. `npm run lint` passes with no errors.
2. `npm run format:check` passes.
3. No newly added `console.log` (warnings and errors are fine).
4. Every `v-for` has a stable `:key`, and no element carries both `v-if` and `v-for`.
5. Comments explain any non-obvious decision in the changed code.
