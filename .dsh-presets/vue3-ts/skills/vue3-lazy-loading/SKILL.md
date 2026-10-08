---
name: vue3-lazy-loading
description: >-
  On-demand loading in a Vue 3 + TypeScript app: typed route splitting with `RouteRecordRaw`,
  `defineAsyncComponent` and its component generic, `import.meta.glob` module typing, library
  on-demand import, generated `components.d.ts` / `auto-imports.d.ts`, icons, and chunk strategy.
  Use when splitting a route or component into its own chunk, wiring a component library, fixing
  missing auto-import types, or when the user asks about lazy loading, code splitting, or bundle
  size.
---

# On-Demand Loading in a Vue 3 App (TypeScript)

Companion skills: `vue3-code-design` (component structure and routing boundaries),
`vue3-script-splitting` (splitting *code into files* — a different axis), `vue3-language-spec`
(import style, the tsconfig project-reference setup, and the `vue-tsc --build` gate).

**Splitting a script into files and loading code on demand are different problems.** Splitting a
composable out of a component does not create a network request; it is a source-organization
decision. On-demand loading is about what ships in the first bundle. Do not reach for a dynamic
`import()` to fix a file that is simply too long — that is `vue3-script-splitting`.

## Four different things are called "on-demand"

Pick the right one before writing config; they solve different problems.

| Mechanism | What it defers | Cost | Use for |
| --- | --- | --- | --- |
| **Route-level code splitting** — `component: () => import(...)` | A whole route's chunk until navigation | One request per route, on navigation | Every route that is not the landing page |
| **`defineAsyncComponent`** | One component's chunk until it first renders | One request, on render | Heavy, rarely shown widgets |
| **Library on-demand import** — `unplugin-vue-components` + resolver | Unused components of a UI library, at build time | Build config + generated `.d.ts` | Element Plus, Ant Design Vue, Naive UI, Vuetify |
| **Auto-import** — `unplugin-auto-import` | Explicit import statements (not bundle size) | Build config + generated `.d.ts` + globals for ESLint | Ergonomics only — it does not shrink the bundle by itself |

Only the first three change what the browser downloads. Auto-import is a convenience layer and is
often mistaken for a size optimization; it is not one.

## Route-level code splitting

**Every route component is lazily imported.** Only the app shell and, at most, the landing route are
eager. Route arrays are typed `RouteRecordRaw[]`, which is a type-only export — under
`verbatimModuleSyntax` it must be `import type`.

```ts
// router/index.ts
import type { RouteRecordRaw } from 'vue-router'
import AppShell from '@/components/layout/AppShell.vue'

const routes: RouteRecordRaw[] = [
  {
    path: '/',
    component: AppShell,                                  // eager: it is the frame
    children: [
      { path: '', name: 'home', component: () => import('@/features/home/views/HomeView.vue') },
      { path: 'orders', name: 'order-list', component: () => import('@/features/orders/views/OrderListView.vue') },
      { path: 'orders/:id', name: 'order-detail', component: () => import('@/features/orders/views/OrderDetailView.vue') },
    ],
  },
]

export default routes
```

Rules:

- **Never lazy-load the layout or shell.** It renders on every route, so deferring it adds a
  request to the critical path and produces a blank frame.
- **One chunk per route, not per component.** A route's view may import feature components; those
  stay inside the route's chunk. Do not nest a dynamic import in the view unless the child is
  genuinely heavy.
- **Type the route array, not each record.** Annotating `routes: RouteRecordRaw[]` gives every
  entry checked `path`, `name`, and `component` shapes, and catches a `component` that resolves to
  the wrong export.
- **Webpack magic comments do not exist here.** Vite documents and supports no equivalent of
  `/* webpackChunkName: "x" */`; do not carry it over expecting it to name a chunk. Name chunks
  through the build config (see *Chunk strategy*) or by naming the file.
- **Co-locate routes with the feature** (`features/orders/routes.ts`, merged in the router) so a
  feature's code and its lazy boundary move together.
