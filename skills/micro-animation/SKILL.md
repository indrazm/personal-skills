---
name: micro-animation
description: Designs and implements UI micro-animations using classical animation principles, direction-aware easing curves (ease-in, ease-out, ease-in-out), motion orchestration, and reduced-motion accessibility. Use when building interactive UI components, transitions, hover/press states, modals, drawers, lists, or auditing frontend motion code.
---

# Micro Animation

Implement purposeful UI micro-interactions grounded in direction-aware easing (`ease-in`, `ease-out`, `ease-in-out`), classical animation principles, and GPU-composited motion orchestration. Every transition must clarify spatial relationships, confirm intent, and feel responsive without delaying user action.

Read `references/easing-and-patterns.md` when implementing CSS tokens, enter/exit transitions, staggered lists, or reduced-motion fallbacks.

## When to Use

- Implementing hover, focus, press, toggle, or feedback transitions on interactive controls
- Building enter, exit, and layout transitions for modals, drawers, popovers, or cards
- Orchestrating staggered lists, multi-step state changes, or shared-element transitions
- Auditing or refining CSS/JS animations that feel stiff, sluggish, or janky

## Easing & Timing Rules (Slow In, Slow Out)

Match every easing curve to motion direction and intent. Never apply `linear` to spatial UI movement (reserve `linear` strictly for continuous spinners and determinate progress fills):

- **Entering / Appearing (`ease-out`):** Start fast for immediate feedback and decelerate cleanly into rest (`cubic-bezier(0.16, 1, 0.3, 1)` or `cubic-bezier(0, 0, 0.2, 1)`).
- **Exiting / Leaving (`ease-in`):** Accelerate cleanly out of view so departing surfaces never linger (`cubic-bezier(0.4, 0, 1, 1)`). Make exits 20% to 30% faster than entrances.
- **On-Screen State Change / Repositioning (`ease-in-out`):** Accelerate from rest and decelerate into the new state (`cubic-bezier(0.4, 0, 0.2, 1)`).
- **Tactile / Spring Controls:** Use spring physics (or slight overshoot `cubic-bezier(0.34, 1.56, 0.64, 1)`) sparingly for toggles, reactions, or drag-release snap-back.

Scale durations strictly to travel distance:

- **Micro-feedback** (button press, hover, checkbox, toggle): `100ms` to `150ms`
- **Small surfaces** (tooltips, dropdowns, tabs, toast enter): `150ms` to `220ms`
- **Large surfaces** (modals, drawers, card expansions): `220ms` to `350ms`

## Classical Animation Principles for UI

1. **Slow In and Slow Out:** Apply `ease-out` on entry, `ease-in` on exit, and `ease-in-out` for in-place state transitions.
2. **Anticipation:** Provide subtle pre-action feedback before major transitions (such as `scale(0.97)` on pointer-down or elevation lift before drag).
3. **Staging:** Direct focus to the active surface by dimming or blurring background layers (`opacity` + `backdrop-filter`) while keeping non-target elements still.
4. **Follow-Through and Overlapping Action:** Avoid moving every child as a rigid slab; offset secondary elements (title, body, actions) by `25ms` to `50ms` after the container.
5. **Secondary Action:** Reinforce primary state transitions with subtle supporting motion (icon morph, checkmark stroke draw, soft ring pulse) that never competes with the main control.
6. **Subtle Squash and Stretch:** Apply minimal scale shifts on tactile interactions (`active:scale-[0.98]`) while preserving crisp text rendering.
7. **Arcs:** Move floating or shared elements along curved paths across X and Y axes rather than mechanical two-step L-shapes.
8. **Timing and Restraint:** Keep motion crisp so the UI never forces the user to wait.

## Motion Orchestration

- **Choreograph by hierarchy:** Animate the container first, then stagger child items by `25ms` to `45ms`. Cap total stagger delay (for example, `<= 200ms`) so long lists never trickle in slowly.
- **Unify exits:** Dismiss modals and groups together with a short `ease-in` instead of reversing a long stagger.
- **Preserve interruptibility:** Use CSS transitions, Web Animations API, or interruptible springs so rapid hover/unhover or open/close toggles reverse smoothly from the current frame without snapping.

## Performance & Accessibility (Mandatory)

- **Composite-only properties:** Animate `transform` (`translate`, `scale`, `rotate`) and `opacity`. Never animate layout-thrashing properties (`width`, `height`, `top`, `left`, `margin`, `padding`) in micro-animations.
- **Reduced motion:** Always ship `@media (prefers-reduced-motion: reduce)` fallbacks that disable spatial translation/scaling and reduce motion to instant updates or subtle `opacity` fades.

## Red Flags

- Applying `linear` easing to modals, drawers, or button transitions
- Applying `ease-in` to elements entering the viewport
- Animating `height`, `width`, `margin`, or `top`/`left` instead of `transform`
- Staggering long lists without a total delay cap
- Omitting `@media (prefers-reduced-motion: reduce)` handling

## Gotchas

- Never let decorative animation block pointer events or delay input responsiveness.
- Verify transitions under CPU throttling; a `300ms` animation that drops frames degrades UX more than no animation.
