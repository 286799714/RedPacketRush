import assert from "assert";
import { ColyseusTestServer } from "@colyseus/testing";

import appConfig from "../src/app.config.js";
import type { PhysicalCard } from "../src/match/cards.js";
import { GameRoom } from "../src/rooms/GameRoom.js";
import { getTestServer } from "./testServer.js";

interface PrivateMatchState {
  seatIndex: number;
  participantId: string;
  hand: PhysicalCard[];
  claimCommitted: boolean;
  claimCardId: string | null;
  finalCommitted: boolean;
  finalGroups: string[][];
}

interface UntypedMessageRoom {
  onMessage(type: string, callback: (payload: unknown) => void): () => void;
}

function onRoomMessage(
  participant: unknown,
  type: string,
  callback: (payload: unknown) => void,
): () => void {
  return (participant as UntypedMessageRoom).onMessage(type, callback);
}

function tickClock(serverRoom: GameRoom, elapsedMilliseconds: number): void {
  serverRoom.clock.currentTime -= elapsedMilliseconds;
  serverRoom.clock.tick();
}

async function startFinalCommit(colyseus: ColyseusTestServer<typeof appConfig>) {
  const host = await colyseus.sdk.create("game", {
    nickname: "甲",
    displayName: "最终结算测试",
    deckMode: "one",
    actionDeadlineSeconds: 15,
  });
  const participants = [
    host,
    await colyseus.sdk.joinById(host.roomId, { nickname: "乙" }),
    await colyseus.sdk.joinById(host.roomId, { nickname: "丙" }),
    await colyseus.sdk.joinById(host.roomId, { nickname: "丁" }),
  ];
  const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
  for (const participant of participants) {
    const handled = serverRoom.waitForMessage("set_ready");
    participant.send("set_ready", { ready: true });
    await handled;
  }
  const openingStatePromises = participants.map((participant) => (
    participant.waitForMessage("match_private_state", 2000) as Promise<PrivateMatchState>
  ));
  const startHandled = serverRoom.waitForMessage("start");
  host.send("start", null);
  await startHandled;
  tickClock(serverRoom, 900);
  let privateStates = await Promise.all(openingStatePromises);
  assert.strictEqual(serverRoom.state.phase, "actor_play");

  for (let turn = 0; turn < 6; turn += 1) {
    const actorSeatIndex = serverRoom.state.actorSeatIndex;
    const actorUpdate = participants[actorSeatIndex].waitForMessage(
      "match_private_state",
      1000,
    ) as Promise<PrivateMatchState>;
    let handled = serverRoom.waitForMessage("play_cards");
    participants[actorSeatIndex].send("play_cards", {
      cardIds: privateStates[actorSeatIndex].hand.slice(0, 3).map((card) => card.id),
    });
    const [, actorPrivateState] = await Promise.all([handled, actorUpdate]);
    privateStates[actorSeatIndex] = actorPrivateState;

    const claimantSeats = participants
      .map((_, seatIndex) => seatIndex)
      .filter((seatIndex) => seatIndex !== actorSeatIndex);
    for (let claimantIndex = 0; claimantIndex < claimantSeats.length; claimantIndex += 1) {
      const seatIndex = claimantSeats[claimantIndex];
      const privateUpdates = claimantIndex === claimantSeats.length - 1
        ? participants.map((participant) => (
          participant.waitForMessage("match_private_state", 1000) as Promise<PrivateMatchState>
        ))
        : [participants[seatIndex].waitForMessage(
          "match_private_state",
          1000,
        ) as Promise<PrivateMatchState>];
      handled = serverRoom.waitForMessage("claim");
      participants[seatIndex].send("claim", { cardId: null });
      await handled;
      const updates = await Promise.all(privateUpdates);
      if (claimantIndex === claimantSeats.length - 1) {
        privateStates = updates;
      } else {
        privateStates[seatIndex] = updates[0];
      }
    }
    assert.strictEqual(serverRoom.state.phase, "claim_reveal");

    const turnBoundaryStates = participants.map((participant) => (
      participant.waitForMessage("match_private_state", 1000) as Promise<PrivateMatchState>
    ));
    tickClock(serverRoom, 900);
    privateStates = await Promise.all(turnBoundaryStates);
  }

  assert.strictEqual(serverRoom.state.phase, "final_commit");
  assert.strictEqual(serverRoom.state.sealedCardCount, 2);
  return { participants, serverRoom, privateStates };
}

function firstLegalGroups(privateState: PrivateMatchState): string[][] {
  const ids = privateState.hand.map((card) => card.id);
  return [ids.slice(0, 3), ids.slice(3, 6)];
}

async function expectFinalSelectionError(
  serverRoom: GameRoom,
  participant: Awaited<ReturnType<typeof startFinalCommit>>["participants"][number],
  payload: unknown,
  expectedCode: string,
): Promise<void> {
  const before = serverRoom.state.toJSON();
  const handled = serverRoom.waitForMessage("final_selection");
  const rejected = participant.waitForMessage("room_error", 1000);
  participant.send("final_selection", payload);
  const [, error] = await Promise.all([handled, rejected]);
  assert.strictEqual(error.code, expectedCode);
  assert.deepStrictEqual(serverRoom.state.toJSON(), before);
}

