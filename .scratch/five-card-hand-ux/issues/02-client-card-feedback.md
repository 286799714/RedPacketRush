# 02 - Sorted hand, acquisition highlight, hint, and score preview

**Status:** done

- [x] Sort cards strongest-first by rank and hearts, diamonds, spades, clubs.
- [x] Track newly drawn and awarded physical card IDs without false reconnect highlights.
- [x] Render acquired cards with blue outlines and let selected styling take priority.
- [x] Add a hint action that selects the canonical best three cards.
- [x] Show `牌型 · +N 分` only when a legal three-card play is selected.
- [x] Cover pure rules, store transitions, and screen behavior with Godot runners.

## TDD slices

- Added a pure CardRules runner for sorting, all categories/scores, Ace behavior, best-three enumeration, and deterministic ties.
- Added MatchStore fixtures for opening/reconnect baselines, either snapshot order, draw/award replacement, hand filtering, and reset behavior.
- Added MatchScreen fixtures for sorted identity, blue/selected priority, hint selection, exact preview copy, and same-action selection preservation.

## Standards review

- Kept acquisition derivation in MatchStore and presentation priority in MatchScreen; no private data was added to public state.
- Independent review found one same-action refresh issue. It was fixed by preserving only still-owned, legal physical IDs within the same phase/action, then independently re-reviewed with no remaining finding.

## Spec review

- Confirmed exact strongest-first suit order `红桃 > 方片 > 黑桃 > 梅花` and compact preview format without “预计”.
- Confirmed the newest acquisition replaces the prior blue set, selection overrides blue, and room/store/action changes clear stale selections.

## Verification

- `run_card_rules_tests.gd`, `run_match_store_tests.gd`, and `run_match_screen_tests.gd`: passed.
- Full Godot editor parse and all 9 headless runners: passed.
- Full repository verification after review repair: passed.

## Commits

- `93d5479` — `feat: 完成五张手牌与自动终局`

## Comments

- The newest acquisition event replaces the previous blue-highlight set.
