import assert from "assert";

import type { PhysicalCard } from "../src/match/cards.js";
import type { MatchView } from "../src/match/MatchEngine.js";
import { chooseBotCommand } from "../src/match/botPolicy.js";
import type { RandomSource } from "../src/match/random.js";

class FixedRandomSource implements RandomSource {
  public constructor(private readonly index: number) {}

  public nextInt(maxExclusive: number): number {
    assert.ok(this.index < maxExclusive);
    return this.index;
  }
}

function card(index: number): PhysicalCard {
  return {
    id: `card-${index}`,
    rank: (index + 2) as PhysicalCard["rank"],
    suit: "clubs",
    copyIndex: 0,
  };
}

function matchView(overrides: {
  phase?: MatchView["publicState"]["phase"];
  seatIndex?: number;
  actorSeatIndex?: number;
  hand?: readonly PhysicalCard[];
  playedCards?: readonly PhysicalCard[];
  claimCommitted?: boolean;
  claimAwards?: MatchView["publicState"]["claimAwards"];
  pendingDiscardSeatIndexes?: readonly number[];
  finalCommitted?: boolean;
} = {}): MatchView {
  const seatIndex = overrides.seatIndex ?? 1;
  return {
    publicState: {
      phase: overrides.phase ?? "actor_play",
      actorSeatIndex: overrides.actorSeatIndex ?? seatIndex,
      firstActorSeatIndex: 0,
      drawPileCount: 20,
      playedCards: overrides.playedCards ?? [],
      playedCategory: null,
      playedScore: 0,
      turnNumber: 3,
      revealedClaims: [],
      claimAwards: overrides.claimAwards ?? [],
      discardedCards: [],
      sealedCardCount: 0,
      pendingDiscardSeatIndexes: overrides.pendingDiscardSeatIndexes ?? [],
      finalResults: [],
      winnerSeatIndexes: [],
      participants: [],
      events: [],
    },
    privateState: {
      seatIndex,
      participantId: `participant-${seatIndex}`,
      hand: overrides.hand ?? Array.from({ length: 8 }, (_, index) => card(index)),
      claimCommitted: overrides.claimCommitted ?? false,
      claimCardId: null,
      finalCommitted: overrides.finalCommitted ?? false,
      finalGroups: [],
    },
  };
}

describe("bot policy", () => {
  it("selects one seeded legal three-card play for the actor", () => {
    const view = matchView();

    assert.deepStrictEqual(chooseBotCommand(view, new FixedRandomSource(55)), {
      type: "play_cards",
      cardIds: ["card-5", "card-6", "card-7"],
    });
  });

  it("selects a seeded played card or pass for an uncommitted claimant", () => {
    const playedCards = [card(0), card(1), card(2)];
    const view = matchView({
      phase: "claim_commit",
      actorSeatIndex: 0,
      playedCards,
    });

    assert.deepStrictEqual(chooseBotCommand(view, new FixedRandomSource(1)), {
      type: "claim",
      cardId: playedCards[1].id,
    });
    assert.deepStrictEqual(chooseBotCommand(view, new FixedRandomSource(3)), {
      type: "claim",
      cardId: null,
    });
    assert.strictEqual(
      chooseBotCommand(matchView({
        phase: "claim_commit",
        actorSeatIndex: 0,
        playedCards,
        claimCommitted: true,
      }), new FixedRandomSource(0)),
      null,
    );
  });

  it("never selects the protected award as a discard", () => {
    const hand = Array.from({ length: 9 }, (_, index) => card(index));
    const view = matchView({
      phase: "award_discard",
      hand,
      pendingDiscardSeatIndexes: [1],
      claimAwards: [{ seatIndex: 1, card: hand[8], source: "unique" }],
    });

    assert.deepStrictEqual(chooseBotCommand(view, new FixedRandomSource(7)), {
      type: "discard",
      cardId: "card-7",
      turnNumber: 3,
    });
  });

  it("uses the engine's best-selection command during final settlement", () => {
    assert.deepStrictEqual(chooseBotCommand(
      matchView({ phase: "final_commit" }),
      new FixedRandomSource(0),
    ), {
      type: "final_selection",
      mode: "best",
    });
    assert.strictEqual(chooseBotCommand(
      matchView({ phase: "final_commit", finalCommitted: true }),
      new FixedRandomSource(0),
    ), null);
  });

  it("does nothing when the seat has no legal command in the current phase", () => {
    assert.strictEqual(chooseBotCommand(
      matchView({ phase: "claim_reveal" }),
      new FixedRandomSource(0),
    ), null);
    assert.strictEqual(chooseBotCommand(
      matchView({ actorSeatIndex: 0 }),
      new FixedRandomSource(0),
    ), null);
  });
});
