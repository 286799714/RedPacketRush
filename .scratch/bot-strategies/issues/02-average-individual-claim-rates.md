# 02 - Average individual conservative Bot Claim rates

**Status:** done

## What to build

Replace the pooled conservative Claim participation probability with fixed Bot A and Bot B statistics. Each Bot's participation probability is its non-Pass Claims divided by its own Claim opportunities; the reported final probability is the arithmetic mean of the two individual probabilities.

## Checklist

- [x] Conservative Bot A and Bot B keep stable identities while their seats rotate.
- [x] Claim opportunities and non-Pass Claims are counted independently for each Bot.
- [x] Output shows both individual probabilities and their arithmetic mean.
- [x] Focused and full server tests plus strict isolated type-check pass.
- [x] TDD, review, verification, and commit evidence are recorded.

## TDD slices

- Red: changing the Match report to require independent Bot A and Bot B counters while returning zero counts failed the positive-opportunity assertion for each identity.
- Green: four fixed Bot identities now rotate through the existing seat-pair schedule; Claim decisions accumulate against the identity occupying each seat, and the report calculates A and B probabilities before their arithmetic mean.
- Review hardening: an uneven synthetic example (A = 1/1, B = 0/3) proves that the result is the individual mean of 50%, not the pooled rate of 25%; seat counters prove that both conservative identities visit every seat 250 times.

## Review

- Standards (`37c2de8...ca2c5fe`): 0 findings. The review confirmed independent identity counters, the non-pooled arithmetic-mean fixture, balanced seat rotation, and explicit sparse-seat validation; no actionable Fowler smells or repository-guideline conflicts were found.
- Spec (`37c2de8...ca2c5fe`): 0 findings. The review confirmed stable A/B identities, per-Bot opportunity and non-Pass participation counts, individual probabilities, and their unweighted arithmetic mean.
- Residual risk: the seeded Monte Carlo test measures the configured sample and intentionally does not guarantee a strategy win-rate threshold.

## Verification

- `npm test -- --grep "Bot strategy Monte Carlo"`: 2 passing; conservative Bot A 99.8842% (7,761/7,770), Bot B 99.8848% (7,806/7,815), arithmetic mean 99.8845%.
- `npm test`: 136 passing in 14 seconds, including the full policy, Match, Room, and Monte Carlo suites.
- `npm run build`: production TypeScript build passed.
- `npx tsc --noEmit --strict --skipLibCheck --target ES2022 --module NodeNext --moduleResolution NodeNext test/BotMonteCarlo.test.ts`: isolated strict type-check passed.
- `scripts/run-bot-monte-carlo.cmd`: the double-click runner completed and displayed both individual probabilities plus the final average.
- `git diff --check`: passed; the pre-existing user-owned `CONTEXT.md` modification remains untouched.

## Commits

- `af50235` - stable Bot identities, independent Claim counters, and individual probability output.
- `ca2c5fe` - non-pooled arithmetic-mean regression test and balanced-seat assertions.

## Comments

- 2026-08-25: Supersedes the pooled `sum(participations) / sum(opportunities)` statistic added in ticket 01; win-rate accounting is unchanged.
- 2026-08-25: The final statistic is deliberately an unweighted mean, so Bot A and Bot B each contribute one half regardless of how many Claim opportunities each receives.
