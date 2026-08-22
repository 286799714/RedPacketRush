# Five-card Hand and Match UX

**Status:** done

## Problem Statement

The current match deals eight cards, requires two disjoint three-card groups at final settlement, leaves hand order dependent on snapshot order, and provides no assistance for choosing a strong play. Newly obtained cards are visually indistinguishable from older cards, the selected play has no score preview, and a finished match has no direct route back to the lobby.

## Goals

1. Keep every participant's normal hand at five cards.
2. Make card ordering and every deterministic best-choice tie-break use rank first and suit second.
3. Make newly drawn or awarded cards easy to identify without interfering with selection feedback.
4. Let the actor select the highest-scoring legal three-card play with one action and see its immediate score.
5. Settle the match from the single highest-scoring three-card group in each five-card hand.
6. Let a participant leave a finished match and return to the lobby with one action.

## Rules

### Hand size and card order

- Deal five private cards to every participant after the point contest.
- An actor still plays exactly three cards and immediately draws exactly three, returning the hand to five.
- An award recipient temporarily holds six cards and must discard one non-awarded card, returning the hand to five.
- Display hands from strongest to weakest by rank: A, K, Q, J, 10 through 2.
- For equal ranks, display and deterministic selection order is hearts, diamonds, spades, clubs (红桃 > 方片 > 黑桃 > 梅花).
- In two-deck mode, `copyIndex` and then physical card ID provide an invisible stable fallback only when rank and suit are identical. They do not change scoring.

### Combination scoring and best-choice tie-break

- Preserve the existing three-card classification and score table:
  - straight flush: 10
  - three of a kind: 8
  - straight: 5
  - flush: 4
  - pair: 2
  - high card: 0
- Preserve the existing straight rules: A-2-3 and Q-K-A are valid; K-A-2 is not.
- A best-choice operation enumerates every three-card subset of the current hand.
- It first chooses the group with the largest score. When several groups have the same score, compare their cards from strongest to weakest using rank and the suit order above, then use the stable physical-card fallback if necessary.
- The server remains authoritative for plays and final settlement. Client-side evaluation exists only for immediate selection and display and must be covered by matching rule fixtures.

### Final settlement

- When fewer than three draw cards remain before a new actor-play phase, preserve the existing behavior of sealing the remainder.
- The server automatically evaluates all ten three-card subsets of each five-card hand and chooses the best group using the canonical tie-break.
- Each participant receives the score of that one group exactly once. Add it to the participant's running score and determine all co-winners from the resulting totals.
- Final settlement does not wait for manual A/B grouping or private final commits. Reveal every participant's chosen group and score together, then continue through the existing final reveal and finished states.

## Client Experience

### Sorted hand and acquisition highlight

- Sort the local hand before rendering it; card identity and current selection survive reordering.
- Do not mark the opening five cards as newly acquired.
- After the local actor successfully plays three cards, mark exactly the three replacement cards with a blue outline.
- When the local participant receives an awarded card, mark that exact card with a blue outline, including during the required discard choice.
- The newest acquisition event replaces the previous blue-highlight set. A highlighted card stays blue until another acquisition event replaces the set, it leaves the hand, or the match view is reset.
- The normal selected-card outline has visual priority over blue. If the player deselects a still-highlighted card, its blue outline returns.

### Hint and play preview

- Add a `提示` button beside the actor's play controls.
- Enable it only when the local participant may legally choose a three-card play. Pressing it replaces the current play selection with the canonical best group from the local hand.
- When exactly three cards are selected and the `出牌` button is enabled, show the selected category and its score beside the button in the exact format `顺子 · +5 分` (using the appropriate category label and score).
- Hide the preview whenever the selection is not a playable three-card group. The preview is the score added by this play, not the participant's projected total score.
- Server validation remains unchanged: the client hint and preview do not authorize or score a play.

### Return to lobby

- In the `finished` phase, show a `返回大厅` button.
- Pressing it uses the existing leave-game-room flow. The application shell clears the room and match screens and shows the lobby.
- Prevent duplicate leave requests while the first request is in progress and surface the existing connection/error state if leaving fails.

## Architecture

- Change the opening hand constant and final-settlement model in the TypeScript match domain. Keep combination classification as a pure function and replace the two-group optimizer with a one-group optimizer for a five-card hand.
- Expose one canonical TypeScript comparison helper for rank/suit ordering so hand-related server decisions do not retain the previous suit order accidentally.
- Add a small pure GDScript combination evaluator/comparator used by sorting, hint selection, and the play preview. Mirror canonical server fixtures in Godot tests to guard cross-language parity.
- Let `MatchStore` derive newly added local physical-card IDs from consecutive authoritative private snapshots and public award context. Keep acquisition tracking out of the scene controller.
- Let `MatchScreen` own presentation priority, selection behavior, and phase-gated buttons. Reuse the established application-shell leave path for returning to the lobby.

## Error Handling and State Transitions

- Reject malformed or non-owned play identifiers without mutating the authoritative match.
- If a stale client preview differs from the authoritative snapshot, the existing command error and next snapshot win; no score is predicted beyond the currently held cards.
- Reset selected IDs and acquisition highlights when leaving the match or replacing the active match store.
- A disconnect/reconnect snapshot re-establishes the current hand. It must not label every restored card as newly drawn; only an acquisition that can be identified from the current match transition is blue.
- Bots and deadlines use the same canonical best-group evaluator as humans and final settlement.

## Verification

- TypeScript unit tests cover five-card opening hands, play/draw returning to five, award/discard returning from six to five, rank/suit comparison, all ten final candidates, deterministic equal-score ties, one-group score addition, and co-winners.
- Room tests cover public hand counts, private five-card snapshots, automatic terminal settlement, bots/deadlines, and unchanged information isolation.
- Godot tests cover sorted rendering data, matching combination categories/scores, best-three selection, preview text and visibility, blue highlight replacement/selection precedence, reconnect behavior, and finished-phase lobby navigation.
- Run the full server tests and TypeScript build. Run available headless Godot test runners and report explicitly if the Godot executable is unavailable in the environment.

## Out of Scope

- Changing combination categories, scores, Ace behavior, claim resolution, or the protected-award discard rule.
- Adding server round trips for each hint or preview update.
- Persisting blue highlight state across leaving a room or restarting the client.
- Redesigning the lobby or the rest of the match table beyond the controls required here.

## Delivery

- Implemented in `93d5479` (`feat: 完成五张手牌与自动终局`).
- Verified with Node.js 24.19, Godot 4.7.1, the full repository suite, the 16-state delivery matrix, and the four-client Native SDK smoke test.
- Independent Spec/Standards review found no blocking or high-severity issues. Its selection-refresh finding was repaired and re-reviewed before delivery.
