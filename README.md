# Indra Zulfi's Agent Skills

My personal collection of reusable skills for AI coding agents—covering the engineering workflows, quality gates, and frontend UI patterns I use day to day.

Built on the [Agent Skills](https://agentskills.io/) specification and installable via [skills.sh](https://skills.sh/).

[![skills.sh](https://skills.sh/b/indrazm/personal-skills)](https://skills.sh/indrazm/personal-skills)

## Installation

Install all skills from this collection:

```bash
npx skills add indrazm/personal-skills
```

Or install a specific skill:

```bash
npx skills add indrazm/personal-skills --skill code-review
```

## Skills in This Collection

### Engineering & Quality

#### `zstack-mode` *(manual invocation only)*

Runs an interactive, gated task loop: asks what task to execute, enforces `code-review` and `changes-verification` after every completed task, and prompts to open a PR via `create-pr` when approved. Marked `disable-model-invocation: true` so agents do not auto-invoke it.

**Use when:**

- Explicitly invoked to run tasks through the full review → verify → optional PR loop

#### `code-review`

Performs multi-axis code review across correctness, readability, architecture, security, and performance by delegating to an independent subagent. Includes a detailed review checklist in `references/review-checklist.md`.

**Use when:**

- Reviewing a PR, diff, file, or code snippet
- Evaluating code before merging any change
- Auditing code quality after implementation or refactoring

#### `debugging`

Performs systematic, bird's-eye root-cause debugging instead of patching downstream symptoms across layers.

**Use when:**

- Tests fail or builds break
- Runtime behavior diverges from expectations
- Regressions or unexpected errors appear

#### `changes-verification`

Enforces deterministic pre-PR verification by discovering changed files and CI workflows, running change-related tests and locally runnable CI checks via `scripts/verify.py`, and writing a commit-bound verification receipt enforced by `scripts/pre-push-hook.sh`.

**Use when:**

- Before creating or updating a pull request (mandatory gate for `create-pr`)
- After completing a feature, refactor, or bug fix
- Verifying that a branch is ready for review or CI

#### `create-pr`

Creates pull requests after enforcing a mandatory `changes-verification` gate, verifying branch hygiene and diff size, and writing evidence-backed PR descriptions.

**Use when:**

- Creating or opening a pull request
- Preparing a branch for review and merge

#### `engineering-decision`

Records, updates, and supersedes engineering and architectural decisions in `docs/decision/` as numbered Markdown files (ADRs) with bidirectional lifecycle tracking. Includes `scripts/adr.py` for deterministic listing/scaffolding and `references/adr-template.md`.

**Use when:**

- Making technical, architectural, data-model, or tooling decisions
- Evaluating trade-offs between engineering approaches
- Superseding, deprecating, or canceling a prior decision

#### `optimize-ci` *(manual invocation only)*

Audits the last 150 GitHub Actions runs via `scripts/audit_ci.py` and optimizes CI pipelines toward sub-1-minute p50 and sub-2-minute p95 PR checks without hiding failures or reducing coverage. Marked `disable-model-invocation: true` so agents do not auto-invoke it.

**Use when:**

- Explicitly invoked to audit and speed up repository CI pipelines

### Frontend & UI

#### `micro-animation`

Designs and implements UI micro-animations using classical animation principles, direction-aware easing curves (`ease-in`, `ease-out`, `ease-in-out`), motion orchestration, and `prefers-reduced-motion` accessibility. Includes reusable tokens and patterns in `references/easing-and-patterns.md`.

**Use when:**

- Adding hover, focus, press, toggle, or feedback animations to UI controls
- Designing enter, exit, and layout transitions for modals, drawers, menus, or cards
- Auditing or refining frontend motion code

#### `optimistic-ui`

Implements optimistic UI updates for mutations (sending messages, editing items, toggles, image uploads) with stable client IDs/hashes, flicker-free image swaps, and restrained enter-only micro-animations. Includes concrete patterns in `references/patterns.md`.

**Use when:**

- Building chat, messaging, comment, or form mutation flows
- Implementing optimistic image or attachment uploads
- Fixing UI flickers, scroll jumps, or re-triggered animations during reconciliation

## Repository Structure

```text
.
├── README.md
├── skills.sh.json
└── skills/
    ├── changes-verification/
    │   ├── SKILL.md
    │   └── scripts/
    │       ├── pre-push-hook.sh
    │       └── verify.py
    ├── code-review/
    │   ├── SKILL.md
    │   └── references/
    │       └── review-checklist.md
    ├── create-pr/
    │   └── SKILL.md
    ├── debugging/
    │   └── SKILL.md
    ├── engineering-decision/
    │   ├── SKILL.md
    │   ├── references/
    │   │   └── adr-template.md
    │   └── scripts/
    │       └── adr.py
    ├── micro-animation/
    │   ├── SKILL.md
    │   └── references/
    │       └── easing-and-patterns.md
    ├── optimistic-ui/
    │   ├── SKILL.md
    │   └── references/
    │       └── patterns.md
    ├── optimize-ci/
    │   ├── SKILL.md
    │   └── scripts/
    │       └── audit_ci.py
    └── zstack-mode/
        └── SKILL.md
```

Each skill directory contains:

- `SKILL.md` — Required YAML frontmatter (`name`, `description`) and instructions for the agent
- `references/` — Optional supporting guides, checklists, and code patterns loaded on demand
- `scripts/` — Optional deterministic helper scripts

## License

MIT
