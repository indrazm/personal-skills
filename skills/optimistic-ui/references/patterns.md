# Optimistic UI Reference Patterns

Concrete patterns for stable-key reconciliation, flicker-free optimistic image uploads, and real-time event deduplication.

## 1. Stable `clientId` State & In-Place Reconciliation

```ts
export type OptimisticStatus = "pending" | "synced" | "failed";

export interface MessageItem {
  clientId: string;        // Immutable React/UI key — NEVER changes
  serverId?: string;       // Filled on reconciliation
  body: string;
  status: OptimisticStatus;
  error?: string;
}

export function insertOptimistic(
  items: MessageItem[],
  body: string
): { next: MessageItem[]; optimistic: MessageItem } {
  const optimistic: MessageItem = {
    clientId: crypto.randomUUID(),
    body,
    status: "pending",
  };
  return { next: [...items, optimistic], optimistic };
}

export function reconcileItem(
  items: MessageItem[],
  serverRecord: { id: string; clientId: string; body: string }
): MessageItem[] {
  const exists = items.some((m) => m.clientId === serverRecord.clientId);
  if (!exists) {
    return [
      ...items,
      {
        clientId: serverRecord.clientId,
        serverId: serverRecord.id,
        body: serverRecord.body,
        status: "synced",
      },
    ];
  }
  return items.map((m) =>
    m.clientId === serverRecord.clientId
      ? { ...m, serverId: serverRecord.id, body: serverRecord.body, status: "synced", error: undefined }
      : m
  );
}
```

Render strictly with `key={item.clientId}` so transitioning from `pending` -> `synced` never remounts the DOM node or replays enter animations.

## 2. Flicker-Free Optimistic Image Handoff

```ts
export async function computeFileHash(file: File): Promise<string> {
  const buffer = await file.arrayBuffer();
  const digest = await crypto.subtle.digest("SHA-256", buffer);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

export async function swapToRemoteImageSafely(
  remoteUrl: string,
  localBlobUrl: string,
  applySrc: (src: string) => void
): Promise<void> {
  const preload = new Image();
  preload.src = remoteUrl;
  await preload.decode();          // Wait until fully fetched & decoded off-screen
  applySrc(remoteUrl);             // Swap src with zero blank frame
  URL.revokeObjectURL(localBlobUrl);
}
```

Always lock the image container's geometry (`aspect-ratio` or explicit `width`/`height`) before upload begins so neither the blob preview nor the decoded remote image causes layout shift.

## 3. WebSocket / SSE Deduplication

Route both the REST response and real-time subscription payloads through the exact same `reconcileItem` reducer keyed by `clientId`. Because `reconcileItem` updates in place when `clientId` matches and appends only when unseen, whichever arrives first (REST or WebSocket) reconciles cleanly with zero duplicates.