- **Prefetch what the user will probably open next** rather than eagerly loading it:

```ts
// Prefetch on idle, or on hover/focus of the link — never on first paint.
const prefetch = () => import('@/features/orders/views/OrderListView.vue')
requestIdleCallback?.(prefetch)
```

A bare `import()` in module scope is *not* lazy — it executes immediately. Prefetching deliberately
means calling it later, on an idle callback or an interaction.

### Directory-driven loading: `import.meta.glob`

For a folder of views or widgets that are chosen at runtime (a plugin registry, a docs set, a
CMS-driven page directory), `import.meta.glob` gives Vite a **static** list it can split into
chunks. A fully dynamic template path cannot be analysed and will either fail or pull everything in.

```ts
import type { Component } from 'vue'

// The type parameter describes the MODULE, not the component.
const lazyViews = import.meta.glob<{ default: Component }>('./views/*.vue')
//    ^ Record<string, () => Promise<{ default: Component }>>

// Each entry resolves to the module, so unwrap `.default` before using it.
const loadView = async (name: string): Promise<Component | undefined> => {
  const load = lazyViews[`./views/${name}.vue`]
  return load === undefined ? undefined : (await load()).default
}

// `{ eager: true }` is a different overload: it yields the module record directly, so there is
// nothing to await — and nothing is code-split.
const eagerViews = import.meta.glob<{ default: Component }>('./views/*.vue', { eager: true })
//    ^ Record<string, { default: Component }>

// A named import of a non-component: state the resolved type explicitly.
const docs = import.meta.glob<string>('./assets/*.md', { query: '?raw', import: 'default' })
//    ^ Record<string, () => Promise<string>>
```

- **The generic is the module type.** Vite's overloads are
  `<M>(glob, options?: ImportGlobOptions<false, string>) => Record<string, () => Promise<M>>` and
  `<M>(glob, options: ImportGlobOptions<true, string>) => Record<string, M>`. Passing
  `<{ default: Component }>` therefore makes the lazy call resolve to `Promise<{ default: Component }>`
  — the component is one property away, and `.default` is not optional.
- **With `import: 'default'` the resolved value is the export itself**, so the generic is the
  export's type (`<string>` for raw text), not a `{ default }` wrapper.
- **Omit `eager: true`** unless you actually want everything in the current chunk; adding it is the
  most common way this API silently stops being lazy. Note the type changes with it: `eager: true`
  returns `Record<string, M>` with no function to call.
- **The pattern must be a literal.** The docs are explicit: "all the arguments in the
  `import.meta.glob` must be passed as literals. You can NOT use variables or expressions in them."
- The keys are literal paths — map your domain id to a path and handle the miss (the index access is
  `| undefined` under `noUncheckedIndexedAccess`, so the miss is already in the type).

## Async components

`defineAsyncComponent` defers a single component's code until it is first rendered. Its type comes
from the loader's resolved module, so pin it explicitly with the component generic.

```ts
import { defineAsyncComponent } from 'vue'
import HeavyChart from './HeavyChart.vue'
import ChartSkeleton from './ChartSkeleton.vue'
import ChartError from './ChartError.vue'

// `typeof HeavyChart` is the component — a constructor — and that is what the generic wants.
// Vue's loader accepts either the component or a module wrapping it
// (`AsyncComponentResolveResult<T> = T | { default: T }`), so a dynamic `import()` satisfies it.
const AsyncHeavyChart = defineAsyncComponent<typeof HeavyChart>(
  () => import('./HeavyChart.vue'),
)

// The options form. The generic goes on the call, not on `loader`.
const AsyncHeavyChartWithFallbacks = defineAsyncComponent<typeof HeavyChart>({
  loader: () => import('./HeavyChart.vue'),
  loadingComponent: ChartSkeleton,   // shown while loading
  errorComponent: ChartError,        // shown on failure — do not omit this
  delay: 200,                        // ms before showing the loading component (avoids a flash)
  timeout: 10_000,                   // ms before the error component is shown
})
```

