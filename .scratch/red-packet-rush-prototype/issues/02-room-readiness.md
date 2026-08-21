# 02 - Create and prepare a four-participant room

**What to build:** A player can create or join a four-seat room, see ownership and readiness, configure the allowed settings as host, fill open seats with bots, and start only when every seat is ready.

**Blocked by:** 01 - Connect to the live lobby.

**Status:** done

- [x] Creating and joining a room establishes one seat per human session and rejects invalid or duplicate occupancy.
- [x] All participants see the same four seats, nicknames, bot markers, readiness, host, deck mode, and action deadline.
- [x] Only the host can change one/two-deck mode, choose 15/30/60 seconds, fill bots, or start.
- [x] Humans can toggle ready; bots are always ready; configuration changes clear human readiness.
- [x] Start is rejected until exactly four seats are ready and accepted exactly once afterward.
- [x] A waiting participant can leave, the seat is released, and host ownership transfers deterministically.
- [x] Started, full, private, or locked rooms cannot be joined from a stale listing.

## Review

- TDD: `23a4781` and the review repairs added `GameRoomReadiness.test.ts` plus room-store, room-screen, adapter, app-shell, lobby, and Native SDK smoke coverage alongside the implementation.
- Standards: 0 hard findings after documenting the implementation-ticket lifecycle. One Duplicated Code judgement call is accepted for the prototype: the Lobby and Room screens keep their small local theme/build helpers because their interaction styling already diverges and a shared UI framework would add coupling (`a4d2a99...fa633f5`).
- Spec: 0 findings (`a4d2a99...fa633f5`).
- Verification: the completion audit's clean checkout passed 129 server tests, TypeScript build, all eight Godot runners, the delivery matrix, and the real four-client Native SDK smoke; room permission, readiness, stale join, and screen flows are included.
