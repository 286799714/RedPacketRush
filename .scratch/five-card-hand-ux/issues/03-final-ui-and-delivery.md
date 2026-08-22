# 03 - Automatic final UI, return to lobby, and delivery verification

**Status:** claimed

- [ ] Normalize one-group final results and remove reachable manual A/B grouping controls.
- [ ] Display each participant's single terminal combination and score.
- [ ] Add a finished-phase `返回大厅` action using the existing room-leave flow.
- [ ] Prevent duplicate leave requests while awaiting confirmation.
- [ ] Update smoke fixtures, capture scenarios, README, and domain context.
- [ ] Run complete server, TypeScript, Godot, and repository verification checks.

## Comments

- Existing lobby cleanup remains owned by `AppShell._on_game_room_left`.
