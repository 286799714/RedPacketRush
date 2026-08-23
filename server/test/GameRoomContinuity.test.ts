import assert from "assert";
import { ColyseusTestServer } from "@colyseus/testing";

import appConfig from "../src/app.config.js";
import { GameRoom } from "../src/rooms/GameRoom.js";
import {
  drainImmediateTasks,
  type PrivateMatchState,
  startActorPlay,
  tickClock,
  waitForCondition,
} from "./gameRoomTestDriver.js";
import { getTestServer } from "./testServer.js";

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


async function startBotAssistedActorPlay(colyseus: ColyseusTestServer<typeof appConfig>) {
  const host = await colyseus.sdk.create("game", {
    nickname: "甲",
    displayName: "机器人时序测试",
    deckMode: "one",
    actionDeadlineSeconds: 15,
  });
  const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
  let handled = serverRoom.waitForMessage("fill_bots");
  host.send("fill_bots", null);
  await handled;
  handled = serverRoom.waitForMessage("set_ready");
  host.send("set_ready", { ready: true });
  await handled;
  const privateStatePromise = host.waitForMessage(
    "match_private_state",
    2000,
  ) as Promise<PrivateMatchState>;
  handled = serverRoom.waitForMessage("start");
  host.send("start", null);
  await handled;
  tickClock(serverRoom, 900);
  const privateState = await privateStatePromise;
  assert.strictEqual(serverRoom.state.phase, "actor_play");
  return { host, serverRoom, privateState };
}

function advanceCurrentPhase(serverRoom: GameRoom): void {
  drainImmediateTasks(serverRoom);
  if (serverRoom.state.phase === "finished") {
    return;
  }
  if (
    serverRoom.state.phase === "point_contest"
    || serverRoom.state.phase === "final_reveal"
  ) {
    tickClock(serverRoom, 900);
  } else if (serverRoom.state.phase === "play_reveal") {
    tickClock(serverRoom, 3_000);
  } else if (serverRoom.state.phase === "claim_reveal") {
    tickClock(serverRoom, 4_000);
  } else if (serverRoom.state.phase === "discard_reveal") {
    tickClock(serverRoom, 2_000);
  } else {
    tickClock(serverRoom, serverRoom.state.actionDeadlineSeconds * 1000);
  }
}

async function expectRoomError(
  serverRoom: GameRoom,
  participant: Awaited<ReturnType<typeof startActorPlay>>["participants"][number],
  type: string,
  payload: unknown,
  expectedCode: string,
): Promise<void> {
  const before = serverRoom.state.toJSON();
  const handled = serverRoom.waitForMessage(type);
  const rejected = participant.waitForMessage("room_error", 1000);
  participant.send(type, payload);
  const [, error] = await Promise.all([handled, rejected]);
  assert.strictEqual(error.code, expectedCode);
  assert.deepStrictEqual(serverRoom.state.toJSON(), before);
}

