# 01 - Five-card server rules and final settlement

**Status:** done

- [x] Deal five opening cards to all four participants.
- [x] Keep play/draw and award/discard transitions at a normal five-card hand.
- [x] Use hearts, diamonds, spades, clubs for equal-rank deterministic comparison.
- [x] Automatically settle the highest-scoring three-card subset from each five-card hand.
- [x] Preserve score categories, privacy, bots, deadlines, co-winners, and final reveal/finished phases.
- [x] Cover the rules with server unit and room tests.

## TDD slices

- Updated opening/play/claim/discard tests around the five-card boundary before accepting the new domain behavior.
- Replaced the eight-card/two-group settlement fixtures with five-card/all-ten-subset cases, including malformed input and deterministic tie-breaks.
- Added room-level automatic reveal, reconnect, timer, bot, co-winner, and score-once coverage before removing the reachable commit phase.

## Standards review

- Centralized rank/suit strength in `cards.ts`; copy index and physical ID remain stable-selection fallbacks only.
- Kept server authority, private-hand isolation, immutable results, physical-card zone checks, and the existing reveal/finished transition.
- Independent review found no server blocker or high-severity issue.

## Spec review

- Confirmed five-card opening, play-three/draw-three, six-to-five award discard, exact suit order, automatic five-choose-three settlement, and one score addition.
- Confirmed `finalResults.groups` remains an array for protocol compatibility but contains exactly one group.

## Verification

- Node.js 24.19: 128 server tests passed.
- `npm run build`: passed.
- Full `scripts/verify.ps1 -SkipInstall`: passed.
- Four-client Native SDK smoke: passed with five-card private hands and an 84-card two-deck opening draw pile.

## Commits

- `93d5479` — `feat: 完成五张手牌与自动终局`

## Comments

- Approved by the user on 2026-08-22; final play-preview copy is `牌型 · +N 分`.
