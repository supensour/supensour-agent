# Case: handling intentionally rejected promises (Vitest)

When code rejects a promise **synchronously** (e.g. in a `forEach`, queue-clear, or cleanup), attaching
the assertion handler *after* the rejection causes Vitest "Unhandled Rejection" errors — false failures
even when the test logic is right.

## Rule

Attach rejection/resolution handlers **before** triggering the rejection. Collect them, then await all.

```js
it('clears queued tasks', async () => {
  const p1 = executor.submit(callable)
  const p2 = executor.submit(callable)

  // 1. Attach assertions FIRST (this installs the .catch handler)
  const pending = []
  pending.push(expect(p1).resolves.toEqual(1))
  pending.push(expect(p2).rejects.toThrow('Task cancelled: queue cleared'))

  // 2. THEN trigger the synchronous rejection
  executor.clearQueue()

  // 3. Await all assertions
  await Promise.all(pending)
})
```

**Why:** `expect(p).rejects.toThrow()` immediately attaches a `.catch()`. Doing it before the trigger
means the handler is in place when the rejection fires → no unhandled-rejection warning.

## Alternatives (equivalent)

- Attach `.catch(err => err)` at submit time, then assert on the resolved error.
- `try { await p } catch (err) { expect(err.message).toBe(...) }` — wrap to assert.

## Use when

Queue clearing, concurrent-op error handling, callback/`forEach` rejections, cleanup that rejects
pending promises — any case where rejection happens synchronously before you can `await`.

## Takeaways

1. Timing matters — handlers before triggers.
2. Use a `pending`/`pendingExpects` array; `await Promise.all(pending)`.
3. Prefer `.resolves` / `.rejects` over `.catch` / `try-catch` for async assertions.