describe("game room action continuity", () => {
  let colyseus: ColyseusTestServer<typeof appConfig>;

  before(async () => colyseus = await getTestServer());

  beforeEach(async () => {
    await colyseus.cleanup();
  });

  it("publishes one actor deadline and includes the current action id in private state", async () => {
    const { participants, serverRoom, privateStates } = await startActorPlay(colyseus);
    const state = serverRoom.state.toJSON();

    assert.ok(Number.isSafeInteger(state.actionId));
    assert.ok(state.actionId > 0);
    assert.ok(state.actionDeadlineAtUnixMs > Date.now());
    assert.ok(state.actionDeadlineAtUnixMs <= Date.now() + 15_500);
    assert.ok(privateStates.every((privateState) => privateState.actionId === state.actionId));
    assert.deepStrictEqual(
      state.seats.map((seat: { bot: boolean; connected: boolean }) => ({
        bot: seat.bot,
        connected: seat.connected,
      })),
      participants.map(() => ({ bot: false, connected: true })),
    );

    await Promise.all(participants.map((participant) => participant.leave()));
  });

  it("rejects missing and stale action ids before an actor play mutates state", async () => {
    const { participants, serverRoom, privateStates } = await startActorPlay(colyseus);
    const actorSeatIndex = serverRoom.state.actorSeatIndex;
    const actor = participants[actorSeatIndex];
    const cardIds = privateStates[actorSeatIndex].hand.slice(0, 3).map((card) => card.id);

    await expectRoomError(
      serverRoom,
      actor,
      "play_cards",
      { cardIds },
      "invalid_payload",
    );
    await expectRoomError(
      serverRoom,
      actor,
      "play_cards",
      { cardIds, actionId: serverRoom.state.actionId - 1 },
      "stale_action",
    );

    await Promise.all(participants.map((participant) => participant.leave()));
  });

  it("keeps one action id and deadline while claim commits are still partial", async () => {
    const { participants, serverRoom, privateStates } = await startActorPlay(colyseus);
    const actorSeatIndex = serverRoom.state.actorSeatIndex;
    const playUpdates = participants.map((participant) => (
      participant.waitForMessage("match_private_state", 1000)
    ));
    let handled = serverRoom.waitForMessage("play_cards");
    participants[actorSeatIndex].send("play_cards", {
      cardIds: privateStates[actorSeatIndex].hand.slice(0, 3).map((card) => card.id),
      actionId: serverRoom.state.actionId,
    });
    await Promise.all([handled, ...playUpdates]);
    assert.strictEqual(serverRoom.state.phase, "play_reveal");
    tickClock(serverRoom, 3_000);
    assert.strictEqual(serverRoom.state.phase, "claim_commit");
    const claimActionId = serverRoom.state.actionId;
    const claimDeadline = serverRoom.state.actionDeadlineAtUnixMs;
    const claimantSeatIndex = participants
      .map((_, seatIndex) => seatIndex)
      .find((seatIndex) => seatIndex !== actorSeatIndex)!;
    const acknowledged = participants[claimantSeatIndex].waitForMessage(
      "match_private_state",
      1000,
    );
    handled = serverRoom.waitForMessage("claim");
    participants[claimantSeatIndex].send("claim", {
      cardId: null,
      actionId: claimActionId,
    });
    await Promise.all([handled, acknowledged]);

    assert.strictEqual(serverRoom.state.phase, "claim_commit");
    assert.strictEqual(serverRoom.state.actionId, claimActionId);
    assert.strictEqual(serverRoom.state.actionDeadlineAtUnixMs, claimDeadline);

    await Promise.all(participants.map((participant) => participant.leave()));
  });

  it("sends every human the new private action id after a human actor plays", async () => {
    const { participants, serverRoom, privateStates } = await startActorPlay(colyseus);
    const actorSeatIndex = serverRoom.state.actorSeatIndex;
    const received = participants.map((): PrivateMatchState[] => []);
    const unsubscribe = participants.map((participant, seatIndex) => onRoomMessage(
      participant,
      "match_private_state",
      (payload) => received[seatIndex].push(payload as PrivateMatchState),
    ));
    const updates = participants.map((participant) => participant.waitForMessage(
      "match_private_state",
      1000,
    ) as Promise<PrivateMatchState>);
    const handled = serverRoom.waitForMessage("play_cards");
    participants[actorSeatIndex].send("play_cards", {
      cardIds: privateStates[actorSeatIndex].hand.slice(0, 3).map((card) => card.id),
      actionId: serverRoom.state.actionId,
    });
    await handled;
    const snapshots = await Promise.all(updates);

    assert.strictEqual(serverRoom.state.phase, "play_reveal");
    assert.ok(snapshots.every((snapshot) => snapshot.actionId === serverRoom.state.actionId));
    assert.deepStrictEqual(
      snapshots.map((snapshot) => snapshot.participantId),
      participants.map((participant) => participant.sessionId),
    );
    assert.deepStrictEqual(received.map((messages) => messages.length), [1, 1, 1, 1]);
    unsubscribe.forEach((removeListener) => removeListener());
    await Promise.all(participants.map((participant) => participant.leave()));
  });

  it("sends every connected human the new private action id after a bot actor plays", async () => {
    const { participants, serverRoom } = await startActorPlay(colyseus);
    const actorSeatIndex = serverRoom.state.actorSeatIndex;
    const connectedParticipants = participants.filter(
      (_, seatIndex) => seatIndex !== actorSeatIndex,
    );
    const received = connectedParticipants.map((): PrivateMatchState[] => []);
    const unsubscribe = connectedParticipants.map((participant, index) => onRoomMessage(
      participant,
      "match_private_state",
      (payload) => received[index].push(payload as PrivateMatchState),
    ));
    const updates = connectedParticipants.map((participant) => participant.waitForMessage(
      "match_private_state",
      1000,
    ) as Promise<PrivateMatchState>);

    await participants[actorSeatIndex].leave();
    drainImmediateTasks(serverRoom);
    const snapshots = await Promise.all(updates);

    assert.strictEqual(serverRoom.state.phase, "play_reveal");
    assert.ok(snapshots.every((snapshot) => snapshot.actionId === serverRoom.state.actionId));
    assert.deepStrictEqual(
      snapshots.map((snapshot) => snapshot.participantId),
      connectedParticipants.map((participant) => participant.sessionId),
    );
    assert.deepStrictEqual(received.map((messages) => messages.length), [1, 1, 1]);
    unsubscribe.forEach((removeListener) => removeListener());
    await Promise.all(connectedParticipants.map((participant) => participant.leave()));
  });

  it("runs bot plays and claims through zero-delay room clock tasks", async () => {
    const { host, serverRoom, privateState } = await startBotAssistedActorPlay(colyseus);
    const actorSeatIndex = serverRoom.state.actorSeatIndex;
    const actorIsBot = serverRoom.state.seats[actorSeatIndex].bot;

    if (actorIsBot) {
      drainImmediateTasks(serverRoom);
      assert.strictEqual(serverRoom.state.phase, "play_reveal");
      assert.strictEqual(serverRoom.state.playEvents.length, 1);
      assert.strictEqual(serverRoom.state.seats[actorSeatIndex].handCount, 5);
    } else {
      const handled = serverRoom.waitForMessage("play_cards");
      host.send("play_cards", {
        cardIds: privateState.hand.slice(0, 3).map((card) => card.id),
        actionId: serverRoom.state.actionId,
      });
      await handled;
      assert.strictEqual(serverRoom.state.phase, "play_reveal");
      tickClock(serverRoom, 3_000);
      drainImmediateTasks(serverRoom);
      assert.strictEqual(serverRoom.state.phase, "claim_reveal");
      assert.strictEqual(serverRoom.state.revealedClaims.length, 3);
    }

    await host.leave();
  });

  it("finishes a one-human three-bot one-deck match using only the room clock", async () => {
    const { host, serverRoom } = await startBotAssistedActorPlay(colyseus);

    for (let step = 0; step < 100 && serverRoom.state.phase !== "finished"; step += 1) {
      advanceCurrentPhase(serverRoom);
    }

    const finished = serverRoom.state.toJSON();
    assert.strictEqual(finished.phase, "finished");
    assert.strictEqual(finished.turnNumber, 10);
    assert.strictEqual(finished.playEvents.length, 10);
    assert.strictEqual(finished.finalResults.length, 4);
    assert.strictEqual(finished.finalEvents.length, 1);
    assert.ok(finished.winnerSeatIndexes.length >= 1);
    assert.strictEqual(finished.drawPileCount, 0);
    assert.strictEqual(finished.sealedCardCount, 2);
    assert.strictEqual(finished.actionDeadlineAtUnixMs, 0);
    assert.deepStrictEqual(
      finished.seats.map((seat: { handCount: number }) => seat.handCount),
      [5, 5, 5, 5],
    );

    await host.leave();
  });

  it("restores a dropped human with fresh public and private state", async () => {
    const { participants, serverRoom } = await startActorPlay(colyseus);
    const seatIndex = serverRoom.state.actorSeatIndex;
    const dropped = participants[seatIndex];
    const sessionId = dropped.sessionId;
    const reconnectionToken = dropped.reconnectionToken;
    dropped.reconnection.enabled = false;

    await dropped.leave(false);
    await waitForCondition(() => serverRoom.state.seats[seatIndex].connected === false);
    assert.strictEqual(serverRoom.state.seats[seatIndex].participantId, sessionId);
    assert.strictEqual(serverRoom.state.seats[seatIndex].bot, false);

    const reconnected = await colyseus.sdk.reconnect(reconnectionToken);
    const privateState = await reconnected.waitForMessage(
      "match_private_state",
      1000,
    ) as PrivateMatchState;
    await waitForCondition(() => serverRoom.state.seats[seatIndex].connected === true);
    await waitForCondition(() => (
      reconnected.state.toJSON().seats?.[seatIndex]?.connected === true
    ));

    assert.strictEqual(reconnected.sessionId, sessionId);
    assert.strictEqual(
      serverRoom.clients.find((client) => client.sessionId === sessionId)?.userData?.seatIndex,
      seatIndex,
    );
    assert.strictEqual(serverRoom.state.seats[seatIndex].bot, false);
    assert.strictEqual(privateState.participantId, sessionId);
    assert.strictEqual(privateState.seatIndex, seatIndex);
    assert.strictEqual(privateState.actionId, serverRoom.state.actionId);
    assert.strictEqual(privateState.hand.length, 5);
    assert.deepStrictEqual(reconnected.state.toJSON(), serverRoom.state.toJSON());
    assert.strictEqual(serverRoom.clients.length, 4);
    assert.strictEqual(new Set(serverRoom.clients.map((client) => client.sessionId)).size, 4);
    assert.strictEqual(
      serverRoom.state.seats.filter((seat) => seat.participantId === sessionId).length,
      1,
    );

    await reconnected.leave();
    await Promise.all(participants
      .filter((_, participantSeatIndex) => participantSeatIndex !== seatIndex)
      .map((participant) => participant.leave()));
  });

  it("turns an expired dropped claimant into a bot and unblocks claims", async () => {
    const { participants, serverRoom } = await startActorPlay(colyseus);
    const actorSeatIndex = serverRoom.state.actorSeatIndex;
    const droppedSeatIndex = (actorSeatIndex + 1) % participants.length;
    const dropped = participants[droppedSeatIndex];
    const sessionId = dropped.sessionId;
    const reconnectionToken = dropped.reconnectionToken;
    dropped.reconnection.enabled = false;

    await dropped.leave(false);
    await waitForCondition(() => serverRoom.state.seats[droppedSeatIndex].connected === false);
    tickClock(serverRoom, 30_000);
    await waitForCondition(() => serverRoom.state.seats[droppedSeatIndex].bot === true);

    const takenOverSeat = serverRoom.state.seats[droppedSeatIndex];
    assert.strictEqual(takenOverSeat.participantId, sessionId);
    assert.strictEqual(takenOverSeat.connected, false);
    assert.strictEqual(takenOverSeat.ready, true);
    assert.strictEqual(serverRoom.state.phase, "play_reveal");
    tickClock(serverRoom, 3_000);
    assert.strictEqual(serverRoom.state.phase, "claim_commit");
    drainImmediateTasks(serverRoom);

    const remainingClaimantSeats = participants
      .map((_, seatIndex) => seatIndex)
      .filter((seatIndex) => seatIndex !== actorSeatIndex && seatIndex !== droppedSeatIndex);
    for (const seatIndex of remainingClaimantSeats) {
      const handled = serverRoom.waitForMessage("claim");
      participants[seatIndex].send("claim", {
        cardId: null,
        actionId: serverRoom.state.actionId,
      });
      await handled;
    }

    assert.strictEqual(serverRoom.state.phase, "claim_reveal");
    const botClaim = serverRoom.state.revealedClaims.find(
      (claim) => claim.seatIndex === droppedSeatIndex,
    );
    assert.strictEqual(botClaim?.cardId, serverRoom.state.claimEvents[0].claims.find(
      (claim) => claim.seatIndex === droppedSeatIndex,
    )?.cardId);
    assert.ok(botClaim);
    await assert.rejects(() => colyseus.sdk.reconnect(reconnectionToken));

    await Promise.all(participants
      .filter((_, seatIndex) => seatIndex !== droppedSeatIndex)
      .map((participant) => participant.leave()));
  });

  it("hands a consented leaving actor to a bot immediately", async () => {
    const { participants, serverRoom } = await startActorPlay(colyseus);
    const actorSeatIndex = serverRoom.state.actorSeatIndex;
    const actor = participants[actorSeatIndex];
    const sessionId = actor.sessionId;

    await actor.leave();
    await waitForCondition(() => serverRoom.state.seats[actorSeatIndex].bot === true);
    assert.strictEqual(serverRoom.state.seats[actorSeatIndex].participantId, sessionId);
    assert.strictEqual(serverRoom.state.seats[actorSeatIndex].connected, false);
    drainImmediateTasks(serverRoom);
    assert.strictEqual(serverRoom.state.phase, "play_reveal");
    assert.strictEqual(serverRoom.state.playEvents.length, 1);

    await Promise.all(participants
      .filter((_, seatIndex) => seatIndex !== actorSeatIndex)
      .map((participant) => participant.leave()));
  });
});
