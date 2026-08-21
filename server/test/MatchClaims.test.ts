import assert from "assert";

import {
  MatchCommandError,
  MatchEngine,
  type MatchParticipant,
  type RevealedClaim,
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
  { seatIndex: 2, participantId: "participant-c", nickname: "丙", bot: false },
  { seatIndex: 3, participantId: "participant-d", nickname: "丁", bot: false },
];

function engineAtClaimCommit(random: MaxIndexRandom): MatchEngine {
  const engine = new MatchEngine(random);
  engine.start(PARTICIPANTS, {
    deckMode: "one",
    actionDeadlineSeconds: 30,
  });
  engine.completePointContest();
  const actorHand = engine.view(0).privateState.hand;
  engine.playCards(0, actorHand.slice(0, 3).map((card) => card.id));
  return engine;
}

function engineAtPointContest(random: MaxIndexRandom): MatchEngine {
  const engine = new MatchEngine(random);
  engine.start(PARTICIPANTS, {
    deckMode: "one",
    actionDeadlineSeconds: 30,
  });
  return engine;
}

function assertRejectedWithoutMutation(
  engine: MatchEngine,
  random: MaxIndexRandom,
  action: () => void,
  expectedCode: string,
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

describe("match secret claims", () => {
  it("keeps one accepted claim private until every non-actor commits", () => {
    const random = new MaxIndexRandom();
    const engine = engineAtClaimCommit(random);
    const beforeViews = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
    const beforeRandomRequests = [...random.requestedMaxima];
    const claimedCardId = beforeViews[0].publicState.playedCards[0].id;

    engine.commitClaim(1, claimedCardId);

    const afterViews = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
    const publicState = afterViews[0].publicState;
    assert.strictEqual(publicState.phase, "claim_commit");
    assert.strictEqual(publicState.claimCommitCount, 1);
    assert.deepStrictEqual(publicState.revealedClaims, []);
    assert.deepStrictEqual(publicState.claimAwards, []);
    assert.deepStrictEqual(publicState.discardedCards, []);
    assert.deepStrictEqual(
      afterViews.map((view) => view.publicState),
      afterViews.map(() => publicState),
    );
    assert.deepStrictEqual(publicState.events, beforeViews[0].publicState.events);
    assert.deepStrictEqual(
      afterViews.map((view) => view.privateState.hand),
      beforeViews.map((view) => view.privateState.hand),
    );
    assert.deepStrictEqual(
      afterViews.map((view) => ({
        committed: view.privateState.claimCommitted,
        cardId: view.privateState.claimCardId,
      })),
      [
        { committed: false, cardId: null },
        { committed: true, cardId: claimedCardId },
        { committed: false, cardId: null },
        { committed: false, cardId: null },
      ],
    );
    assert.deepStrictEqual(random.requestedMaxima, beforeRandomRequests);
  });

  it("rejects the actor's claim without changing match state or randomness", () => {
    const random = new MaxIndexRandom();
    const engine = engineAtClaimCommit(random);
    const playedCardId = engine.view(0).publicState.playedCards[0].id;

    assertRejectedWithoutMutation(
      engine,
      random,
      () => engine.commitClaim(0, playedCardId),
      "actor_cannot_claim",
    );
  });

  it("rejects a claim outside claim-commit without changing state or randomness", () => {
    const random = new MaxIndexRandom();
    const engine = engineAtPointContest(random);

    assertRejectedWithoutMutation(
      engine,
      random,
      () => engine.commitClaim(1, null),
      "invalid_phase",
    );
  });

  it("rejects invalid claimants and non-played physical card identifiers atomically", () => {
    const cases: ReadonlyArray<{
      seatIndex: number;
      cardId: string | null;
    }> = [
      { seatIndex: 4, cardId: null },
      { seatIndex: 1, cardId: 42 as unknown as string },
      { seatIndex: 1, cardId: "" },
      { seatIndex: 1, cardId: "copy-0:clubs:2" },
      { seatIndex: 1, cardId: "not-a-physical-card" },
    ];

    for (const claim of cases) {
      const random = new MaxIndexRandom();
      const engine = engineAtClaimCommit(random);
      assertRejectedWithoutMutation(
        engine,
        random,
        () => engine.commitClaim(claim.seatIndex, claim.cardId),
        "invalid_claim",
      );
    }
  });

  it("rejects a second claim from the same non-actor atomically", () => {
    const random = new MaxIndexRandom();
    const engine = engineAtClaimCommit(random);
    const playedCardId = engine.view(0).publicState.playedCards[0].id;
    engine.commitClaim(1, playedCardId);

    assertRejectedWithoutMutation(
      engine,
      random,
      () => engine.commitClaim(1, null),
      "claim_already_committed",
    );
  });

  it("reveals three passes together, scores each passer, and discards the table", () => {
    const random = new MaxIndexRandom();
    const engine = engineAtClaimCommit(random);
    const beforeViews = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
    const playedCards = beforeViews[0].publicState.playedCards;
    const beforeRandomRequests = [...random.requestedMaxima];

    engine.commitClaim(1, null);
    engine.commitClaim(2, null);
    engine.commitClaim(3, null);

    const afterViews = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
    const publicState = afterViews[0].publicState;
    const revealedPasses: readonly RevealedClaim[] = [
      { seatIndex: 1, cardId: null },
      { seatIndex: 2, cardId: null },
      { seatIndex: 3, cardId: null },
    ];
    assert.strictEqual(publicState.phase, "claim_reveal");
    assert.strictEqual(publicState.claimCommitCount, 3);
    assert.deepStrictEqual(publicState.revealedClaims, revealedPasses);
    assert.deepStrictEqual(publicState.claimAwards, []);
    assert.deepStrictEqual(publicState.discardedCards, playedCards);
    assert.deepStrictEqual(publicState.playedCards, []);
    assert.deepStrictEqual(
      publicState.participants.map((participant) => participant.score),
      [beforeViews[0].publicState.participants[0].score, 1, 1, 1],
    );
    assert.deepStrictEqual(
      publicState.participants.map((participant) => participant.handCount),
      [8, 8, 8, 8],
    );
    assert.deepStrictEqual(
      afterViews.map((view) => view.privateState.hand),
      beforeViews.map((view) => view.privateState.hand),
    );
    assert.deepStrictEqual(publicState.events.at(-1), {
      type: "claims_resolved",
      turnNumber: 1,
      claims: revealedPasses,
      awards: [],
      discardedCards: playedCards,
    });
    assert.deepStrictEqual(random.requestedMaxima, beforeRandomRequests);
  });

  it("awards three unique claims as the exact selected physical cards", () => {
    const random = new MaxIndexRandom();
    const engine = engineAtClaimCommit(random);
    const beforeViews = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
    const playedCards = beforeViews[0].publicState.playedCards;
    const beforeRandomRequests = [...random.requestedMaxima];

    engine.commitClaim(1, playedCards[0].id);
    engine.commitClaim(2, playedCards[1].id);
    engine.commitClaim(3, playedCards[2].id);

    const afterViews = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
    const publicState = afterViews[0].publicState;
    const awards = [
      { seatIndex: 1, card: playedCards[0], source: "unique" },
      { seatIndex: 2, card: playedCards[1], source: "unique" },
      { seatIndex: 3, card: playedCards[2], source: "unique" },
    ];
    assert.strictEqual(publicState.phase, "claim_reveal");
    assert.deepStrictEqual(publicState.claimAwards, awards);
    assert.deepStrictEqual(publicState.discardedCards, []);
    assert.deepStrictEqual(publicState.playedCards, []);
    assert.deepStrictEqual(
      publicState.participants.map((participant) => participant.handCount),
      [8, 9, 9, 9],
    );
    for (let seatIndex = 1; seatIndex < PARTICIPANTS.length; seatIndex += 1) {
      assert.deepStrictEqual(
        afterViews[seatIndex].privateState.hand,
        [...beforeViews[seatIndex].privateState.hand, playedCards[seatIndex - 1]],
      );
    }
    assert.deepStrictEqual(publicState.events.at(-1), {
      type: "claims_resolved",
      turnNumber: 1,
      claims: [
        { seatIndex: 1, cardId: playedCards[0].id },
        { seatIndex: 2, cardId: playedCards[1].id },
        { seatIndex: 3, cardId: playedCards[2].id },
      ],
      awards,
      discardedCards: [],
    });
    assert.deepStrictEqual(random.requestedMaxima, beforeRandomRequests);
  });

  it("removes unique awards before deterministic collision draws", () => {
    const scenarios = [
      {
        name: "collision plus unique",
        choices: [0, 0, 1] as const,
        expectedAwards: [
          { seatIndex: 3, cardIndex: 1, source: "unique" },
          { seatIndex: 1, cardIndex: 2, source: "collision" },
          { seatIndex: 2, cardIndex: 0, source: "collision" },
        ],
        expectedDiscardIndexes: [] as number[],
        expectedRandomMaxima: [2],
        expectedPassSeats: [] as number[],
      },
      {
        name: "collision plus pass",
        choices: [0, 0, null] as const,
        expectedAwards: [
          { seatIndex: 1, cardIndex: 2, source: "collision" },
          { seatIndex: 2, cardIndex: 1, source: "collision" },
        ],
        expectedDiscardIndexes: [0],
        expectedRandomMaxima: [3, 2],
        expectedPassSeats: [3],
      },
      {
        name: "three participant collision",
        choices: [0, 0, 0] as const,
        expectedAwards: [
          { seatIndex: 1, cardIndex: 2, source: "collision" },
          { seatIndex: 2, cardIndex: 1, source: "collision" },
          { seatIndex: 3, cardIndex: 0, source: "collision" },
        ],
        expectedDiscardIndexes: [] as number[],
        expectedRandomMaxima: [3, 2],
        expectedPassSeats: [] as number[],
      },
    ];

    for (const scenario of scenarios) {
      const random = new MaxIndexRandom();
      const engine = engineAtClaimCommit(random);
      const before = engine.view(0).publicState;
      const playedCards = before.playedCards;
      const beforeRandomCount = random.requestedMaxima.length;
      scenario.choices.forEach((choice, offset) => {
        engine.commitClaim(offset + 1, choice === null ? null : playedCards[choice].id);
      });

      const publicState = engine.view(0).publicState;
      assert.deepStrictEqual(
        publicState.claimAwards,
        scenario.expectedAwards.map((award) => ({
          seatIndex: award.seatIndex,
          card: playedCards[award.cardIndex],
          source: award.source,
        })),
        scenario.name,
      );
      assert.deepStrictEqual(
        publicState.discardedCards,
        scenario.expectedDiscardIndexes.map((index) => playedCards[index]),
        scenario.name,
      );
      assert.deepStrictEqual(
        random.requestedMaxima.slice(beforeRandomCount),
        scenario.expectedRandomMaxima,
        scenario.name,
      );
      for (const award of scenario.expectedAwards) {
        assert.strictEqual(
          engine.view(award.seatIndex).privateState.hand.at(-1),
          playedCards[award.cardIndex],
          scenario.name,
        );
      }
      for (const seatIndex of scenario.expectedPassSeats) {
        assert.strictEqual(
          publicState.participants[seatIndex].score,
          before.participants[seatIndex].score + 1,
          scenario.name,
        );
      }
    }
  });

  it("turns missing deadline choices into passes and resolves only once", () => {
    const random = new MaxIndexRandom();
    const engine = engineAtClaimCommit(random);
    const beforeViews = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
    const playedCards = beforeViews[0].publicState.playedCards;
    const claimedCardId = playedCards[0].id;
    engine.commitClaim(1, claimedCardId);

    engine.resolveClaimsAtDeadline();

    const afterViews = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
    const publicState = afterViews[0].publicState;
    assert.strictEqual(publicState.phase, "claim_reveal");
    assert.strictEqual(publicState.claimCommitCount, 1);
    assert.deepStrictEqual(publicState.revealedClaims, [
      { seatIndex: 1, cardId: claimedCardId },
      { seatIndex: 2, cardId: null },
      { seatIndex: 3, cardId: null },
    ]);
    assert.deepStrictEqual(publicState.claimAwards, [{
      seatIndex: 1,
      card: playedCards[0],
      source: "unique",
    }]);
    assert.deepStrictEqual(publicState.discardedCards, playedCards.slice(1));
    assert.deepStrictEqual(
      publicState.participants.map((participant) => participant.score),
      [beforeViews[0].publicState.participants[0].score, 0, 1, 1],
    );
    assert.deepStrictEqual(
      afterViews.map((view) => ({
        committed: view.privateState.claimCommitted,
        cardId: view.privateState.claimCardId,
      })),
      [
        { committed: false, cardId: null },
        { committed: true, cardId: claimedCardId },
        { committed: false, cardId: null },
        { committed: false, cardId: null },
      ],
    );
    assertRejectedWithoutMutation(
      engine,
      random,
      () => engine.resolveClaimsAtDeadline(),
      "invalid_phase",
    );
  });
});
