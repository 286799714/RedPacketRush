# 09 - Finish the playable desktop delivery

**What to build:** The complete lobby-room-match journey has cohesive Chinese presentation, responsive table layout, visible feedback for every state, a real SDK-to-server smoke path, and concise run instructions for local play.

**Blocked by:** 08 - Keep timed and disconnected matches moving.

**Status:** done

- [x] Lobby, waiting room, match, final results, disconnected, empty, loading, validation, and retry states use one coherent visual system.
- [x] Card rank and suit remain readable without relying on color alone; interactive and disabled states are distinct.
- [x] Short reveal and collision motion communicates state change and honors reduced-motion behavior where available.
- [x] Screens at 1280x720 and 960x540 contain no overlapping, clipped, or off-screen essential text and controls.
- [x] A live smoke test proves Godot matchmaking, joining, one private hand message, one player intent, and one public state update against a local server.
- [x] Server unit/integration tests, TypeScript build, Godot headless parse/run checks, and the full bot-assisted match pass from a clean checkout.
- [x] Run documentation states exact Node, Godot, SDK, install, server, and client steps plus prototype limitations.
- [x] No generated cache, secret, dependency directory, or editor-local state is tracked.

## Review

- Standards: 0 findings after repair (`2bac80c...33e6c99`).
- Spec: 0 findings after repair (`2bac80c...33e6c99`).
- Verification: a content-clean checkout completed `npm ci`, 129 server tests, TypeScript build, Godot editor parse, eight Godot headless runners, the 17-state delivery matrix, tracked-artifact hygiene, and a real four-client Native SDK smoke covering matchmaking, private hand delivery, a player intent, and synchronized public claim reveal.
- Visual evidence: 34 GPU captures (17 states at both 960x540 and 1280x720) were checked for clipping and overlap, including participant disconnect, bot takeover, validation, retry, final reveal, and finished ranking. Existing Godot ObjectDB/resource exit warnings remain non-fatal.
