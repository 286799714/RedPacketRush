import assert from "assert";

import {
  MatchCommandError,
  MatchEngine,
  type MatchParticipant,
} from "../src/match/MatchEngine.js";
import {
  SeededRandomSource,
  type RandomSource,
} from "../src/match/random.js";

class MaxIndexRandom implements RandomSource {
  public readonly requestedMaxima: number[] = [];

  public nextInt(maxExclusive: number): number {
    this.requestedMaxima.push(maxExclusive);
    return maxExclusive - 1;
  }
}

const PARTICIPANTS: readonly MatchParticipant[] = [
  { seatIndex: 0, participantId: "participant-a", nickname: "甲", bot: false },
  { seatIndex: 1, participantId: "participant-b", nickname: "乙", bot: false },
  { seatIndex: 2, participantId: "participant-c", nickname: "丙", bot: false },
  { seatIndex: 3, participantId: "participant-d", nickname: "丁", bot: false },
];

function startedEngine(
  random: RandomSource = new MaxIndexRandom(),
  deckMode: "one" | "two" = "one",
): MatchEngine {
  const engine = new MatchEngine(random);
  engine.start(PARTICIPANTS, { deckMode, actionDeadlineSeconds: 30 });
  engine.completePointContest();
  return engine;
}

function playFirstThree(engine: MatchEngine): {
  actorSeatIndex: number;
  originalHands: ReturnType<MatchEngine["view"]>["privateState"]["hand"][];
} {
  const publicState = engine.view(0).publicState;
  const actorSeatIndex = publicState.actorSeatIndex;
  const originalHands = PARTICIPANTS.map(({ seatIndex }) => (
    engine.view(seatIndex).privateState.hand
  ));
  engine.playCards(
    actorSeatIndex,
    originalHands[actorSeatIndex].slice(0, 3).map((card) => card.id),
  );
  return { actorSeatIndex, originalHands };
}

function discardOriginalCards(
  engine: MatchEngine,
  seatIndexes: readonly number[],
  originalHands: readonly (readonly { id: string }[])[],
): void {
  for (const seatIndex of seatIndexes) {
    engine.discardCard(seatIndex, originalHands[seatIndex][0].id);
  }
}

function assertRejectedWithoutMutation(
  engine: MatchEngine,
  action: () => void,
  expectedCode: string,
): void {
  const beforeViews = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
  let thrown: unknown;
  try {
    action();
  } catch (error) {
    thrown = error;
  }

  assert.ok(thrown instanceof MatchCommandError);
  assert.strictEqual(thrown.code, expectedCode);
  assert.deepStrictEqual(
    PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex)),
    beforeViews,
  );
}

