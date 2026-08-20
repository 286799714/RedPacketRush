import { Client, Room } from "colyseus";

import { GameRoomState } from "./schema/GameRoomState.js";

export const DECK_MODES = ["one", "two"] as const;
export type DeckMode = (typeof DECK_MODES)[number];

export const ACTION_DEADLINES = [15, 30, 60] as const;
export type ActionDeadlineSeconds = (typeof ACTION_DEADLINES)[number];

export type GameRoomStatus = "waiting" | "started";

export interface GameRoomMetadata {
  displayName: string;
  deckMode: DeckMode;
  actionDeadlineSeconds: ActionDeadlineSeconds;
  participantCount: number;
  status: GameRoomStatus;
}

export interface GameRoomOptions {
  nickname?: unknown;
  displayName?: unknown;
  deckMode?: unknown;
  actionDeadlineSeconds?: unknown;
}

type RecordLike = Record<string, unknown>;

interface RoomError {
  code: string;
  message: string;
}

const ROOM_ERRORS = {
  alreadyStarted: { code: "already_started", message: "对局已经开始" },
  configurePhase: { code: "invalid_phase", message: "房间当前不能修改设置" },
  fillBotsPhase: { code: "invalid_phase", message: "房间当前不能添加机器人" },
  hostOnly: { code: "host_only", message: "只有房主可以执行此操作" },
  invalidCommandPayload: { code: "invalid_payload", message: "该命令不接受参数" },
  invalidReady: { code: "invalid_ready", message: "准备状态必须是布尔值" },
  invalidSettings: { code: "invalid_settings", message: "房间设置无效" },
  noSeat: { code: "not_participant", message: "当前连接没有占用座位" },
  notReady: { code: "not_ready", message: "需要四个已准备座位才能开始" },
  readyPhase: { code: "invalid_phase", message: "房间当前不能修改准备状态" },
} as const satisfies Record<string, RoomError>;

