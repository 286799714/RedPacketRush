import assert from "assert";

import { createPhysicalDeck } from "../src/match/cards.js";
import {
  MatchEngine,
  type MatchParticipant,
  type PointContestRoundEvent,
  type PublicMatchEvent,
} from "../src/match/MatchEngine.js";
import {
  SeededRandomSource,
  type RandomSource,
} from "../src/match/random.js";

class MaxIndexRandom implements RandomSource {
  public nextInt(maxExclusive: number): number {
    return maxExclusive - 1;
  }
}

class SequenceRandom implements RandomSource {
  public readonly requestedMaxima: number[] = [];
  private nextValueIndex = 0;

  public constructor(private readonly values: readonly number[]) {}

  public nextInt(maxExclusive: number): number {
    this.requestedMaxima.push(maxExclusive);
    if (this.nextValueIndex < this.values.length) {
      const value = this.values[this.nextValueIndex];
      this.nextValueIndex += 1;
      return value;
    }
    return maxExclusive - 1;
  }
}

const PARTICIPANTS: readonly MatchParticipant[] = [
  { seatIndex: 0, participantId: "participant-a", nickname: "甲", bot: false },
  { seatIndex: 1, participantId: "participant-b", nickname: "乙", bot: false },
  { seatIndex: 2, participantId: "participant-c", nickname: "丙", bot: true },
  { seatIndex: 3, participantId: "participant-d", nickname: "丁", bot: true },
];

function pointContestEvents(
  events: readonly PublicMatchEvent[],
): PointContestRoundEvent[] {
  const contestEvents = events.filter((event): event is PointContestRoundEvent => (
    event.type === "point_contest_round"
  ));
  assert.strictEqual(contestEvents.length, events.length);
  return contestEvents;
}

function buildExhaustedPointContestSequence(): number[] {
  let cards = [...createPhysicalDeck("two")];
  const drawnCards = [] as typeof cards;
  const values: number[] = [];
  const draw = (cardId: string): void => {
    const index = cards.findIndex((card) => card.id === cardId);
    assert.notStrictEqual(index, -1, `missing fixed-sequence card ${cardId}`);
    values.push(index);
    const [card] = cards.splice(index, 1);
    drawnCards.push(card);
  };

  draw("copy-0:hearts:14");
  draw("copy-1:hearts:14");
  draw("copy-0:clubs:2");
  draw("copy-1:clubs:2");
  for (const card of createPhysicalDeck("one")) {
    if (card.id === "copy-0:hearts:14" || card.id === "copy-0:clubs:2") {
      continue;
    }
    draw(card.id);
    draw(card.id.replace("copy-0:", "copy-1:"));
  }
  assert.strictEqual(cards.length, 0);

  cards = [...drawnCards];
  draw("copy-0:clubs:2");
  draw("copy-0:hearts:14");
  return values;
}

