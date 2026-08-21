# 08 - Keep timed and disconnected matches moving

**What to build:** Deadlines, bots, leave handling, and reconnection keep every waiting room and every match phase progressing without leaking private state or abandoning a seat.

**Blocked by:** 07 - Complete final settlement.

**Status:** done

- [x] Every actionable phase publishes one server deadline and performs a legal deterministic fallback exactly once when it expires.
- [x] Bots submit legal plays, claims or passes, required discards, and optimal final combinations through the same rule boundary as humans.
- [x] A consented waiting-room leave releases the seat and transfers host ownership when needed.
- [x] An abnormal in-match disconnect preserves the human seat for a 30-second reconnection window and visibly marks it disconnected.
- [x] A valid reconnect restores the same participant and sends fresh public and private snapshots without duplicating a seat.
- [x] Expired reconnection hands control to a visible bot and unblocks the current phase.
- [x] Reconnect and timeout races during play, claim commit, award discard, and final commit resolve once without stale commands winning.
- [x] Room-level tests can complete a full bot-assisted match without manual timing or nondeterministic sleeps.

## Review

- TDD: `e3bcc47` through `8d5e58b` added deterministic bot, deadline, full-match, disconnect, reconnect, takeover, and four-phase race regressions alongside the implementation and its review repairs.
- Standards: 0 findings after repair (`a8cdef8...8d5e58b`).
- Spec: 0 findings after repair (`a8cdef8...8d5e58b`).
- Verification: server 129 tests, TypeScript build, seven Godot runners, Native four-client SDK smoke, driver-level matchmaking race gates, and GPU visual checks at 960x540 and 1280x720 all passed. Existing Godot ObjectDB/resource exit warnings remain non-fatal.
