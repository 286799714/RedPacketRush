# 06 - Discard awards and rotate the actor

**What to build:** Every award recipient must restore an eight-card hand by discarding an older card, after which the server visibly chooses the next actor and opens another complete turn.

**Blocked by:** 05 - Resolve secret claims and collisions.

**Status:** done

- [x] Each recipient has nine private cards until submitting one discard and non-recipients remain at eight.
- [x] The card awarded this turn cannot be discarded; stale, duplicate, or unowned discard commands do not mutate state.
- [x] All required discards are public events and no next turn opens until every recipient is complete.
- [x] The next actor is the recipient with the greatest awarded rank then suit.
- [x] Exact duplicate rank-and-suit ties choose the nearest tied seat clockwise after the current actor; deck-copy identity is never a strength.
- [x] If all participants passed and no card was awarded, the same actor continues.
- [x] At every turn boundary all hands contain eight cards and every physical card exists in exactly one valid zone.
- [x] The Godot client forces eligible recipients into discard mode and then updates actor and controls without layout shift.

## Review

- Standards: 0 findings after repair (`51e1e88...ec9edcc`).
- Spec: 0 findings after repair (`51e1e88...ec9edcc`).
- Verification: server 84 tests, TypeScript build, seven Godot runners, and Native four-client smoke all passed. Existing Godot ObjectDB/resource exit warnings remain non-fatal.