**Why `typeof` and not `InstanceType`.** They are different types, and only one of them is a
component:

```ts
type ChartComponent = typeof HeavyChart
//   ^ the component constructor — satisfies `T extends Component`
type ChartInstance = InstanceType<typeof HeavyChart>
//   ^ the mounted instance — what a template ref points at, NOT a component
```

`defineAsyncComponent<T extends Component>` constrains `T` to a component, so
`InstanceType<typeof HeavyChart>` does not satisfy it. `InstanceType` belongs to template refs, not
here (`vue3-language-spec` covers where).

**Pin the generic, do not rely on inference.** Inference reads the loader's resolved module, and
when it cannot land on the component — the loader is stored in a variable, wrapped in a helper, or
produced by a factory — `T` falls back to its declared default
`{ new (): ComponentPublicInstance }`, a component that accepts **no props**. Nothing errors at the
call site; the prop contract simply stops being checked. Annotating the generic (or the loader's
return type) keeps the wrapper exactly as strict as the component it wraps.

Use it for: editors, chart/visualization libraries, maps, PDF and media viewers, rich tables, and
anything in a modal or a below-the-fold tab that most visits never open.

**Do not use it for:**

- **Anything above the fold or in the first paint.** Deferring the hero component makes Largest
  Contentful Paint worse, not better.
- **Small components.** One extra request costs more than the bytes saved.
- **A component that renders on every visit.** You have added a request and a loading state to the
  critical path for nothing.
- **Something already inside a lazily loaded route.** The route's chunk is loaded on navigation;
  nesting an async component inside it buys a second waterfall round trip.

**What actually happens when a load fails.** Vue does not fail silently. Without an `errorComponent`
the error goes through `handleError` — thrown in dev so it is noticeable, `console.error` in
production — and the wrapper stays in its loading state indefinitely (so a blank region only if no
`loadingComponent` was given either). Set `errorComponent` for the user-facing message, and `onError`
only when you want retry control.

The full options object accepts `loader`, `loadingComponent`, `errorComponent`, `delay`, `timeout`,
`suspensible`, and `onError`, plus `hydrate` (3.5+, for SSR lazy hydration). `suspensible` defaults to
`true`; `delay` defaults to **200 ms**; `timeout` defaults to **Infinity** (no timer unless you set
one). `onError(error, retry, fail, attempts)` lets you retry or fail explicitly.

`<Suspense>` is the alternative when you want to orchestrate loading in the template. Note the
official status: `<Suspense>` **is an experimental feature** — "not guaranteed to reach stable
status and the API may change". It waits on either components with an async `setup()` **or** async
components, and it provides no error handling of its own, so errors must be caught in the parent via
`errorCaptured` / `onErrorCaptured()`. Prefer `defineAsyncComponent` unless you specifically need
`Suspense`'s fallback semantics.

## Component-library on-demand import

A full-library install defeats tree shaking:

```ts
// Wrong — every component and the whole stylesheet ship, whatever you use.
import ElementPlus from 'element-plus'
import 'element-plus/dist/index.css'
app.use(ElementPlus)
```

The on-demand equivalent resolves components as they appear in templates, at build time:

```ts
// vite.config.ts
import Components from 'unplugin-vue-components/vite'
import AutoImport from 'unplugin-auto-import/vite'
import { ElementPlusResolver } from 'unplugin-vue-components/resolvers'

export default defineConfig({
  plugins: [
    vue(),
    Components({
      resolvers: [ElementPlusResolver()],   // default importStyle: 'css'
      dts: 'src/components.d.ts',
      dirs: ['src/components'],             // your own components too, if you want them global
    }),
    AutoImport({
      // APIs that are functions, not components: ElMessage, ElMessageBox, ElNotification.
      resolvers: [ElementPlusResolver()],
      imports: ['vue', 'vue-router', 'pinia'],
      dts: 'src/auto-imports.d.ts',
    }),
  ],
})
```

Notes that save hours:

- **`Components()` handles tags; `AutoImport()` handles functions.** A `ElMessage.success()` with no
  import needs the second plugin — that is the most common "it works but the message box is
  undefined" cause.
- **The resolver imports styles per component, so a style import is normally not your job.**
  `ElementPlusResolver`'s `importStyle` defaults to `'css'`, and it injects
  `element-plus/es/components/<name>/style/css` plus the base style. If a surface renders unstyled,
  check the setup before hand-adding imports: the resolver must be registered in **both**
  `Components()` and `AutoImport()`, because only `AutoImport()`'s resolver addon pushes the
  side-effect imports for script-level functions.
- **Without the plugin, the official path is still a plugin.** Element Plus's "manually import"
  guidance says tree shaking works out of the box but that you need `unplugin-element-plus` for
  styles; it does not document a plugin-free per-component style import. That plugin's README is
  where the raw specifier is documented: `element-plus/es/components/<name>/style/css`.
- **The libraries differ — check each one's own guide rather than assuming:**
  - **Ant Design Vue** — ES modules tree-shake with individual imports (`import { Button } from
    'ant-design-vue'`), and its "Import on Demand" section recommends no resolver at all. As of v4
    styles are CSS-in-JS, so no per-component style import is needed; only the optional
    `ant-design-vue/dist/reset.css` remains, and `babel-plugin-import` is no longer supported.
  - **Naive UI** — tree-shakeable by design (`"sideEffects": false`) and, in its own words, "you
    don't need to import any CSS to use the components".
  - **Element Plus** — the one that genuinely needs resolver wiring, because its styles ship as
    separate per-component files rather than being injected at runtime.
- **Keep one library.** Two UI libraries double the on-demand config and the bundle.
- **Auto-import makes symbols invisible to `grep`.** `ElMessage` and `ref` appear with no import
  line. Limit auto-import to the UI library and, at most, Vue core — and never auto-import your own
  modules, or a reader cannot tell where anything comes from.

### Generated declaration files

The `dts` option is not optional bookkeeping. These two files are what make the plugin's
registrations real to the type system, and they are written on the first dev/build run:

| File | Declares |
| --- | --- |
| `src/components.d.ts` | Every component the resolver can resolve, so `<ElButton />` in a template is a known component with typed props rather than an unknown tag |
| `src/auto-imports.d.ts` | Every API the auto-import plugin injects, so `ref`, `computed`, `useRoute`, `ElMessage` are declared names |

- **They must be inside the tsconfig `include`.** `tsconfig.app.json` includes `src/**/*`, so the
  default `src/…` output is already covered — but pointing `dts` at the project root or a `types/`
  directory outside `include` hides it from `vue-tsc --build` and from Volar.
- **Commit them, or generate them before the type gate in CI.** Without them, every template using a
  resolver-resolved component fails the gate with `Cannot find name 'ElButton'`, and Volar shows no
  props, no completion, and no error either — the failure looks like a broken editor rather than a
  missing file.
- **Regenerate after a library upgrade or a resolver-list change.** A stale `components.d.ts` is
  worse than none: it declares components that no longer resolve, so the type gate passes while the
  runtime fails.
- See `vue3-language-spec` for the full project-reference setup and how the gate is invoked.

### Auto-import globals and the type gate

With `strict` and `verbatimModuleSyntax`, an auto-imported API is an **undeclared name** until the
generated declaration lands. Two independent gates have to know about it:

1. **The type gate** — `vue-tsc --build` reads the generated `.d.ts`. If it is missing, or exists
   outside `include`, the error is `Cannot find name 'ref'`.
2. **ESLint** — the auto-imported names must also be declared as globals, or `no-undef` reports code
   that compiles perfectly.

The rule at stake is `no-undef`, which the base `js.configs.recommended` enables for every linted
file. typescript-eslint's `eslint-recommended` layer switches it off for TypeScript files, but that
override is scoped by file extension, so a `.vue` script block can still trip it. Declaring the
globals is harmless where the rule is off and required where it is on:

```js
// eslint.config.js
{
  files: ['**/*.{ts,vue}'],
  languageOptions: {
    globals: {
      ...globals.browser,
      // Mirror what unplugin-auto-import injects. Keep this list in step with the plugin config —
      // a name added to `imports` and not here is a lint error, not a type error.
      ref: 'readonly',
      computed: 'readonly',
      watch: 'readonly',
      watchEffect: 'readonly',
      onMounted: 'readonly',
      onUnmounted: 'readonly',
      ElMessage: 'readonly',
    },
  },
}
```

## Icons

Three approaches with genuinely different trade-offs:

- **`unplugin-icons`** — build-time, imported as components, tree-shaken, one icon = one small
  module. Best default.
- **`@iconify/vue`** — runtime; icon data is fetched on demand over the network. Good for a very
  large or user-configurable set, at the cost of a request and a flash.
- **An SVG sprite or a hand-rolled icon component** — fine for a small fixed set; keep it out of the
  main bundle if the set is large.

Do not bundle a whole icon pack as components you import eagerly "just in case".

## What must never be lazy-loaded

| Anti-pattern | Why it is worse | Do instead |
| --- | --- | --- |
| Lazy-loading the layout/shell | Adds a request to the critical path; blank frame | Eager import in the router |
| `defineAsyncComponent` for above-the-fold UI | Worse LCP | Eager import |
| Dynamic `import()` inside a template expression | Re-created on every render; may re-fetch | Load once, store the resolved component |
| Fully dynamic import path (`` import(`./views/${name}.vue`) ``) | Vite cannot analyse it; fails or bundles everything — and it cannot be typed | `import.meta.glob` with a static map |
| `import.meta.glob(..., { eager: true })` when you meant lazy | Everything lands in the current chunk | Drop `eager` |
| Reading `.default` off an `eager: true` glob result | The eager overload returns the module record, not a loader, so there is no function to call | Await only the non-eager form |
| Full-library install plus one component | Whole library and its CSS ship | Resolver, or individual imports |
| Async component without `errorComponent` | The failure is an unhandled error, and the wrapper sits in its loading state for good (blank only if `loadingComponent` is also missing) | Set `errorComponent`, and `timeout` if you want a bounded wait |
| Lazy-loading a 2 KB component | Round trip costs more than the bytes | Eager |
| Nested async components inside a lazy route | Serial waterfall, two round trips | Flatten; let the route chunk carry it |
| Loading states on every deferred widget | Layout thrash and flicker | `delay` on `defineAsyncComponent`; skeletons sized like the content |
| Generated `components.d.ts` outside the tsconfig `include` | Templates using resolved components fail the type gate with `Cannot find name` | Keep `dts` under `src/` |

## Verifying the split actually happened

Never assume a config worked. Check the build output.

```sh
npm run build        # one line per emitted file, with raw and gzip size
npm run type-check   # vue-tsc --build — the gate a green build does not run
```

- **The route's code must not be in the entry chunk.** If it is, the dynamic import was flattened —
  usually an `eager: true` or a static import elsewhere pulling it back in.
- **Add a visualizer** for anything non-trivial: `rollup-plugin-visualizer` produces a treemap of
  exactly what is in each chunk, and its current peer range accepts Rolldown, so it works on Vite 8.
  It is not a Vite-official recommendation — Vite's own docs point at `vite-plugin-inspect` instead.
- **Watch the initial payload**, not the total. Total size is the wrong metric; the number that
  matters is what loads before first paint.
- **Check the network waterfall** in DevTools for a route you have not visited: it should be absent
  from the initial load and appear as one chunk on navigation.
- **A green build proves nothing about this.** Vite transpiles without type-checking, so the build
  also proves nothing about the types — run both gates.

## Chunk strategy

- **Split vendor code** so an app-code change does not invalidate the vendor chunk. The option name
  is **version-split**, because Vite 8 replaced Rollup with Rolldown — check the installed major
  before copying either snippet.

