---
name: vue3-language-spec
description: >-
  TypeScript coding standards for Vue 3: the official style guide priorities, the
  `@vue/tsconfig` project-reference setup and `vue-tsc --build` gate, strictness rules (no `any`,
  no `!`, no silencing `as`, `import type`), `as const` over `enum`, typing props/emits/models/slots,
  typescript-eslint flat config, Prettier, and TSDoc. Use when writing or reviewing TypeScript,
  SFCs, or templates, when configuring tsconfig or ESLint, or when asked about coding standards or
  type errors.
---

# TypeScript Language and Coding Standards (Vue 3)

Companion skills: `vue3-code-design` (structure and component contracts),
`vue3-script-splitting` (when to extract code into another file), `vue3-code-review` (the checklist).

**This project is TypeScript throughout.** Every `<script setup>` carries `lang="ts"`, every module
is `.ts`, and every test is `.spec.ts`. There is no `.js` source under `src/` — mixing the two
languages silently disables the type checker for half the graph.

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
| Component/instance options order | Not applicable — `<script setup>` only. Inside the script, use the order in *SFC style* below. |
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

## Project setup

The base config is abstracted in `@vue/tsconfig` (requires TypeScript ≥ 5.8 and Vue ≥ 3.4). The
project uses TypeScript **project references** so app code, Node-side config, and tests get different
globals.

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
// tsconfig.app.json — browser/app code
{
  "extends": "@vue/tsconfig/tsconfig.dom.json",
  "include": ["env.d.ts", "src/**/*", "src/**/*.vue"],
  "exclude": ["src/**/__tests__/*"],
  "compilerOptions": {
    // Extra safety for array and object lookups, but may have false positives.
    "noUncheckedIndexedAccess": true,

    // Path mapping for cleaner imports.
    "paths": { "@/*": ["./src/*"] },

    // `vue-tsc --build` produces a .tsbuildinfo file for incremental type-checking.
    "tsBuildInfoFile": "./node_modules/.tmp/tsconfig.app.tsbuildinfo"
  }
}
```

```jsonc
// tsconfig.node.json — modules that run in Node.js via transpilation or type-stripping
{
  "extends": "@tsconfig/node24/tsconfig.json",
  "include": [
    "vite.config.*", "vitest.config.*", "cypress.config.*",
    "playwright.config.*", "eslint.config.*"
  ],
  "compilerOptions": {
    "module": "preserve",
    "moduleResolution": "bundler",
    "allowImportingTsExtensions": true,
    "types": ["node"],
    "noEmit": true,
    "tsBuildInfoFile": "./node_modules/.tmp/tsconfig.node.tsbuildinfo"
  }
}
```

```ts
// env.d.ts — one line, at the project root
/// <reference types="vite/client" />
```

What the base configs already guarantee, so you do not re-specify them:

- `@vue/tsconfig/tsconfig.json` sets `strict: true`, `noImplicitThis: true`, `noEmit: true`,
  `module: "ESNext"`, `moduleResolution: "bundler"`, `target: "ESNext"`,
  `verbatimModuleSyntax: true`, `jsx: "preserve"`, `jsxImportSource: "vue"`,
  `moduleDetection: "force"`, `resolveJsonModule: true`, `allowImportingTsExtensions: true`,
  `useDefineForClassFields: true`, `esModuleInterop: true`,
  `forceConsistentCasingInFileNames: true`, `skipLibCheck: true`, `libReplacement: false`.
- `@vue/tsconfig/tsconfig.dom.json` sets `lib: ["ES2022", "DOM", "DOM.Iterable"]` and `types: []` —
  the empty `types` array is deliberate: it stops Node's globals leaking into browser code.

Two consequences worth internalising:

- **`verbatimModuleSyntax` is on.** A type-only import must be written `import type { Order } from
  './types'`, or it survives into the emitted/bundled output. This matters especially in
  `<script setup>`.
- **`noUncheckedIndexedAccess` is on.** `orders[0]` is typed `Order | undefined`, and
  `record[key]` is `T | undefined` even when the key "obviously" exists. Handle it — do not paper
  over it with `!`.

Type checking is a separate gate from the build: Vite transpiles without checking. Scripts:

```json
"scripts": {
  "dev": "vite",
  "build": "vue-tsc --build && vite build",
  "preview": "vite preview",
  "type-check": "vue-tsc --build",
  "lint": "eslint . --fix",
  "format": "prettier --write --cache src/",
  "format:check": "prettier --check src/",
  "test": "vitest run",
  "test:watch": "vitest"
}
```

IDE support is the **Vue - Official** extension (Volar). If Vetur is installed, disable it. A
`declare module '*.vue'` shim is **not** needed — `vue-tsc` and Volar type `.vue` files directly, and
adding the shim would erase every prop type in the project.

## Naming

| Thing | Convention | Example |
| --- | --- | --- |
| Component file | `PascalCase.vue` | `OrderSummary.vue` |
| Component in script/template | `PascalCase`, multi-word | `<OrderSummary />` |
| View (route) component | `PascalCase` + `View` suffix | `OrderListView.vue` |
| Base component | `Base` prefix | `BaseButton.vue` |
| Child coupled to one parent | Parent name as prefix | `OrderListRow.vue` |
| Composable | `use` + `PascalCase`, file `useXxx.ts` | `useOrderFilters.ts` |
| Pinia store | `useXxxStore`, file `xxx.ts` | `stores/orders.ts` → `useOrdersStore()` |
| Feature API module | `<feature>.api.ts` | `orders.api.ts` |
| Domain types module | `types.ts` in the feature | `Order`, `OrderStatus` |
| **Interface** | `PascalCase`, **no `I` prefix** | `OrderContext`, not `IOrderContext` |
| **Type alias** | `PascalCase` | `OrderStatus`, `Result<T>` |
| **Generic parameter** | `T`, or `T` + meaning when there are several | `T`, `TItem`, `TKey extends PropertyKey` |
| Variables, functions, props | `camelCase` | `orderTotal`, `loadOrders()` |
| Booleans | `is` / `has` / `should` / `can` prefix | `isLoading`, `hasMore`, `canSubmit` |
| Event handler function | `handle` + `Event` | `handleSubmit`, `handleRowClick` |
| Callback **prop** | `on` + `Event` | `onSelect`, `onClose` |
| Emitted event (script) | `camelCase` | `emit('orderShipped')` |
| Emitted event (template) | `kebab-case` | `@order-shipped="..."` |
| Props in template | `kebab-case` | `:order-total="total"` |
| True constants (module scope) | `UPPER_SNAKE_CASE` | `MAX_RETRY_COUNT`, `API_BASE_URL` |
| `as const` object | `PascalCase` for the object, `UPPER_SNAKE` for its members if they are constants | `OrderStatus.Paid` |
| Injection key | `XxxKey` | `const OrderContextKey: InjectionKey<OrderContext> = Symbol('order-context')` |
| CSS class | `kebab-case` | `.order-list__item` |
| Route `name` | `kebab-case` | `name: 'order-list'` |
| Module file | `kebab-case` | `format-currency.ts` |
| Test file | `<subject>.spec.ts` in `__tests__/` | `useOrderFilters.spec.ts` |
| Ambient type file | `*.d.ts`, only for globals | `env.d.ts` |

Rules that follow from the table:

- **No `I` prefix on interfaces and no `T` prefix on types.** `OrderContext`, not `IOrderContext`;
  `OrderStatus`, not `TOrderStatus`. Modern TypeScript code does not encode the kind of a type in
  its name, and Volar shows you the kind on hover.
- **Component names are multi-word and general-word-first.** `SearchButtonClear` reads correctly;
  `ClearSearchButton` does not.
- **No underscore prefixes** for "private" members. Module-level privacy is what non-export does; a
  leading `_` on a parameter means "intentionally unused" and nothing else.
- **Name by role, not by type.** `orders` not `ordersArray`; `visibleOrders` not `filteredList`.
- **No single-letter names** except `i`/`j` loop indices in a three-line loop and `e` in a one-line
  catch. Use `error`.
- **No abbreviations** the domain does not already use (`order` not `ord`, `quantity` not `qty`).
  This applies to component names too.
- **Files and directories are `kebab-case`**, except `.vue` components, which are `PascalCase`
  everywhere — never kebab-case in one place and PascalCase in another.

## Type rules

These are the house rules. Everything else in this section explains them.

1. `strict: true` is not negotiable, and `any` is not allowed.
2. `!` (non-null assertion) and `as` are not a way to make the compiler agree with you.
3. Every exported function states its return type.
4. External data is **validated**, not cast.
5. `enum` is not used.
6. `import type` for anything that exists only in the type system.

### `any` is banned; `unknown` is the honest type

`any` disables checking for the value and everything it touches. When a value genuinely has an
unknown shape, use `unknown` and narrow it — the compiler then forces you to prove what it is before
you use it.

```ts
// Wrong — the whole downstream graph is now unchecked.
function parseConfig(raw: any) {
  return raw.retries * 1000
}

