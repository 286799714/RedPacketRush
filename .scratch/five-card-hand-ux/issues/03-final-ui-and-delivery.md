# 03 - Automatic final UI, return to lobby, and delivery verification

**Status:** done

- [x] Normalize one-group final results and remove reachable manual A/B grouping controls.
- [x] Display each participant's single terminal combination and score.
- [x] Add a finished-phase `返回大厅` action using the existing room-leave flow.
- [x] Prevent duplicate leave requests while awaiting confirmation.
- [x] Update smoke fixtures, capture scenarios, README, and domain context.
- [x] Run complete server, TypeScript, Godot, and repository verification checks.

## TDD slices

- Updated adapter fixtures to accept exactly one final group and reject malformed group counts.
- Added finished-screen and AppShell tests for single-group display, return visibility, duplicate-request suppression, and lobby restoration.
- Reworked the delivery capture fixtures to cover five-card actor play, six-card award discard with blue outline, and one-group finished ranking.

## Standards review

- Reused the existing adapter leave path and AppShell cleanup instead of introducing a parallel navigation state.
- Kept legacy A/B client helpers unreachable for compatibility; the server no longer registers final-selection messages or exposes a commit phase.
- Independent review found no blocking or high-severity delivery issue.

## Spec review

- Confirmed one authoritative terminal group per participant, exact per-group score display, all co-winners, and a finished-only return action.
- Confirmed README, server README, domain context, smoke expectations, and capture matrix describe five-card behavior.

## Verification

- Full `scripts/verify.ps1 -SkipInstall`: 128 server tests, TypeScript build, Godot parse, 9 runners, and 16 capture scenarios passed.
- GPU delivery capture produced 16 nonblank scenarios at both supported viewport sizes; actor, award/discard, and finished layouts were visually inspected.
- Four-client Native SDK smoke: passed.
- `git diff --check`: passed (line-ending conversion notices only).

## Commits

- `93d5479` — `feat: 完成五张手牌与自动终局`

## Comments

- Existing lobby cleanup remains owned by `AppShell._on_game_room_left`.