```ts
// vite.config.ts — Vite 8 (Rolldown)
build: {
  rolldownOptions: {
    output: {
      codeSplitting: {
        groups: [{ name: 'vendor', test: /node_modules/ }],
      },
    },
  },
},
```

```ts
// vite.config.ts — Vite 5, 6, 7 (Rollup)
build: {
  rollupOptions: {
    output: {
      manualChunks: {
        vue: ['vue', 'vue-router', 'pinia'],
      },
    },
  },
},
```

- **Do not paste the Rollup snippet into a Vite 8 project.** In v8, `build.rollupOptions` is a
  *deprecated alias* of `build.rolldownOptions`, the **object form of `output.manualChunks` is
  removed outright** (a hard failure, not a warning), and the function form is deprecated in favour
  of `output.codeSplitting`. Rolldown also had an `advancedChunks` option that is already superseded
  by `codeSplitting` — treat it as history, not as the thing to migrate to.
- **Split where code is conditionally needed, not by size.** A route boundary and a genuinely heavy
  widget are seams; a chunk per small component is not an improvement. Every boundary is a request
  the browser has to discover and schedule, and a chunk that is always used together with another
  just adds a round trip for no deferred bytes. (Vite's docs give no guidance against over-splitting
  either way — this is a design rule, not a documented one.)
- **Vite generates `<link rel="modulepreload">` directives for entry chunks and their direct imports**
  in the built HTML, and includes the polyfill by default. Do not hand-roll preload tags;
  `build.modulePreload: false` turns it off, and `{ polyfill: false }` keeps the directives without
  the polyfill.
- **A lazily loaded route is not preloaded by default** — that is the point. Add hover/idle prefetch
  for the routes users reliably take next.
- **`vite build` reports raw and gzip size, not brotli.** `build.chunkSizeWarningLimit` (default
  500 kB) warns against the **uncompressed** size, so a passing build does not mean a small
  compressed payload.

## Decision table

| Situation | Choice |
| --- | --- |
| A route that is not the landing page | `() => import(...)` in a `RouteRecordRaw[]` |
| The app shell / layout | Eager import |
| Editor, chart, map, PDF viewer, heavy table | `defineAsyncComponent<typeof X>` with loading + error components |
| A modal's contents that most visits never open | `defineAsyncComponent` |
| Above-the-fold hero or primary content | Eager import |
| A folder of views/widgets chosen at runtime | `import.meta.glob<{ default: Component }>` (no `eager`) |
| A UI library | Resolver-based on-demand import, with `dts` inside `include` |
| A small fixed icon set | Eager icon component |
| A very large or user-configurable icon set | Build-time `unplugin-icons`, or runtime `@iconify/vue` |
| Pure composition-API convenience | `unplugin-auto-import` — ergonomics, not size |

## Checklist

- [ ] Every non-landing route is a dynamic `import()`; the shell is eager; the array is typed
      `RouteRecordRaw[]`.
- [ ] No `webpackChunkName` comments — Vite does not support them.
- [ ] If vendor chunks are configured, the option matches the installed Vite major
      (`rolldownOptions.output.codeSplitting` on 8, `rollupOptions.output.manualChunks` on 5–7).
- [ ] Every `defineAsyncComponent` is pinned with `<typeof TheComponent>` and has a
      `loadingComponent`, an `errorComponent`, and a `delay`.
- [ ] Nothing above the fold is deferred.
- [ ] `import.meta.glob` calls that should be lazy do not pass `eager: true`, and the lazy form
      unwraps `.default`.
- [ ] The UI library is imported on demand and its styles actually render.
- [ ] `src/components.d.ts` and `src/auto-imports.d.ts` exist, sit inside the tsconfig `include`, and
      are committed or generated before the type gate.
- [ ] Auto-imported names are declared in ESLint's `languageOptions.globals`.
- [ ] `vue-tsc --build` and `npm run build` both pass, and the build shows the route code in its own
      chunk, not in the entry.
- [ ] The initial payload was measured before and after, not assumed.
