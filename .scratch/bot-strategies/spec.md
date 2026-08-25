# Conservative and aggressive bot strategies

**Status:** done

## Goal

Replace random Bot decisions with two deterministic strategies, give both strategies the same hand-preserving discard policy, and measure their aggregate win rates over 1,000 seeded Matches.

## Strategy rules

- A Bot Actor plays the highest-scoring three-card Combination in its five-card hand. Equal-scoring Combinations are resolved by card strength using the existing rank, suit, physical-copy, and id preference.
- An aggressive Bot always Claims the strongest played card.
- A conservative Bot passes when no played card adds a same-rank, same-suit, or adjacent-rank relation to its hand. Otherwise it Claims the card with the lexicographically greatest relation counts: same rank, then same suit, then adjacent rank. Equal improvements prefer the strongest card.
- If a conservative Bot already holds any Combination above a pair, it ignores improvement and always Claims the strongest played card to compete for the Actor role.
- Ace is adjacent to both King and 2, matching its high role in Q-K-A and low role in A-2-3.

## Shared discard policy

Every discard candidate is classified by its strongest relation to any other card in the six-card hand. Bots discard from the first available class in this order:

1. no same rank, same suit, or adjacent rank;
2. adjacent rank only;
3. same suit without adjacency;
4. same suit and adjacent rank;
5. same rank.

Same-rank membership takes precedence over every other relation. Within one class the weakest card is discarded, so the policy is deterministic. The awarded card remains eligible.

## Room integration

- Bot strategy is an explicit input to the pure policy API; it is not synchronized as a new client-visible room setting.
- Normal Room automation assigns even-numbered seats the conservative strategy and odd-numbered seats the aggressive strategy. Filled Bot nicknames identify their strategy. A disconnected human seat taken over by a Bot follows the same seat-based assignment.
- Human deadline fallbacks remain deterministic rules fallbacks and are not redefined as a Bot strategy.

## Monte Carlo test

- Drive the public `MatchEngine` phase and command APIs directly with one deck and seeds 1 through 1,000.
- Every Match contains two conservative and two aggressive Bots. Cycle through all six choices of conservative seats to reduce seat-position bias.
- Split one win credit evenly across co-winners, aggregate credit by strategy, and print both win rates. The two rates must total 100% apart from floating-point tolerance.
- Keep stable identities for conservative Bot A and Bot B while rotating their seats. Calculate each Bot's Claim participation probability independently, then report the arithmetic mean of those two probabilities rather than pooling their opportunities.
- Assert completion and accounting invariants, not a minimum win-rate threshold.

## Testing seams

- Policy behavior is observed through the exported `chooseBotCommand` function.
- Whole-Match simulation is observed through public `MatchEngine` commands and `winnerSeatIndexes`.

## Out of scope

- A client control for choosing Bot strategy.
- Persisting strategy in synchronized Room schema.
- Skill levels, adaptive play, hidden-information inference, or production balancing guarantees.