// Right — narrow before use, and the caller gets a real type back.
function parseConfig(raw: unknown): Config {
  if (typeof raw !== 'object' || raw === null) {
    throw new TypeError('config must be an object')
  }
  const { retries, timeoutMs } = raw as Record<string, unknown>
  return {
    retries: typeof retries === 'number' ? retries : 0,
    timeoutMs: typeof timeoutMs === 'number' ? timeoutMs : 30_000,
  }
}
```

A single `as Record<string, unknown>` at the **validation boundary** is legitimate — that is where
untyped data enters the program. The same cast in the middle of a component is not.

### No non-null assertions

`!` tells the compiler to stop checking. It compiles away and produces a runtime crash exactly when
the value is missing — the case the check existed to catch.

```ts
// Wrong — crashes on the empty-list path the compiler was warning about.
const first = orders.value[0]!.id

// Right — narrow.
const first = orders.value[0]
if (first === undefined) return
first.id

// Right — or give a real fallback.
const firstId = orders.value[0]?.id ?? null
```

`noUncheckedIndexedAccess` makes this frequent. That is the point: the compiler is telling you the
list can be empty.

### `as` casts — only at a validated boundary

An `as` cast is an assertion, not a conversion. Use it only where you have already proved the shape
by other means, and say so in a comment.

- **Allowed**: after an explicit validation (as above), `as const` on a literal, and
  `event.target as HTMLInputElement` in a DOM handler where the element type is known from the
  markup.
- **Banned**: `x as unknown as Y`, `data as Order[]` on a `fetch` response, `props as SomeOtherType`,
  and any cast whose only purpose is to silence an error.
- **If you are tempted to cast, that is the type system asking for a better type or a runtime
  check** — usually a discriminated union or a parse function.

### Return types on exported functions

Inferred returns are fine for local callbacks. Every **exported** function, composable, store
action, and API function declares its return type, because it is part of the public API and an
accidental inference change would propagate silently.

```ts
// Right — the contract is in the source, not in the compiler's head.
export async function fetchOrders(options: FetchOptions = {}): Promise<Order[]> { /* … */ }

