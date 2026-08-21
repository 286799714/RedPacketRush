import assert from "assert";

import {
  MatchCommandError,
  MatchEngine,
  type MatchCommandErrorCode,
  type MatchParticipant,
} from "../src/match/MatchEngine.js";
import { SeededRandomSource } from "../src/match/random.js";

const PARTICIPANTS: readonly MatchParticipant[] = [
  { seatIndex: 0, participantId: "participant-a", nickname: "甲", bot: false },
  { seatIndex: 1, participantId: "participant-b", nickname: "乙", bot: false },
  { seatIndex: 2, participantId: "participant-c", nickname: "丙", bot: true },
  { seatIndex: 3, participantId: "participant-d", nickname: "丁", bot: true },
];

function engineAtFinalCommit(seed = 17): MatchEngine {
  const engine = new MatchEngine(new SeededRandomSource(seed));
  engine.start(PARTICIPANTS, { deckMode: "one", actionDeadlineSeconds: 30 });
  engine.completePointContest();
  for (let turn = 0; turn < 6; turn += 1) {
    const actorSeatIndex = engine.view(0).publicState.actorSeatIndex;
    const cardIds = engine.view(actorSeatIndex).privateState.hand
      .slice(0, 3)
      .map((card) => card.id);
    engine.playCards(actorSeatIndex, cardIds);
    for (const { seatIndex } of PARTICIPANTS) {
      if (seatIndex !== actorSeatIndex) {
        engine.commitClaim(seatIndex, null);
      }
    }
    engine.completeClaimReveal();
  }
  assert.strictEqual(engine.view(0).publicState.phase, "final_commit");
  return engine;
}

function firstLegalGroups(engine: MatchEngine, seatIndex: number): string[][] {
  const ids = engine.view(seatIndex).privateState.hand.map((card) => card.id);
  return [ids.slice(0, 3), ids.slice(3, 6)];
}

function assertSameSelectedCards(
  actualGroups: readonly (readonly string[])[],
  submittedGroups: readonly (readonly string[])[],
): void {
  assert.strictEqual(actualGroups.length, 2);
  assert.ok(actualGroups.every((group) => group.length === 3));
  assert.deepStrictEqual(
    actualGroups.flat().sort(),
    submittedGroups.flat().sort(),
  );
}

function assertRejectedWithoutMutation(
  engine: MatchEngine,
  action: () => void,
  expectedCode: MatchCommandErrorCode,
): void {
  const before = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
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
    before,
  );
}

describe("match final settlement", () => {
  it("keeps commits owner-private and rejects invalid or duplicate selections atomically", () => {
    const engine = engineAtFinalCommit();
    const seatZeroGroups = firstLegalGroups(engine, 0);
    const seatZeroHand = engine.view(0).privateState.hand;
    const otherCardId = engine.view(1).privateState.hand[0].id;
    const invalidSelections: readonly (readonly (readonly string[])[])[] = [
      [seatZeroGroups[0]],
      [seatZeroGroups[0], seatZeroGroups[1].slice(0, 2)],
      [seatZeroGroups[0], [seatZeroGroups[0][0], ...seatZeroGroups[1].slice(0, 2)]],
      [seatZeroGroups[0], [otherCardId, ...seatZeroGroups[1].slice(1)]],
      [seatZeroGroups[0], [seatZeroGroups[1][0], seatZeroGroups[1][1], ""]],
    ];
    for (const groups of invalidSelections) {
      assertRejectedWithoutMutation(
        engine,
        () => engine.commitFinalSelection(0, groups),
        "invalid_final_selection",
      );
    }

    const publicBefore = engine.view(0).publicState;
    engine.commitFinalSelection(0, seatZeroGroups);

    const views = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
    assert.deepStrictEqual(views[0].publicState, publicBefore);
    assert.deepStrictEqual(
      views.map((view) => view.privateState.finalCommitted),
      [true, false, false, false],
    );
    assertSameSelectedCards(views[0].privateState.finalGroups, seatZeroGroups);
    assert.ok(views.slice(1).every((view) => view.privateState.finalGroups.length === 0));
    assert.ok(!Object.hasOwn(views[0].publicState, "finalCommitCount"));
    assert.deepStrictEqual(views[0].publicState.finalResults, []);
    assert.deepStrictEqual(views[0].publicState.winnerSeatIndexes, []);
    assertRejectedWithoutMutation(
      engine,
      () => engine.commitBestFinalSelection(0),
      "final_selection_already_committed",
    );
    assert.strictEqual(seatZeroHand.length, 8);
  });

  it("uses best choices for missing commits at the fallback boundary", () => {
    const engine = engineAtFinalCommit(23);
    const manualGroups = firstLegalGroups(engine, 0);
    engine.commitFinalSelection(0, manualGroups);

    engine.resolveFinalSelectionsAtDeadline();

    const views = PARTICIPANTS.map(({ seatIndex }) => engine.view(seatIndex));
    const state = views[0].publicState;
    assert.strictEqual(state.phase, "final_reveal");
    assert.strictEqual(state.finalResults.length, 4);
    assertSameSelectedCards(
      state.finalResults[0].groups.map((group) => group.cards.map((card) => card.id)),
      manualGroups,
    );
    assert.ok(views.every((view) => view.privateState.finalCommitted));
    assertRejectedWithoutMutation(
      engine,
      () => engine.resolveFinalSelectionsAtDeadline(),
      "invalid_phase",
    );
  });

  it("reveals all selections together, adds scores once, and finishes without mutation", () => {
    const engine = engineAtFinalCommit(41);
    const scoresBefore = engine.view(0).publicState.participants.map((participant) => participant.score);
    const groupsBySeat = PARTICIPANTS.map(({ seatIndex }) => firstLegalGroups(engine, seatIndex));

    for (let seatIndex = 0; seatIndex < 3; seatIndex += 1) {
      engine.commitFinalSelection(seatIndex, groupsBySeat[seatIndex]);
      assert.strictEqual(engine.view(0).publicState.phase, "final_commit");
      assert.deepStrictEqual(engine.view(0).publicState.finalResults, []);
    }
    engine.commitFinalSelection(3, groupsBySeat[3]);

    const revealed = engine.view(0).publicState;
    assert.strictEqual(revealed.phase, "final_reveal");
    assert.strictEqual(revealed.actorSeatIndex, -1);
    assert.strictEqual(revealed.finalResults.length, 4);
    assert.strictEqual(revealed.events.filter((event) => event.type === "final_settlement").length, 1);
    assert.deepStrictEqual(
      revealed.participants.map((participant, seatIndex) => participant.score - scoresBefore[seatIndex]),
      revealed.finalResults.map((result) => result.totalScore),
    );
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
    assert.deepStrictEqual(
      finished.participants.map((participant) => participant.score),
      revealed.participants.map((participant) => participant.score),
    );
    assertRejectedWithoutMutation(
      engine,
      () => engine.completeFinalReveal(),
      "invalid_phase",
    );
  });

  it("publishes every seat tied at the highest final score as a co-winner", () => {
    const engine = engineAtFinalCommit(6);
    for (const { seatIndex } of PARTICIPANTS) {
      engine.commitBestFinalSelection(seatIndex);
    }
    const tiedState = engine.view(0).publicState;

    const highestScore = Math.max(...tiedState.participants.map((participant) => participant.score));
    assert.deepStrictEqual(tiedState.winnerSeatIndexes, [1, 2, 3]);
    assert.ok(tiedState.winnerSeatIndexes.every((seatIndex) => (
      tiedState.participants[seatIndex].score === highestScore
    )));
  });
});
