# 05 - Resolve secret claims and collisions

**What to build:** Each non-actor can privately claim one played card or pass, then all choices reveal together and resolve into pass points, unique awards, or blind collision awards exactly once.

**Blocked by:** 04 - Play and score a combination.

**Status:** done

- [x] Only the three non-actors can commit one valid played-card identifier or pass during claim commit.
- [x] A commit is acknowledged only to its owner and no unrevealed choice appears in shared state or another client's messages.
- [x] Claims reveal only after all three commits or the configured deadline.
- [x] Passers receive exactly one point and unique claimants receive the exact selected physical card.
- [x] Unique awards are removed before all remaining played cards are shuffled for collision participants.
- [x] All-pass, three-unique, two-collision-plus-unique, two-collision-plus-pass, and three-player-collision cases are deterministic under fixed random input.
- [x] The Godot table presents one secret choice, a pass action, waiting state, simultaneous reveal, collision motion, and public outcome history.

## Review

- TDD: `16928b4`, `368a6c4`, and `d05fbd6` added pure claim-resolution, room privacy, match-store, match-screen, adapter, and Native SDK smoke coverage with each implementation and review slice.
- Standards: 0 findings (`8e71eea...d05fbd6`).
- Spec: 0 findings (`8e71eea...d05fbd6`).
- Verification: server 72 tests, TypeScript build, seven Godot runners, and Native four-client smoke all passed. Existing Godot ObjectDB/resource exit warnings remain non-fatal.
