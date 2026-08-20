# 02 - Create and prepare a four-participant room

**What to build:** A player can create or join a four-seat room, see ownership and readiness, configure the allowed settings as host, fill open seats with bots, and start only when every seat is ready.

**Blocked by:** 01 - Connect to the live lobby.

**Status:** ready-for-agent

- [ ] Creating and joining a room establishes one seat per human session and rejects invalid or duplicate occupancy.
- [ ] All participants see the same four seats, nicknames, bot markers, readiness, host, deck mode, and action deadline.
- [ ] Only the host can change one/two-deck mode, choose 15/30/60 seconds, fill bots, or start.
- [ ] Humans can toggle ready; bots are always ready; configuration changes clear human readiness.
- [ ] Start is rejected until exactly four seats are ready and accepted exactly once afterward.
- [ ] A waiting participant can leave, the seat is released, and host ownership transfers deterministically.
- [ ] Started, full, private, or locked rooms cannot be joined from a stale listing.