export function useOrderFilters(
  orders: MaybeRefOrGetter<Order[]>,
  initial: Partial<OrderFilters> = {},
): UseOrderFiltersResult { /* … */ }
```

Use `void` for functions called for effect. Do not use `undefined` as a return annotation — `void`
is what says "ignore the return".

### `interface` vs `type`

| Use | When |
| --- | --- |
| `interface` | An object shape that other code might extend, or that a component's props/emits/context describes. Also required for declaration merging (`declare module 'vue'`). |
| `type` | Unions, intersections, mapped/conditional types, tuples, function types, and anything derived from another type. |

Both are erased. Prefer `interface` for "a thing with these fields" and `type` for "one of these
shapes". Do not declare an `interface` you will never extend and never merge — `type` is fine, and
consistency within a file matters more than the choice.

### Discriminated unions over optional flags

Optional booleans that must agree with each other are a bug generator. Model the states instead, so
impossible combinations cannot be constructed.

```ts
// Wrong — loading && data && error is representable, and every consumer must guard all three.
interface State {
  loading?: boolean
  data?: Order[]
  error?: Error
}

// Right — exactly one state exists at a time, and the compiler narrows on `status`.
type OrdersState =
  | { status: 'idle' }
  | { status: 'loading' }
  | { status: 'ready'; orders: Order[] }
  | { status: 'failed'; error: Error }

