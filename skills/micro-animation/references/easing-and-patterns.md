# Micro-Animation Tokens & Patterns

Reference CSS tokens and accessible patterns for implementing micro-animations cleanly.

## Motion Custom Properties

```css
:root {
  /* Direction-aware easing curves */
  --ease-enter: cubic-bezier(0.16, 1, 0.3, 1);     /* ease-out: fast start, smooth rest */
  --ease-exit: cubic-bezier(0.4, 0, 1, 1);        /* ease-in: clean acceleration out */
  --ease-move: cubic-bezier(0.4, 0, 0.2, 1);      /* ease-in-out: on-screen reposition */
  --ease-spring: cubic-bezier(0.34, 1.56, 0.64, 1);

  /* Distance-scaled durations */
  --dur-micro: 120ms;   /* press, hover, checkbox, toggle */
  --dur-small: 180ms;   /* tooltip, popover, toast, tabs */
  --dur-large: 260ms;   /* modal, drawer, panel */
  --dur-exit-ratio: 0.75;
}
```

## Tactile Button Feedback (Anticipation + Subtle Scale)

```css
.btn {
  transition:
    transform var(--dur-micro) var(--ease-enter),
    background-color var(--dur-micro) var(--ease-move);
}

.btn:active {
  transform: scale(0.97);
}
```

## Surface Enter & Faster Unified Exit

```css
.surface {
  opacity: 0;
  transform: translateY(6px) scale(0.98);
  transition:
    opacity calc(var(--dur-small) * 0.75) var(--ease-exit),
    transform calc(var(--dur-small) * 0.75) var(--ease-exit);
}

.surface[data-open="true"] {
  opacity: 1;
  transform: translateY(0) scale(1);
  transition:
    opacity var(--dur-small) var(--ease-enter),
    transform var(--dur-small) var(--ease-enter);
}
```

## Capped List Stagger

Cap `--stagger-index` (for example `Math.min(index, 6)`) so total delay stays `<= 200ms`:

```css
.list-item {
  opacity: 0;
  transform: translateY(8px);
  animation: item-enter var(--dur-small) var(--ease-enter) forwards;
  animation-delay: calc(var(--stagger-index, 0) * 30ms);
}

@keyframes item-enter {
  to {
    opacity: 1;
    transform: translateY(0);
  }
}
```

## Mandatory Reduced-Motion Fallback

```css
@media (prefers-reduced-motion: reduce) {
  .btn,
  .surface,
  .list-item {
    animation-duration: 1ms !important;
    animation-delay: 0ms !important;
    transition-duration: 120ms !important;
    transform: none !important;
  }
}
```
