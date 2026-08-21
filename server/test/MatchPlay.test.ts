import assert from "assert";

import {
  MatchCommandError,
  MatchEngine,
  type MatchCommandErrorCode,
  type MatchParticipant,
} from "../src/match/MatchEngine.js";
import type { RandomSource } from "../src/match/random.js";

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
  { seatIndex: 2, participantId: "participant-c", nickname: "丙", bot: true },
  { seatIndex: 3, participantId: "participant-d", nickname: "丁", bot: true },
];

function startedEngine(random: RandomSource = new MaxIndexRandom()): MatchEngine {
  const engine = new MatchEngine(random);
  engine.start(PARTICIPANTS, {
    deckMode: "one",
    actionDeadlineSeconds: 30,
  });
  return engine;
}

function assertCommandRejectedWithoutMutation(
  engine: MatchEngine,
  random: MaxIndexRandom,
  action: () => void,
  expectedCode: MatchCommandErrorCode,
): void {
  const beforeViews = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
  const beforeRandomRequests = [...random.requestedMaxima];
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
  assert.deepStrictEqual(random.requestedMaxima, beforeRandomRequests);
}

describe("match actor play", () => {
  it("atomically scores and publishes three owned cards while drawing replacements", () => {
    const engine = startedEngine();
    engine.completePointContest();
    const beforeViews = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
    const actorHand = beforeViews[0].privateState.hand;
    const playedCards = actorHand.slice(0, 3);

    engine.playCards(0, playedCards.map((card) => card.id));

    const afterViews = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
    const publicState = afterViews[0].publicState;
    assert.strictEqual(publicState.phase, "claim_commit");
    assert.strictEqual(publicState.actorSeatIndex, 0);
    assert.strictEqual(publicState.firstActorSeatIndex, 0);
    assert.strictEqual(publicState.turnNumber, 1);
    assert.deepStrictEqual(publicState.playedCards, playedCards);
    assert.strictEqual(publicState.playedCategory, "flush");
    assert.strictEqual(publicState.playedScore, 4);
    assert.strictEqual(publicState.drawPileCount, 17);
    assert.strictEqual(publicState.participants[0].score, 4);
    assert.strictEqual(publicState.participants[0].handCount, 8);
    assert.deepStrictEqual(publicState.events.at(-1), {
      type: "cards_played",
      turnNumber: 1,
      actorSeatIndex: 0,
      cards: playedCards,
      category: "flush",
      score: 4,
    });

    const actorAfterIds = afterViews[0].privateState.hand.map((card) => card.id);
    assert.ok(playedCards.every((card) => !actorAfterIds.includes(card.id)));
    assert.strictEqual(
      actorAfterIds.filter((id) => actorHand.some((card) => card.id === id)).length,
      5,
    );
    for (let seatIndex = 1; seatIndex < PARTICIPANTS.length; seatIndex += 1) {
      assert.deepStrictEqual(
        afterViews[seatIndex].privateState,
        beforeViews[seatIndex].privateState,
      );
    }
  });

  it("rejects play outside actor-play phase without changing state or randomness", () => {
    const random = new MaxIndexRandom();
    const engine = startedEngine(random);
    const cardIds = engine.view(0).privateState.hand.slice(0, 3).map((card) => card.id);

    assertCommandRejectedWithoutMutation(
      engine,
      random,
      () => engine.playCards(0, cardIds),
      "invalid_phase",
    );
  });

  it("rejects a non-actor without changing state or randomness", () => {
    const random = new MaxIndexRandom();
    const engine = startedEngine(random);
    engine.completePointContest();
    const cardIds = engine.view(1).privateState.hand.slice(0, 3).map((card) => card.id);

    assertCommandRejectedWithoutMutation(
      engine,
      random,
      () => engine.playCards(1, cardIds),
      "not_actor",
    );
  });

  it("rejects a play without exactly three identifiers", () => {
    const random = new MaxIndexRandom();
    const engine = startedEngine(random);
    engine.completePointContest();
    const cardIds = engine.view(0).privateState.hand.slice(0, 2).map((card) => card.id);

    assertCommandRejectedWithoutMutation(
      engine,
      random,
      () => engine.playCards(0, cardIds),
      "invalid_play",
    );
  });

  it("rejects duplicate card identifiers", () => {
    const random = new MaxIndexRandom();
    const engine = startedEngine(random);
    engine.completePointContest();
    const [firstCard, secondCard] = engine.view(0).privateState.hand;

    assertCommandRejectedWithoutMutation(
      engine,
      random,
      () => engine.playCards(0, [firstCard.id, firstCard.id, secondCard.id]),
      "invalid_play",
    );
  });

  it("rejects non-string card identifiers", () => {
    const random = new MaxIndexRandom();
    const engine = startedEngine(random);
    engine.completePointContest();
    const [firstCard, secondCard] = engine.view(0).privateState.hand;
    const malformedIds = [firstCard.id, secondCard.id, 42] as unknown as string[];

    assertCommandRejectedWithoutMutation(
      engine,
      random,
      () => engine.playCards(0, malformedIds),
      "invalid_play",
    );
  });

  it("rejects empty card identifiers", () => {
    const random = new MaxIndexRandom();
    const engine = startedEngine(random);
    engine.completePointContest();
    const [firstCard, secondCard] = engine.view(0).privateState.hand;

    assertCommandRejectedWithoutMutation(
      engine,
      random,
      () => engine.playCards(0, [firstCard.id, secondCard.id, ""]),
      "invalid_play",
    );
  });

  it("rejects an unowned physical card identifier", () => {
    const random = new MaxIndexRandom();
    const engine = startedEngine(random);
    engine.completePointContest();
    const actorCards = engine.view(0).privateState.hand.slice(0, 2);
    const otherCard = engine.view(1).privateState.hand[0];

    assertCommandRejectedWithoutMutation(
      engine,
      random,
      () => engine.playCards(0, [actorCards[0].id, actorCards[1].id, otherCard.id]),
      "card_not_owned",
    );
  });

  it("rejects a duplicate command after the actor's play has resolved", () => {
    const random = new MaxIndexRandom();
    const engine = startedEngine(random);
    engine.completePointContest();
    const cardIds = engine.view(0).privateState.hand.slice(0, 3).map((card) => card.id);
    engine.playCards(0, cardIds);

    assertCommandRejectedWithoutMutation(
      engine,
      random,
      () => engine.playCards(0, cardIds),
      "invalid_phase",
    );
  });
});
