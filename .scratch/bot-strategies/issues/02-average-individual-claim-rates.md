# 02 - Average individual conservative Bot Claim rates

**Status:** claimed

## What to build

Replace the pooled conservative Claim participation probability with fixed Bot A and Bot B statistics. Each Bot's participation probability is its non-Pass Claims divided by its own Claim opportunities; the reported final probability is the arithmetic mean of the two individual probabilities.

## Checklist

- [ ] Conservative Bot A and Bot B keep stable identities while their seats rotate.
- [ ] Claim opportunities and non-Pass Claims are counted independently for each Bot.
- [ ] Output shows both individual probabilities and their arithmetic mean.
- [ ] Focused and full server tests plus strict isolated type-check pass.
- [ ] TDD, review, verification, and commit evidence are recorded.

## TDD slices

- Red: changing the Match report to require independent Bot A and Bot B counters while returning zero counts failed the positive-opportunity assertion for each identity.
- Green: four fixed Bot identities now rotate through the existing seat-pair schedule; Claim decisions accumulate against the identity occupying each seat, and the report calculates A and B probabilities before their arithmetic mean.

## Review

Pending.

## Verification

Pending.

## Commits

Pending.

## Comments

- 2026-08-25: Supersedes the pooled `sum(participations) / sum(opportunities)` statistic added in ticket 01; win-rate accounting is unchanged.