describe("match award discard and actor rotation", () => {
  it("holds recipients at nine and accepts only pre-award hand cards", () => {
    const engine = startedEngine();
    const { actorSeatIndex, originalHands } = playFirstThree(engine);
    const claimantSeats = [0, 1, 2, 3].filter((seatIndex) => seatIndex !== actorSeatIndex);
    const playedCards = engine.view(0).publicState.playedCards;

    engine.commitClaim(claimantSeats[0], playedCards[0].id);
    engine.commitClaim(claimantSeats[1], playedCards[1].id);
    engine.commitClaim(claimantSeats[2], null);

    let publicState = engine.view(0).publicState;
    assert.strictEqual(publicState.phase, "claim_reveal");
    assert.deepStrictEqual(publicState.pendingDiscardSeatIndexes, claimantSeats.slice(0, 2));
    assert.deepStrictEqual(
      publicState.participants.map((participant) => participant.handCount),
      [0, 1, 2, 3].map((seatIndex) => claimantSeats.slice(0, 2).includes(seatIndex) ? 9 : 8),
    );
    assertRejectedWithoutMutation(
      engine,
      () => engine.discardCard(claimantSeats[0], originalHands[claimantSeats[0]][0].id),
      "invalid_phase",
    );

    engine.completeClaimReveal();
    assert.strictEqual(engine.view(0).publicState.phase, "award_discard");
    const protectedCardId = engine.view(0).publicState.claimAwards.find(
      (award) => award.seatIndex === claimantSeats[0],
    )?.card.id;
    assert.ok(protectedCardId);
    assertRejectedWithoutMutation(
      engine,
      () => engine.discardCard(claimantSeats[0], protectedCardId),
      "awarded_card_protected",
    );
    assertRejectedWithoutMutation(
      engine,
      () => engine.discardCard(claimantSeats[0], originalHands[claimantSeats[1]][0].id),
      "card_not_owned",
    );
    assertRejectedWithoutMutation(
      engine,
      () => engine.discardCard(claimantSeats[2], originalHands[claimantSeats[2]][0].id),
      "discard_not_required",
    );

    const discardedCard = originalHands[claimantSeats[0]][0];
    engine.discardCard(claimantSeats[0], discardedCard.id);
    publicState = engine.view(0).publicState;
    assert.strictEqual(publicState.phase, "award_discard");
    assert.deepStrictEqual(publicState.pendingDiscardSeatIndexes, [claimantSeats[1]]);
    assert.strictEqual(publicState.participants[claimantSeats[0]].handCount, 8);
    assert.strictEqual(publicState.participants[claimantSeats[1]].handCount, 9);
    assert.deepStrictEqual(publicState.discardEvents, [{
      type: "card_discarded",
      turnNumber: 1,
      seatIndex: claimantSeats[0],
      card: discardedCard,
    }]);
    assert.ok(publicState.discardedCards.some((card) => card.id === discardedCard.id));
    assertRejectedWithoutMutation(
      engine,
      () => engine.discardCard(claimantSeats[0], originalHands[claimantSeats[0]][1].id),
      "discard_not_required",
    );
  });

  it("waits for every discard then selects the strongest award by rank and suit", () => {
    const engine = startedEngine();
    const { actorSeatIndex, originalHands } = playFirstThree(engine);
    assert.strictEqual(actorSeatIndex, 0);
    const playedCards = engine.view(0).publicState.playedCards;

    engine.commitClaim(1, playedCards[2].id);
    engine.commitClaim(2, playedCards[0].id);
    engine.commitClaim(3, playedCards[1].id);
    engine.completeClaimReveal();

    engine.discardCard(1, originalHands[1][0].id);
    engine.discardCard(3, originalHands[3][0].id);
    assert.strictEqual(engine.view(0).publicState.phase, "award_discard");
    assert.strictEqual(engine.view(0).publicState.actorSeatIndex, actorSeatIndex);

    engine.discardCard(2, originalHands[2][0].id);
    const views = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
    const publicState = views[0].publicState;
    assert.strictEqual(publicState.phase, "actor_play");
    assert.strictEqual(publicState.actorSeatIndex, 2);
    assert.deepStrictEqual(publicState.pendingDiscardSeatIndexes, []);
    assert.deepStrictEqual(publicState.revealedClaims, []);
    assert.deepStrictEqual(publicState.claimAwards, []);
    assert.strictEqual(publicState.playedCategory, null);
    assert.strictEqual(publicState.playedScore, 0);
    assert.ok(publicState.participants.every((participant) => participant.handCount === 8));
    assert.deepStrictEqual(
      views.map((view) => ({
        claimCommitted: view.privateState.claimCommitted,
        claimCardId: view.privateState.claimCardId,
      })),
      views.map(() => ({ claimCommitted: false, claimCardId: null as string | null })),
    );
    assertRejectedWithoutMutation(
      engine,
      () => engine.discardCard(2, originalHands[2][1].id),
      "invalid_phase",
    );
  });

  it("ignores deck-copy identity and breaks exact award ties clockwise", () => {
    const engine = startedEngine(new SeededRandomSource(5), "two");
    const actorSeatIndex = engine.view(0).publicState.actorSeatIndex;
    assert.strictEqual(actorSeatIndex, 3);
    const originalHands = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex).privateState.hand);
    const actorHand = originalHands[actorSeatIndex];
    const duplicateCards = actorHand.filter((card) => card.rank === 2 && card.suit === "clubs");
    assert.deepStrictEqual(duplicateCards.map((card) => card.copyIndex).sort(), [0, 1]);
    const thirdCard = actorHand.find((card) => !duplicateCards.some(({ id }) => id === card.id));
    assert.ok(thirdCard);
    engine.playCards(actorSeatIndex, [...duplicateCards.map((card) => card.id), thirdCard.id]);

    engine.commitClaim(0, duplicateCards[0].id);
    engine.commitClaim(1, null);
    engine.commitClaim(2, duplicateCards[1].id);
    engine.completeClaimReveal();
    discardOriginalCards(engine, [0, 2], originalHands);

    assert.strictEqual(engine.view(0).publicState.phase, "actor_play");
    assert.strictEqual(engine.view(0).publicState.actorSeatIndex, 0);
  });

  it("uses suit strength after equal awarded ranks", () => {
    const engine = startedEngine(new SeededRandomSource(1));
    const actorSeatIndex = engine.view(0).publicState.actorSeatIndex;
    assert.strictEqual(actorSeatIndex, 2);
    const originalHands = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex).privateState.hand);
    const actorHand = originalHands[actorSeatIndex];
    const clubsFive = actorHand.find((card) => card.rank === 5 && card.suit === "clubs");
    const diamondsFive = actorHand.find((card) => card.rank === 5 && card.suit === "diamonds");
    const thirdCard = actorHand.find((card) => (
      card.id !== clubsFive?.id && card.id !== diamondsFive?.id
    ));
    assert.ok(clubsFive);
    assert.ok(diamondsFive);
    assert.ok(thirdCard);
    engine.playCards(actorSeatIndex, [clubsFive.id, diamondsFive.id, thirdCard.id]);

    engine.commitClaim(0, diamondsFive.id);
    engine.commitClaim(1, null);
    engine.commitClaim(3, clubsFive.id);
    engine.completeClaimReveal();
    discardOriginalCards(engine, [0, 3], originalHands);

    assert.strictEqual(engine.view(0).publicState.actorSeatIndex, 0);
  });

  it("retains the actor when everyone passes", () => {
    const engine = startedEngine();
    const { actorSeatIndex } = playFirstThree(engine);
    for (const seatIndex of [0, 1, 2, 3]) {
      if (seatIndex !== actorSeatIndex) {
        engine.commitClaim(seatIndex, null);
      }
    }

    const revealedState = engine.view(0).publicState;
    assert.strictEqual(revealedState.phase, "claim_reveal");
    engine.completeClaimReveal();

    const nextState = engine.view(0).publicState;
    assert.strictEqual(nextState.phase, "actor_play");
    assert.strictEqual(nextState.actorSeatIndex, actorSeatIndex);
    assert.deepStrictEqual(nextState.pendingDiscardSeatIndexes, []);
    assert.deepStrictEqual(nextState.revealedClaims, []);
    assert.deepStrictEqual(nextState.claimAwards, []);
  });

  it("auto-discards legal older cards for every pending recipient at deadline", () => {
    const engine = startedEngine();
    const { actorSeatIndex, originalHands } = playFirstThree(engine);
    const claimantSeats = [0, 1, 2, 3].filter((seatIndex) => seatIndex !== actorSeatIndex);
    const playedCards = engine.view(0).publicState.playedCards;
    claimantSeats.forEach((seatIndex, index) => engine.commitClaim(seatIndex, playedCards[index].id));
    engine.completeClaimReveal();

    engine.resolveDiscardAtDeadline();

    const state = engine.view(0).publicState;
    assert.strictEqual(state.phase, "actor_play");
    assert.deepStrictEqual(state.pendingDiscardSeatIndexes, []);
    assert.strictEqual(state.discardEvents.length, 3);
    assert.deepStrictEqual(
      state.discardEvents.map((event) => event.seatIndex),
      claimantSeats,
    );
    for (const event of state.discardEvents) {
      assert.ok(originalHands[event.seatIndex].some((card) => card.id === event.card.id));
      assert.ok(!playedCards.some((card) => card.id === event.card.id));
    }
    assert.ok(state.participants.every((participant) => participant.handCount === 8));
    assertRejectedWithoutMutation(
      engine,
      () => engine.resolveDiscardAtDeadline(),
      "invalid_phase",
    );
  });

  it("seals the final one-deck remainder instead of opening an undrawable turn", () => {
    const engine = startedEngine();
    const actorSeatIndex = engine.view(0).publicState.actorSeatIndex;

    for (let turn = 1; turn <= 6; turn += 1) {
      const actorHand = engine.view(actorSeatIndex).privateState.hand;
      engine.playCards(actorSeatIndex, actorHand.slice(0, 3).map((card) => card.id));
      for (const seatIndex of [0, 1, 2, 3]) {
        if (seatIndex !== actorSeatIndex) {
          engine.commitClaim(seatIndex, null);
        }
      }
      assert.strictEqual(engine.view(0).publicState.phase, "claim_reveal");
      engine.completeClaimReveal();
      assert.strictEqual(
        engine.view(0).publicState.phase,
        turn < 6 ? "actor_play" : "final_commit",
      );
    }

    const views = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
    const state = views[0].publicState;
    assert.strictEqual(state.actorSeatIndex, actorSeatIndex);
    assert.strictEqual(state.drawPileCount, 0);
    assert.strictEqual(state.sealedCards.length, 2);
    assert.strictEqual(state.discardedCards.length, 18);
    assert.ok(state.participants.every((participant) => participant.handCount === 8));
    const allCardIds = [
      ...views.flatMap((view) => view.privateState.hand.map((card) => card.id)),
      ...state.discardedCards.map((card) => card.id),
      ...state.sealedCards.map((card) => card.id),
    ];
    assert.strictEqual(allCardIds.length, 52);
    assert.strictEqual(new Set(allCardIds).size, 52);
  });
});
