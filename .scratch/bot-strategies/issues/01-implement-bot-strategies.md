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

## Review

Pending.

## Verification

Pending.

## Commits

Pending.

## Comments

- 2026-08-25: The requested singular conservative “largest card” play is specified as the strongest legal three-card Combination because every Actor command requires exactly three cards.
- 2026-08-25: The overlapping discard descriptions are made exclusive by strongest-relation precedence; deterministic weakest-card tie-breaking fills the unspecified tie behavior.
