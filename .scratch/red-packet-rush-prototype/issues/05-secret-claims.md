# 05 - Resolve secret claims and collisions

**What to build:** Each non-actor can privately claim one played card or pass, then all choices reveal together and resolve into pass points, unique awards, or blind collision awards exactly once.

**Blocked by:** 04 - Play and score a combination.

**Status:** in-progress

- [ ] Only the three non-actors can commit one valid played-card identifier or pass during claim commit.
- [ ] A commit is acknowledged only to its owner and no unrevealed choice appears in shared state or another client's messages.
- [ ] Claims reveal only after all three commits or the configured deadline.
- [ ] Passers receive exactly one point and unique claimants receive the exact selected physical card.
- [ ] Unique awards are removed before all remaining played cards are shuffled for collision participants.
- [ ] All-pass, three-unique, two-collision-plus-unique, two-collision-plus-pass, and three-player-collision cases are deterministic under fixed random input.
- [ ] The Godot table presents one secret choice, a pass action, waiting state, simultaneous reveal, collision motion, and public outcome history.
