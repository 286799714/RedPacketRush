# Red Packet Rush Playable Prototype

**Status:** ready-for-agent

## Problem Statement

The repository contains an empty Colyseus server template and an empty Godot project, but no playable experience. A player cannot discover a room, gather four participants, configure a match, play the card-and-claim loop, recover from a disconnect, or complete final settlement. The prototype must make the full rules understandable and independently testable while preventing clients from seeing or deciding private and random game state.

## Solution

Build a desktop Godot prototype with three connected surfaces: a public lobby, a four-seat room, and a complete match table. Colyseus owns room lifecycle and every game decision. Humans use temporary nicknames, a host configures deck mode and the action deadline, and bots can fill empty seats so one person can test the whole game. The client renders public snapshots and targeted private state, sends only player intentions, and presents every required choice without exposing hidden hands or claim commits.

## User Stories

1. As a player, I want to enter a temporary nickname, so that I can be identified without creating an account.
2. As a player, I want to see whether the server is connected, so that I know when room actions are available.
3. As a player, I want to see currently joinable rooms update live, so that I do not act on stale availability.
4. As a player, I want to create a named room, so that I can host a match.
5. As a player, I want to join a listed room with one action, so that gathering players is quick.
6. As a player, I want full or started rooms to be unavailable, so that I cannot enter an invalid seat.
7. As a room participant, I want to see all four seats and their readiness, so that I know what blocks the match.
8. As a host, I want to choose one-deck or two-deck mode, so that I can select the intended match length.
9. As a host, I want to choose a 15, 30, or 60 second action deadline, so that the room can set its pace.
10. As a host, I want to fill open seats with bots, so that the fixed four-participant match is testable alone.
11. As a human participant, I want to toggle ready, so that starting the match is consensual.
12. As a participant, I want bots to be visibly identified and always ready, so that their status is unambiguous.
13. As a host, I want start disabled until exactly four seats are ready, so that an invalid match cannot begin.
14. As a non-host, I want host-only controls disabled, so that configuration ownership is clear.
15. As a participant, I want the host role to transfer when the waiting host leaves, so that the room remains usable.
16. As a lobby user, I want a started room removed from the joinable list, so that the list remains accurate.
17. As a participant, I want the opening point contest shown as public reveals, so that the first actor is auditable.
18. As a tied point-contest leader, I want only tied leaders to draw again, so that a unique actor is eventually selected.
19. As a participant, I want contest cards returned and reshuffled before dealing, so that every match starts from a full configured deck.
20. As a participant, I want exactly eight private cards after the deal, so that all seats begin equally.
21. As an actor, I want only my legal three-card play control enabled, so that I cannot issue an out-of-phase command.
22. As an actor, I want to select exactly three distinct cards from my hand, so that the play is valid.
23. As an actor, I want the played combination and its score shown immediately, so that scoring is understandable.
24. As an actor, I want to draw three private cards after playing, so that my hand returns to eight.
25. As a participant, I want a three-card combination to score only its highest applicable category, so that scores do not double count.
26. As a participant, I want pairs to score 2, flushes 4, straights 5, three of a kind 8, straight flushes 10, and high card 0, so that the stated score table is enforced.
27. As a participant, I want A-2-3 and Q-K-A to count as straights but not K-A-2, so that Ace behavior is predictable.
28. As a non-actor, I want to secretly claim one played card or pass, so that other players cannot react to my choice.
29. As a non-actor, I want my claim commit confirmed privately, so that I know it was accepted without revealing it.
30. As a participant, I want all claim choices revealed together after every commit or the deadline, so that early submissions give no information advantage.
31. As a passer, I want to gain one point at reveal, so that declining card competition has the stated value.
32. As a unique claimant, I want to receive the exact card I selected, so that uncontested claims resolve directly.
33. As a collision participant, I want unique awards removed before remaining played cards are shuffled, so that the collision pool follows the example.
34. As a collision participant, I want one remaining card awarded blindly, so that every colliding participant receives exactly one card.
35. As a participant, I want unused played cards to enter the public discard history, so that card movement is auditable.
36. As an award recipient, I want to discard one original hand card, so that my hand returns from nine cards to eight.
37. As an award recipient, I want the newly awarded card protected from immediate discard, so that receiving a card has a real consequence.
38. As a participant, I want all required discards completed before the next turn, so that no one starts with an invalid hand.
39. As a participant, I want the highest awarded card to determine the next actor, so that turn ownership follows the rules.
40. As a participant, I want rank ties ordered clubs, spades, diamonds, then hearts, so that red beats black and hearts are highest.
41. As a participant, I want exact duplicate ties in two-deck mode resolved by the nearest eligible seat clockwise after the current actor, so that the result is deterministic and visible.
42. As the current actor, I want to act again when everyone passes, so that a turn always has a successor.
43. As a participant, I want a new turn blocked when fewer than three draw cards remain, so that no partial turn can corrupt hand size.
44. As a participant, I want any one-deck remainder sealed when final settlement begins, so that the end condition is explicit.
45. As a participant, I want to select two disjoint three-card combinations from my eight cards, so that final settlement follows the rules.
46. As a participant, I want a best-combination action, so that I can finish final settlement quickly.
47. As an inactive or bot participant, I want final selection to default to the highest scoring legal pair of combinations at the deadline, so that the match cannot stall.
48. As a participant, I want final choices hidden until all participants lock them, so that no one can optimize in response to another reveal.
49. As a participant, I want the two final combination scores added to my running score, so that the final ranking is correct.
50. As a tied top scorer, I want to share victory, so that no unstated tie-break changes the result.
51. As a participant, I want the current phase, actor, deck count, four scores, hand counts, and event history always visible, so that I can understand the match state.
52. As a participant, I want only my own hand and unrevealed claim visible to me, so that private information stays private.
53. As a disconnected human, I want 30 seconds to reconnect to my seat, so that a brief network interruption does not end my game.
54. As the other participants, I want a timed-out disconnected seat taken over by a bot, so that the match continues.
55. As a reconnected human, I want a fresh authoritative public and private snapshot, so that my client cannot resume from stale state.
56. As a player, I want clear disabled, waiting, timeout, connection, validation, and finished states, so that every workflow has visible feedback.
57. As a desktop player, I want the table to remain usable from 1280x720 down to 960x540, so that common window sizes do not overlap or clip controls.

