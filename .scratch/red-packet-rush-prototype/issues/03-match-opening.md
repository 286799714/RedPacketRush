# 03 - Start a match and deal private hands

**What to build:** Four prepared participants can enter a visible point contest, resolve repeated ties, receive private eight-card hands from a reshuffled full deck, and arrive at the first actor-play phase on the match table.

**Blocked by:** 02 - Create and prepare a four-participant room.

**Status:** done

- [x] One- and two-deck physical cards have stable unique identifiers without jokers.
- [x] The point contest compares rank then suit, repeats only among tied leaders, and always selects one first actor under deterministic tests.
- [x] Contest cards return before the full deck is shuffled and four eight-card hands are dealt.
- [x] Public state reveals contest events, first actor, phase, deck count, scores, and hand counts but no private cards.
- [x] Each human receives only their own complete private hand; no client receives another hand.
- [x] The Godot match table renders four participants, contest history, actor, deck count, and the local hand.
- [x] Fixed random sequences cover immediate and repeated point-contest ties in automated tests.

## Review

- TDD: `ffb62c1` and `68ae920` added pure-engine, room, match-store, match-screen, adapter, app-shell, and Native SDK smoke coverage with the match-opening implementation and review repair.
- Standards: 0 hard findings after documenting the implementation-ticket lifecycle. One Data Clumps judgement call is accepted for the prototype: participant, card, and point-contest views stay as adapter-normalized dictionaries rather than a parallel client object graph (`fa633f5...c054af3`).
- Spec: 0 findings (`fa633f5...c054af3`).
- Verification: the completion audit's clean checkout passed 129 server tests, TypeScript build, all eight Godot runners, the delivery matrix, and the real four-client Native SDK smoke; deterministic tie redraws and private-hand isolation are included.
