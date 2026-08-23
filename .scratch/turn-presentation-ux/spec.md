# Turn presentation and card-face UX

## Problem

The transition from an actor's play through claims and required discards is too fast and too text-heavy. Awarded cards are also treated as protected even though recipients should be free to discard any one of their six cards.

## Required behavior

- After receiving a claimed card, a participant may discard any owned card, including that newly awarded card.
- During actionable `actor_play`, the center shows only `请选择 3 张牌打出`; the latest point contest remains available in history instead of occupying the table center.
- An actor play enters a three-second `play_reveal` presentation phase before claims open. The actor's seat region shows all three played cards, the combination label, and the score added.
- Claim resolution remains public for four seconds. Each recipient's seat region shows the exact awarded card with a blue border and the label `抢牌获得`.
- During `award_discard`, the center says `你需要弃置一张牌` for a pending local recipient and `等待其他玩家弃牌` otherwise; it does not show the latest point contest.
- As each recipient discards, their seat region shows the exact public discard. When all required discards are complete, a two-second `discard_reveal` buffer keeps every discard visible before the next actor is selected.
- A card drawn after playing is labeled `出牌获得`; a card awarded after claiming is labeled `抢牌获得`. Selection styling takes priority over the blue acquisition outline.
- Every interactive or public card display uses traditional playing-card face artwork. Text card identities remain in history, tooltips, and semantic control names where useful.
- A player's seat region means the open table area immediately inward from that player's information box, between the information box and table center. Played, awarded, and discarded cards must not cover the information box or an active center prompt.
- Card faces are large enough to read at both supported delivery resolutions and fill their presentation outline without decorative padding; only the thin selection or state outline may remain around the artwork.

## Authority and information boundaries

- The server owns presentation phases, durations, actor rotation, bot actions, and deadline actions.
- `play_reveal` and `discard_reveal` are non-actionable and publish no action deadline.
- Claim choices stay private until the existing simultaneous claim reveal.
- Played cards, awards, and discards are public audit events, so their seat-region presentation introduces no new secret data.

## Asset decision

Use the 52 face PNGs from Mesmedir's **Bridge-Sized Playing Card Deck (PNG, CC0)**. Omit jokers and backs. Record the source and CC0 license beside the assets.

## Verification

- TypeScript rule and room tests cover the two presentation phases, timer boundaries, bot/deadline continuity, reconnection races, awarded-card discard, and delayed actor rotation.
- Godot tests cover texture-backed faces, acquisition labels, selectable awarded cards, center prompts, per-seat play/award/discard panels, inward seat placement, non-overlap, and edge-to-edge card artwork.
- The delivery capture matrix includes `play_reveal`, `claim_reveal`, `award_discard`, and `discard_reveal` at 960×540 and 1280×720.