## Implementation Decisions

- Use the official Colyseus Native Godot SDK pinned to `godot-v0.17.11` and GDScript. Encapsulate it behind one realtime-client adapter so scene controllers never handle protocol details.
- Use Colyseus 0.17's built-in lobby room for live listings and one custom game room with realtime listing enabled. Starting a match makes the room private and locked so it disappears reliably from the lobby.
- Treat the server as the sole authority. Clients send typed intentions for create, join, configure, ready, start, play, claim, discard, and final selection; the server validates identity, ownership, phase, payload shape, and card ownership.
- Keep the rules engine independent of room transport. It receives an injectable seeded random source and emits public events plus per-participant private state.
- Represent every physical card with an immutable identifier, rank, suit, and deck-copy index. Claims and selections reference physical identifiers, while comparisons ignore the copy index.
- Use a 52-card pack without jokers. Rank is 2 through A. Suit order is clubs, spades, diamonds, hearts. Ace is low only for A-2-3 and high for Q-K-A.
- Model the match as explicit phases: waiting, point contest, actor play, claim commit, claim reveal, award discard, final commit, final reveal, and finished. Reject stale and duplicate commands without mutating state.
- Store only public match data in synchronized room state: room status, settings, seats, readiness, phase, actor, scores, hand counts, deck count, played cards after play, revealed claim results, deadlines, and public events.
- Deliver private hands, private claim confirmation, reconnect snapshots, and any unrevealed personal choice only through targeted messages.
- Support deck mode and action deadline as the only persistent room settings. Bots are a host command rather than a rules variant.
- Start with exactly four ready seats. Bots use normal seats and legal intents, select plays and claims with a simple seeded strategy, satisfy discards, and optimize final settlement.
- During the point contest, tied leaders alone draw again. Return all contest cards, shuffle the full configured deck, then deal eight cards to each participant.
- Score a played combination once using the highest category in this order: straight flush, three of a kind, straight, flush, pair, high card.
- Resolve claims atomically. Remove unique awards first, shuffle every remaining played card, then award one blind card to each participant in the single possible collision group. Passers receive one point. Discard every unawarded table card after resolution.
- Require every award recipient to discard one card that was in their hand before the award. Do not recycle played or discarded cards.
- Select the next actor among award recipients by awarded-card rank and suit. Resolve a remaining physical duplicate tie by clockwise seat order after the current actor. If there are no recipients, retain the current actor.
- Check draw-pile capacity before opening an actor-play phase. With fewer than three cards, seal the remainder and enter final settlement.
- Require two disjoint final combinations. Keep commits private until all are locked, auto-optimize on timeout, add both combination scores, and allow co-winners.
- Give every actionable phase the room's configured deadline. Invalid commands receive a private error and do not consume the participant's opportunity. At deadline, the server makes a legal deterministic choice.
- Allow abnormal disconnects to reconnect for 30 seconds. Before a match, remove the departed seat and transfer host ownership; during a match, retain the seat and let a bot take control after grace expires.
- Build one persistent Godot application shell with lobby, room, and match screens. Render a dense desktop card-table interface in Simplified Chinese with clear suit symbols, a public event log, short claim-resolution motion, and phase-gated controls.