// Consumers get exhaustiveness for free.
function describe(state: OrdersState): string {
  switch (state.status) {
    case 'idle': return 'Not loaded'
    case 'loading': return 'Loading…'
    case 'ready': return `${state.orders.length} orders`
    case 'failed': return state.error.message
  }
}
```

This is the single highest-value typing pattern for Vue components, because the template and the
script then both narrow on the same discriminant.

### `enum` is not used

Use an `as const` object plus a derived union. It is erasable, tree-shakeable, and works with
`verbatimModuleSyntax` and `erasableSyntaxOnly`.

```ts
// types.ts
export const ORDER_STATUS = {
  Pending: 'pending',
  Paid: 'paid',
  Shipped: 'shipped',
} as const

export type OrderStatus = (typeof ORDER_STATUS)[keyof typeof ORDER_STATUS]
// 'pending' | 'paid' | 'shipped'

// Usage is unchanged for reading, and the type is a real union.
const label = ORDER_STATUS.Paid
```

For a list of values you also need at runtime, derive the array from the object:

```ts
export const ORDER_STATUSES = Object.values(ORDER_STATUS)
// OrderStatus[] — and it cannot drift from the type.
```

### Validating external data

Anything crossing a boundary — `fetch`, `JSON.parse`, `localStorage`, `postMessage`, a query string —
is `unknown` until proven otherwise. `data as Order[]` is a lie the compiler will not catch.

```ts
// Right — parse at the boundary, return a real type, and let it throw on garbage.
export async function fetchOrders({ signal }: { signal?: AbortSignal } = {}): Promise<Order[]> {
  const response = await fetch('/api/orders', { signal })
  if (!response.ok) {
    throw new Error(`Failed to load orders: ${response.status} ${response.statusText}`)
  }
  const payload: unknown = await response.json()
  if (!Array.isArray(payload)) {
    throw new TypeError('Expected /api/orders to return an array')
  }
  return payload.map(toOrder)
}

function toOrder(raw: unknown): Order {
  if (typeof raw !== 'object' || raw === null) throw new TypeError('order must be an object')
  const record = raw as Record<string, unknown>
  if (typeof record.id !== 'string') throw new TypeError('order.id must be a string')
  if (typeof record.total !== 'number') throw new TypeError('order.total must be a number')
  return { id: record.id, total: record.total }
}
```

For anything larger than a handful of fields, use a schema library (Zod, Valibot) and infer the type
from the schema — `z.infer<typeof OrderSchema>` — so the validator and the type cannot drift.

### Branded ids

Two `string`s that mean different things will be swapped eventually. A brand makes that a type
error at zero runtime cost.

```ts
export type OrderId = string & { readonly __brand: 'OrderId' }
export type CustomerId = string & { readonly __brand: 'CustomerId' }

// Constructed once, at the boundary.
export const asOrderId = (value: string): OrderId => value as OrderId

function loadOrder(id: OrderId): Promise<Order> { /* … */ }

declare const customerId: CustomerId
loadOrder(customerId)
//        ~~~~~~~~~~ Type 'CustomerId' is not assignable to type 'OrderId'.
```

Apply this to ids that travel through props, route params, and store actions — that is where the
mistakes happen. Do not brand every string.

### `satisfies` for config-shaped literals

`satisfies` checks a value against a type **without** widening it, so you keep the literal types
while still being validated.

```ts
interface RouteMeta {
  requiresAuth: boolean
  title: string
}