describe("match opening", () => {
  it("creates stable unique physical cards for one- and two-deck matches", () => {
    const oneDeck = createPhysicalDeck("one");
    const twoDecks = createPhysicalDeck("two");

    assert.strictEqual(oneDeck.length, 52);
    assert.strictEqual(twoDecks.length, 104);
    assert.strictEqual(new Set(oneDeck.map((card) => card.id)).size, 52);
    assert.strictEqual(new Set(twoDecks.map((card) => card.id)).size, 104);
    assert.deepStrictEqual(oneDeck[0], {
      id: "copy-0:clubs:2",
      rank: 2,
      suit: "clubs",
      copyIndex: 0,
    });
    assert.deepStrictEqual(twoDecks[103], {
      id: "copy-1:hearts:14",
      rank: 14,
      suit: "hearts",
      copyIndex: 1,
    });
    assert.ok(twoDecks.every((card) => card.rank >= 2 && card.rank <= 14));
    assert.ok(twoDecks.every((card) => Object.isFrozen(card)));
  });

  it("reveals an immediate point-contest winner and deals the opening hands", () => {
    const engine = new MatchEngine(new MaxIndexRandom());

    engine.start(PARTICIPANTS, {
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });

    const view = engine.view(0);
    assert.deepStrictEqual(view.publicState, {
      phase: "point_contest",
      actorSeatIndex: 0,
      firstActorSeatIndex: 0,
      drawPileCount: 32,
      playedCards: [],
      playedCategory: null,
      playedScore: 0,
      turnNumber: 0,
      revealedClaims: [],
      claimAwards: [],
      discardedCards: [],
      sealedCardCount: 0,
      pendingDiscardSeatIndexes: [],
      finalResults: [],
      winnerSeatIndexes: [],
      participants: [
        { ...PARTICIPANTS[0], score: 0, handCount: 5 },
        { ...PARTICIPANTS[1], score: 0, handCount: 5 },
        { ...PARTICIPANTS[2], score: 0, handCount: 5 },
        { ...PARTICIPANTS[3], score: 0, handCount: 5 },
      ],
      events: [
        {
          type: "point_contest_round",
          roundNumber: 1,
          reveals: [
            {
              seatIndex: 0,
              card: { id: "copy-0:hearts:14", rank: 14, suit: "hearts", copyIndex: 0 },
            },
            {
              seatIndex: 1,
              card: { id: "copy-0:hearts:13", rank: 13, suit: "hearts", copyIndex: 0 },
            },
            {
              seatIndex: 2,
              card: { id: "copy-0:hearts:12", rank: 12, suit: "hearts", copyIndex: 0 },
            },
            {
              seatIndex: 3,
              card: { id: "copy-0:hearts:11", rank: 11, suit: "hearts", copyIndex: 0 },
            },
          ],
          tiedSeats: [],
          winnerSeatIndex: 0,
        },
      ],
    });
    assert.deepStrictEqual(view.privateState, {
      seatIndex: 0,
      participantId: "participant-a",
      hand: [
        { id: "copy-0:hearts:14", rank: 14, suit: "hearts", copyIndex: 0 },
        { id: "copy-0:hearts:10", rank: 10, suit: "hearts", copyIndex: 0 },
        { id: "copy-0:hearts:6", rank: 6, suit: "hearts", copyIndex: 0 },
        { id: "copy-0:hearts:2", rank: 2, suit: "hearts", copyIndex: 0 },
        { id: "copy-0:diamonds:11", rank: 11, suit: "diamonds", copyIndex: 0 },
      ],
      claimCommitted: false,
      claimCardId: null,
      finalCommitted: false,
      finalGroups: [],
    });

    engine.completePointContest();
    assert.strictEqual(engine.view(0).publicState.phase, "actor_play");
    assert.throws(() => engine.completePointContest(), /point contest is not active/);
  });

  it("redraws only exact-strength leaders until the point contest has one winner", () => {
    const random = new SequenceRandom([0, 50, 0, 100, 0, 98]);
    const engine = new MatchEngine(random);

    engine.start(PARTICIPANTS, {
      deckMode: "two",
      actionDeadlineSeconds: 15,
    });

    const publicState = engine.view(2).publicState;
    assert.strictEqual(publicState.actorSeatIndex, 3);
    assert.strictEqual(publicState.drawPileCount, 84);
    assert.deepStrictEqual(publicState.events, [
      {
        type: "point_contest_round",
        roundNumber: 1,
        reveals: [
          {
            seatIndex: 0,
            card: { id: "copy-0:clubs:2", rank: 2, suit: "clubs", copyIndex: 0 },
          },
          {
            seatIndex: 1,
            card: { id: "copy-0:hearts:14", rank: 14, suit: "hearts", copyIndex: 0 },
          },
          {
            seatIndex: 2,
            card: { id: "copy-0:clubs:3", rank: 3, suit: "clubs", copyIndex: 0 },
          },
          {
            seatIndex: 3,
            card: { id: "copy-1:hearts:14", rank: 14, suit: "hearts", copyIndex: 1 },
          },
        ],
        tiedSeats: [1, 3],
        winnerSeatIndex: null,
      },
      {
        type: "point_contest_round",
        roundNumber: 2,
        reveals: [
          {
            seatIndex: 1,
            card: { id: "copy-0:clubs:4", rank: 4, suit: "clubs", copyIndex: 0 },
          },
          {
            seatIndex: 3,
            card: { id: "copy-1:hearts:13", rank: 13, suit: "hearts", copyIndex: 1 },
          },
        ],
        tiedSeats: [],
        winnerSeatIndex: 3,
      },
    ]);
    assert.deepStrictEqual(random.requestedMaxima.slice(0, 7), [
      104,
      103,
      102,
      101,
      100,
      99,
      104,
    ]);
  });

  it("recycles exhausted contest cards and keeps tied leaders drawing", () => {
    const random = new SequenceRandom(buildExhaustedPointContestSequence());
    const engine = new MatchEngine(random);

    engine.start(PARTICIPANTS, {
      deckMode: "two",
      actionDeadlineSeconds: 30,
    });

    const publicState = engine.view(0).publicState;
    const contestEvents = pointContestEvents(publicState.events);
    assert.strictEqual(contestEvents.length, 52);
    assert.deepStrictEqual(contestEvents[50].tiedSeats, [0, 1]);
    assert.strictEqual(contestEvents[51].winnerSeatIndex, 1);
    assert.strictEqual(publicState.actorSeatIndex, 1);
    assert.strictEqual(publicState.drawPileCount, 84);
    assert.deepStrictEqual(random.requestedMaxima.slice(102, 106), [2, 1, 104, 103]);
  });

  it("orders equal point-contest ranks from clubs through hearts", () => {
    const engine = new MatchEngine(new SequenceRandom([12, 24, 36, 48]));

    engine.start(PARTICIPANTS, {
      deckMode: "one",
      actionDeadlineSeconds: 60,
    });

    const [round] = pointContestEvents(engine.view(0).publicState.events);
    assert.deepStrictEqual(
      round.reveals.map((reveal) => ({
        seatIndex: reveal.seatIndex,
        rank: reveal.card.rank,
        suit: reveal.card.suit,
      })),
      [
        { seatIndex: 0, rank: 14, suit: "clubs" },
        { seatIndex: 1, rank: 14, suit: "spades" },
        { seatIndex: 2, rank: 14, suit: "diamonds" },
        { seatIndex: 3, rank: 14, suit: "hearts" },
      ],
    );
    assert.strictEqual(round.winnerSeatIndex, 3);
  });

  it("returns contest cards to a full deck and isolates every private hand", () => {
    const engine = new MatchEngine(new MaxIndexRandom());
    engine.start(PARTICIPANTS, {
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });

    const views = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
    const publicState = views[0].publicState;
    const dealtIds = views.flatMap((view) => view.privateState.hand.map((card) => card.id));
    const contestIds = pointContestEvents(publicState.events).flatMap((event) => (
      event.reveals.map((reveal) => reveal.card.id)
    ));

    assert.strictEqual(new Set(dealtIds).size, 20);
    assert.strictEqual(publicState.drawPileCount + dealtIds.length, 52);
    assert.ok(contestIds.every((cardId) => dealtIds.includes(cardId)));
    for (const [seatIndex, view] of views.entries()) {
      assert.deepStrictEqual(view.publicState, publicState);
      assert.strictEqual(view.privateState.seatIndex, seatIndex);
      assert.strictEqual(view.privateState.participantId, PARTICIPANTS[seatIndex].participantId);
      assert.strictEqual(view.privateState.hand.length, 5);
      assert.deepStrictEqual(Object.keys(view.privateState), [
        "seatIndex",
        "participantId",
        "hand",
        "claimCommitted",
        "claimCardId",
        "finalCommitted",
        "finalGroups",
      ]);
    }
    assert.deepStrictEqual(Object.keys(publicState), [
      "phase",
      "actorSeatIndex",
      "firstActorSeatIndex",
      "drawPileCount",
      "playedCards",
      "playedCategory",
      "playedScore",
      "turnNumber",
      "revealedClaims",
      "claimAwards",
      "discardedCards",
      "sealedCardCount",
      "pendingDiscardSeatIndexes",
      "finalResults",
      "winnerSeatIndexes",
      "participants",
      "events",
    ]);
    assert.ok(publicState.participants.every((participant) => !("hand" in participant)));
  });

  it("rejects invalid participant sets before consuming randomness", () => {
    const invalidParticipantSets: readonly (readonly MatchParticipant[])[] = [
      PARTICIPANTS.slice(0, 3),
      [PARTICIPANTS[0], PARTICIPANTS[1], PARTICIPANTS[2], {
        ...PARTICIPANTS[3],
        seatIndex: 2,
      }],
      [PARTICIPANTS[0], PARTICIPANTS[1], PARTICIPANTS[2], {
        ...PARTICIPANTS[3],
        participantId: PARTICIPANTS[0].participantId,
      }],
    ];

    for (const participants of invalidParticipantSets) {
      const random = new SequenceRandom([]);
      const engine = new MatchEngine(random);
      assert.throws(() => engine.start(participants, {
        deckMode: "one",
        actionDeadlineSeconds: 30,
      }));
      assert.deepStrictEqual(random.requestedMaxima, []);
      assert.throws(() => engine.view(0), /match has not started/);
    }
  });

  it("fails fast on an invalid random index without retaining a partial match", () => {
    const random = new SequenceRandom([52]);
    const engine = new MatchEngine(random);

    assert.throws(() => engine.start(PARTICIPANTS, {
      deckMode: "one",
      actionDeadlineSeconds: 30,
    }), /invalid index 52 for 52/);
    assert.throws(() => engine.view(0), /match has not started/);

    engine.start(PARTICIPANTS, {
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    assert.strictEqual(engine.view(0).publicState.phase, "point_contest");
  });

  it("provides a deterministic seeded random source for production matches", () => {
    const first = new SeededRandomSource(20260821);
    const second = new SeededRandomSource(20260821);
    const firstValues = Array.from({ length: 8 }, () => first.nextInt(52));
    const secondValues = Array.from({ length: 8 }, () => second.nextInt(52));

    assert.deepStrictEqual(firstValues, secondValues);
    assert.ok(firstValues.every((value) => value >= 0 && value < 52));
  });
});