describe("game room final settlement", () => {
  let colyseus: ColyseusTestServer<typeof appConfig>;

  before(async () => colyseus = await getTestServer());

  beforeEach(async () => {
    await colyseus.cleanup();
  });

  it("validates manual messages atomically and acknowledges a commit only to its owner", async () => {
    const { participants, serverRoom, privateStates } = await startFinalCommit(colyseus);
    const groups = firstLegalGroups(privateStates[0]);

    await expectFinalSelectionError(serverRoom, participants[0], null, "invalid_payload");
    await expectFinalSelectionError(
      serverRoom,
      participants[0],
      { mode: "manual", groups: [groups[0]] },
      "invalid_payload",
    );
    await expectFinalSelectionError(
      serverRoom,
      participants[0],
      { mode: "manual", groups: [groups[0], [groups[0][0], ...groups[1].slice(1)]] },
      "invalid_final_selection",
    );

    const publicBefore = serverRoom.state.toJSON();
    const privateMessages = participants.map((): PrivateMatchState[] => []);
    const publicStateChanges = participants.map(() => 0);
    participants.forEach((participant, seatIndex) => {
      onRoomMessage(participant, "match_private_state", (payload) => {
        privateMessages[seatIndex].push(payload as PrivateMatchState);
      });
      participant.onStateChange(() => {
        publicStateChanges[seatIndex] += 1;
      });
    });
    await new Promise((resolve) => setTimeout(resolve, 50));
    publicStateChanges.fill(0);
    const acknowledged = participants[0].waitForMessage(
      "match_private_state",
      1000,
    ) as Promise<PrivateMatchState>;
    const handled = serverRoom.waitForMessage("final_selection");
    participants[0].send("final_selection", { mode: "manual", groups });
    const [, privateState] = await Promise.all([handled, acknowledged]);
    await new Promise((resolve) => setTimeout(resolve, 50));

    assert.deepStrictEqual(serverRoom.state.toJSON(), publicBefore);
    assert.strictEqual(privateState.finalCommitted, true);
    assert.strictEqual(privateState.finalGroups.length, 2);
    assert.deepStrictEqual(privateMessages.map((messages) => messages.length), [1, 0, 0, 0]);
    assert.deepStrictEqual(publicStateChanges, [0, 0, 0, 0]);
    assert.ok(!Object.hasOwn(serverRoom.state.toJSON(), "finalCommitCount"));
    assert.ok(!Object.hasOwn(serverRoom.state.toJSON(), "finalGroups"));
    await expectFinalSelectionError(
      serverRoom,
      participants[0],
      { mode: "best" },
      "final_selection_already_committed",
    );

    await Promise.all(participants.map((participant) => participant.leave()));
  });

  it("reveals the fourth commit to everyone then finishes after the display interval", async () => {
    const { participants, serverRoom } = await startFinalCommit(colyseus);
    for (let seatIndex = 0; seatIndex < 3; seatIndex += 1) {
      const acknowledged = participants[seatIndex].waitForMessage(
        "match_private_state",
        1000,
      );
      const handled = serverRoom.waitForMessage("final_selection");
      participants[seatIndex].send("final_selection", { mode: "best" });
      await Promise.all([handled, acknowledged]);
      assert.strictEqual(serverRoom.state.phase, "final_commit");
      assert.strictEqual(serverRoom.state.finalResults.length, 0);
    }

    const revealMessages = participants.map((participant) => (
      participant.waitForMessage("match_private_state", 1000) as Promise<PrivateMatchState>
    ));
    const handled = serverRoom.waitForMessage("final_selection");
    participants[3].send("final_selection", { mode: "best" });
    await Promise.all([handled, ...revealMessages]);

    const revealed = serverRoom.state.toJSON();
    assert.strictEqual(revealed.phase, "final_reveal");
    assert.strictEqual(revealed.finalResults.length, 4);
    assert.ok(revealed.finalResults.every((result: { groups: unknown[] }) => result.groups.length === 2));
    assert.ok(revealed.winnerSeatIndexes.length >= 1);
    assert.deepStrictEqual(revealed.finalEvents, [{
      results: revealed.finalResults,
      winnerSeatIndexes: revealed.winnerSeatIndexes,
    }]);
    await expectFinalSelectionError(
      serverRoom,
      participants[3],
      { mode: "best" },
      "invalid_phase",
    );

    const finishedMessages = participants.map((participant) => (
      participant.waitForMessage("match_private_state", 1000)
    ));
    tickClock(serverRoom, 900);
    await Promise.all(finishedMessages);
    assert.strictEqual(serverRoom.state.phase, "finished");
    assert.deepStrictEqual(serverRoom.state.toJSON().finalResults, revealed.finalResults);
    assert.deepStrictEqual(serverRoom.state.toJSON().winnerSeatIndexes, revealed.winnerSeatIndexes);

    await Promise.all(participants.map((participant) => participant.leave()));
  });
});
