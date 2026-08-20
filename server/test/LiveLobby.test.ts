import assert from "assert";
import { ColyseusTestServer } from "@colyseus/testing";

import appConfig from "../src/app.config.js";
import { getTestServer } from "./testServer.js";

describe("live lobby room listing", () => {
  let colyseus: ColyseusTestServer<typeof appConfig>;

  before(async () => colyseus = await getTestServer());

  beforeEach(async () => {
    await colyseus.cleanup();
  });

  it("publishes a new game room and removes it when it becomes locked", async () => {
    const lobby = await colyseus.sdk.joinOrCreate("lobby");
    const initialRooms = await lobby.waitForMessage("rooms");
    assert.deepStrictEqual(initialRooms, []);

    const roomAdded = lobby.waitForMessage("+");
    const game = await colyseus.createRoom("game", {
      displayName: "Test table",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });

    const [addedRoomId, addedListing] = await roomAdded;
    assert.strictEqual(addedRoomId, game.roomId);
    assert.strictEqual(addedListing.name, "game");
    assert.deepStrictEqual(addedListing.metadata, {
      displayName: "Test table",
      deckMode: "one",
      actionDeadlineSeconds: 30,
      participantCount: 0,
      status: "waiting",
    });

    const roomRemoved = lobby.waitForMessage("-");
    await game.lock();

    assert.strictEqual(await roomRemoved, game.roomId);
    await assert.rejects(
      () => colyseus.sdk.joinById(game.roomId),
      /locked/,
    );

    await lobby.leave();
  });

  it("omits already locked rooms from a new lobby connection", async () => {
    const game = await colyseus.createRoom("game", {
      displayName: "Stale table",
      deckMode: "one",
      actionDeadlineSeconds: 30,
    });
    await game.lock();

    const lobby = await colyseus.sdk.joinOrCreate("lobby");

    assert.deepStrictEqual(await lobby.waitForMessage("rooms"), []);
    await lobby.leave();
  });
});
