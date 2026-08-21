import assert from "assert";
import type { ColyseusTestServer } from "@colyseus/testing";

import appConfig from "../src/app.config.js";
import type { PhysicalCard } from "../src/match/cards.js";
import { GameRoom, type ActionDeadlineSeconds } from "../src/rooms/GameRoom.js";

export interface PrivateMatchState {
  seatIndex: number;
  participantId: string;
  hand: PhysicalCard[];
  actionId: number;
}

export function tickClock(serverRoom: GameRoom, elapsedMilliseconds: number): void {
  serverRoom.clock.currentTime -= elapsedMilliseconds;
  serverRoom.clock.tick();
}

export async function waitForCondition(
  condition: () => boolean,
  attempts = 100,
): Promise<void> {
  for (let attempt = 0; attempt < attempts; attempt += 1) {
    if (condition()) {
      return;
    }
    await new Promise<void>((resolve) => setImmediate(resolve));
  }
  throw new Error("condition was not reached");
}

export function drainImmediateTasks(serverRoom: GameRoom): void {
  for (let attempt = 0; attempt < 8; attempt += 1) {
    tickClock(serverRoom, 0);
  }
}

export async function startActorPlay(
  colyseus: ColyseusTestServer<typeof appConfig>,
  actionDeadlineSeconds: ActionDeadlineSeconds = 15,
) {
  const host = await colyseus.sdk.create("game", {
    nickname: "甲",
    displayName: "行动时序测试",
    deckMode: "one",
    actionDeadlineSeconds,
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
