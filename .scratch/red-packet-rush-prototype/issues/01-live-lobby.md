# 01 - Connect to the live lobby

**What to build:** A player can launch the Godot client, enter a temporary nickname, connect through the pinned official Colyseus Native SDK, and watch the public list of joinable game rooms update in real time.

**Blocked by:** None - can start immediately.

**Status:** ready-for-agent

- [ ] The client exposes connecting, connected, retryable error, and disconnected states in Simplified Chinese.
- [ ] The server registers a live lobby and only advertises joinable game rooms.
- [ ] Room additions, metadata changes, and removals update without manually refreshing.
- [ ] The SDK version and generated-schema workflow are pinned and reproducible.
- [ ] Generated caches, build output, secrets, and editor-local files are ignored by Git.
- [ ] An automated integration check proves that a newly created room appears and a locked room disappears.
