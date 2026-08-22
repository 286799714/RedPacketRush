import assert from "assert";

import { findBestFinalSelection } from "../src/match/finalSettlement.js";
import {
  MatchCommandError,
  MatchEngine,
  type MatchParticipant,
} from "../src/match/MatchEngine.js";
import { SeededRandomSource } from "../src/match/random.js";

const PARTICIPANTS: readonly MatchParticipant[] = [
  { seatIndex: 0, participantId: "participant-a", nickname: "甲", bot: false },
  { seatIndex: 1, participantId: "participant-b", nickname: "乙", bot: false },
  { seatIndex: 2, participantId: "participant-c", nickname: "丙", bot: false },
  { seatIndex: 3, participantId: "participant-d", nickname: "丁", bot: false },
];

function startEngine(seed: number): MatchEngine {
  const engine = new MatchEngine(new SeededRandomSource(seed));
  engine.start(PARTICIPANTS, {
    deckMode: "one",
    actionDeadlineSeconds: 30,
  });
  engine.completePointContest();
  return engine;
}

function playPassingTurn(engine: MatchEngine): void {
  const actorSeatIndex = engine.view(0).publicState.actorSeatIndex;
  const actorHand = engine.view(actorSeatIndex).privateState.hand;
  engine.playCards(actorSeatIndex, actorHand.slice(0, 3).map((card) => card.id));
  for (const { seatIndex } of PARTICIPANTS) {
    if (seatIndex !== actorSeatIndex) {
      engine.commitClaim(seatIndex, null);
    }
  }
}

function assertRejectedWithoutMutation(engine: MatchEngine, action: () => void): void {
  const before = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
  let thrown: unknown;
  try {
    action();
  } catch (error) {
    thrown = error;
  }
  assert.ok(thrown instanceof MatchCommandError);
  assert.strictEqual(thrown.code, "invalid_phase");
  assert.deepStrictEqual(
    PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex)),
    before,
  );
}

describe("match final settlement", () => {
  it("keeps results hidden until the final turn boundary then reveals one best group per seat", () => {
    const engine = startEngine(19);
    for (let turn = 1; turn <= 9; turn += 1) {
      playPassingTurn(engine);
      assert.strictEqual(engine.view(0).publicState.phase, "claim_reveal");
      assert.deepStrictEqual(engine.view(0).publicState.finalResults, []);
      engine.completeClaimReveal();
      assert.strictEqual(engine.view(0).publicState.phase, "actor_play");
    }

    playPassingTurn(engine);
    const beforeRevealViews = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
    const beforeReveal = beforeRevealViews[0].publicState;
    assert.strictEqual(beforeReveal.phase, "claim_reveal");
    assert.deepStrictEqual(beforeReveal.finalResults, []);
    assert.ok(beforeRevealViews.every((view) => !view.privateState.finalCommitted));

    const expectedSelections = beforeRevealViews.map((view) => (
      findBestFinalSelection(view.privateState.hand)
    ));
    engine.completeClaimReveal();

    const views = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
    const revealed = views[0].publicState;
    assert.strictEqual(revealed.phase, "final_reveal");
    assert.strictEqual(revealed.actorSeatIndex, -1);
    assert.strictEqual(revealed.drawPileCount, 0);
    assert.strictEqual(revealed.sealedCardCount, 2);
    assert.strictEqual(revealed.finalResults.length, 4);
    assert.ok(revealed.finalResults.every((result) => result.groups.length === 1));
    assert.deepStrictEqual(
      revealed.finalResults.map((result) => result.groups),
      expectedSelections.map((selection) => selection.groups),
    );
    assert.deepStrictEqual(
      revealed.participants.map((participant, seatIndex) => (
        participant.score - beforeReveal.participants[seatIndex].score
      )),
      revealed.finalResults.map((result) => result.totalScore),
    );
    assert.ok(views.every((view) => view.privateState.finalCommitted));
    assert.deepStrictEqual(
      views.map((view) => view.privateState.finalGroups),
      expectedSelections.map((selection) => (
        selection.groups.map((group) => group.cards.map((card) => card.id))
      )),
    );
    assert.strictEqual(
      revealed.events.filter((event) => event.type === "final_settlement").length,
      1,
    );
  });

  it("adds every final score exactly once, records all winners, and then finishes", () => {
    const engine = startEngine(41);
    while (engine.view(0).publicState.phase === "actor_play") {
      playPassingTurn(engine);
      engine.completeClaimReveal();
    }

    const revealed = engine.view(0).publicState;
    assert.strictEqual(revealed.phase, "final_reveal");
    const highestScore = Math.max(...revealed.participants.map((participant) => participant.score));
    assert.deepStrictEqual(
      revealed.winnerSeatIndexes,
      revealed.participants
        .filter((participant) => participant.score === highestScore)
        .map((participant) => participant.seatIndex),
    );
    assert.deepStrictEqual(revealed.events.at(-1), {
      type: "final_settlement",
      results: revealed.finalResults,
      winnerSeatIndexes: revealed.winnerSeatIndexes,
    });

    engine.completeFinalReveal();
    const finished = engine.view(0).publicState;
    assert.strictEqual(finished.phase, "finished");
    assert.strictEqual(finished.actorSeatIndex, -1);
    assert.deepStrictEqual(finished.finalResults, revealed.finalResults);
    assert.deepStrictEqual(
      finished.participants.map((participant) => participant.score),
      revealed.participants.map((participant) => participant.score),
    );
    assertRejectedWithoutMutation(engine, () => engine.completeFinalReveal());
  });
});
