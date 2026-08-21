# 04 - Play and score a combination

**What to build:** The current actor can select exactly three owned cards, play them publicly, receive the correct highest-category score, and draw three private replacement cards while every other participant remains read-only.

**Blocked by:** 03 - Start a match and deal private hands.

**Status:** done

- [x] The classifier scores high card 0, pair 2, flush 4, straight 5, three of a kind 8, and straight flush 10 without double counting.
- [x] A-2-3 and Q-K-A are straights; K-A-2 is not; two-deck duplicate edge cases score correctly.
- [x] Only the actor can submit exactly three distinct card identifiers currently in their hand.
- [x] A valid play atomically removes three cards, adds its score, publishes the played cards, and privately draws back to eight.
- [x] Wrong-phase, malformed, duplicate, stale, or unowned-card commands leave state unchanged and return a private error.
- [x] The Godot hand supports clear three-card selection, a stable action control, disabled non-actor state, and visible score feedback.

## Review

- TDD: `a97a5ec` and its review repairs added combination, engine-play, room-play, match-store, match-screen, adapter, and Native SDK smoke coverage alongside the implementation.
- Standards: 0 hard findings after documenting the implementation-ticket lifecycle. One Data Clumps judgement call is accepted for the prototype: card and play-event dictionaries remain normalized once at the realtime-adapter boundary and consumed as view data (`d36eb5...1db088d`).
- Spec: 0 findings (`d36eb5...1db088d`).
- Verification: the completion audit's clean checkout passed 129 server tests, TypeScript build, all eight Godot runners, the delivery matrix, and the real four-client Native SDK smoke; every scoring category, Ace boundary, atomic rejection, and draw-to-eight path is included.
