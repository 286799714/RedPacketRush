# 07 - Complete final settlement

**What to build:** A match stops before an actor cannot draw three cards, lets every participant privately lock two disjoint final combinations or choose the best legal option, then reveals final scores and co-winners.

**Blocked by:** 06 - Discard awards and rotate the actor.

**Status:** done

- [x] A new actor-play phase never opens with fewer than three draw cards; any remainder is sealed and shown publicly.
- [x] One-deck mode reaches final settlement after six complete turns with the expected two-card remainder under normal consumption.
- [x] Each submission contains two disjoint three-card groups owned by that participant and leaves two unused cards.
- [x] The server can deterministically find a maximum-scoring legal pair of groups for bots, timeouts, and the client's best-choice request.
- [x] Final commits remain private until all four are locked, then selected cards and both combination scores reveal together.
- [x] Both final scores add to running score exactly once and all equal top scores produce co-winners.
- [x] The Godot client supports manual grouping, best-choice selection, lock confirmation, waiting, reveal, and finished ranking states.
- [x] Automated tests cover invalid overlap, optimal-selection ties, duplicate submission, score addition, and co-winners.

## Review

- Standards: 0 findings (`7ad6975...bed9625`).
- Spec: 0 findings (`7ad6975...bed9625`).
- Verification: server 95 tests, TypeScript build, seven Godot runners, Native four-client smoke, and GPU visual checks at 960x540 and 1280x720 all passed. Existing Godot ObjectDB/resource exit warnings remain non-fatal.
