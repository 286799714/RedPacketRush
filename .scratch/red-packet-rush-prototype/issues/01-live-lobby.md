# 01 - Connect to the live lobby

**What to build:** A player can launch the Godot client, enter a temporary nickname, connect through the pinned official Colyseus Native SDK, and watch the public list of joinable game rooms update in real time.

**Blocked by:** None - can start immediately.

**Status:** done

- [x] The client exposes connecting, connected, retryable error, and disconnected states in Simplified Chinese.
- [x] The server registers a live lobby and only advertises joinable game rooms.
- [x] Room additions, metadata changes, and removals update without manually refreshing.
- [x] The SDK version and generated-schema workflow are pinned and reproducible.
- [x] Generated caches, build output, secrets, and editor-local files are ignored by Git.
- [x] An automated integration check proves that a newly created room appears and a locked room disappears.

## Review

- TDD: `5386db5` added `LiveLobby.test.ts`, the lobby-store runner, and the Native SDK smoke together with the lobby implementation; `a4d2a99` then applied the review vocabulary repair.
- Standards: 0 hard findings after documenting the implementation-ticket lifecycle. One Data Clumps judgement call is accepted for the prototype: SDK room summaries remain normalized dictionaries at the realtime-adapter boundary instead of adding a second DTO layer (`a354f6d...a4d2a99`).
- Spec: 0 findings (`a354f6d...a4d2a99`).
- Verification: the completion audit's clean checkout passed 129 server tests, TypeScript build, all eight Godot runners, the delivery matrix, and the real four-client Native SDK smoke; the lobby listing integration and lobby-store coverage are included.
