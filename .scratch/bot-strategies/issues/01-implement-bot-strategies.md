# 01 - Implement conservative and aggressive Bot strategies

**Status:** claimed

## What to build

Replace random Bot play, Claim, and discard choices with the two strategies and shared discard ordering in the feature spec, integrate deterministic profiles into Room automation, and add the seeded 1,000-Match win-rate test.

## Checklist

- [ ] Conservative and aggressive Bots play their strongest legal Combination.
- [ ] Conservative Claim decisions follow improvement priority and the above-pair override.
- [ ] Aggressive Bots always Claim the strongest played card.
- [ ] Both profiles use the five-class deterministic discard policy.
- [ ] Room-created and takeover Bots receive a stable strategy without changing the client protocol.
- [ ] The Monte Carlo test runs exactly 1,000 Matches with two Bots of each strategy and reports both aggregate win rates.
- [ ] Focused tests, full server tests, and the TypeScript build pass.
- [ ] Standards and Spec reviews have no unresolved findings.
- [ ] TDD slices, verification, review evidence, and implementation commits are recorded below.

## TDD slices

- Actor play: calling the old random policy with a strategy failed at `random.nextInt`; adding the explicit strategies and canonical best-Combination selection made the focused Bot policy suite pass (5 tests).
- Aggressive Claim: the new strategy initially reached the unimplemented Claim branch; selecting the strongest played card made the focused suite pass (6 tests).
- Conservative Claim: a fixed Pass first satisfied the no-improvement example, then failed rank-over-suit-over-adjacency and above-pair examples; relation-count comparison plus the canonical best-Combination score made all Claim examples pass. The no-improvement example also caught and repaired an over-broad A-2 adjacency check that treated any ranks summing to 16 as adjacent.
- Shared discard: both strategies initially reached the unimplemented discard branch; five exclusive relation classes and weakest-card tie-breaking made all five discard scenarios pass for both strategies (11 focused tests total).
- Room integration: Bot-fill initially exposed generic nicknames; one seat-to-strategy mapping now names and drives Room Bots, while the obsolete random-policy overload and Room random source were removed. Bot policy, fill, zero-delay actions, and a complete one-human/three-Bot Match pass together (14 focused tests), as does the TypeScript build.

## Review

Pending.

## Verification

Pending.

## Commits

Pending.

## Comments

- 2026-08-25: The requested singular conservative “largest card” play is specified as the strongest legal three-card Combination because every Actor command requires exactly three cards.
- 2026-08-25: The overlapping discard descriptions are made exclusive by strongest-relation precedence; deterministic weakest-card tie-breaking fills the unspecified tie behavior.
