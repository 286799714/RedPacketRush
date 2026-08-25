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
      throw new Error("timed out waiting for room state");
    }
    await new Promise((resolve) => setTimeout(resolve, 10));
  }
}

function failNextMatchmakingWrites(serverRoom: GameRoom, failureCount: number): () => number {
  const commitMatchmaking = serverRoom.setMatchmaking.bind(serverRoom);
  let remainingFailures = failureCount;
  let commitCount = 0;
  serverRoom.setMatchmaking = async (updates): Promise<void> => {
    commitCount += 1;
    if (remainingFailures > 0) {
      remainingFailures -= 1;
      throw new Error("injected matchmaking failure");
    }
    await commitMatchmaking(updates);
  };
  return () => commitCount;
}

describe("four-participant room readiness", () => {
  let colyseus: ColyseusTestServer<typeof appConfig>;

  before(async () => colyseus = await getTestServer());

  beforeEach(async () => {
    await colyseus.cleanup();
  });

  it("seats the creator as the waiting host with the configured settings", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "周四牌局",
      deckMode: "two",
      actionDeadlineSeconds: 60,
    });
    await new Promise<void>((resolve) => host.onStateChange.once(() => resolve()));

    assert.deepStrictEqual(host.state.toJSON(), {
      status: "waiting",
      displayName: "周四牌局",
      deckMode: "two",
      actionDeadlineSeconds: 60,
      actionId: 0,
      actionDeadlineAtUnixMs: 0,
      hostParticipantId: host.sessionId,
      phase: "",
      actorSeatIndex: -1,
      firstActorSeatIndex: -1,
      drawPileCount: 0,
      turnNumber: 0,
      playedCards: [],
      playedCategory: "",
      playedScore: 0,
      revealedClaims: [],
      claimAwards: [],
      discardedCards: [],
      sealedCardCount: 0,
      pendingDiscardSeatIndexes: [],
      finalResults: [],
      winnerSeatIndexes: [],
      seats: [
        {
          seatIndex: 0,
          participantId: host.sessionId,
          nickname: "甲",
          bot: false,
          ready: true,
          connected: true,
          score: 0,
          handCount: 0,
        },
        {
          seatIndex: 1,
          participantId: "",
          nickname: "",
          bot: false,
          ready: false,
          connected: false,
          score: 0,
          handCount: 0,
        },
        {
          seatIndex: 2,
          participantId: "",
          nickname: "",
          bot: false,
          ready: false,
          connected: false,
          score: 0,
          handCount: 0,
        },
        {
          seatIndex: 3,
          participantId: "",
          nickname: "",
          bot: false,
          ready: false,
          connected: false,
          score: 0,
          handCount: 0,
        },
      ],
      contestRounds: [],
      playEvents: [],
      claimEvents: [],
      discardEvents: [],
      finalEvents: [],
    });

    await host.leave();
  });

  it("lets a human participant publish their readiness", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "准备测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    await new Promise<void>((resolve) => host.onStateChange.once(() => resolve()));
    const guest = await colyseus.sdk.joinById(host.roomId, { nickname: "乙" });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    const handled = serverRoom.waitForMessage("set_ready");

    guest.send("set_ready", { ready: true });
    await handled;

    assert.strictEqual(serverRoom.state.seats[1].ready, true);
    await guest.leave();
    await host.leave();
  });

  it("keeps the waiting host ready when it sends a false readiness update", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "房主准备测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    const handled = serverRoom.waitForMessage("set_ready");

    host.send("set_ready", { ready: false });
    await handled;

    assert.strictEqual(serverRoom.state.seats[0].ready, true);
    await host.leave();
  });

  it("keeps the host ready when configuration clears other human readiness", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "配置测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const guest = await colyseus.sdk.joinById(host.roomId, { nickname: "乙" });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);

    let handled = serverRoom.waitForMessage("set_ready");
    guest.send("set_ready", { ready: true });
    await handled;

    handled = serverRoom.waitForMessage("configure");
    host.send("configure", { deckMode: "two", actionDeadlineSeconds: 60 });
    await handled;

    assert.strictEqual(serverRoom.state.deckMode, "two");
    assert.strictEqual(serverRoom.state.actionDeadlineSeconds, 60);
    assert.deepStrictEqual(
      Array.from(serverRoom.state.seats, (seat) => seat.ready),
      [true, false, false, false],
    );
    assert.deepStrictEqual(serverRoom.metadata, {
      displayName: "配置测试",
      deckMode: "two",
      actionDeadlineSeconds: 60,
      participantCount: 2,
      status: "waiting",
    });

    await guest.leave();
    await host.leave();
  });

  it("serializes concurrent configuration commits and keeps the latest settings", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "配置竞态测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    const commitMatchmaking = serverRoom.setMatchmaking.bind(serverRoom);
    let releaseFirstCommit = (): void => {};
    const firstCommitGate = new Promise<void>((resolve) => {
      releaseFirstCommit = resolve;
    });
    let markFirstCommitEntered = (): void => {};
    const firstCommitEntered = new Promise<void>((resolve) => {
      markFirstCommitEntered = resolve;
    });
    let commitCount = 0;
    let firstCommitFinished = false;
    serverRoom.setMatchmaking = async (updates): Promise<void> => {
      commitCount += 1;
      const isFirstCommit = commitCount === 1;
      if (isFirstCommit) {
        markFirstCommitEntered();
        await firstCommitGate;
      }
      await commitMatchmaking(updates);
      if (isFirstCommit) {
        firstCommitFinished = true;
      }
    };

    const firstHandled = serverRoom.waitForMessage("configure");
    host.send("configure", { deckMode: "two", actionDeadlineSeconds: 30 });
    await firstCommitEntered;
    host.send("configure", { deckMode: "one", actionDeadlineSeconds: 60 });
    releaseFirstCommit();
    await firstHandled;
    await waitUntil(() => (
      firstCommitFinished
      && serverRoom.metadata.deckMode === "one"
      && serverRoom.metadata.actionDeadlineSeconds === 60
    ));

    assert.strictEqual(serverRoom.state.deckMode, "one");
    assert.strictEqual(serverRoom.state.actionDeadlineSeconds, 60);
    assert.strictEqual(serverRoom.metadata.deckMode, "one");
    assert.strictEqual(serverRoom.metadata.actionDeadlineSeconds, 60);

    await host.leave();
  });

  it("repairs the listing when a stale configuration write mutates then rejects", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "配置失败恢复测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    const commitMatchmaking = serverRoom.setMatchmaking.bind(serverRoom);
    let releaseFirstCommit = (): void => {};
    const firstCommitGate = new Promise<void>((resolve) => {
      releaseFirstCommit = resolve;
    });
    let markFirstCommitEntered = (): void => {};
    const firstCommitEntered = new Promise<void>((resolve) => {
      markFirstCommitEntered = resolve;
    });
    let commitCount = 0;
    serverRoom.setMatchmaking = async (updates): Promise<void> => {
      commitCount += 1;
      const isFirstCommit = commitCount === 1;
      if (isFirstCommit) {
        markFirstCommitEntered();
        await firstCommitGate;
      }
      await commitMatchmaking(updates);
      if (isFirstCommit) {
        throw new Error("injected stale persistence failure");
      }
    };

    const firstHandled = serverRoom.waitForMessage("configure");
    host.send("configure", { deckMode: "two", actionDeadlineSeconds: 30 });
    await firstCommitEntered;
    host.send("configure", { deckMode: "one", actionDeadlineSeconds: 60 });
    releaseFirstCommit();
    await firstHandled;
    await waitUntil(() => (
      serverRoom.metadata.deckMode === "one"
      && serverRoom.metadata.actionDeadlineSeconds === 60
    ));

    assert.strictEqual(serverRoom.state.deckMode, "one");
    assert.strictEqual(serverRoom.state.actionDeadlineSeconds, 60);
    assert.strictEqual(serverRoom.metadata.deckMode, "one");
    assert.strictEqual(serverRoom.metadata.actionDeadlineSeconds, 60);
    assert.strictEqual(commitCount >= 3, true);

    await host.leave();
  });

  it("contains exhausted configuration persistence and repairs it on the room clock", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "配置恢复测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    const commitCount = failNextMatchmakingWrites(serverRoom, 2);

    const handled = serverRoom.waitForMessage("configure");
    host.send("configure", { deckMode: "two", actionDeadlineSeconds: 60 });
    await handled;

    serverRoom.clock.currentTime -= 200;
    serverRoom.clock.tick();
    await waitUntil(() => (
      serverRoom.metadata.deckMode === "two"
      && serverRoom.metadata.actionDeadlineSeconds === 60
    ));

    assert.strictEqual(commitCount(), 3);
    await host.leave();
  });

  it("rejects a non-host configuration without changing public settings", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "权限测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const guest = await colyseus.sdk.joinById(host.roomId, { nickname: "乙" });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    const handled = serverRoom.waitForMessage("configure");
    const rejected = guest.waitForMessage("room_error", 1000);

    guest.send("configure", { deckMode: "two", actionDeadlineSeconds: 60 });
    await handled;

    assert.deepStrictEqual(await rejected, {
      code: "host_only",
      message: "只有房主可以执行此操作",
    });
    assert.strictEqual(serverRoom.state.deckMode, "one");
    assert.strictEqual(serverRoom.state.actionDeadlineSeconds, 30);

    await guest.leave();
    await host.leave();
  });

  it("lets the host fill every open seat with ready bots and locks the room", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "机器人测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    const handled = serverRoom.waitForMessage("fill_bots");

    host.send("fill_bots", null);
    await handled;

    const seats = Array.from(serverRoom.state.seats);
    assert.strictEqual(seats.filter((seat) => seat.participantId !== "").length, 4);
    assert.strictEqual(new Set(seats.map((seat) => seat.participantId)).size, 4);
    assert.deepStrictEqual(
      seats.slice(1).map((seat) => ({
        nickname: seat.nickname,
        bot: seat.bot,
        ready: seat.ready,
      })),
      [
        { nickname: "激进型机器人 2", bot: true, ready: true },
        { nickname: "保守型机器人 3", bot: true, ready: true },
        { nickname: "激进型机器人 4", bot: true, ready: true },
      ],
    );
    assert.strictEqual(serverRoom.metadata.participantCount, 4);
    assert.strictEqual(serverRoom.locked, true);

    const nextHandled = serverRoom.waitForMessage("configure");
    host.send("configure", { deckMode: "two", actionDeadlineSeconds: 60 });
    await nextHandled;
    assert.deepStrictEqual(
      serverRoom.state.seats.toArray().map((seat) => seat.ready),
      [true, true, true, true],
    );

    await host.leave();
  });

  it("leaves an empty seat unready when no human can inherit the host", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "空房主测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    const handled = serverRoom.waitForMessage("fill_bots");
    host.send("fill_bots");
    await handled;

    await host.leave();

    assert.strictEqual(serverRoom.state.hostParticipantId, "");
    assert.strictEqual(serverRoom.state.seats[0].participantId, "");
    assert.strictEqual(serverRoom.state.seats[0].ready, false);
  });

  it("keeps a bot-filled room joinable when the host leaves during persistence", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "填充离开竞态测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const guest = await colyseus.sdk.joinById(host.roomId, { nickname: "乙" });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    const commitMatchmaking = serverRoom.setMatchmaking.bind(serverRoom);
    let releaseFirstCommit = (): void => {};
    const firstCommitGate = new Promise<void>((resolve) => {
      releaseFirstCommit = resolve;
    });
    let markFirstCommitEntered = (): void => {};
    const firstCommitEntered = new Promise<void>((resolve) => {
      markFirstCommitEntered = resolve;
    });
    let commitCount = 0;
    serverRoom.setMatchmaking = async (updates): Promise<void> => {
      commitCount += 1;
      if (commitCount === 1) {
        markFirstCommitEntered();
        await firstCommitGate;
      }
      await commitMatchmaking(updates);
    };

    const fillHandled = serverRoom.waitForMessage("fill_bots");
    host.send("fill_bots", null);
    await firstCommitEntered;
    const leaving = host.leave();
    await waitUntil(() => serverRoom.state.seats[0].participantId === "");
    releaseFirstCommit();
    await Promise.all([fillHandled, leaving]);
    await waitUntil(() => (
      serverRoom.metadata.participantCount === 3
      && !serverRoom.locked
    ));

    assert.strictEqual(serverRoom.state.seats[0].participantId, "");
    assert.strictEqual(serverRoom.state.hostParticipantId, guest.sessionId);
    assert.strictEqual(serverRoom.metadata.participantCount, 3);
    assert.strictEqual(serverRoom.locked, false);

    await guest.leave();
  });

  it("contains exhausted bot-fill persistence and repairs it on the room clock", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "填充恢复测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    const commitCount = failNextMatchmakingWrites(serverRoom, 2);

    const handled = serverRoom.waitForMessage("fill_bots");
    host.send("fill_bots", null);
    await handled;

    serverRoom.clock.currentTime -= 200;
    serverRoom.clock.tick();
    await waitUntil(() => (
      serverRoom.metadata.participantCount === 4
      && serverRoom.locked
    ));

    assert.strictEqual(commitCount(), 3);
    await host.leave();
  });

  it("rejects malformed fill-bots payloads without changing the room", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "机器人参数测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    const beforeState = serverRoom.state.toJSON();
    const beforeMetadata = { ...serverRoom.metadata };
    for (const payload of [{ unexpected: true }, "unexpected"]) {
      const handled = serverRoom.waitForMessage("fill_bots");
      const rejected = host.waitForMessage("room_error", 1000);

      host.send("fill_bots", payload);
      await handled;

      assert.deepStrictEqual(await rejected, {
        code: "invalid_payload",
        message: "该命令不接受参数",
      });
      assert.deepStrictEqual(serverRoom.state.toJSON(), beforeState);
      assert.deepStrictEqual(serverRoom.metadata, beforeMetadata);
      assert.strictEqual(serverRoom.locked, false);
    }

    await host.leave();
  });

  it("rejects bot fill and start commands from a non-host", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "房主命令测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const guest = await colyseus.sdk.joinById(host.roomId, { nickname: "乙" });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);

    let handled = serverRoom.waitForMessage("fill_bots");
    let rejected = guest.waitForMessage("room_error", 1000);
    guest.send("fill_bots");
    await handled;
    assert.strictEqual((await rejected).code, "host_only");
    assert.strictEqual(serverRoom.metadata.participantCount, 2);

    handled = serverRoom.waitForMessage("start");
    rejected = guest.waitForMessage("room_error", 1000);
    guest.send("start");
    await handled;
    assert.strictEqual((await rejected).code, "host_only");
    assert.strictEqual(serverRoom.state.status, "waiting");

    await guest.leave();
    await host.leave();
  });

  it("rejects start until every non-host human participant is ready", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "开始条件测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const guest = await colyseus.sdk.joinById(host.roomId, { nickname: "乙" });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    let handled = serverRoom.waitForMessage("fill_bots");
    host.send("fill_bots");
    await handled;

    handled = serverRoom.waitForMessage("start");
    const rejected = host.waitForMessage("room_error", 1000);
    host.send("start");
    await handled;

    assert.deepStrictEqual(await rejected, {
      code: "not_ready",
      message: "需要四个已准备座位才能开始",
    });
    assert.strictEqual(serverRoom.state.status, "waiting");
    assert.strictEqual(serverRoom.metadata.status, "waiting");

    await guest.leave();
    await host.leave();
  });

  it("rejects malformed start payloads without changing the room", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "开始参数测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    const beforeState = serverRoom.state.toJSON();
    const beforeMetadata = { ...serverRoom.metadata };
    for (const payload of [{ unexpected: true }, "unexpected"]) {
      const handled = serverRoom.waitForMessage("start");
      const rejected = host.waitForMessage("room_error", 1000);

      host.send("start", payload);
      await handled;

      assert.deepStrictEqual(await rejected, {
        code: "invalid_payload",
        message: "该命令不接受参数",
      });
      assert.deepStrictEqual(serverRoom.state.toJSON(), beforeState);
      assert.deepStrictEqual(serverRoom.metadata, beforeMetadata);
      assert.strictEqual(serverRoom.locked, false);
    }

    await host.leave();
  });

  it("starts a room with a ready host and bots without a readiness command", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "正式开始测试",
      deckMode: "two",
      actionDeadlineSeconds: 60,
    });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    let handled = serverRoom.waitForMessage("fill_bots");
    host.send("fill_bots");
    await handled;

    const privateStateReceived = host.waitForMessage("match_private_state", 2000);
    handled = serverRoom.waitForMessage("start");
    host.send("start", null);
    await handled;
    assert.strictEqual((await privateStateReceived).hand.length, 5);

    assert.strictEqual(serverRoom.state.status, "started");
    assert.strictEqual(serverRoom.metadata.status, "started");
    const [listing] = await matchMaker.query({ roomId: host.roomId });
    assert.strictEqual(listing.private, true);
    assert.strictEqual(listing.locked, true);

    handled = serverRoom.waitForMessage("start");
    const rejected = host.waitForMessage("room_error", 1000);
    host.send("start");
    await handled;
    assert.strictEqual((await rejected).code, "already_started");
    assert.strictEqual(serverRoom.state.status, "started");

    await host.leave();
  });

  it("releases a waiting seat and transfers the host clockwise to a human", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "离开测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const guest = await colyseus.sdk.joinById(host.roomId, { nickname: "乙" });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    const handled = serverRoom.waitForMessage("fill_bots");
    host.send("fill_bots");
    await handled;
    assert.strictEqual(serverRoom.locked, true);

    await host.leave();

    assert.deepStrictEqual(serverRoom.state.seats[0].toJSON(), {
      seatIndex: 0,
      participantId: "",
      nickname: "",
      bot: false,
      ready: false,
      connected: false,
      score: 0,
      handCount: 0,
    });
    assert.strictEqual(serverRoom.state.hostParticipantId, guest.sessionId);
    assert.strictEqual(serverRoom.state.seats[1].ready, true);
    assert.strictEqual(serverRoom.metadata.participantCount, 3);
    assert.strictEqual(serverRoom.locked, false);

    const newcomer = await colyseus.sdk.joinById(serverRoom.roomId, { nickname: "丁" });
    assert.strictEqual(serverRoom.state.seats[0].participantId, newcomer.sessionId);
    assert.strictEqual(serverRoom.state.hostParticipantId, guest.sessionId);

    await newcomer.leave();
    await guest.leave();
  });

  it("keeps the participant count current when a join overtakes a waiting leave", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "加入离开竞态测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const guest = await colyseus.sdk.joinById(host.roomId, { nickname: "乙" });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    const commitMatchmaking = serverRoom.setMatchmaking.bind(serverRoom);
    let releaseFirstCommit = (): void => {};
    const firstCommitGate = new Promise<void>((resolve) => {
      releaseFirstCommit = resolve;
    });
    let markFirstCommitEntered = (): void => {};
    const firstCommitEntered = new Promise<void>((resolve) => {
      markFirstCommitEntered = resolve;
    });
    let commitCount = 0;
    serverRoom.setMatchmaking = async (updates): Promise<void> => {
      commitCount += 1;
      if (commitCount === 1) {
        markFirstCommitEntered();
        await firstCommitGate;
      }
      await commitMatchmaking(updates);
    };

    const leaving = host.leave();
    await firstCommitEntered;
    await waitUntil(() => serverRoom.state.seats[0].participantId === "");
    const joining = colyseus.sdk.joinById(serverRoom.roomId, { nickname: "丙" });
    await waitUntil(() => (
      serverRoom.state.seats[0].participantId !== ""
      && serverRoom.state.seats[0].participantId !== host.sessionId
    ));
    releaseFirstCommit();
    const [newcomer] = await Promise.all([joining, leaving]);

    assert.strictEqual(serverRoom.state.seats[0].participantId, newcomer.sessionId);
    assert.strictEqual(serverRoom.metadata.participantCount, 2);
    assert.strictEqual(serverRoom.locked, false);

    await newcomer.leave();
    await guest.leave();
  });

  it("rejects malformed readiness without mutating the public state", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "准备校验测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    const before = serverRoom.state.toJSON();
    const handled = serverRoom.waitForMessage("set_ready");
    const rejected = host.waitForMessage("room_error", 1000);

    host.send("set_ready", { ready: "true" });
    await handled;

    assert.strictEqual((await rejected).code, "invalid_ready");
    assert.deepStrictEqual(serverRoom.state.toJSON(), before);
    await host.leave();
  });

  it("synchronizes the same four public seats to every human participant", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "同步测试",
      deckMode: "two",
      actionDeadlineSeconds: 15,
    });
    await new Promise<void>((resolve) => host.onStateChange.once(() => resolve()));
    const hostPatched = new Promise<void>((resolve) => {
      host.onStateChange.once(() => resolve());
    });
    const guest = await colyseus.sdk.joinById(host.roomId, { nickname: "乙" });
    if (Object.keys(guest.state.toJSON()).length === 0) {
      await new Promise<void>((resolve) => guest.onStateChange.once(() => resolve()));
    }
    await hostPatched;

    assert.deepStrictEqual(guest.state.toJSON(), host.state.toJSON());
    assert.strictEqual(guest.state.seats.length, 4);
    assert.strictEqual(guest.state.hostParticipantId, host.sessionId);
    assert.deepStrictEqual(
      guest.state.seats.toArray().map((seat: { nickname: string }) => seat.nickname),
      ["甲", "乙", "", ""],
    );

    await guest.leave();
    await host.leave();
  });

  it("rejects a stale join when a waiting room is private but unlocked", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "私有房间测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);
    await serverRoom.setPrivate(true);

    assert.strictEqual(serverRoom.locked, false);
    await assert.rejects(
      () => colyseus.sdk.joinById(host.roomId, { nickname: "乙" }),
      /private/,
    );
    assert.strictEqual(serverRoom.metadata.participantCount, 1);

    await host.leave();
  });

  it("rejects invalid and stale joins without occupying another seat", async () => {
    const host = await colyseus.sdk.create("game", {
      nickname: "甲",
      displayName: "加入校验测试",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    const serverRoom = colyseus.getRoomById<GameRoom>(host.roomId);

    await assert.rejects(
      () => colyseus.sdk.joinById(host.roomId, { nickname: "   " }),
    );
    assert.strictEqual(serverRoom.metadata.participantCount, 1);

    const handled = serverRoom.waitForMessage("fill_bots");
    host.send("fill_bots");
    await handled;
    await assert.rejects(
      () => colyseus.sdk.joinById(host.roomId, { nickname: "乙" }),
      /locked/,
    );
    assert.strictEqual(serverRoom.metadata.participantCount, 4);

    await host.leave();
  });
});
