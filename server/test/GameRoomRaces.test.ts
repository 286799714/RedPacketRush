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

async function reconnectBeforeDeadline(
  colyseus: ColyseusTestServer<typeof appConfig>,
  serverRoom: GameRoom,
  participant: Awaited<ReturnType<typeof startActorPlay>>["participants"][number],
  seatIndex: number,
) {
  const reconnectionToken = participant.reconnectionToken;
  participant.reconnection.enabled = false;
  await participant.leave(false);
  await waitForCondition(() => serverRoom.state.seats[seatIndex].connected === false);
  tickClock(serverRoom, 14_000);
  const reconnected = await colyseus.sdk.reconnect(reconnectionToken);
  const privateState = await reconnected.waitForMessage(
    "match_private_state",
    1000,
  ) as PrivateMatchState;
  await waitForCondition(() => serverRoom.state.seats[seatIndex].connected === true);
  return { reconnected, privateState };
}

async function expectStaleAction(
  serverRoom: GameRoom,
  participant: { send(type: string, payload: unknown): void; waitForMessage(type: string, timeout?: number): Promise<unknown> },
  type: string,
  payload: unknown,
): Promise<void> {
  const before = serverRoom.state.toJSON();
  const handled = serverRoom.waitForMessage(type);
  const rejected = participant.waitForMessage("room_error", 1000) as Promise<{ code: string }>;
  participant.send(type, payload);
  const [, error] = await Promise.all([handled, rejected]);
  assert.strictEqual(error.code, "stale_action");
  assert.deepStrictEqual(serverRoom.state.toJSON(), before);
}

async function expireToBot(
  serverRoom: GameRoom,
  participant: Awaited<ReturnType<typeof startActorPlay>>["participants"][number],
  seatIndex: number,
): Promise<string> {
  const reconnectionToken = participant.reconnectionToken;
  participant.reconnection.enabled = false;
  await participant.leave(false);
  await waitForCondition(() => serverRoom.state.seats[seatIndex].connected === false);
  tickClock(serverRoom, 30_000);
  await waitForCondition(() => serverRoom.state.seats[seatIndex].bot === true);
  drainImmediateTasks(serverRoom);
  return reconnectionToken;
}

async function enterClaimCommit(
  result: Awaited<ReturnType<typeof startActorPlay>>,
): Promise<void> {
  const { participants, serverRoom, privateStates } = result;
  const actorSeatIndex = serverRoom.state.actorSeatIndex;
  const handled = serverRoom.waitForMessage("play_cards");
  participants[actorSeatIndex].send("play_cards", {
    cardIds: privateStates[actorSeatIndex].hand.slice(0, 3).map((card) => card.id),
    actionId: serverRoom.state.actionId,
  });
  await handled;
  assert.strictEqual(serverRoom.state.phase, "claim_commit");
}

async function enterSingleAwardDiscard(
  result: Awaited<ReturnType<typeof startActorPlay>>,
): Promise<number> {
  await enterClaimCommit(result);
  const { participants, serverRoom } = result;
  const actorSeatIndex = serverRoom.state.actorSeatIndex;
  const claimantSeatIndexes = participants
    .map((_, seatIndex) => seatIndex)
    .filter((seatIndex) => seatIndex !== actorSeatIndex);
  const awardedSeatIndex = claimantSeatIndexes[0];
  const cardId = serverRoom.state.playedCards[0].id;
  for (const seatIndex of claimantSeatIndexes) {
    const handled = serverRoom.waitForMessage("claim");
    participants[seatIndex].send("claim", {
      cardId: seatIndex === awardedSeatIndex ? cardId : null,
      actionId: serverRoom.state.actionId,
    });
    await handled;
  }
  assert.strictEqual(serverRoom.state.phase, "claim_reveal");
  tickClock(serverRoom, 900);
  assert.strictEqual(serverRoom.state.phase, "award_discard");
  return awardedSeatIndex;
}

function advanceToFinalReveal(serverRoom: GameRoom): void {
  for (let step = 0; step < 80 && serverRoom.state.phase !== "final_reveal"; step += 1) {
    if (serverRoom.state.phase === "claim_reveal") {
      tickClock(serverRoom, 900);
    } else {
      tickClock(serverRoom, serverRoom.state.actionDeadlineSeconds * 1000);
    }
  }
  assert.strictEqual(serverRoom.state.phase, "final_reveal");
}

async function leaveParticipants(
  participants: Awaited<ReturnType<typeof startActorPlay>>["participants"],
  replacedSeatIndex: number,
  replacement: Awaited<ReturnType<ColyseusTestServer<typeof appConfig>["sdk"]["reconnect"]>>,
): Promise<void> {
  await replacement.leave();
  await Promise.all(participants
    .filter((_, seatIndex) => seatIndex !== replacedSeatIndex)
    .map((participant) => participant.leave()));
}

