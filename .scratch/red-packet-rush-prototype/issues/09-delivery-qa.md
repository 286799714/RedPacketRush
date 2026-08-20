# 09 - Finish the playable desktop delivery

**What to build:** The complete lobby-room-match journey has cohesive Chinese presentation, responsive table layout, visible feedback for every state, a real SDK-to-server smoke path, and concise run instructions for local play.

**Blocked by:** 08 - Keep timed and disconnected matches moving.

**Status:** ready-for-agent

- [ ] Lobby, waiting room, match, final results, disconnected, empty, loading, validation, and retry states use one coherent visual system.
- [ ] Card rank and suit remain readable without relying on color alone; interactive and disabled states are distinct.
- [ ] Short reveal and collision motion communicates state change and honors reduced-motion behavior where available.
- [ ] Screens at 1280x720 and 960x540 contain no overlapping, clipped, or off-screen essential text and controls.
- [ ] A live smoke test proves Godot matchmaking, joining, one private hand message, one player intent, and one public state update against a local server.
- [ ] Server unit/integration tests, TypeScript build, Godot headless parse/run checks, and the full bot-assisted match pass from a clean checkout.
- [ ] Run documentation states exact Node, Godot, SDK, install, server, and client steps plus prototype limitations.
- [ ] No generated cache, secret, dependency directory, or editor-local state is tracked.
