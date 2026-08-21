import assert from "assert";
import { ColyseusTestServer } from "@colyseus/testing";
import { matchMaker } from "colyseus";

import appConfig from "../src/app.config.js";
import { GameRoom } from "../src/rooms/GameRoom.js";
import { getTestServer } from "./testServer.js";

async function waitUntil(condition: () => boolean, timeoutMs = 2000): Promise<void> {
  const deadline = Date.now() + timeoutMs;
  while (!condition()) {
    if (Date.now() >= deadline) {
      throw new Error("timed out waiting for match state");
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

describe("game room match opening", () => {
  let colyseus: ColyseusTestServer<typeof appConfig>;

  before(async () => colyseus = await getTestServer());

  beforeEach(async () => {
    await colyseus.cleanup();
  });

  it("publishes the point contest and sends only the local opening hand", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "开局测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);

    let handled = serverRoom.waitForMessage("fill_bots");
    host.send("fill_bots", null);
    await handled;
    handled = serverRoom.waitForMessage("set_ready");
    host.send("set_ready", { ready: true });
    await handled;

    const observedPhases: string[] = [];
    host.onStateChange((state) => {
      observedPhases.push(state.phase);
    });
    const privateStateReceived = host.waitForMessage("match_private_state", 2000);
    handled = serverRoom.waitForMessage("start");
    host.send("start", null);
    await handled;
    assert.strictEqual(serverRoom.state.phase, "point_contest");
    await waitUntil(() => observedPhases.includes("point_contest"));
    const privateState = await privateStateReceived;
    await waitUntil(() => serverRoom.state.phase === "actor_play");
    const publicState = serverRoom.state.toJSON();

    assert.strictEqual(publicState.status, "started");
    assert.strictEqual(publicState.phase, "actor_play");
    assert.ok(observedPhases.includes("point_contest"));
    assert.ok(Number.isInteger(publicState.actorSeatIndex));
    assert.strictEqual(publicState.drawPileCount, 20);
    assert.strictEqual(publicState.contestRounds.length >= 1, true);
    assert.deepStrictEqual(
      publicState.seats.map((seat: { score: number; handCount: number }) => ({
        score: seat.score,
        handCount: seat.handCount,
      })),
      Array.from({ length: 4 }, () => ({ score: 0, handCount: 8 })),
    );
    assert.ok(!Object.hasOwn(publicState, "hand"));
    assert.ok(publicState.seats.every((seat: object) => !Object.hasOwn(seat, "hand")));

    assert.strictEqual(privateState.participantId, host.sessionId);
    assert.strictEqual(privateState.seatIndex, 0);
    assert.strictEqual(privateState.hand.length, 8);
    assert.strictEqual(new Set(privateState.hand.map((card: { id: string }) => card.id)).size, 8);

    await host.leave();
  });

  it("isolates four human opening hands from every other participant", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "私有手牌测试",
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

    const privateStatesReceived = participants.map((participant) => (
      participant.waitForMessage("match_private_state", 2000)
    ));
    const handled = serverRoom.waitForMessage("start");
    host.send("start", null);
    await handled;
    const privateStates = await Promise.all(privateStatesReceived);

    for (const [seatIndex, privateState] of privateStates.entries()) {
      assert.strictEqual(privateState.seatIndex, seatIndex);
      assert.strictEqual(privateState.participantId, participants[seatIndex].sessionId);
      assert.strictEqual(privateState.hand.length, 8);
    }
    const allPrivateCardIds = privateStates.flatMap((privateState) => (
      privateState.hand.map((card: { id: string }) => card.id)
    ));
    assert.strictEqual(allPrivateCardIds.length, 32);
    assert.strictEqual(new Set(allPrivateCardIds).size, 32);
    const synchronizedState = serverRoom.state.toJSON();
    assert.ok(!Object.hasOwn(synchronizedState, "hand"));
    assert.ok(synchronizedState.seats.every(
      (seat: object) => !Object.hasOwn(seat, "hand"),
    ));

    await Promise.all(participants.map((participant) => participant.leave()));
  });

  it("keeps a failed matchmaking commit retryable without exposing a partial match", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "开局重试测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);

    let handled = serverRoom.waitForMessage("fill_bots");
    host.send("fill_bots", null);
    await handled;
    handled = serverRoom.waitForMessage("set_ready");
    host.send("set_ready", { ready: true });
    await handled;

    const commitMatchmaking = serverRoom.setMatchmaking.bind(serverRoom);
    let failNextCommit = true;
    serverRoom.setMatchmaking = async (updates): Promise<void> => {
      if (failNextCommit) {
        failNextCommit = false;
        throw new Error("injected matchmaking failure");
      }
      await commitMatchmaking(updates);
    };

    const startFailure = host.waitForMessage("room_error", 1000);
    handled = serverRoom.waitForMessage("start");
    host.send("start", null);
    const [, roomError] = await Promise.all([handled, startFailure]);

    assert.deepStrictEqual(roomError, {
      code: "start_failed",
      message: "对局启动失败，请重试",
    });
    assert.strictEqual(serverRoom.state.status, "waiting");
    assert.strictEqual(serverRoom.state.phase, "");
    assert.strictEqual(serverRoom.metadata.status, "waiting");

    const privateStateReceived = host.waitForMessage("match_private_state", 2000);
    handled = serverRoom.waitForMessage("start");
    host.send("start", null);
    await handled;
    const privateState = await privateStateReceived;
    assert.strictEqual(privateState.participantId, host.sessionId);
    assert.strictEqual(serverRoom.state.status, "started");

    await host.leave();
  });

  it("allows only one matchmaking commit while a match is starting", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "并发开局测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);

    let handled = serverRoom.waitForMessage("fill_bots");
    host.send("fill_bots", null);
    await handled;
    handled = serverRoom.waitForMessage("set_ready");
    host.send("set_ready", { ready: true });
    await handled;

    const commitMatchmaking = serverRoom.setMatchmaking.bind(serverRoom);
    let releaseCommit = (): void => {};
    const commitGate = new Promise<void>((resolve) => {
      releaseCommit = resolve;
    });
    let markCommitEntered = (): void => {};
    const commitEntered = new Promise<void>((resolve) => {
      markCommitEntered = resolve;
    });
    let commitCount = 0;
    serverRoom.setMatchmaking = async (updates): Promise<void> => {
      commitCount += 1;
      markCommitEntered();
      await commitGate;
      await commitMatchmaking(updates);
    };

    const privateStateReceived = host.waitForMessage("match_private_state", 2000);
    host.send("start", null);
    await commitEntered;

    const rejected = host.waitForMessage("room_error", 1000);
    host.send("start", null);
    assert.deepStrictEqual(await rejected, {
      code: "start_in_progress",
      message: "对局正在启动",
    });
    assert.strictEqual(commitCount, 1);

    releaseCommit();
    const privateState = await privateStateReceived;
    assert.strictEqual(privateState.participantId, host.sessionId);
    assert.strictEqual(serverRoom.state.status, "started");

    await host.leave();
  });

  it("cancels a start when a waiting participant leaves during the matchmaking commit", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "离开竞态测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const guest = await colyseus.sdk.joinById(host.roomId, { nickname: "乙" });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);

    let handled = serverRoom.waitForMessage("fill_bots");
    host.send("fill_bots", null);
    await handled;
    handled = serverRoom.waitForMessage("set_ready");
    host.send("set_ready", { ready: true });
    await handled;
    handled = serverRoom.waitForMessage("set_ready");
    guest.send("set_ready", { ready: true });
    await handled;

    const commitMatchmaking = serverRoom.setMatchmaking.bind(serverRoom);
    let releaseCommit = (): void => {};
    const commitGate = new Promise<void>((resolve) => {
      releaseCommit = resolve;
    });
    let markCommitEntered = (): void => {};
    const commitEntered = new Promise<void>((resolve) => {
      markCommitEntered = resolve;
    });
    serverRoom.setMatchmaking = async (updates): Promise<void> => {
      markCommitEntered();
      await commitGate;
      await commitMatchmaking(updates);
    };

    handled = serverRoom.waitForMessage("start");
    host.send("start", null);
    await commitEntered;
    const leaving = host.leave();
    await waitUntil(() => serverRoom.state.seats[0].participantId === "");
    releaseCommit();
    await Promise.all([handled, leaving]);

    assert.strictEqual(serverRoom.state.status, "waiting");
    assert.strictEqual(serverRoom.state.phase, "");
    assert.strictEqual(serverRoom.state.hostParticipantId, guest.sessionId);
    assert.strictEqual(serverRoom.state.seats[0].participantId, "");
    assert.strictEqual(serverRoom.metadata.status, "waiting");
    assert.strictEqual(serverRoom.metadata.participantCount, 3);
    const [listing] = await matchMaker.query({ roomId: serverRoom.roomId });
    assert.strictEqual(listing.private, false);
    assert.strictEqual(listing.locked, false);

    await guest.leave();
  });

  it("restores the current waiting listing when a start commit fails after the host leaves", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "失败离开竞态测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const guest = await colyseus.sdk.joinById(host.roomId, { nickname: "乙" });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);

    let handled = serverRoom.waitForMessage("fill_bots");
    host.send("fill_bots", null);
    await handled;
    handled = serverRoom.waitForMessage("set_ready");
    host.send("set_ready", { ready: true });
    await handled;
    handled = serverRoom.waitForMessage("set_ready");
    guest.send("set_ready", { ready: true });
    await handled;

    let releaseCommit = (): void => {};
    const commitGate = new Promise<void>((resolve) => {
      releaseCommit = resolve;
    });
    let markCommitEntered = (): void => {};
    const commitEntered = new Promise<void>((resolve) => {
      markCommitEntered = resolve;
    });
    const commitMatchmaking = serverRoom.setMatchmaking.bind(serverRoom);
    let commitCount = 0;
    serverRoom.setMatchmaking = async (updates): Promise<void> => {
      commitCount += 1;
      if (commitCount === 1) {
        markCommitEntered();
        await commitGate;
        throw new Error("injected matchmaking failure");
      }
      await commitMatchmaking(updates);
    };

    handled = serverRoom.waitForMessage("start");
    host.send("start", null);
    await commitEntered;
    const leaving = host.leave();
    await waitUntil(() => serverRoom.state.seats[0].participantId === "");
    releaseCommit();
    await Promise.all([handled, leaving]);

    assert.strictEqual(serverRoom.state.status, "waiting");
    assert.strictEqual(serverRoom.state.hostParticipantId, guest.sessionId);
    assert.strictEqual(serverRoom.metadata.status, "waiting");
    assert.strictEqual(serverRoom.metadata.participantCount, 3);
    const [listing] = await matchMaker.query({ roomId: serverRoom.roomId });
    assert.strictEqual(listing.private, false);
    assert.strictEqual(listing.locked, false);

    await guest.leave();
  });

  it("retries a transient persistence failure while cancelling a stale start", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "取消恢复重试测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const guest = await colyseus.sdk.joinById(host.roomId, { nickname: "乙" });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);

    let handled = serverRoom.waitForMessage("fill_bots");
    host.send("fill_bots", null);
    await handled;
    handled = serverRoom.waitForMessage("set_ready");
    host.send("set_ready", { ready: true });
    await handled;
    handled = serverRoom.waitForMessage("set_ready");
    guest.send("set_ready", { ready: true });
    await handled;

    const commitMatchmaking = serverRoom.setMatchmaking.bind(serverRoom);
    let releaseCommit = (): void => {};
    const commitGate = new Promise<void>((resolve) => {
      releaseCommit = resolve;
    });
    let markCommitEntered = (): void => {};
    const commitEntered = new Promise<void>((resolve) => {
      markCommitEntered = resolve;
    });
    let commitCount = 0;
    serverRoom.setMatchmaking = async (updates): Promise<void> => {
      commitCount += 1;
      if (commitCount === 1) {
        markCommitEntered();
        await commitGate;
        await commitMatchmaking(updates);
        return;
      }
      if (commitCount === 2) {
        throw new Error("injected recovery failure");
      }
      await commitMatchmaking(updates);
    };

    handled = serverRoom.waitForMessage("start");
    host.send("start", null);
    await commitEntered;
    const leaving = host.leave();
    await waitUntil(() => serverRoom.state.seats[0].participantId === "");
    releaseCommit();
    await Promise.all([handled, leaving]);

    assert.strictEqual(commitCount >= 3, true);
    assert.strictEqual(serverRoom.state.status, "waiting");
    assert.strictEqual(serverRoom.metadata.status, "waiting");
    assert.strictEqual(serverRoom.metadata.participantCount, 3);
    const [listing] = await matchMaker.query({ roomId: serverRoom.roomId });
    assert.strictEqual(listing.private, false);
    assert.strictEqual(listing.locked, false);

    await guest.leave();
  });

  it("repairs an ambiguously committed start after immediate recovery is exhausted", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "定时恢复测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);

    let handled = serverRoom.waitForMessage("fill_bots");
    host.send("fill_bots", null);
    await handled;
    handled = serverRoom.waitForMessage("set_ready");
    host.send("set_ready", { ready: true });
    await handled;

    const commitMatchmaking = serverRoom.setMatchmaking.bind(serverRoom);
    let commitCount = 0;
    serverRoom.setMatchmaking = async (updates): Promise<void> => {
      commitCount += 1;
      if (commitCount === 1) {
        await commitMatchmaking(updates);
        throw new Error("injected ambiguous start failure");
      }
      if (commitCount <= 3) {
        throw new Error("injected immediate recovery failure");
      }
      await commitMatchmaking(updates);
    };

    const startFailure = host.waitForMessage("room_error", 1000);
    handled = serverRoom.waitForMessage("start");
    host.send("start", null);
    const [, roomError] = await Promise.all([handled, startFailure]);

    assert.strictEqual(roomError.code, "start_failed");
    assert.strictEqual(serverRoom.state.status, "waiting");
    assert.strictEqual(serverRoom.metadata.status, "started");
    let [listing] = await matchMaker.query({ roomId: serverRoom.roomId });
    assert.strictEqual(listing.private, true);
    assert.strictEqual(listing.locked, true);

    serverRoom.clock.currentTime -= 200;
    serverRoom.clock.tick();
    await new Promise<void>((resolve) => setImmediate(resolve));
    await waitUntil(() => serverRoom.metadata.status === "waiting");

    [listing] = await matchMaker.query({ roomId: serverRoom.roomId });
    assert.strictEqual(commitCount >= 4, true);
    assert.strictEqual(listing.metadata.status, "waiting");
    assert.strictEqual(listing.private, false);
    assert.strictEqual(listing.locked, true);

    await host.leave();
  });
});