## Testing Decisions

- Test externally observable behavior instead of private methods or scene-tree implementation details. The main acceptance seam is a real in-process Colyseus room receiving player intents and producing synchronized public state plus targeted private messages.
- Cover combination scoring, card comparison, shuffling, point-contest ties, claim resolution, next-actor selection, deck exhaustion, and optimal final grouping at the pure rules-engine seam with fixed random sequences.
- Cover room creation, live lobby listing, four-seat readiness, host permissions, start locking, invalid or duplicate messages, private information isolation, deadline actions, leave, reconnect, and bot takeover using the existing Colyseus testing harness and Mocha assertion style.
- Cover Godot lobby-room-match navigation and every phase-gated control with a fake realtime adapter that feeds representative public and private snapshots.
- Keep one live smoke path from the headless Godot project through the official Native SDK to a local Colyseus process, proving matchmaking, room join, one private hand delivery, and one public state update.
- Run visual checks at 1280x720 and 960x540 for the lobby, full waiting room, actor play, secret claim, discard, final settlement, disconnected, error, and finished states. Reject clipping, overlap, unreadable card identity, or secrets appearing in shared UI.
- Add security-oriented assertions that one client's synchronized state and targeted messages never contain another participant's hand or unrevealed claim.

## Out of Scope

- Accounts, passwords, profiles, databases, persistent progression, currencies, purchases, analytics, or cloud deployment.
- Password rooms, invitations, friends, matchmaking queues, chat, spectators, late join, tournament flow, or room search.
- Mobile exports, console exports, browser exports, localization beyond Simplified Chinese, controller support, or production accessibility certification.
- Production-grade bot intelligence, skill-based matchmaking, anti-cheat beyond server authority and payload validation, or cryptographically verifiable randomness.
- Additional deck types, jokers, configurable scoring tables, configurable participant count, house rules, replays, or saved matches.

## Further Notes

- Runtime and CI should use Node.js 22 or newer because the resolved Colyseus core dependency requires it even though the template declares an older minimum.
- The official Godot SDK is beta. Pinning its release and isolating it behind an adapter are explicit risk controls; the integration research note records the primary-source compatibility evidence.
- The one-deck mode produces six complete turns after the initial deal and leaves two sealed cards before final settlement unless claim-independent future rules change draw-pile consumption.