// Right — validated, but `title` stays a literal type and typos are caught.
export const ROUTE_META = {
  'order-list': { requiresAuth: true, title: 'Orders' },
  'order-detail': { requiresAuth: true, title: 'Order' },
} satisfies Record<string, RouteMeta>
```

Do not write `const x: SomeType = {...}` when you need the narrow literal types; that is what
`satisfies` is for.

### Other type rules

- **No `Function` type.** Write the signature: `(id: string) => void`.
- **No `Object`, `{}`, or `Record<string, any>`.** Use a named interface, or `unknown` when the shape
  is genuinely unknown.
- **Prefer `readonly T[]` for parameters you do not mutate**, so a caller's array cannot be sorted
  in place by a function they handed it to.
- **`import type` for types** (`verbatimModuleSyntax`). `import { type Order, fetchOrders } from
  './orders'` is fine when mixing value and type imports.
- **Avoid `exactOptionalPropertyTypes`-hostile code** — do not assign `undefined` explicitly to an
  optional property; omit it. The flag is not enabled by the base config, but the habit keeps it
  possible to turn on later.
- **Do not type-annotate what is obviously inferred.** `const count = ref(0)` needs no
  `ref<number>(0)`. Annotate where the type is not inferable (`ref<Order[]>([])`) or where the
  annotation is documentation.
- **`@ts-expect-error` over `@ts-ignore`**, always with a comment explaining why and, ideally, a
  link to the issue that will let you remove it.

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
commas everywhere, and `(arg) =>` even for a single argument. Prettier does not type-check — it will
happily format code that does not compile. Run both:

```sh
npm run format && npm run type-check
```

## Linting — ESLint flat config with typescript-eslint

`eslint-plugin-vue` needs `vue-eslint-parser` to parse `.vue` files, so the TypeScript parser goes in
`parserOptions.parser` — **never** in `parser`. Putting `@typescript-eslint/parser` at the top level
breaks every template rule.

```js
// eslint.config.js
import js from '@eslint/js'
import prettier from 'eslint-config-prettier/flat'
import { defineConfig } from 'eslint/config'
import pluginVue from 'eslint-plugin-vue'
import globals from 'globals'
import tseslint from 'typescript-eslint'