async function leaveRemainingParticipants(
  participants: Awaited<ReturnType<typeof startActorPlay>>["participants"],
  droppedSeatIndex: number,
): Promise<void> {
  await Promise.all(participants
    .filter((_, seatIndex) => seatIndex !== droppedSeatIndex)
    .map((participant) => participant.leave()));
}

describe("game room reconnect and timeout races", () => {
  let colyseus: ColyseusTestServer<typeof appConfig>;

  before(async () => colyseus = await getTestServer());

  beforeEach(async () => {
    await colyseus.cleanup();
  });

  it("lets a reconnected actor play just before the deadline exactly once", async () => {
    const result = await startActorPlay(colyseus);
    const { participants, serverRoom } = result;
    const seatIndex = serverRoom.state.actorSeatIndex;
    const actionId = serverRoom.state.actionId;
    const { reconnected, privateState } = await reconnectBeforeDeadline(
      colyseus,
      serverRoom,
      participants[seatIndex],
      seatIndex,
    );
    const cardIds = privateState.hand.slice(0, 3).map((card) => card.id);
    const handled = serverRoom.waitForMessage("play_cards");
    reconnected.send("play_cards", { cardIds, actionId });
    await handled;
    tickClock(serverRoom, 1_000);

    assert.strictEqual(serverRoom.state.phase, "claim_commit");
    assert.strictEqual(serverRoom.state.playEvents.length, 1);
    await expectStaleAction(serverRoom, reconnected, "play_cards", { cardIds, actionId });
    await leaveParticipants(participants, seatIndex, reconnected);
  });

  it("lets a reconnected claimant commit just before the deadline exactly once", async () => {
    const result = await startActorPlay(colyseus);
    await enterClaimCommit(result);
    const { participants, serverRoom } = result;
    const actorSeatIndex = serverRoom.state.actorSeatIndex;
    const seatIndex = (actorSeatIndex + 1) % participants.length;
    const actionId = serverRoom.state.actionId;
    const { reconnected } = await reconnectBeforeDeadline(
      colyseus,
      serverRoom,
      participants[seatIndex],
      seatIndex,
    );
    const cardId = serverRoom.state.playedCards[0].id;
    const handled = serverRoom.waitForMessage("claim");
    reconnected.send("claim", { cardId, actionId });
    await handled;
    tickClock(serverRoom, 1_000);

    assert.strictEqual(serverRoom.state.phase, "claim_reveal");
    assert.strictEqual(serverRoom.state.claimEvents.length, 1);
    await expectStaleAction(serverRoom, reconnected, "claim", { cardId, actionId });
    await leaveParticipants(participants, seatIndex, reconnected);
  });

  it("lets a reconnected recipient discard just before the deadline exactly once", async () => {
    const result = await startActorPlay(colyseus);
    const seatIndex = await enterSingleAwardDiscard(result);
    const { participants, serverRoom } = result;
    const actionId = serverRoom.state.actionId;
    const turnNumber = serverRoom.state.turnNumber;
    const { reconnected, privateState } = await reconnectBeforeDeadline(
      colyseus,
      serverRoom,
      participants[seatIndex],
      seatIndex,
    );
    const protectedCardId = serverRoom.state.claimAwards.find(
      (award) => award.seatIndex === seatIndex,
    )?.card.id;
    const cardId = privateState.hand.find((card) => card.id !== protectedCardId)!.id;
    const handled = serverRoom.waitForMessage("discard");
    reconnected.send("discard", { cardId, turnNumber, actionId });
    await handled;
    tickClock(serverRoom, 1_000);

    assert.strictEqual(serverRoom.state.phase, "actor_play");
    assert.strictEqual(serverRoom.state.discardEvents.length, 1);
    assert.strictEqual(serverRoom.state.seats[seatIndex].handCount, 5);
    assert.strictEqual(serverRoom.state.pendingDiscardSeatIndexes.length, 0);
    await expectStaleAction(
      serverRoom,
      reconnected,
      "discard",
      { cardId, turnNumber, actionId },
    );
    await leaveParticipants(participants, seatIndex, reconnected);
  });

  it("gives a reconnecting finalist the automatic result without settling twice", async () => {
    const result = await startActorPlay(colyseus);
    const { participants, serverRoom } = result;
    advanceToFinalReveal(serverRoom);
    const seatIndex = 0;
    const { reconnected, privateState } = await reconnectBeforeDeadline(
      colyseus,
      serverRoom,
      participants[seatIndex],
      seatIndex,
    );
    assert.strictEqual(serverRoom.state.phase, "finished");
    assert.strictEqual(serverRoom.state.finalEvents.length, 1);
    assert.strictEqual(privateState.finalCommitted, true);
    assert.strictEqual(privateState.finalGroups.length, 1);
    await leaveParticipants(participants, seatIndex, reconnected);
  });

  it("rejects an actor reconnect after expiry and lets its bot play exactly once", async () => {
    const result = await startActorPlay(colyseus, 60);
    const { participants, serverRoom } = result;
    const seatIndex = serverRoom.state.actorSeatIndex;
    const reconnectionToken = await expireToBot(
      serverRoom,
      participants[seatIndex],
      seatIndex,
    );

    assert.strictEqual(serverRoom.state.phase, "claim_commit");
    assert.strictEqual(serverRoom.state.playEvents.length, 1);
    const actionId = serverRoom.state.actionId;
    drainImmediateTasks(serverRoom);
    assert.strictEqual(serverRoom.state.actionId, actionId);
    assert.strictEqual(serverRoom.state.playEvents.length, 1);
    await assert.rejects(() => colyseus.sdk.reconnect(reconnectionToken));
    await leaveRemainingParticipants(participants, seatIndex);
  });

  it("rejects a claimant reconnect after expiry and commits its bot claim exactly once", async () => {
    const result = await startActorPlay(colyseus, 60);
    await enterClaimCommit(result);
    const { participants, serverRoom } = result;
    const actorSeatIndex = serverRoom.state.actorSeatIndex;
    const seatIndex = (actorSeatIndex + 1) % participants.length;
    const reconnectionToken = await expireToBot(
      serverRoom,
      participants[seatIndex],
      seatIndex,
    );
    const remainingClaimantSeats = participants
      .map((_, candidateSeatIndex) => candidateSeatIndex)
      .filter((candidateSeatIndex) => (
        candidateSeatIndex !== actorSeatIndex && candidateSeatIndex !== seatIndex
      ));
    for (const claimantSeatIndex of remainingClaimantSeats) {
      const handled = serverRoom.waitForMessage("claim");
      participants[claimantSeatIndex].send("claim", {
        cardId: null,
        actionId: serverRoom.state.actionId,
      });
      await handled;
    }

    assert.strictEqual(serverRoom.state.phase, "claim_reveal");
    assert.strictEqual(serverRoom.state.claimEvents.length, 1);
    assert.strictEqual(
      serverRoom.state.revealedClaims.filter((claim) => claim.seatIndex === seatIndex).length,
      1,
    );
    await assert.rejects(() => colyseus.sdk.reconnect(reconnectionToken));
    await leaveRemainingParticipants(participants, seatIndex);
  });

  it("rejects a recipient reconnect after expiry and lets its bot discard exactly once", async () => {
    const result = await startActorPlay(colyseus, 60);
    const seatIndex = await enterSingleAwardDiscard(result);
    const { participants, serverRoom } = result;
    const reconnectionToken = await expireToBot(
      serverRoom,
      participants[seatIndex],
      seatIndex,
    );

    assert.ok(
      serverRoom.state.phase === "actor_play" || serverRoom.state.phase === "claim_commit",
    );
    assert.strictEqual(serverRoom.state.discardEvents.length, 1);
    assert.strictEqual(serverRoom.state.seats[seatIndex].handCount, 5);
    assert.strictEqual(serverRoom.state.pendingDiscardSeatIndexes.length, 0);
    const actionId = serverRoom.state.actionId;
    drainImmediateTasks(serverRoom);
    assert.strictEqual(serverRoom.state.actionId, actionId);
    assert.strictEqual(serverRoom.state.discardEvents.length, 1);
    await assert.rejects(() => colyseus.sdk.reconnect(reconnectionToken));
    await leaveRemainingParticipants(participants, seatIndex);
  });

  it("rejects a finalist reconnect after expiry without settling twice", async () => {
    const result = await startActorPlay(colyseus, 60);
    const { participants, serverRoom } = result;
    advanceToFinalReveal(serverRoom);
    const seatIndex = 0;
    const reconnectionToken = await expireToBot(
      serverRoom,
      participants[seatIndex],
      seatIndex,
    );
    assert.strictEqual(serverRoom.state.phase, "finished");
    assert.strictEqual(serverRoom.state.finalEvents.length, 1);
    drainImmediateTasks(serverRoom);
    assert.strictEqual(serverRoom.state.finalEvents.length, 1);
    await assert.rejects(() => colyseus.sdk.reconnect(reconnectionToken));
    await leaveRemainingParticipants(participants, seatIndex);
  });
});
