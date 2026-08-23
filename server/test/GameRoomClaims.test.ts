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
  actionId: number;
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

async function startClaimCommit(colyseus: ColyseusTestServer<typeof appConfig>) {
  const host = await colyseus.sdk.create("game", {
    nickname: "甲",
    displayName: "秘密抢牌测试",
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
  let handled = serverRoom.waitForMessage("start");
  host.send("start", null);
  await handled;
  assert.strictEqual(serverRoom.state.phase, "point_contest");
  tickClock(serverRoom, 900);
  const openingStates = await Promise.all(openingStatePromises);
  assert.strictEqual(serverRoom.state.phase, "actor_play");

  const actorSeatIndex = serverRoom.state.actorSeatIndex;
  const replacementStatesReceived = participants.map((participant) => (
    participant.waitForMessage("match_private_state", 2000)
  ));
  handled = serverRoom.waitForMessage("play_cards");
  participants[actorSeatIndex].send("play_cards", {
    cardIds: openingStates[actorSeatIndex].hand.slice(0, 3).map((card) => card.id),
    actionId: serverRoom.state.actionId,
  });
  await Promise.all([handled, ...replacementStatesReceived]);
  assert.strictEqual(serverRoom.state.phase, "play_reveal");
  const claimCommitStatesReceived = participants.map((participant) => (
    participant.waitForMessage("match_private_state", 2000)
  ));
  tickClock(serverRoom, 3_000);
  await Promise.all(claimCommitStatesReceived);
  assert.strictEqual(serverRoom.state.phase, "claim_commit");

  return { participants, serverRoom, actorSeatIndex };
}

async function assertClaimRejectedWithoutMutation(
  serverRoom: GameRoom,
  participant: {
    send(type: string, payload: unknown): void;
    waitForMessage(type: string, timeout?: number): Promise<{ code: string }>;
  },
  payload: unknown,
  expectedCode: string,
): Promise<void> {
  const before = serverRoom.state.toJSON();
  const rejected = participant.waitForMessage("room_error", 1000);
  const handled = serverRoom.waitForMessage("claim");
  participant.send("claim", isRecordPayload(payload)
    ? { ...payload, actionId: serverRoom.state.actionId }
    : payload);
  const [, roomError] = await Promise.all([handled, rejected]);

  assert.strictEqual(roomError.code, expectedCode);
  assert.deepStrictEqual(serverRoom.state.toJSON(), before);
}

function isRecordPayload(payload: unknown): payload is Record<string, unknown> {
  return typeof payload === "object" && payload !== null && !Array.isArray(payload);
}

describe("game room secret claims", () => {
  let colyseus: ColyseusTestServer<typeof appConfig>;

  before(async () => colyseus = await getTestServer());

  beforeEach(async () => {
    await colyseus.cleanup();
  });

  it("rejects a claim privately before a match has started", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "抢牌阶段测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    const before = serverRoom.state.toJSON();

    const rejected = host.waitForMessage("room_error", 1000);
    host.send("claim", { cardId: null });

    assert.deepStrictEqual(await rejected, {
      code: "invalid_phase",
      message: "当前阶段不能抢牌",
    });
    assert.deepStrictEqual(serverRoom.state.toJSON(), before);

    await host.leave();
  });

  it("rejects a malformed claim without changing public or private state", async () => {
    const { participants, serverRoom, actorSeatIndex } = await startClaimCommit(colyseus);
    const claimantSeatIndex = (actorSeatIndex + 1) % participants.length;
    const claimant = participants[claimantSeatIndex];
    const before = serverRoom.state.toJSON();
    const privateMessages = participants.map((): PrivateMatchState[] => []);
    participants.forEach((participant, seatIndex) => {
      onRoomMessage(participant, "match_private_state", (payload) => {
        privateMessages[seatIndex].push(payload as PrivateMatchState);
      });
    });

    const rejected = claimant.waitForMessage("room_error", 1000);
    claimant.send("claim", {});

    assert.deepStrictEqual(await rejected, {
      code: "invalid_payload",
      message: "抢牌参数必须包含牌标识或空值",
    });
    assert.deepStrictEqual(serverRoom.state.toJSON(), before);
    assert.deepStrictEqual(privateMessages.map((messages) => messages.length), [0, 0, 0, 0]);

    await Promise.all(participants.map((participant) => participant.leave()));
  });

  it("acknowledges one valid claim only to its owner without revealing the choice", async () => {
    const { participants, serverRoom, actorSeatIndex } = await startClaimCommit(colyseus);
    const claimantSeatIndex = (actorSeatIndex + 1) % participants.length;
    const claimant = participants[claimantSeatIndex];
    const claimedCardId = serverRoom.state.playedCards[0].id;
    const beforePublicState = serverRoom.state.toJSON();
    const privateMessages = participants.map((): PrivateMatchState[] => []);
    participants.forEach((participant, seatIndex) => {
      onRoomMessage(participant, "match_private_state", (payload) => {
        privateMessages[seatIndex].push(payload as PrivateMatchState);
      });
    });

    const acknowledged = claimant.waitForMessage("match_private_state", 1000) as Promise<PrivateMatchState>;
    const handled = serverRoom.waitForMessage("claim");
    claimant.send("claim", {
      cardId: claimedCardId,
      actionId: serverRoom.state.actionId,
    });
    const [, privateState] = await Promise.all([handled, acknowledged]);

    const publicState = serverRoom.state.toJSON();
    assert.deepStrictEqual(publicState, beforePublicState);
    assert.ok(!Object.hasOwn(publicState, "claimCommitCount"));
    assert.ok(!Object.hasOwn(publicState, "claimCardId"));
    assert.ok(publicState.seats.every((seat: object) => !Object.hasOwn(seat, "claimCardId")));
    assert.strictEqual(privateState.seatIndex, claimantSeatIndex);
    assert.strictEqual(privateState.participantId, claimant.sessionId);
    assert.strictEqual(privateState.claimCommitted, true);
    assert.strictEqual(privateState.claimCardId, claimedCardId);
    assert.deepStrictEqual(
      privateMessages.map((messages) => messages.length),
      participants.map((_, seatIndex) => seatIndex === claimantSeatIndex ? 1 : 0),
    );

    await Promise.all(participants.map((participant) => participant.leave()));
  });

  it("reveals and records one all-pass resolution after the third commit", async () => {
    const { participants, serverRoom, actorSeatIndex } = await startClaimCommit(colyseus);
    const claimantSeatIndexes = participants
      .map((_, seatIndex) => seatIndex)
      .filter((seatIndex) => seatIndex !== actorSeatIndex);
    const playedCards = serverRoom.state.playedCards.toJSON();
    const scoresBefore = serverRoom.state.seats.map((seat) => seat.score);

    for (const seatIndex of claimantSeatIndexes) {
      const acknowledged = participants[seatIndex].waitForMessage("match_private_state", 1000);
      const handled = serverRoom.waitForMessage("claim");
      participants[seatIndex].send("claim", {
        cardId: null,
        actionId: serverRoom.state.actionId,
      });
      await Promise.all([handled, acknowledged]);
    }

    const publicState = serverRoom.state.toJSON();
    assert.strictEqual(publicState.phase, "claim_reveal");
    assert.deepStrictEqual(publicState.playedCards, []);
    assert.deepStrictEqual(publicState.revealedClaims, claimantSeatIndexes.map((seatIndex) => ({
      seatIndex,
      passed: true,
      cardId: "",
    })));
    assert.deepStrictEqual(publicState.claimAwards, []);
    assert.deepStrictEqual(publicState.discardedCards, playedCards);
    assert.deepStrictEqual(
      publicState.seats.map((seat: { score: number }, seatIndex: number) => (
        seat.score - scoresBefore[seatIndex]
      )),
      participants.map((_, seatIndex) => seatIndex === actorSeatIndex ? 0 : 1),
    );
    assert.deepStrictEqual(publicState.claimEvents, [{
      turnNumber: 1,
      claims: claimantSeatIndexes.map((seatIndex) => ({
        seatIndex,
        passed: true,
        cardId: "",
      })),
      awards: [],
      discardedCards: playedCards,
    }]);

    await Promise.all(participants.map((participant) => participant.leave()));
  });

  it("resolves missing claims once at the configured deadline using the room clock", async () => {
    const { participants, serverRoom } = await startClaimCommit(colyseus);

    tickClock(serverRoom, 14_000);
    assert.strictEqual(serverRoom.state.phase, "claim_commit");
    assert.strictEqual(serverRoom.state.claimEvents.length, 0);

    const deadlineSnapshots = participants.map((participant) => (
      participant.waitForMessage("match_private_state", 1000) as Promise<PrivateMatchState>
    ));
    tickClock(serverRoom, 1_000);
    const privateStates = await Promise.all(deadlineSnapshots);
    assert.strictEqual(serverRoom.state.phase, "claim_reveal");
    assert.strictEqual(serverRoom.state.claimEvents.length, 1);
    for (let seatIndex = 0; seatIndex < privateStates.length; seatIndex += 1) {
      assert.strictEqual(privateStates[seatIndex].participantId, participants[seatIndex].sessionId);
      assert.strictEqual(privateStates[seatIndex].claimCommitted, false);
      assert.strictEqual(privateStates[seatIndex].claimCardId, null);
    }
    tickClock(serverRoom, 4_000);
    assert.strictEqual(serverRoom.state.phase, "actor_play");
    assert.strictEqual(serverRoom.state.claimEvents.length, 1);
    const actorActionId = serverRoom.state.actionId;
    tickClock(serverRoom, 15_000);
    assert.strictEqual(serverRoom.state.phase, "play_reveal");
    tickClock(serverRoom, 3_000);
    assert.strictEqual(serverRoom.state.phase, "claim_commit");
    assert.strictEqual(serverRoom.state.actionId, actorActionId + 2);
    assert.strictEqual(serverRoom.state.turnNumber, 2);
    assert.strictEqual(serverRoom.state.claimEvents.length, 1);
    assert.strictEqual(serverRoom.state.playEvents.length, 2);

    await Promise.all(participants.map((participant) => participant.leave()));
  });

  it("rejects actor, invalid, duplicate, and late claims without mutation", async () => {
    const { participants, serverRoom, actorSeatIndex } = await startClaimCommit(colyseus);
    const claimantSeatIndexes = participants
      .map((_, seatIndex) => seatIndex)
      .filter((seatIndex) => seatIndex !== actorSeatIndex);
    const playedCardId = serverRoom.state.playedCards[0].id;

    await assertClaimRejectedWithoutMutation(
      serverRoom,
      participants[actorSeatIndex],
      { cardId: playedCardId },
      "actor_cannot_claim",
    );
    await assertClaimRejectedWithoutMutation(
      serverRoom,
      participants[claimantSeatIndexes[0]],
      { cardId: "not-a-played-physical-card" },
      "invalid_claim",
    );

    let acknowledged = participants[claimantSeatIndexes[0]].waitForMessage(
      "match_private_state",
      1000,
    );
    let handled = serverRoom.waitForMessage("claim");
    participants[claimantSeatIndexes[0]].send("claim", {
      cardId: null,
      actionId: serverRoom.state.actionId,
    });
    await Promise.all([handled, acknowledged]);
    await assertClaimRejectedWithoutMutation(
      serverRoom,
      participants[claimantSeatIndexes[0]],
      { cardId: playedCardId },
      "claim_already_committed",
    );

    for (const seatIndex of claimantSeatIndexes.slice(1)) {
      acknowledged = participants[seatIndex].waitForMessage("match_private_state", 1000);
      handled = serverRoom.waitForMessage("claim");
      participants[seatIndex].send("claim", {
        cardId: null,
        actionId: serverRoom.state.actionId,
      });
      await Promise.all([handled, acknowledged]);
    }
    assert.strictEqual(serverRoom.state.phase, "claim_reveal");
    await assertClaimRejectedWithoutMutation(
      serverRoom,
      participants[claimantSeatIndexes[1]],
      { cardId: null },
      "invalid_phase",
    );

    await Promise.all(participants.map((participant) => participant.leave()));
  });

  it("projects unique and collision awards with owner-scoped reveal snapshots", async () => {
    const { participants, serverRoom, actorSeatIndex } = await startClaimCommit(colyseus);
    const claimantSeatIndexes = participants
      .map((_, seatIndex) => seatIndex)
      .filter((seatIndex) => seatIndex !== actorSeatIndex);
    const playedCards = serverRoom.state.playedCards.toJSON();
    const claimCardIds = [playedCards[0].id, playedCards[0].id, playedCards[1].id];

    for (let index = 0; index < 2; index += 1) {
      const seatIndex = claimantSeatIndexes[index];
      const acknowledged = participants[seatIndex].waitForMessage("match_private_state", 1000);
      const handled = serverRoom.waitForMessage("claim");
      participants[seatIndex].send("claim", {
        cardId: claimCardIds[index],
        actionId: serverRoom.state.actionId,
      });
      await Promise.all([handled, acknowledged]);
    }

    const revealSnapshots = participants.map((participant) => (
      participant.waitForMessage("match_private_state", 1000) as Promise<PrivateMatchState>
    ));
    const finalSeatIndex = claimantSeatIndexes[2];
    const handled = serverRoom.waitForMessage("claim");
    participants[finalSeatIndex].send("claim", {
      cardId: claimCardIds[2],
      actionId: serverRoom.state.actionId,
    });
    await handled;
    const privateStates = await Promise.all(revealSnapshots);

    const publicState = serverRoom.state.toJSON();
    const expectedClaims = claimantSeatIndexes.map((seatIndex, index) => ({
      seatIndex,
      passed: false,
      cardId: claimCardIds[index],
    }));
    assert.strictEqual(publicState.phase, "claim_reveal");
    assert.deepStrictEqual(publicState.revealedClaims, expectedClaims);
    assert.strictEqual(publicState.claimAwards.length, 3);
    const uniqueAward = publicState.claimAwards.find(
      (award: { source: string }) => award.source === "unique",
    );
    assert.deepStrictEqual(uniqueAward, {
      seatIndex: finalSeatIndex,
      card: playedCards[1],
      source: "unique",
    });
    const collisionAwards = publicState.claimAwards.filter(
      (award: { source: string }) => award.source === "collision",
    );
    assert.deepStrictEqual(
      collisionAwards.map((award: { seatIndex: number }) => award.seatIndex),
      claimantSeatIndexes.slice(0, 2),
    );
    assert.deepStrictEqual(
      collisionAwards.map((award: { card: { id: string } }) => award.card.id).sort(),
      [playedCards[0].id, playedCards[2].id].sort(),
    );
    assert.deepStrictEqual(publicState.discardedCards, []);
    assert.deepStrictEqual(publicState.claimEvents, [{
      turnNumber: 1,
      claims: expectedClaims,
      awards: publicState.claimAwards,
      discardedCards: [],
    }]);
    assert.deepStrictEqual(
      publicState.seats.map((seat: { handCount: number }) => seat.handCount),
      participants.map((_, seatIndex) => seatIndex === actorSeatIndex ? 5 : 6),
    );

    for (let seatIndex = 0; seatIndex < privateStates.length; seatIndex += 1) {
      const privateState = privateStates[seatIndex];
      assert.strictEqual(privateState.seatIndex, seatIndex);
      assert.strictEqual(privateState.participantId, participants[seatIndex].sessionId);
      assert.strictEqual(privateState.hand.length, seatIndex === actorSeatIndex ? 5 : 6);
      assert.strictEqual(privateState.claimCommitted, seatIndex !== actorSeatIndex);
      assert.strictEqual(
        privateState.claimCardId,
        seatIndex === actorSeatIndex
          ? null
          : claimCardIds[claimantSeatIndexes.indexOf(seatIndex)],
      );
    }

    await Promise.all(participants.map((participant) => participant.leave()));
  });
});