// `defineConfig` is ESLint core's helper. `tseslint.config(...)` still works in
// typescript-eslint v8 but is deprecated in favour of this one.
export default defineConfig([
  { ignores: ['dist/**', 'coverage/**', 'node_modules/**', '**/*.d.ts'] },

  {
    extends: [
      js.configs.recommended,
      ...tseslint.configs.recommended,
      ...pluginVue.configs['flat/recommended'],
    ],
    files: ['**/*.{ts,vue}'],
    languageOptions: {
      ecmaVersion: 'latest',
      sourceType: 'module',
      globals: { ...globals.browser },
      parserOptions: {
        // vue-eslint-parser stays the top-level parser; TS handles the <script> block.
        parser: tseslint.parser,
      },
    },
    rules: {
      // ── TypeScript: enforce the house rules above ────────────────────────
      '@typescript-eslint/no-explicit-any': 'error',
      '@typescript-eslint/no-non-null-assertion': 'error',
      '@typescript-eslint/consistent-type-imports': ['error', { prefer: 'type-imports' }],
      '@typescript-eslint/consistent-type-definitions': ['error', 'interface'],
      '@typescript-eslint/no-unused-vars': [
        'error',
        { argsIgnorePattern: '^_', varsIgnorePattern: '^_' },
      ],
      '@typescript-eslint/explicit-module-boundary-types': 'error',
      '@typescript-eslint/no-empty-object-type': 'error',
      '@typescript-eslint/no-unsafe-function-type': 'error',
      '@typescript-eslint/no-namespace': 'error',
      // `enum` is banned by project convention — use an `as const` object.
      'no-restricted-syntax': [
        'error',
        { selector: 'TSEnumDeclaration', message: 'Use an `as const` object plus a derived union.' },
      ],

      // ── language ────────────────────────────────────────────────────────
      'no-var': 'error',
      'prefer-const': 'error',
      'object-shorthand': ['error', 'always'],
      'prefer-template': 'error',
      'no-param-reassign': ['error', { props: false }],
      'require-await': 'error',
      'no-console': ['warn', { allow: ['warn', 'error'] }],
      eqeqeq: ['error', 'always', { null: 'ignore' }],

      // ── Vue: enforce this project's style-guide choices ──────────────────
      'vue/component-api-style': ['error', ['script-setup']],
      'vue/block-lang': ['error', { script: { lang: 'ts' } }],
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

      // ── size tripwires (opt-in: no preset enables these) ─────────────────
      'vue/max-lines-per-block': ['warn', { script: 200, template: 150, skipBlankLines: true }],
    },
  },

  {
    files: ['*.config.{js,ts}', 'vite.config.ts', 'vitest.config.ts'],
    languageOptions: { globals: { ...globals.node } },
  },

  { files: ['src/**/*.spec.ts'], languageOptions: { globals: { ...globals.node, ...globals.vitest } } },

  // Must stay last: turns off every rule Prettier already handles.
  prettier,
])
```

Notes:

- **`eslint-config-prettier/flat` is the documented flat-config entry point**, not the package root;
  the root default export is rules-only and carries no `name`. Whichever you import, it must be last
  in the array — it only turns rules off, so anything after it wins.
- **Nine of the `vue/*` rules configured above are opt-in**: `component-api-style`,
  `block-lang`, `define-macros-order`, `component-name-in-template-casing`, `no-unused-refs`,
  `prefer-true-attribute-shorthand`, `max-lines-per-block`, `enforce-style-attribute`, and
  `new-line-between-multi-line-property` are in no preset, so they only take effect because this
  config names them explicitly.
- `tseslint.configs.recommended` is the **non-type-aware** set: fast, no project service required.
  Moving to `recommendedTypeChecked` (rules like `no-floating-promises`,
  `no-unnecessary-condition`) requires typed linting and, for `.vue`, both
  `parserOptions.projectService: true` and `parserOptions.extraFileExtensions: ['.vue']`. Add it
  deliberately — it roughly doubles lint time.
- `pluginVue.configs['flat/recommended']` is `strongly-recommended` plus community defaults. Use
  `flat/recommended-error` to make every rule an error.
- `npm run lint` and `npm run type-check` must both pass before work is considered done. ESLint does
  not type-check; `vue-tsc` does not lint.

## Syntax

| Prefer | Avoid | Why |
| --- | --- | --- |
| `const` by default, `let` when reassigned | `var` | `var` hoists and leaks out of blocks |
| `===` / `!==` | `==` / `!=` (except `== null`) | Coercion is a bug source; `== null` catches both null and undefined |
| `a?.b`, `a?.[i]`, `fn?.()` | `a && a.b && a.b.c` | Intent explicit, short-circuits nested access |
| `value ?? fallback` | `value \|\| fallback` | `\|\|` also replaces `0`, `''`, and `false` |
| `structuredClone(obj)` | `JSON.parse(JSON.stringify(obj))` | Loses `Date`, `Map`, `undefined`, and is slow |
| `Object.entries` / `Object.fromEntries` | `for...in` | `for...in` walks the prototype chain |
| `Array.isArray(x)` | `typeof x === 'object'` | Arrays are objects |
| `Object.hasOwn(obj, key)` | `obj.hasOwnProperty(key)` | Works on null-prototype objects |
| `.at(-1)` | `.length - 1` index math | Reads better |
| `toSorted` / `toReversed` (ES2023) | in-place `sort`/`reverse` on shared state | Never mutate a prop or store array in place |
| `#private` class fields | `this._private` | Real encapsulation, if a class is warranted |
| Optional catch binding `catch {}` | `catch (e) {}` with unused `e` | Says nothing is needed |

**Banned outright:** `eval`, `new Function`, `with`, `arguments`, `debugger`, `namespace`,
`enum`, modifying built-in prototypes, `document.write`, `innerHTML` assignment, and mutating an
array or object that arrived as a prop or came out of a store.

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

```ts
import { computed, ref, watch, type Ref } from 'vue'
import { useRoute } from 'vue-router'

import { formatCurrency } from '@/lib/format-currency'
import { useOrdersStore } from '@/features/orders'
import type { Order } from '@/features/orders/types'

import { useOrderFilters } from '../composables/useOrderFilters'

import './order-list.css'
```

- **Omit the extension for `.ts` imports** — `moduleResolution: "bundler"` resolves them, and
  `allowImportingTsExtensions` exists only so that a `.ts` extension is *permitted*, not preferred.
  Keep the `.vue` extension on component imports.
- **`import type` for type-only imports** (`verbatimModuleSyntax`). Inline form when mixing:
  `import { fetchOrders, type Order } from './orders.api'`.
- **Named exports for everything except a `.vue` SFC's implicit default.** `export function foo()`,
  never `export default function`. Named exports are rename-safe and greppable.
- **`@/` is the alias for `src/`**, configured in both `vite.config.ts` and `tsconfig.app.json`.
  Both must agree, or Vite resolves an import the type checker cannot.
- **No circular imports.** TypeScript tolerates some cycles that break at runtime; do not rely on it.

## Functions and control flow

- **Small and single-purpose.** Extract when a function needs a comment to explain a section.
  Roughly: over ~40 lines, or more than three levels of nesting, is too much.
- **Early returns over nested `if`.** Guard clauses first, happy path last.
- **Maximum three parameters.** Beyond that, take one options object with a named interface.
- **Pure by default.** A function that computes returns; a function that mutates says so in its name.
- **No boolean parameters.** `createOrder(true)` is unreadable — use an options object.
- **Prefer `for...of` over `forEach`** when you need `await`, `break`, or `continue`.
- **Split complex computeds** (style guide B13). One `computed` per derivation; compose them.
- **Generic over `unknown` + cast.** If a function works for any type, say so with a type parameter
  and a constraint, not with `unknown` and a cast at each call site.

```ts
// Guard clauses, happy path last, types narrowed by the guards.
export function resolveDiscount(order: Order | undefined, membership?: Membership): number {
  if (order === undefined) return 0
  if (order.total <= 0) return 0
  if (membership?.active !== true) return 0

  return order.total * membership.discountRate
}
```

## Async

- **`async`/`await` over `.then()` chains.** One `await` per operation, `try/catch` for failure.
- **Never leave a promise unhandled.** Every call returns, `await`s, or explicitly handles with
  `.catch()`. An `async` lifecycle hook or event handler that rejects produces an unhandled
  rejection the user never sees — enable `no-floating-promises` if you want the linter to catch it.
- **Type the rejection path.** A `try/catch` binds `unknown`, not `Error`; narrow before using it.
- **Run independent work in parallel**, sequentially only when order or dependency requires it.

```ts
const [orders, customers] = await Promise.all([fetchOrders(), fetchCustomers()])

// One failure should not discard the successes.
const results = await Promise.allSettled(tasks)
const succeeded = results
  .filter((r): r is PromiseFulfilledResult<Order> => r.status === 'fulfilled')
  .map((r) => r.value)
```

- **Cancellation is explicit.** Pass an `AbortController` signal into `fetch` and abort it when the
  component unmounts or the watched source changes.
- **Never `await` inside a `computed` or a getter.** Computeds are synchronous.
- **Debounce and throttle at the boundary**, not inside the view.

## Errors

- **Throw `Error` (or a subclass), never a string or an object literal.** Only `Error` carries a
  stack, and `catch` cannot narrow a thrown string.
- **Catch only what you can handle.** An empty `catch {}` that swallows a real failure is worse than
  letting it propagate.
- **Narrow the caught value**, because `catch` binds `unknown` under `strict`:

```ts
try {
  orders.value = await fetchOrders()
} catch (cause: unknown) {
  error.value = cause instanceof Error ? cause : new Error(String(cause))
}
```

- **Prefer a `Result` type over exceptions for expected failures** in domain code, and reserve
  exceptions for the genuinely exceptional:

```ts
export type Result<T, E = Error> =
  | { ok: true; value: T }
  | { ok: false; error: E }
```

- **Preserve the cause** when wrapping: `throw new Error('Failed to load orders', { cause })`.
- **Never log and rethrow the same error** — either handle it or let it bubble.

## Comments and TSDoc

**Every non-trivial file, component, composable, and exported function gets comments.** The comment
explains *why* — the constraint, the workaround, the domain rule — not *what* the next line does.
`// increment i` is noise; `// The API returns cents; the UI works in dollars` is a comment.

- **TSDoc on exported functions, composables, and types**, documenting the contract. Types cover
  the shape; the doc covers the meaning, the throwing behaviour, and whether inputs may be refs.

```ts
/**
 * Filter an order list by a keyword and a status.
 *
 * @param orders - Orders to filter. Not mutated.
 * @param filters - Filter criteria; omitted fields match everything.
 * @returns A new array containing the matching orders.
 * @example
 * const visible = filterOrders(orders, { status: ORDER_STATUS.Paid })
 */