function isRecordLike(value: unknown): value is RecordLike {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function parseDisplayName(value: unknown): string {
  if (value === undefined) {
    return "Red Packet Rush";
  }

  if (typeof value !== "string") {
    throw new Error("displayName must be a string");
  }

  const displayName = value.trim();
  if (displayName.length === 0 || displayName.length > 40) {
    throw new Error("displayName must contain between 1 and 40 characters");
  }

  return displayName;
}

function parseDeckMode(value: unknown): DeckMode {
  if (value === undefined) {
    return "one";
  }

  if (value !== "one" && value !== "two") {
    throw new Error("deckMode must be one or two");
  }

  return value;
}

function parseActionDeadline(value: unknown): ActionDeadlineSeconds {
  if (value === undefined) {
    return 30;
  }

  if (value !== 15 && value !== 30 && value !== 60) {
    throw new Error("actionDeadlineSeconds must be 15, 30, or 60");
  }

  return value;
}

function parseNickname(value: unknown): string {
  if (typeof value !== "string") {
    throw new Error("nickname must be a string");
  }

  const nickname = value.trim();
  if (nickname.length === 0 || nickname.length > 20) {
    throw new Error("nickname must contain between 1 and 20 characters");
  }

  return nickname;
}

export function parseGameRoomOptions(options: unknown): GameRoomMetadata {
  if (!isRecordLike(options)) {
    throw new Error("game room options must be an object");
  }

  return {
    displayName: parseDisplayName(options.displayName),
    deckMode: parseDeckMode(options.deckMode),
    actionDeadlineSeconds: parseActionDeadline(options.actionDeadlineSeconds),
    participantCount: 0,
    status: "waiting",
  };
}

export class GameRoom extends Room<{
  state: GameRoomState;
  metadata: GameRoomMetadata;
}> {
  public maxClients = 4;
  private matchmakingPrivate = false;

  public override async setPrivate(isPrivate = true, persist = true): Promise<void> {
    this.matchmakingPrivate = isPrivate;
    await super.setPrivate(isPrivate, persist);
  }

  public onCreate(options: GameRoomOptions): void {
    this.metadata = parseGameRoomOptions(options);
    this.setState(new GameRoomState(this.metadata));
    this.onMessage("set_ready", (client, message: unknown) => {
      this.setParticipantReady(client, message);
    });
    this.onMessage("configure", async (client, message: unknown) => {
      await this.configureRoom(client, message);
    });
    this.onMessage("fill_bots", async (client, message: unknown) => {
      await this.fillBots(client, message);
    });
    this.onMessage("start", async (client, message: unknown) => {
      await this.startMatch(client, message);
    });
  }

  public async onJoin(client: Client, options: GameRoomOptions): Promise<void> {
    if (this.matchmakingPrivate) {
      throw new Error("room is private");
    }
    if (this.state.status !== "waiting") {
      throw new Error("match has already started");
    }
    const nickname = parseNickname(options.nickname);
    const duplicateSeat = this.state.seats.find(
      (candidate) => candidate.participantId === client.sessionId,
    );
    if (duplicateSeat) {
      throw new Error("participant already occupies a seat");
    }
    const seat = this.state.seats.find((candidate) => candidate.participantId === "");
    if (!seat) {
      throw new Error("room has no open seat");
    }

    seat.occupy(client.sessionId, nickname);
    client.userData = { seatIndex: seat.seatIndex };
    if (this.state.hostParticipantId === "") {
      this.state.hostParticipantId = client.sessionId;
    }
    await this.updateParticipantCount();
  }

  public async onLeave(client: Client): Promise<void> {
    if (this.state.status !== "waiting") {
      return;
    }
    const seatIndex = client.userData?.seatIndex;
    if (typeof seatIndex !== "number") {
      return;
    }
    const seat = this.state.seats[seatIndex];
    if (!seat || seat.participantId !== client.sessionId) {
      return;
    }

    const wasHost = this.state.hostParticipantId === client.sessionId;
    seat.clear();
    if (wasHost) {
      this.state.hostParticipantId = this.findNextHumanParticipantId(seatIndex);
    }
    await this.updateParticipantCount();
    await this.unlock();
  }

  private setParticipantReady(client: Client, message: unknown): void {
    if (this.state.status !== "waiting") {
      this.sendRoomError(client, ROOM_ERRORS.readyPhase);
      return;
    }
    if (!isRecordLike(message) || typeof message.ready !== "boolean") {
      this.sendRoomError(client, ROOM_ERRORS.invalidReady);
      return;
    }

    const seat = this.state.seats.find(
      (candidate) => candidate.participantId === client.sessionId && !candidate.bot,
    );
    if (!seat) {
      this.sendRoomError(client, ROOM_ERRORS.noSeat);
      return;
    }
    seat.ready = message.ready;
  }

  private async configureRoom(client: Client, message: unknown): Promise<void> {
    if (!this.authorizeWaitingHost(client, ROOM_ERRORS.configurePhase)) {
      return;
    }
    if (!isRecordLike(message)) {
      this.sendRoomError(client, ROOM_ERRORS.invalidSettings);
      return;
    }
    if (
      (message.deckMode !== "one" && message.deckMode !== "two")
      || (message.actionDeadlineSeconds !== 15
        && message.actionDeadlineSeconds !== 30
        && message.actionDeadlineSeconds !== 60)
    ) {
      this.sendRoomError(client, ROOM_ERRORS.invalidSettings);
      return;
    }

    const changed = (
      message.deckMode !== this.state.deckMode
      || message.actionDeadlineSeconds !== this.state.actionDeadlineSeconds
    );
    if (!changed) {
      return;
    }

    this.state.deckMode = message.deckMode;
    this.state.actionDeadlineSeconds = message.actionDeadlineSeconds;
    for (const seat of this.state.seats) {
      if (seat.participantId !== "" && !seat.bot) {
        seat.ready = false;
      }
    }
    await this.setMetadata({
      deckMode: message.deckMode,
      actionDeadlineSeconds: message.actionDeadlineSeconds,
    });
  }

  private async fillBots(client: Client, message: unknown): Promise<void> {
    if (!this.authorizeWaitingHost(client, ROOM_ERRORS.fillBotsPhase)) {
      return;
    }
    if (message !== undefined && message !== null) {
      this.sendRoomError(client, ROOM_ERRORS.invalidCommandPayload);
      return;
    }

    for (const seat of this.state.seats) {
      if (seat.participantId === "") {
        seat.occupy(
          `bot-${this.roomId}-${seat.seatIndex}`,
          `机器人 ${seat.seatIndex + 1}`,
          true,
        );
      }
    }
    await this.updateParticipantCount();
    await this.lock();
  }

  private async updateParticipantCount(): Promise<void> {
    const participantCount = this.state.seats.reduce(
      (count, seat) => count + (seat.participantId === "" ? 0 : 1),
      0,
    );
    await this.setMetadata({ participantCount });
  }

  private findNextHumanParticipantId(afterSeatIndex: number): string {
    for (let offset = 1; offset <= this.state.seats.length; offset += 1) {
      const seatIndex = (afterSeatIndex + offset) % this.state.seats.length;
      const seat = this.state.seats[seatIndex];
      if (seat.participantId !== "" && !seat.bot) {
        return seat.participantId;
      }
    }
    return "";
  }

  private async startMatch(client: Client, message: unknown): Promise<void> {
    if (!this.authorizeWaitingHost(client, ROOM_ERRORS.alreadyStarted)) {
      return;
    }
    if (message !== undefined && message !== null) {
      this.sendRoomError(client, ROOM_ERRORS.invalidCommandPayload);
      return;
    }
    const allReady = this.state.seats.every(
      (seat) => seat.participantId !== "" && seat.ready,
    );
    if (!allReady) {
      this.sendRoomError(client, ROOM_ERRORS.notReady);
      return;
    }

    this.state.status = "started";
    await this.setMatchmaking({
      metadata: { ...this.metadata, status: "started" },
      private: true,
      locked: true,
    });
  }

  private authorizeWaitingHost(client: Client, phaseError: RoomError): boolean {
    if (this.state.status !== "waiting") {
      this.sendRoomError(client, phaseError);
      return false;
    }
    if (this.state.hostParticipantId !== client.sessionId) {
      this.sendRoomError(client, ROOM_ERRORS.hostOnly);
      return false;
    }
    return true;
  }

  private sendRoomError(client: Client, error: RoomError): void {
    client.send("room_error", error);
  }
}
