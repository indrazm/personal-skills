---
name: optimistic-ui
description: Implements optimistic UI updates for user mutations (messages, edits, toggles, image uploads) using stable client IDs and content hashes, flicker-free image swaps, and restrained enter-only micro-animations. Use when building interactive mutations, chat/messaging flows, forms, file/image uploads, or fixing UI flicker during network reconciliation.
---

# Optimistic UI

Make every user mutation feel instantaneous by updating UI state immediately, reconciling server responses in place via stable client IDs and hashes, and ensuring reconciliation never unmounts nodes, flickers images, or replays animations.

Read `references/patterns.md` when implementing optimistic state stores, flicker-free image uploads, or WebSocket/SSE deduplication.

## When to Use

- Sending chat messages, comments, posts, or form submissions
- Updating, toggling, reordering, or deleting UI records
- Uploading and previewing optimistic images, attachments, or avatars
- Fixing UI flashes, lost focus/scroll jumps, or re-triggered animations on API confirmation

## Core Optimistic Pattern

Apply this lifecycle to every user-initiated mutation:

1. **Snapshot prior state:** Capture rollback state before mutating so failures can roll back or surface inline retry cleanly.
2. **Generate a stable `clientId`:** Create a UUID (`crypto.randomUUID()`) or idempotency key client-side before issuing the request.
3. **Mutate state immediately:** Insert or update the item with `status: "pending"` and `clientId`.
4. **Reconcile in place:** When the server responds, merge `serverId` and canonical fields into the existing record matched by `clientId` without changing its UI key.
5. **Handle failures gracefully:** On error, set `status: "failed"` with inline Retry/Discard controls (for user-authored content) or roll back cleanly (for toggles/reactions).

## Stable IDs, Hashes & Image Uploads

Never allow reconciliation to unmount and remount DOM nodes:

- **Keep UI list keys immutable:** Key rendered items by `clientId` (never swap `key={tempId}` to `key={serverId}`, and never key mutable lists by array index). Swapping keys destroys and recreates DOM nodes, causing flashes, lost scroll/focus, and replayed enter animations.
- **Deduplicate with idempotency keys:** Send `clientId` in the mutation payload and echo it back in both REST responses and WebSocket/SSE events so retries and real-time updates merge in place instead of appending duplicates.
- **Flicker-free optimistic image uploads:**
  - Compute a stable attachment `clientId` and content hash (SHA-256 of file bytes or `name + size + lastModified` paired with `clientId`) before starting upload.
  - Render immediately via `URL.createObjectURL(file)` inside a container with locked dimensions (`aspect-ratio` or explicit width/height) to eliminate layout shift.
  - Render upload progress as a lightweight overlay (`opacity` / `transform`) without resizing the media frame.
  - When the remote URL returns, preload and decode it off-screen (`img.decode()`) before swapping `src`, and only revoke the object URL (`URL.revokeObjectURL`) after the remote image is verified ready (or on unmount).

## Animation Discipline

Pair optimistic updates with restrained, composite-only motion:

- **Animate only on initial insertion:** Play one `ease-out` enter transition (`150ms` to `220ms`, `transform` + `opacity`) when the optimistic item is inserted.
- **Zero re-animation on reconciliation:** Keep the element mounted when `status` transitions from `pending` to `synced`; transition only subtle indicators (such as `opacity: 0.7 -> 1.0` over `120ms ease-out`).
- **No layout-thrashing animations:** Never animate `height`, `width`, `margin`, or `top`/`left` for status badges or retry banners; reserve space or animate `transform` and `opacity`.
- **Honor `prefers-reduced-motion`:** Fall back to instant updates or subtle `opacity` fades when reduced motion is active.

## Red Flags

- Using `serverId` or array index as the UI `key` and swapping keys after API confirmation
- Blocking UI updates until the network request finishes
- Swapping a local blob preview `src` to an uncached remote URL before decoding completes (causes image blink)
- Replaying enter animations when REST or WebSocket confirmation arrives
- Dropping user input on network failure instead of providing Retry

## Gotchas

- Propagate `clientId` through both REST responses and real-time streams (WebSockets/SSE) so real-time echoes reconcile the optimistic item in place.
- Always call `URL.revokeObjectURL` after remote image handoff or component unmount to prevent memory leaks.