export function filterOrders(
  orders: readonly Order[],
  filters: Partial<OrderFilters> = {},
): Order[] { /* … */ }
```

- **Document the `@throws`** on any function that can throw — the return type never mentions it.
- **Component `<script setup>` gets a block comment** above the macros stating the component's
  responsibility and its contract, unless the component is trivial.
- **`// TODO(name): what and why`** for deferred work. A `TODO` without an owner and a reason is not
  allowed.
- **`// eslint-disable-next-line rule -- reason`** whenever a rule is suppressed. A bare disable is
  not allowed, and `@ts-expect-error` always carries a reason.
- **Comment every regular expression, non-obvious arithmetic, and magic number** at its definition.
- **Delete commented-out code.** Version control remembers it.

## SFC, template, and CSS style

**Block order is fixed** (style guide C4): `<script setup lang="ts">`, then `<template>`, then
`<style>`. **Inside `<script setup>`**, use this order: imports, macros (`defineOptions`,
`defineProps`, `defineEmits`, `defineModel`, `defineSlots`), local state, computeds, watchers,
functions, lifecycle hooks, `defineExpose`. Optionally one blank line between those groups.

**Element attribute order** is the official 10-group order (style guide C2). Within one element:

1. `is`
2. `v-for`
3. conditionals and loop state: `v-if`, `v-else-if`, `v-else`, `v-show`, `v-cloak`
4. render modifiers: `v-pre`, `v-once`
5. `id`
6. `ref`, `key`
7. `v-model`
8. every other attribute and binding (props, `class`, `style`, plain attributes)
9. `v-on` handlers
10. `v-html`, `v-text`

