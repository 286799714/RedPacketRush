import assert from "assert";
import { ColyseusTestServer } from "@colyseus/testing";

import appConfig from "../src/app.config.js";
import type { PhysicalCard } from "../src/match/cards.js";
import { classifyCombination } from "../src/match/combinations.js";
import { GameRoom } from "../src/rooms/GameRoom.js";
import { getTestServer } from "./testServer.js";

interface PrivateMatchState {
  seatIndex: number;
  participantId: string;
  hand: PhysicalCard[];
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

async function waitUntil(condition: () => boolean, timeoutMs = 2000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (!condition()) {
    if (Date.now() >= deadline) {
      throw new Error("timed out waiting for room state");
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

function tickClock(serverRoom: GameRoom, elapsedMilliseconds: number): void {
  serverRoom.clock.currentTime -= elapsedMilliseconds;
  serverRoom.clock.tick();
}

function chooseHighestScoringCombination(hand: readonly PhysicalCard[]): PhysicalCard[] {
  let selected = [hand[0], hand[1], hand[2]];
  for (let first = 0; first < hand.length - 2; first += 1) {
    for (let second = first + 1; second < hand.length - 1; second += 1) {
      for (let third = second + 1; third < hand.length; third += 1) {
        const candidate = [hand[first], hand[second], hand[third]];
        if (classifyCombination(candidate).score > classifyCombination(selected).score) {
          selected = candidate;
        }
      }
    }
  }
  return selected;
}

async function startFourHumanMatch(colyseus: ColyseusTestServer<typeof appConfig>) {
  const host = await colyseus.sdk.create("game", {
    nickname: "甲",
    displayName: "非法出牌测试",
    deckMode: "one",
    actionDeadlineSeconds: 30,
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
  const handled = serverRoom.waitForMessage("start");
  host.send("start", null);
  await handled;
  const openingStates = await Promise.all(openingStatePromises);
  await waitUntil(() => serverRoom.state.phase === "actor_play");
  return { host, participants, serverRoom, openingStates };
}

describe("game room actor play", () => {
  let colyseus: ColyseusTestServer<typeof appConfig>;

  before(async () => colyseus = await getTestServer());

  beforeEach(async () => {
    await colyseus.cleanup();
  });

  it("rejects play commands privately before a match engine has started", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "阶段校验测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    const beforeState = serverRoom.state.toJSON();
    const privateMessages: PrivateMatchState[] = [];
    const roomErrors: Array<{ code: string }> = [];
    onRoomMessage(host, "match_private_state", (payload) => {
      privateMessages.push(payload as PrivateMatchState);
    });
    onRoomMessage(host, "room_error", (payload) => {
      roomErrors.push(payload as { code: string });
    });

    const rejected = host.waitForMessage("room_error", 1000);
    host.send("play_cards", { cardIds: ["card-a", "card-b", "card-c"] });
    assert.strictEqual((await rejected).code, "invalid_phase");
    await new Promise((resolve) => setTimeout(resolve, 50));

    assert.deepStrictEqual(serverRoom.state.toJSON(), beforeState);
    assert.strictEqual(privateMessages.length, 0);
    assert.strictEqual(roomErrors.length, 1);

    await host.leave();
  });

  it("rejects play commands during the point contest without exposing private state", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "拼点阶段测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
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
    const startHandled = serverRoom.waitForMessage("start");
    host.send("start", null);
    await startHandled;
    assert.strictEqual(serverRoom.state.phase, "point_contest");
    const actorSeatIndex = serverRoom.state.actorSeatIndex;
    const actor = participants[actorSeatIndex];
    const beforeState = serverRoom.state.toJSON();
    const privateMessages: PrivateMatchState[][] = participants.map((): PrivateMatchState[] => []);
    const roomErrors: Array<Array<{ code: string }>> = participants.map((): Array<{ code: string }> => []);
    participants.forEach((participant, seatIndex) => {
      onRoomMessage(participant, "match_private_state", (payload) => {
        privateMessages[seatIndex].push(payload as PrivateMatchState);
      });
      onRoomMessage(participant, "room_error", (payload) => {
        roomErrors[seatIndex].push(payload as { code: string });
      });
    });

    const rejected = actor.waitForMessage("room_error", 1000);
    actor.send("play_cards", {
      cardIds: ["card-a", "card-b", "card-c"],
      actionId: serverRoom.state.actionId,
    });
    assert.strictEqual((await rejected).code, "invalid_phase");
    await new Promise((resolve) => setTimeout(resolve, 50));

    assert.deepStrictEqual(serverRoom.state.toJSON(), beforeState);
    assert.deepStrictEqual(privateMessages.map((messages) => messages.length), [0, 0, 0, 0]);
    assert.deepStrictEqual(
      roomErrors.map((errors) => errors.length),
      participants.map((_, seatIndex) => seatIndex === actorSeatIndex ? 1 : 0),
    );

    await Promise.all(participants.map((participant) => participant.leave()));
  });

  it("publishes and scores the actor's three cards while replacing only their private hand", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "出牌测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
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
    const openingStates = await Promise.all(openingStatePromises);
    await waitUntil(() => serverRoom.state.phase === "actor_play");

    const actorSeatIndex = serverRoom.state.actorSeatIndex;
    const actor = participants[actorSeatIndex];
    const actorOpeningState = openingStates[actorSeatIndex];
    const selectedCards = chooseHighestScoringCombination(actorOpeningState.hand);
    const expected = classifyCombination(selectedCards);
    const before = serverRoom.state.toJSON();
    const replacementMessages: PrivateMatchState[][] = participants.map((): PrivateMatchState[] => []);
    participants.forEach((participant, seatIndex) => {
      onRoomMessage(participant, "match_private_state", (payload) => {
        replacementMessages[seatIndex].push(payload as PrivateMatchState);
      });
    });

    handled = serverRoom.waitForMessage("play_cards");
    actor.send("play_cards", {
      cardIds: selectedCards.map((card) => card.id),
      actionId: serverRoom.state.actionId,
    });
    await handled;
    await waitUntil(() => serverRoom.state.phase === "play_reveal");
    assert.strictEqual(serverRoom.state.actionDeadlineAtUnixMs, 0);
    tickClock(serverRoom, 3_000);
    await waitUntil(() => serverRoom.state.phase === "claim_commit");
    await waitUntil(() => replacementMessages.every((messages) => messages.length === 2));
    await waitUntil(() => participants.every(
      (participant) => participant.state.phase === "claim_commit",
    ));
    await new Promise((resolve) => setTimeout(resolve, 50));

    const publicState = serverRoom.state.toJSON();
    assert.strictEqual(publicState.turnNumber, 1);
    assert.strictEqual(publicState.phase, "claim_commit");
    assert.strictEqual(publicState.playedCategory, expected.category);
    assert.strictEqual(publicState.playedScore, expected.score);
    assert.deepStrictEqual(publicState.playedCards, selectedCards);
    assert.strictEqual(publicState.drawPileCount, before.drawPileCount - 3);
    assert.strictEqual(publicState.seats[actorSeatIndex].handCount, 5);
    assert.strictEqual(publicState.seats[actorSeatIndex].score, expected.score);
    assert.deepStrictEqual(publicState.contestRounds, before.contestRounds);
    assert.deepStrictEqual(publicState.playEvents, [{
      turnNumber: 1,
      actorSeatIndex,
      cards: selectedCards,
      category: expected.category,
      score: expected.score,
    }]);

    const [replacementState] = replacementMessages[actorSeatIndex];
    assert.strictEqual(replacementState.seatIndex, actorSeatIndex);
    assert.strictEqual(replacementState.participantId, actor.sessionId);
    assert.strictEqual(replacementState.hand.length, 5);
    const replacementIds = replacementState.hand.map((card) => card.id);
    assert.ok(selectedCards.every((card) => !replacementIds.includes(card.id)));
    assert.strictEqual(
      replacementIds.filter((id) => actorOpeningState.hand.some((card) => card.id === id)).length,
      2,
    );
    for (let seatIndex = 0; seatIndex < participants.length; seatIndex += 1) {
      assert.strictEqual(replacementMessages[seatIndex].length, 2);
      const privateState = replacementMessages[seatIndex].at(-1)!;
      assert.strictEqual(privateState.actionId, serverRoom.state.actionId);
      if (seatIndex !== actorSeatIndex) {
        assert.deepStrictEqual(privateState.hand, openingStates[seatIndex].hand);
      }
    }

    await Promise.all(participants.map((participant) => participant.leave()));
  });

  it("rejects a non-actor without changing any public or private match state", async () => {
    const { participants, serverRoom, openingStates } = await startFourHumanMatch(colyseus);
    const actorSeatIndex = serverRoom.state.actorSeatIndex;
    const nonActorSeatIndex = (actorSeatIndex + 1) % participants.length;
    const nonActor = participants[nonActorSeatIndex];
    const beforePublicState = serverRoom.state.toJSON();
    const privateMessages: PrivateMatchState[][] = participants.map((): PrivateMatchState[] => []);
    const roomErrors: Array<Array<{ code: string }>> = participants.map((): Array<{ code: string }> => []);
    participants.forEach((participant, seatIndex) => {
      onRoomMessage(participant, "match_private_state", (payload) => {
        privateMessages[seatIndex].push(payload as PrivateMatchState);
      });
      onRoomMessage(participant, "room_error", (payload) => {
        roomErrors[seatIndex].push(payload as { code: string });
      });
    });

    const rejected = nonActor.waitForMessage("room_error", 1000);
    const handled = serverRoom.waitForMessage("play_cards");
    nonActor.send("play_cards", {
      cardIds: openingStates[nonActorSeatIndex].hand.slice(0, 3).map((card) => card.id),
      actionId: serverRoom.state.actionId,
    });
    await handled;
    assert.strictEqual((await rejected).code, "not_actor");
    await new Promise((resolve) => setTimeout(resolve, 50));

    assert.deepStrictEqual(serverRoom.state.toJSON(), beforePublicState);
    assert.deepStrictEqual(privateMessages.map((messages) => messages.length), [0, 0, 0, 0]);
    assert.deepStrictEqual(
      roomErrors.map((errors) => errors.length),
      participants.map((_, seatIndex) => seatIndex === nonActorSeatIndex ? 1 : 0),
    );

    await Promise.all(participants.map((participant) => participant.leave()));
  });

  it("rejects malformed card identifiers privately without changing match state", async () => {
    const { participants, serverRoom } = await startFourHumanMatch(colyseus);
    const actorSeatIndex = serverRoom.state.actorSeatIndex;
    const actor = participants[actorSeatIndex];
    const beforePublicState = serverRoom.state.toJSON();
    const privateMessages: PrivateMatchState[][] = participants.map((): PrivateMatchState[] => []);
    const roomErrors: Array<Array<{ code: string }>> = participants.map((): Array<{ code: string }> => []);
    participants.forEach((participant, seatIndex) => {
      onRoomMessage(participant, "match_private_state", (payload) => {
        privateMessages[seatIndex].push(payload as PrivateMatchState);
      });
      onRoomMessage(participant, "room_error", (payload) => {
        roomErrors[seatIndex].push(payload as { code: string });
      });
    });

    const rejected = actor.waitForMessage("room_error", 1000);
    actor.send("play_cards", {
      cardIds: "not-an-array",
      actionId: serverRoom.state.actionId,
    });
    assert.strictEqual((await rejected).code, "invalid_payload");
    await new Promise((resolve) => setTimeout(resolve, 50));

    assert.deepStrictEqual(serverRoom.state.toJSON(), beforePublicState);
    assert.deepStrictEqual(privateMessages.map((messages) => messages.length), [0, 0, 0, 0]);
    assert.deepStrictEqual(
      roomErrors.map((errors) => errors.length),
      participants.map((_, seatIndex) => seatIndex === actorSeatIndex ? 1 : 0),
    );

    await Promise.all(participants.map((participant) => participant.leave()));
  });

  it("keeps duplicate, stale, and unowned card commands atomic and private", async () => {
    const { participants, serverRoom, openingStates } = await startFourHumanMatch(colyseus);
    const actorSeatIndex = serverRoom.state.actorSeatIndex;
    const actor = participants[actorSeatIndex];
    const actorCards = openingStates[actorSeatIndex].hand;
    const otherSeatIndex = (actorSeatIndex + 1) % participants.length;
    const beforePublicState = serverRoom.state.toJSON();
    const privateMessages: PrivateMatchState[][] = participants.map((): PrivateMatchState[] => []);
    const roomErrors: Array<Array<{ code: string }>> = participants.map((): Array<{ code: string }> => []);
    participants.forEach((participant, seatIndex) => {
      onRoomMessage(participant, "match_private_state", (payload) => {
        privateMessages[seatIndex].push(payload as PrivateMatchState);
      });
      onRoomMessage(participant, "room_error", (payload) => {
        roomErrors[seatIndex].push(payload as { code: string });
      });
    });
    const commands = [
      {
        cardIds: [actorCards[0].id, actorCards[0].id, actorCards[1].id],
        expectedCode: "invalid_play",
      },
      {
        cardIds: [
          actorCards[0].id,
          actorCards[1].id,
          openingStates[otherSeatIndex].hand[0].id,
        ],
        expectedCode: "card_not_owned",
      },
      {
        cardIds: [actorCards[0].id, actorCards[1].id, "copy-1:clubs:2"],
        expectedCode: "card_not_owned",
      },
    ];

    for (const command of commands) {
      const rejected = actor.waitForMessage("room_error", 1000);
      actor.send("play_cards", {
        cardIds: command.cardIds,
        actionId: serverRoom.state.actionId,
      });
      assert.strictEqual((await rejected).code, command.expectedCode);
      assert.deepStrictEqual(serverRoom.state.toJSON(), beforePublicState);
    }
    await new Promise((resolve) => setTimeout(resolve, 50));

    assert.deepStrictEqual(privateMessages.map((messages) => messages.length), [0, 0, 0, 0]);
    assert.deepStrictEqual(
      roomErrors.map((errors) => errors.length),
      participants.map((_, seatIndex) => seatIndex === actorSeatIndex ? commands.length : 0),
    );

    await Promise.all(participants.map((participant) => participant.leave()));
  });
});
