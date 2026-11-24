# Preferred Code Structure & Conventions

Follow existing repository conventions first when working in an established codebase. For greenfield work, new modules, or repos adopting this stack, follow these architecture and style standards.

## 1. Monorepo & Toolchain

- **Runtime & package manager:** Bun workspace monorepo (strict TypeScript, ESM). Use `bun`/`bunx` exclusively (never `npm`, `yarn`, or `pnpm`). Prefer Bun built-ins (`Bun.serve`, `Bun.file`, `bun:test`, `bun:sqlite`).
- **Workspace layout:**
  ```text
  apps/       Deployable apps (api/control-plane, web/platform, runtime/worker, cli)
  packages/   Shared internal packages (@scope/<name>, "workspace:*", shipped as TS source with no build step)
  tooling/    Custom lint rules and CI/automation scripts
  docs/       Numbered Markdown knowledge base (rules/, decision/, products/, bugs/)
  e2e/        End-to-end tests (Playwright)
  ```
- **App isolation:** Apps never import from another app; move shared code into `packages/`.
- **Dependencies:** Install dependencies in the workspace that uses them, never at the repo root unless truly workspace-wide.
- **Fast local quality tooling:** `bun check` (TypeScript 7 / `tsgo`), `bun lint` (`oxlint`), `bun fmt` (`oxfmt`), and `hk` (`hk.pkl`) for fast git hooks (`pre-commit` formatting/linting, `pre-push` full typecheck + lint + format + affected unit tests).

## 2. TypeScript & Hygiene Rules

- **Strict types:** Avoid `any`, `type X = unknown`, and chained assertions (`as unknown as T`) in production source.
- **No comments in TypeScript source:** Clear names, explicit types, and tests explain *what*; architectural *why* belongs in `docs/decision/`. Keep only tool directives (`@ts-*`, `oxlint-disable`, `/// <reference>`).
- **Types live in `types.ts`:** Place exported `type` and `interface` definitions in their module's `types.ts` and import them with `import type`. Keep component `Props` and Zod-inferred types beside their code.
- **No barrel files:** Never create `index.ts` files that only re-export; import directly from the exact file path.
- **Clean expressions & transforms:**
  - Prefer `flatMap` over `.filter().map()` chains.
  - Never copy the accumulator inside `reduce` (no `return { ...acc, ... }`).
  - Avoid nested ternaries, lonely `if` blocks, conditional object spreads, `Reflect.get`/`Reflect.apply`, and module mocking in tests.
  - Keep `if` blocks visually padded and control flow flat with early returns.
- **Never hand-edit generated files** (such as `routeTree.gen.ts` or generated SQL migrations).

## 3. Frontend Architecture (React, Vite, TanStack Router, Base UI, Jotai, Tailwind 4)

### Feature Modules & Strict Layering

Place feature code in `src/modules/<kebab-case>/` (create only folders the module needs):

```text
src/modules/<module-name>/
├── components/   Reusable feature components (one component per file, named exports)
├── hooks/        Reusable hooks (one hook per file: use-<thing>.ts)
├── atoms/        Shared client state (Jotai atoms)
└── types.ts      Module-shared types
```

Enforce strict top-down layering—each layer talks only to the layer below:

```text
routes/  (thin pages: read params, compose components, no state logic)
  -> modules/<name>/components/  (feature UI)
     -> modules/<name>/hooks/    (read/mutate state, own side effects like toasts & navigation)
        -> modules/<name>/atoms/ (Jotai atoms)
```

- **Routes and components NEVER import atoms.** They call module hooks.
- **Hooks own mutations and side effects** (create/update/delete + toast notifications).
- **Pages live directly in `src/routes/`** (file-based routing; no separate `pages/` folder). Code used by only one route stays in that route file until reused.
- **Imports:** Relative inside a module (`../hooks/use-items`); `@/` alias across modules and shared layers (`@/lib/format`, `@/modules/other/hooks/use-other`). Never reach sideways into another module via `../../`. Keep cross-module dependencies acyclic.
- **Shared layers:** Feature-agnostic clients/helpers in `src/lib/`; shared UI primitives in `packages/ui/src/` (or `src/components/`).

### UI Primitives, Icons, Colors & Fonts

- **Headless primitives only:** Build interactive and form elements on Base UI (`@base-ui/react`) wrapped in the shared UI components layer (shadcn Base UI variant). Never use raw `<button>`, `<input>`, `<select>`, `<textarea>`, `<label>`, `<form>`, `<fieldset>`, `<dialog>`, `<progress>`, or `<meter>` in feature code.
- **Single import boundary:** Import `@base-ui/react/*` only inside the UI primitives package/folder; feature code imports the wrappers.
- **Icons:** Use `@tabler/icons-react` (outline by default, `*Filled` for active states) with uniform CSS stroke width.
- **Semantic color tokens only:** Use Tailwind 4 semantic theme tokens (`bg-background`, `text-foreground`, `bg-card`, `bg-primary`, `text-muted-foreground`, `border-border`, `destructive`) defined in `src/index.css` (oklch light/dark themes, dark mode class-based default). Never use raw palette classes (`neutral-*`, `red-*`, `white`, `black`) or hardcoded hex/rgb values in components.
- **Typography:** Use theme font tokens (`font-sans`, `font-mono`), never hardcoded font families.
- **Local state first:** Prefer `useState` for local component state; promote to module `atoms/` only when state is shared.

## 4. Backend / API Architecture (Elysia on Bun, Zod, Drizzle + Postgres)

### Feature Modules

Organize backend features in `src/modules/<kebab-case>/` (include only files needed):

```text
src/modules/<module-name>/
├── router.ts    HTTP routes & request validation only; never touches db directly
├── schema.ts    Zod schemas (params, body, query) and inferred types
├── service.ts   Business logic & database access; knows nothing about HTTP
└── types.ts     Shared module types (when needed)
```

- **Method-chained routers:** Build routers in a single chain (`new Elysia({ prefix }).get(...).post(...).patch(...)`) so full end-to-end type inference is preserved. Export `<name>Router` and `<name>Service`.
- **Zod via Standard Schema:** Use Zod in `schema.ts` rather than framework-proprietary validators.
- **Composition root:** Instantiate long-lived singletons once in `src/composition.ts` and pass them into routers from `src/index.ts` (which mounts routers and exports `type App`) so modules never cross-import each other's singletons.
- **Typed domain errors:** Throw typed domain errors from `src/errors.ts` (`NotFoundError` 404, `ConflictError` 409, `ForbiddenError` 403, `UnprocessableError` 422, `UnavailableError` 503) handled by a top-level error router.
- **Tenant/session scoping:** Scope every query and mutation to the authenticated session/organization.

### Database & Config

- **Drizzle + Postgres (`packages/db`):** One table per file in `src/schema/`, plural `snake_case` table/column names, UUID `id`, `created_at`/`updated_at`. Generate migrations via the package script (`bun run db:generate`), never by hand.
- **Environment config:** Read from `process.env` and document every variable with a safe placeholder in `.env.example`. Never commit secrets or `.env`.
