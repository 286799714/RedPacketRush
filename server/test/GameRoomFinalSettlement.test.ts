import assert from "assert";
import { ColyseusTestServer } from "@colyseus/testing";

import appConfig from "../src/app.config.js";
import type { PhysicalCard } from "../src/match/cards.js";
import { GameRoom } from "../src/rooms/GameRoom.js";
import {
  startActorPlay,
  tickClock,
} from "./gameRoomTestDriver.js";
import { getTestServer } from "./testServer.js";

interface FinalPrivateMatchState {
  seatIndex: number;
  participantId: string;
  hand: PhysicalCard[];
  finalCommitted: boolean;
  finalGroups: string[][];
  actionId: number;
}

interface MessageParticipant {
  waitForMessage(type: string, timeout?: number): Promise<unknown>;
}

async function waitForFinalPrivateState(
  participant: MessageParticipant,
): Promise<FinalPrivateMatchState> {
  for (let attempt = 0; attempt < 30; attempt += 1) {
    const privateState = await participant.waitForMessage(
      "match_private_state",
      1000,
    ) as FinalPrivateMatchState;
    if (privateState.finalCommitted) {
      return privateState;
    }
  }
  throw new Error("final private state was not received");
}

function advanceToLastClaimReveal(serverRoom: GameRoom): void {
  for (let step = 0; step < 80; step += 1) {
    if (serverRoom.state.phase === "claim_reveal" && serverRoom.state.turnNumber === 10) {
      return;
    }
    if (serverRoom.state.phase === "play_reveal") {
      tickClock(serverRoom, 3_000);
    } else if (serverRoom.state.phase === "claim_reveal") {
      tickClock(serverRoom, 4_000);
    } else if (serverRoom.state.phase === "discard_reveal") {
      tickClock(serverRoom, 2_000);
    } else {
      tickClock(serverRoom, serverRoom.state.actionDeadlineSeconds * 1000);
    }
  }
  throw new Error("match did not reach the final claim reveal");
}

describe("game room final settlement", () => {
  let colyseus: ColyseusTestServer<typeof appConfig>;

  before(async () => colyseus = await getTestServer());

  beforeEach(async () => {
    await colyseus.cleanup();
  });

  it("automatically reveals one best group for every player with no commit wait", async () => {
    const { participants, serverRoom } = await startActorPlay(colyseus);
    advanceToLastClaimReveal(serverRoom);

    const before = serverRoom.state.toJSON();
    assert.strictEqual(before.phase, "claim_reveal");
    assert.strictEqual(before.turnNumber, 10);
    assert.strictEqual(before.finalResults.length, 0);
    assert.deepStrictEqual(
      before.seats.map((seat: { handCount: number }) => seat.handCount),
      [5, 5, 5, 5],
    );
    const finalPrivateMessages = participants.map((participant) => (
      waitForFinalPrivateState(participant)
    ));

    tickClock(serverRoom, 4_000);
    const revealed = serverRoom.state.toJSON();
    const privateStates = await Promise.all(finalPrivateMessages);
    assert.strictEqual(revealed.phase, "final_reveal");
    assert.strictEqual(revealed.actorSeatIndex, -1);
    assert.strictEqual(revealed.actionDeadlineAtUnixMs, 0);
    assert.strictEqual(revealed.drawPileCount, 0);
    assert.strictEqual(revealed.sealedCardCount, 2);
    assert.strictEqual(revealed.finalResults.length, 4);
    assert.ok(revealed.finalResults.every((result: { groups: unknown[] }) => (
      result.groups.length === 1
    )));
    assert.deepStrictEqual(revealed.finalEvents, [{
      results: revealed.finalResults,
      winnerSeatIndexes: revealed.winnerSeatIndexes,
    }]);
    assert.ok(revealed.winnerSeatIndexes.length >= 1);
    assert.deepStrictEqual(privateStates.map((privateState) => ({
      handCount: privateState.hand.length,
      finalCommitted: privateState.finalCommitted,
      finalGroupCount: privateState.finalGroups.length,
    })), Array.from({ length: 4 }, () => ({
      handCount: 5,
      finalCommitted: true,
      finalGroupCount: 1,
    })));
    assert.deepStrictEqual(
      revealed.seats.map((seat: { score: number }, seatIndex: number) => (
        seat.score - before.seats[seatIndex].score
      )),
      revealed.finalResults.map((result: { totalScore: number }) => result.totalScore),
    );

    await Promise.all(participants.map((participant) => participant.leave()));
  });

  it("finishes after the reveal interval without adding final scores twice", async () => {
    const { participants, serverRoom } = await startActorPlay(colyseus);
    advanceToLastClaimReveal(serverRoom);
    tickClock(serverRoom, 4_000);
    const revealed = serverRoom.state.toJSON();
    const finishedMessages = participants.map((participant) => (
      participant.waitForMessage("match_private_state", 1000)
    ));

    tickClock(serverRoom, 900);
    await Promise.all(finishedMessages);

    const finished = serverRoom.state.toJSON();
    assert.strictEqual(finished.phase, "finished");
    assert.strictEqual(finished.actorSeatIndex, -1);
    assert.strictEqual(finished.finalEvents.length, 1);
    assert.deepStrictEqual(finished.finalResults, revealed.finalResults);
    assert.deepStrictEqual(finished.winnerSeatIndexes, revealed.winnerSeatIndexes);
    assert.deepStrictEqual(
      finished.seats.map((seat: { score: number }) => seat.score),
      revealed.seats.map((seat: { score: number }) => seat.score),
    );

    await Promise.all(participants.map((participant) => participant.leave()));
  });
});
