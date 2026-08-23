# 01 - Implement turn presentation and card-face UX

**Status:** claimed

- [x] Remove awarded-card discard protection from authoritative rules and bot policy.
- [x] Add server-owned play and discard presentation phases with 3s/4s/2s timing.
- [x] Render real card faces in the match UI and record their CC0 attribution.
- [x] Add source-specific acquisition labels and per-seat play, award, and discard presentation.
- [x] Replace the discard-stage latest-contest content with local/waiting prompts.
- [x] Extend rule, room, store, screen, and delivery-capture tests.
- [x] Update domain and operator documentation.
- [x] Complete Standards review, Spec review, and full verification.
- [ ] Commit the completed implementation.

## TDD slices

- Rule tests first rejected discarding the awarded card, then passed after the protection was removed.
- Match and room tests first expected `play_reveal` and `discard_reveal`, then passed after engine transitions and room timers were added.
- Godot screen tests first failed on texture-backed faces, acquisition labels, seat presentation, center prompts, and awarded-card selection, then passed after the presentation implementation.

## Standards review

- Presentation delays are server-owned non-actionable phases; clients cannot skip them or submit a command against them.
- Existing action IDs, stale-command checks, room timers, bot policy, and reconnect paths remain the only continuity mechanisms.
- New seat displays consume only already-public play, award, and discard events. Private hands and unrevealed claim choices remain isolated.
- Card art is loaded through one suit/rank catalog and carries source/license attribution; no network dependency is introduced at runtime.
- Manual review found no blocking or high-severity issue. The first 960×540 claim layout overlapped; seat action panels were repositioned and recaptured before completion.

## Spec review

- Confirmed awarded cards are legal discard choices for humans, bots, and deadline fallback.
- Confirmed 3s play reveal, 4s claim reveal, and 2s discard reveal boundaries, including delayed next-actor selection.
- Confirmed exact center prompts, per-seat played/awarded/discarded card faces, blue award borders, and both acquisition-source labels.
- Confirmed point-contest, hand, and claim-choice card surfaces now use texture-backed faces while the audit history keeps textual identity.

## Verification

- `scripts/verify.ps1 -SkipInstall`: Node.js 24.19, 128 server tests, TypeScript build, Godot parse, 9 headless runners, and 18 delivery scenarios passed.
- GPU delivery capture produced 18 nonblank scenarios at both 960×540 and 1280×720; the four turn-presentation states were visually inspected after the overlap repair.
- `git diff --check`: passed (line-ending conversion notices only).

## Comments

- The previous five-card UX spec explicitly kept protected awards out of scope; this newer feature changes that rule intentionally.
