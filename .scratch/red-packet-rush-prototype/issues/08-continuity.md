# 08 - Keep timed and disconnected matches moving

**What to build:** Deadlines, bots, leave handling, and reconnection keep every waiting room and every match phase progressing without leaking private state or abandoning a seat.

**Blocked by:** 07 - Complete final settlement.

**Status:** claimed

- [ ] Every actionable phase publishes one server deadline and performs a legal deterministic fallback exactly once when it expires.
- [ ] Bots submit legal plays, claims or passes, required discards, and optimal final combinations through the same rule boundary as humans.
- [ ] A consented waiting-room leave releases the seat and transfers host ownership when needed.
- [ ] An abnormal in-match disconnect preserves the human seat for a 30-second reconnection window and visibly marks it disconnected.
- [ ] A valid reconnect restores the same participant and sends fresh public and private snapshots without duplicating a seat.
- [ ] Expired reconnection hands control to a visible bot and unblocks the current phase.
- [ ] Reconnect and timeout races during play, claim commit, award discard, and final commit resolve once without stale commands winning.
- [ ] Room-level tests can complete a full bot-assisted match without manual timing or nondeterministic sleeps.