Other template rules:

- **Shorthand `:` and `@` and `#`, always** (B15) — `v-bind="object"` and `v-on="handlers"` keep
  their full form because the shorthand has no meaning there.
- **One attribute per line** once an element has more than two attributes or the tag exceeds 100
  characters (B11).
- **Self-close content-less components**: `<BaseIcon name="plus" />` (B6).
- **Always quote non-empty attribute values** (B14).
- **`:key` on every `v-for`**, bound to a stable domain id — never the index (A3).
- **No complex expressions in the template** (B12). Move them to a `computed`, where they also get
  a type.
- **No `v-html`.** If HTML must be rendered, sanitize it with DOMPurify at the boundary and record
  why in a comment.
- **PascalCase component tags** in SFC templates (B7).
- **Type casts in templates are a last resort.** `(x as number).toFixed(2)` works when the script is
  `lang="ts"`, but a `computed` with a narrower type is almost always better.
- **Annotate DOM event handler parameters.** Without an annotation the parameter is implicitly `any`
  and `strict` errors:

```ts
function handleChange(event: Event): void {
  const target = event.target as HTMLInputElement
  console.log(target.value)
}
```

CSS rules:

- **`<style scoped>` is the default** (style guide A5). Only `src/assets/styles/` may be unscoped.
- **Use class selectors, not element selectors, in `scoped` styles** (style guide D1) — element
  selectors in scoped styles compile to attribute selectors and are slow.
- **Reach into a child with `:deep()`, and only when the child is not yours.**
- **Theme through CSS custom properties** (`var(--color-surface)`).
- **No `!important`** outside a documented third-party override.
- **Class naming**: `block__element--modifier` (BEM) for components with more than a couple of
  elements; a single descriptive kebab-case class for small ones.

## Definition of done for any change

1. `npm run type-check` (`vue-tsc --build`) passes with zero errors.
2. `npm run lint` passes with zero errors.
3. `npm run format:check` passes.
4. No `any`, no non-null assertion `!`, and no silencing `as` cast was added.
5. Every `v-for` has a stable `:key`, and no element carries both `v-if` and `v-for`.
6. No newly added `console.log` (warnings and errors are fine).
7. Comments and TSDoc explain any non-obvious decision in the changed code.
