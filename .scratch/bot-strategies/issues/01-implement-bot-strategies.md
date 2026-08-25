# 01 - Implement conservative and aggressive Bot strategies

**Status:** done

## What to build

Replace random Bot play, Claim, and discard choices with the two strategies and shared discard ordering in the feature spec, integrate deterministic profiles into Room automation, and add the seeded 1,000-Match win-rate test.

## Checklist

- [x] Conservative and aggressive Bots play their strongest legal Combination.
- [x] Conservative Claim decisions follow improvement priority and the above-pair override.
- [x] Aggressive Bots always Claim the strongest played card.
- [x] Both profiles use the five-class deterministic discard policy.
- [x] Room-created and takeover Bots receive a stable strategy without changing the client protocol.
- [x] The Monte Carlo test runs exactly 1,000 Matches with two Bots of each strategy and reports both aggregate win rates.
- [x] Focused tests, full server tests, and the TypeScript build pass.
- [x] Standards and Spec reviews have no unresolved findings.
- [x] TDD slices, verification, review evidence, and implementation commits are recorded below.

## TDD slices

- Actor play: calling the old random policy with a strategy failed at `random.nextInt`; adding the explicit strategies and canonical best-Combination selection made the focused Bot policy suite pass (5 tests).
- Aggressive Claim: the new strategy initially reached the unimplemented Claim branch; selecting the strongest played card made the focused suite pass (6 tests).
- Conservative Claim: a fixed Pass first satisfied the no-improvement example, then failed rank-over-suit-over-adjacency and above-pair examples; relation-count comparison plus the canonical best-Combination score made all Claim examples pass. The no-improvement example also caught and repaired an over-broad A-2 adjacency check that treated any ranks summing to 16 as adjacent.
- Shared discard: both strategies initially reached the unimplemented discard branch; five exclusive relation classes and weakest-card tie-breaking made all five discard scenarios pass for both strategies (11 focused tests total).
- Room integration: Bot-fill initially exposed generic nicknames; one seat-to-strategy mapping now names and drives Room Bots, while the obsolete random-policy overload and Room random source were removed. Bot policy, fill, zero-delay actions, and a complete one-human/three-Bot Match pass together (14 focused tests), as does the TypeScript build.
- Monte Carlo: the new public-engine driver completed all 1,000 seeded Matches on its first run, with two Bots per strategy in every Match and balanced seat exposure. Co-winner credit accounting produced conservative 48.42% and aggressive 51.58% in about 0.8 seconds; only completion and accounting invariants are asserted.
- Conservative Claim participation: the first report shape returned zero opportunities and failed its positive-denominator assertion; counting conservative non-Actor Claim opportunities and non-Pass choices made the focused test pass and added the probability to its output.

## Review

- Standards (`668a6ef...977511e`): one hard process finding, no code-quality findings, and no actionable Fowler smells. The finding required closing this ticket with its checklist, review, verification, and commit evidence; follow-up review after `3c39086` confirmed the repair with 0 remaining findings.
- Spec (`668a6ef...977511e`): 0 findings. The review confirmed strongest-Combination play, both Claim profiles, all five discard classes, stable Room routing, and the 1,000-Match accounting against this feature spec and the originating request.
- Residual risks: the human actor deadline fallback intentionally remains first-three, and takeover strategy routing is seat-based without a dedicated dispatch assertion; existing complete Bot/takeover Match tests cover legal progression.

## Verification

- `npm test`: 135 passing in 14 seconds, including all policy, Room, complete-Match, and Monte Carlo coverage.
- Monte Carlo result (seeds 1 through 1,000; co-winners split): conservative 48.42%, aggressive 51.58%; conservative Claim participation 99.88% (15,567 of 15,585 opportunities).
- `npm run build`: production TypeScript build passed.
- Isolated strict type-check of `test/BotMonteCarlo.test.ts` and its imported rules modules passed.
- `git diff --check` and final worktree hygiene passed before ticket close-out.
- The broader test-inclusive `tsconfig.json` type-check still reports pre-existing errors in unchanged `GameRoomContinuity.test.ts` and `GameRoomRaces.test.ts`; production build and the new test's isolated strict check are clean.

## Commits

- `3f6f50d` - strongest Bot Actor play and feature specification.
- `9a2184d` - conservative/aggressive Claim behavior and shared discard policy.
- `64780c7` - Room strategy routing, names, and removal of random Bot decisions.
- `977511e` - 1,000-Match Monte Carlo test and operator documentation.
- `3c39086` - completed ticket lifecycle, review, and verification evidence.

## Comments

- 2026-08-25: The requested singular conservative “largest card” play is specified as the strongest legal three-card Combination because every Actor command requires exactly three cards.
- 2026-08-25: The overlapping discard descriptions are made exclusive by strongest-relation precedence; deterministic weakest-card tie-breaking fills the unspecified tie behavior.
- 2026-08-25: Follow-up added a double-click Windows launcher and defined conservative Claim participation as selecting a played card instead of Pass across all conservative Claim opportunities.
