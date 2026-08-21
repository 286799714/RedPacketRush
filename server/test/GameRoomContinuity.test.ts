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
  actionId: number;
}

function tickClock(serverRoom: GameRoom, elapsedMilliseconds: number): void {
  serverRoom.clock.currentTime -= elapsedMilliseconds;
  serverRoom.clock.tick();
}

async function startActorPlay(colyseus: ColyseusTestServer<typeof appConfig>) {
  const host = await colyseus.sdk.create("game", {
    nickname: "甲",
    displayName: "行动时序测试",
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
  const privateStatePromises = participants.map((participant) => (
    participant.waitForMessage("match_private_state", 2000) as Promise<PrivateMatchState>
  ));
  const handled = serverRoom.waitForMessage("start");
  host.send("start", null);
  await handled;
  assert.strictEqual(serverRoom.state.phase, "point_contest");
  assert.strictEqual(serverRoom.state.actionDeadlineAtUnixMs, 0);
  tickClock(serverRoom, 900);
  const privateStates = await Promise.all(privateStatePromises);
  assert.strictEqual(serverRoom.state.phase, "actor_play");
  return { participants, serverRoom, privateStates };
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
    const actorUpdate = participants[actorSeatIndex].waitForMessage("match_private_state", 1000);
    let handled = serverRoom.waitForMessage("play_cards");
    participants[actorSeatIndex].send("play_cards", {
      cardIds: privateStates[actorSeatIndex].hand.slice(0, 3).map((card) => card.id),
      actionId: serverRoom.state.actionId,
    });
    await Promise.all([handled, actorUpdate]);
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
});
