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
}

function tickClock(serverRoom: GameRoom, elapsedMilliseconds: number): void {
  serverRoom.clock.currentTime -= elapsedMilliseconds;
  serverRoom.clock.tick();
}

async function startClaimCommit(colyseus: ColyseusTestServer<typeof appConfig>) {
  const host = await colyseus.sdk.create("game", {
    nickname: "甲",
    displayName: "弃牌轮转测试",
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
  tickClock(serverRoom, 900);
  const openingStates = await Promise.all(openingStatePromises);
  const actorSeatIndex = serverRoom.state.actorSeatIndex;
  const actorUpdate = participants[actorSeatIndex].waitForMessage("match_private_state", 2000);
  handled = serverRoom.waitForMessage("play_cards");
  participants[actorSeatIndex].send("play_cards", {
    cardIds: openingStates[actorSeatIndex].hand.slice(0, 3).map((card) => card.id),
  });
  await Promise.all([handled, actorUpdate]);
  assert.strictEqual(serverRoom.state.phase, "claim_commit");
  return { participants, serverRoom, openingStates, actorSeatIndex };
}

async function revealUniqueAwards(
  participants: Awaited<ReturnType<typeof startClaimCommit>>["participants"],
  serverRoom: GameRoom,
  actorSeatIndex: number,
): Promise<number[]> {
  const claimantSeats = [0, 1, 2, 3].filter((seatIndex) => seatIndex !== actorSeatIndex);
  const playedCardIds = serverRoom.state.playedCards.toArray().map((card) => card.id);
  for (let index = 0; index < claimantSeats.length; index += 1) {
    const seatIndex = claimantSeats[index];
    const handled = serverRoom.waitForMessage("claim");
    participants[seatIndex].send("claim", { cardId: playedCardIds[index] });
    await handled;
  }
  assert.strictEqual(serverRoom.state.phase, "claim_reveal");
  tickClock(serverRoom, 900);
  assert.strictEqual(serverRoom.state.phase, "award_discard");
  return claimantSeats;
}

async function expectDiscardError(
  serverRoom: GameRoom,
  participant: Awaited<ReturnType<typeof startClaimCommit>>["participants"][number],
  payload: unknown,
  expectedCode: string,
): Promise<void> {
  const before = serverRoom.state.toJSON();
  const handled = serverRoom.waitForMessage("discard");
  const rejected = participant.waitForMessage("room_error", 1000);
  participant.send("discard", payload);
  await handled;
  assert.strictEqual((await rejected).code, expectedCode);
  assert.deepStrictEqual(serverRoom.state.toJSON(), before);
}

describe("game room award discard and actor rotation", () => {
  let colyseus: ColyseusTestServer<typeof appConfig>;

  before(async () => colyseus = await getTestServer());

  beforeEach(async () => {
    await colyseus.cleanup();
  });

  it("projects public discard progress and opens the next turn after the last command", async () => {
    const { participants, serverRoom, openingStates, actorSeatIndex } = await startClaimCommit(colyseus);
    const claimantSeats = await revealUniqueAwards(participants, serverRoom, actorSeatIndex);
    const awards = serverRoom.state.claimAwards.toJSON();
    const strongestAward = [...awards].sort((left, right) => (
      right.card.rank - left.card.rank
      || ["clubs", "spades", "diamonds", "hearts"].indexOf(right.card.suit)
        - ["clubs", "spades", "diamonds", "hearts"].indexOf(left.card.suit)
    ))[0];

    for (let index = 0; index < claimantSeats.length; index += 1) {
      const seatIndex = claimantSeats[index];
      const handled = serverRoom.waitForMessage("discard");
      const privateUpdate = participants[seatIndex].waitForMessage("match_private_state", 1000);
      participants[seatIndex].send("discard", { cardId: openingStates[seatIndex].hand[0].id });
      await Promise.all([handled, privateUpdate]);
      assert.strictEqual(serverRoom.state.seats[seatIndex].handCount, 8);
      assert.strictEqual(
        serverRoom.state.phase,
        index < claimantSeats.length - 1 ? "award_discard" : "actor_play",
      );
    }

    assert.strictEqual(serverRoom.state.actorSeatIndex, strongestAward.seatIndex);
    assert.deepStrictEqual(serverRoom.state.pendingDiscardSeatIndexes.toJSON(), []);
    assert.deepStrictEqual(serverRoom.state.claimAwards.toJSON(), []);
    assert.deepStrictEqual(serverRoom.state.revealedClaims.toJSON(), []);
    assert.deepStrictEqual(
      serverRoom.state.seats.toArray().map((seat) => seat.handCount),
      [8, 8, 8, 8],
    );
    assert.deepStrictEqual(
      serverRoom.state.discardEvents.toJSON().map((event) => event.seatIndex),
      claimantSeats,
    );
    await expectDiscardError(
      serverRoom,
      participants[claimantSeats.at(-1)!],
      { cardId: openingStates[claimantSeats.at(-1)!].hand[1].id },
      "invalid_phase",
    );
    await Promise.all(participants.map((participant) => participant.leave()));
  });

  it("rejects malformed, protected, unowned, and duplicate discard messages atomically", async () => {
    const { participants, serverRoom, openingStates, actorSeatIndex } = await startClaimCommit(colyseus);
    const claimantSeats = await revealUniqueAwards(participants, serverRoom, actorSeatIndex);
    const firstSeat = claimantSeats[0];
    const protectedCardId = serverRoom.state.claimAwards.find(
      (award) => award.seatIndex === firstSeat,
    )?.card.id;
    assert.ok(protectedCardId);

    await expectDiscardError(serverRoom, participants[firstSeat], null, "invalid_payload");
    await expectDiscardError(serverRoom, participants[firstSeat], { cardId: null }, "invalid_payload");
    await expectDiscardError(
      serverRoom,
      participants[firstSeat],
      { cardId: protectedCardId },
      "awarded_card_protected",
    );
    await expectDiscardError(
      serverRoom,
      participants[firstSeat],
      { cardId: openingStates[claimantSeats[1]].hand[0].id },
      "card_not_owned",
    );

    let handled = serverRoom.waitForMessage("discard");
    participants[firstSeat].send("discard", { cardId: openingStates[firstSeat].hand[0].id });
    await handled;
    await expectDiscardError(
      serverRoom,
      participants[firstSeat],
      { cardId: openingStates[firstSeat].hand[1].id },
      "discard_not_required",
    );
    await Promise.all(participants.map((participant) => participant.leave()));
  });

  it("uses the action deadline to discard for every pending recipient exactly once", async () => {
    const { participants, serverRoom, actorSeatIndex } = await startClaimCommit(colyseus);
    await revealUniqueAwards(participants, serverRoom, actorSeatIndex);

    tickClock(serverRoom, 15_000);

    const resolved = serverRoom.state.toJSON();
    assert.strictEqual(resolved.phase, "actor_play");
    assert.deepStrictEqual(resolved.seats.map((seat: { handCount: number }) => seat.handCount), [8, 8, 8, 8]);
    assert.strictEqual(resolved.discardEvents.length, 3);
    tickClock(serverRoom, 15_000);
    assert.deepStrictEqual(serverRoom.state.toJSON(), resolved);
    await Promise.all(participants.map((participant) => participant.leave()));
  });

  it("keeps an all-pass actor after the public reveal interval", async () => {
    const { participants, serverRoom, actorSeatIndex } = await startClaimCommit(colyseus);
    for (const seatIndex of [0, 1, 2, 3]) {
      if (seatIndex === actorSeatIndex) {
        continue;
      }
      const handled = serverRoom.waitForMessage("claim");
      participants[seatIndex].send("claim", { cardId: null });
      await handled;
    }
    assert.strictEqual(serverRoom.state.phase, "claim_reveal");

    tickClock(serverRoom, 900);

    assert.strictEqual(serverRoom.state.phase, "actor_play");
    assert.strictEqual(serverRoom.state.actorSeatIndex, actorSeatIndex);
    assert.deepStrictEqual(serverRoom.state.pendingDiscardSeatIndexes.toJSON(), []);
    await Promise.all(participants.map((participant) => participant.leave()));
  });
});
