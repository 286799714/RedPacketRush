# 06 - Discard awards and rotate the actor

**What to build:** Every award recipient must restore an eight-card hand by discarding an older card, after which the server visibly chooses the next actor and opens another complete turn.

**Blocked by:** 05 - Resolve secret claims and collisions.

**Status:** claimed

- [ ] Each recipient has nine private cards until submitting one discard and non-recipients remain at eight.
- [ ] The card awarded this turn cannot be discarded; stale, duplicate, or unowned discard commands do not mutate state.
- [ ] All required discards are public events and no next turn opens until every recipient is complete.
- [ ] The next actor is the recipient with the greatest awarded rank then suit.
- [ ] Exact duplicate rank-and-suit ties choose the nearest tied seat clockwise after the current actor; deck-copy identity is never a strength.
- [ ] If all participants passed and no card was awarded, the same actor continues.
- [ ] At every turn boundary all hands contain eight cards and every physical card exists in exactly one valid zone.
- [ ] The Godot client forces eligible recipients into discard mode and then updates actor and controls without layout shift.
