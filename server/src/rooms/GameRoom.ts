import { randomInt } from "node:crypto";
import { Client, Room, type Deferred } from "colyseus";

import { DECK_MODES, type DeckMode } from "../match/cards.js";
import {
  ACTION_DEADLINES,
  MatchCommandError,
  MatchEngine,
  type ActionDeadlineSeconds,
  type MatchPhase,
  type PublicMatchState,
} from "../match/MatchEngine.js";
import {
  chooseAutomaticPlayCardIds,
  chooseBotCommand,
  eligibleBotCommandType,
  type BotCommand,
} from "../match/botPolicy.js";
import { SeededRandomSource, type RandomSource } from "../match/random.js";
import {
  CardDiscardedEventState,
  ClaimAwardState,
  ClaimsResolvedEventState,
  FinalResultState,
  FinalSettlementEventState,
  GameRoomState,
  PlayEventState,
  PointContestRoundState,
  PublicCardState,
  RevealedClaimState,
} from "./schema/GameRoomState.js";

export { ACTION_DEADLINES, DECK_MODES };
export type { ActionDeadlineSeconds, DeckMode };

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

interface PendingReconnection {
  readonly seatIndex: number;
  readonly deferred: Deferred<Client>;
  timer: { clear(): void } | null;
}

const ROOM_ERRORS = {
  alreadyStarted: { code: "already_started", message: "对局已经开始" },
  configurePhase: { code: "invalid_phase", message: "房间当前不能修改设置" },
  fillBotsPhase: { code: "invalid_phase", message: "房间当前不能添加机器人" },
  hostOnly: { code: "host_only", message: "只有房主可以执行此操作" },
  invalidCommandPayload: { code: "invalid_payload", message: "该命令不接受参数" },
  invalidClaimPayload: { code: "invalid_payload", message: "抢牌参数必须包含牌标识或空值" },
  invalidDiscardPayload: { code: "invalid_payload", message: "弃牌参数必须包含牌标识" },
  invalidPlayPayload: { code: "invalid_payload", message: "出牌参数必须是牌标识数组" },
  invalidReady: { code: "invalid_ready", message: "准备状态必须是布尔值" },
  invalidSettings: { code: "invalid_settings", message: "房间设置无效" },
  noSeat: { code: "not_participant", message: "当前连接没有占用座位" },
  notReady: { code: "not_ready", message: "需要四个已准备座位才能开始" },
  playPhase: { code: "invalid_phase", message: "当前阶段不能出牌" },
  claimPhase: { code: "invalid_phase", message: "当前阶段不能抢牌" },
  discardPhase: { code: "invalid_phase", message: "当前阶段不能弃牌" },
  readyPhase: { code: "invalid_phase", message: "房间当前不能修改准备状态" },
  startFailed: { code: "start_failed", message: "对局启动失败，请重试" },
  startInProgress: { code: "start_in_progress", message: "对局正在启动" },
  staleAction: { code: "stale_action", message: "操作已过期，请按最新状态重试" },
} as const satisfies Record<string, RoomError>;

const POINT_CONTEST_DISPLAY_MILLISECONDS = 900;
const PLAY_REVEAL_DISPLAY_MILLISECONDS = 3_000;
const CLAIM_REVEAL_DISPLAY_MILLISECONDS = 4_000;
const DISCARD_REVEAL_DISPLAY_MILLISECONDS = 2_000;
const FINAL_REVEAL_DISPLAY_MILLISECONDS = 900;
const RECONNECTION_GRACE_MILLISECONDS = 30_000;
const MAX_ACTION_ID = 0xffff_ffff;

function isRecordLike(value: unknown): value is RecordLike {
  return typeof value === "object" && value !== null && !Array.isArray(value);
}

function isActionId(value: unknown): value is number {
  return Number.isSafeInteger(value) && (value as number) >= 0 && (value as number) <= MAX_ACTION_ID;
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

function isDeckMode(value: unknown): value is DeckMode {
  return DECK_MODES.some((deckMode) => deckMode === value);
}

function parseDeckMode(value: unknown): DeckMode {
  if (value === undefined) {
    return "one";
  }

  if (!isDeckMode(value)) {
    throw new Error("deckMode must be one or two");
  }

  return value;
}

function isActionDeadline(value: unknown): value is ActionDeadlineSeconds {
  return ACTION_DEADLINES.some((deadline) => deadline === value);
}

function parseActionDeadline(value: unknown): ActionDeadlineSeconds {
  if (value === undefined) {
    return 30;
  }

  if (!isActionDeadline(value)) {
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
  private matchEngine: MatchEngine | null = null;
  private botRandom: RandomSource | null = null;
  private botTimer: { clear(): void } | null = null;
  private pendingReconnections = new Map<string, PendingReconnection>();
  private phaseTimer: { clear(): void } | null = null;
  private startInProgress = false;
  private matchmakingWriteTail: Promise<void> = Promise.resolve();
  private matchmakingRecoveryTimer: { clear(): void } | null = null;

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
    this.onMessage("play_cards", (client, message: unknown) => {
      this.playCards(client, message);
    });
    this.onMessage("claim", (client, message: unknown) => {
      this.commitClaim(client, message);
    });
    this.onMessage("discard", (client, message: unknown) => {
      this.discardCard(client, message);
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
      this.ensureWaitingHostReady();
    }
    await this.synchronizeMatchmaking();
  }

  public async onDrop(client: Client): Promise<void> {
    if (this.state.status === "waiting") {
      await this.releaseWaitingSeat(client);
      return;
    }
    const seat = this.humanSeatFor(client);
    if (!seat || seat.bot) {
      return;
    }

    seat.connected = false;
    const deferred = this.allowReconnection(client, "manual");
    const pending: PendingReconnection = {
      seatIndex: seat.seatIndex,
      deferred,
      timer: null,
    };
    this.pendingReconnections.set(client.sessionId, pending);
    pending.timer = this.clock.setTimeout(() => {
      if (this.pendingReconnections.get(client.sessionId) === pending) {
        deferred.reject(new Error("reconnection window expired"));
      }
    }, RECONNECTION_GRACE_MILLISECONDS);

    try {
      await deferred;
    } catch {
      this.expireReconnection(client.sessionId, pending);
    }
  }

  public onReconnect(client: Client): void {
    const pending = this.pendingReconnections.get(client.sessionId);
    if (!pending) {
      return;
    }
    const seat = this.state.seats[pending.seatIndex];
    if (!seat || seat.participantId !== client.sessionId || seat.bot) {
      return;
    }

    pending.timer?.clear();
    this.pendingReconnections.delete(client.sessionId);
    seat.connected = true;
    this.sendPrivateMatchState(client);
  }

  public async onLeave(client: Client): Promise<void> {
    if (this.state.status === "waiting") {
      await this.releaseWaitingSeat(client);
      return;
    }
    this.takeOverHumanSeat(client.sessionId, client.userData?.seatIndex);
  }

  private async releaseWaitingSeat(client: Client): Promise<void> {
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
      this.ensureWaitingHostReady();
    }
    await this.synchronizeMatchmakingEventually();
  }

  private humanSeatFor(client: Client) {
    const seatIndex = client.userData?.seatIndex;
    if (typeof seatIndex !== "number") {
      return null;
    }
    const seat = this.state.seats[seatIndex];
    return seat?.participantId === client.sessionId ? seat : null;
  }

  private expireReconnection(
    participantId: string,
    pending: PendingReconnection,
  ): void {
    if (this.pendingReconnections.get(participantId) !== pending) {
      return;
    }
    pending.timer?.clear();
    this.pendingReconnections.delete(participantId);
    this.takeOverHumanSeat(participantId, pending.seatIndex);
  }

  private takeOverHumanSeat(participantId: string, seatIndex: unknown): void {
    if (typeof seatIndex !== "number") {
      return;
    }
    const seat = this.state.seats[seatIndex];
    if (!seat || seat.participantId !== participantId || seat.bot) {
      return;
    }
    const pending = this.pendingReconnections.get(participantId);
    pending?.timer?.clear();
    this.pendingReconnections.delete(participantId);
    seat.bot = true;
    seat.connected = false;
    seat.ready = true;
    if (this.matchEngine) {
      this.scheduleBotAction(this.matchEngine);
    }
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
    if (seat.participantId === this.state.hostParticipantId) {
      this.ensureWaitingHostReady();
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
    if (!isDeckMode(message.deckMode) || !isActionDeadline(message.actionDeadlineSeconds)) {
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
      if (
        seat.participantId !== ""
        && !seat.bot
        && seat.participantId !== this.state.hostParticipantId
      ) {
        seat.ready = false;
      }
    }
    await this.synchronizeMatchmakingEventually();
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
    await this.synchronizeMatchmakingEventually();
  }

  private currentMetadata(): GameRoomMetadata {
    const participantCount = this.state.seats.reduce(
      (count, seat) => count + (seat.participantId === "" ? 0 : 1),
      0,
    );
    return {
      displayName: this.state.displayName,
      deckMode: this.state.deckMode,
      actionDeadlineSeconds: this.state.actionDeadlineSeconds,
      participantCount,
      status: this.state.status,
    };
  }

  private enqueueMatchmakingWrite(operation: () => Promise<void>): Promise<void> {
    const result = this.matchmakingWriteTail.then(operation);
    this.matchmakingWriteTail = result.catch(() => {});
    return result;
  }

  private clearMatchmakingRecovery(): void {
    this.matchmakingRecoveryTimer?.clear();
    this.matchmakingRecoveryTimer = null;
  }

  private scheduleMatchmakingRecovery(): void {
    if (this.matchmakingRecoveryTimer !== null) {
      return;
    }
    const timer = this.clock.setTimeout(() => {
      if (this.matchmakingRecoveryTimer !== timer) {
        return;
      }
      this.matchmakingRecoveryTimer = null;
      void this.synchronizeMatchmakingEventually();
    }, 100);
    this.matchmakingRecoveryTimer = timer;
  }

  private async persistCurrentMatchmaking(): Promise<void> {
    let lastError: unknown = new Error("matchmaking persistence failed");
    for (let attempt = 0; attempt < 2; attempt += 1) {
      const metadata = this.currentMetadata();
      const shouldBePrivate = metadata.status === "started" || this.matchmakingPrivate;
      const shouldBeLocked = (
        metadata.status === "started"
        || metadata.participantCount >= this.maxClients
      );

      try {
        await this.setMatchmaking({
          metadata,
          private: shouldBePrivate,
          locked: shouldBeLocked,
        });
        this.clearMatchmakingRecovery();
        return;
      } catch (error) {
        lastError = error;
      }
    }
    this.scheduleMatchmakingRecovery();
    throw lastError;
  }

  private synchronizeMatchmaking(): Promise<void> {
    return this.enqueueMatchmakingWrite(async () => {
      await this.persistCurrentMatchmaking();
    });
  }

  private async synchronizeMatchmakingEventually(): Promise<void> {
    try {
      await this.synchronizeMatchmaking();
    } catch {
      // The room-clock recovery repairs the listing after the command completes.
    }
  }

  private async recoverMatchmakingWithinWrite(): Promise<void> {
    try {
      await this.persistCurrentMatchmaking();
    } catch {
      // The scheduled recovery keeps retrying after this command releases the write queue.
    }
  }

  private async startMatch(client: Client, message: unknown): Promise<void> {
    if (!this.authorizeWaitingHost(client, ROOM_ERRORS.alreadyStarted)) {
      return;
    }
    if (this.startInProgress) {
      this.sendRoomError(client, ROOM_ERRORS.startInProgress);
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

    this.startInProgress = true;
    const waitingPrivate = this.matchmakingPrivate;
    const startingHostParticipantId = this.state.hostParticipantId;
    const startingDeckMode = this.state.deckMode;
    const startingActionDeadlineSeconds = this.state.actionDeadlineSeconds;
    const startingSeats = this.state.seats.map((seat) => ({
      seatIndex: seat.seatIndex,
      participantId: seat.participantId,
      nickname: seat.nickname,
      bot: seat.bot,
    }));
    const startContextIsCurrent = (): boolean => (
      this.state.status === "waiting"
      && this.state.hostParticipantId === startingHostParticipantId
      && this.state.deckMode === startingDeckMode
      && this.state.actionDeadlineSeconds === startingActionDeadlineSeconds
      && this.state.seats.length === startingSeats.length
      && this.state.seats.every((seat, index) => {
        const startingSeat = startingSeats[index];
        return (
          seat.ready
          && seat.seatIndex === startingSeat.seatIndex
          && seat.participantId === startingSeat.participantId
          && seat.nickname === startingSeat.nickname
          && seat.bot === startingSeat.bot
        );
      })
    );
    try {
      const matchEngine = new MatchEngine(new SeededRandomSource(
        randomInt(1, 0x1_0000_0000),
      ));
      const botRandom = new SeededRandomSource(randomInt(1, 0x1_0000_0000));
      matchEngine.start(
        startingSeats,
        {
          deckMode: startingDeckMode,
          actionDeadlineSeconds: startingActionDeadlineSeconds,
        },
      );
      const publicMatchState = matchEngine.view(0).publicState;

      await this.enqueueMatchmakingWrite(async () => {
        if (!startContextIsCurrent()) {
          await this.recoverMatchmakingWithinWrite();
          if (this.humanSeatFor(client)) {
            this.sendRoomError(client, ROOM_ERRORS.startFailed);
          }
          return;
        }

        try {
          await this.setMatchmaking({
            metadata: { ...this.currentMetadata(), status: "started" },
            private: true,
            locked: true,
          });
        } catch {
          this.matchmakingPrivate = waitingPrivate;
          await this.recoverMatchmakingWithinWrite();
          if (this.humanSeatFor(client)) {
            this.sendRoomError(client, ROOM_ERRORS.startFailed);
          }
          return;
        }

        if (!startContextIsCurrent()) {
          this.matchmakingPrivate = waitingPrivate;
          await this.recoverMatchmakingWithinWrite();
          return;
        }

        this.matchmakingPrivate = true;
        this.matchEngine = matchEngine;
        this.botRandom = botRandom;
        this.state.status = "started";
        this.autoDispose = false;
        this.enterMatchPhase(matchEngine, publicMatchState);
      });
    } finally {
      this.startInProgress = false;
    }
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

  private ensureWaitingHostReady(): void {
    if (this.state.hostParticipantId === "") {
      return;
    }
    const hostSeat = this.state.seats.find(
      (candidate) => candidate.participantId === this.state.hostParticipantId,
    );
    if (hostSeat && !hostSeat.bot) {
      hostSeat.ready = true;
    }
  }

  private playCards(client: Client, message: unknown): void {
    if (!this.matchEngine) {
      this.sendRoomError(client, ROOM_ERRORS.playPhase);
      return;
    }
    if (
      !isRecordLike(message)
      || !Array.isArray(message.cardIds)
      || !Array.from(message.cardIds).every((cardId) => typeof cardId === "string")
      || !isActionId(message.actionId)
    ) {
      this.sendRoomError(client, ROOM_ERRORS.invalidPlayPayload);
      return;
    }
    if (!this.authorizeCurrentAction(client, message.actionId)) {
      return;
    }
    const seatIndex = client.userData?.seatIndex;
    if (typeof seatIndex !== "number") {
      throw new Error("cannot play cards without an occupied seat");
    }

    try {
      this.submitPlay(this.matchEngine, seatIndex, message.cardIds);
    } catch (error) {
      if (error instanceof MatchCommandError) {
        this.sendRoomError(client, { code: error.code, message: error.message });
        return;
      }
      throw error;
    }
  }

  private commitClaim(client: Client, message: unknown): void {
    if (!this.matchEngine) {
      this.sendRoomError(client, ROOM_ERRORS.claimPhase);
      return;
    }
    if (
      !isRecordLike(message)
      || !Object.hasOwn(message, "cardId")
      || (message.cardId !== null && typeof message.cardId !== "string")
      || !isActionId(message.actionId)
    ) {
      this.sendRoomError(client, ROOM_ERRORS.invalidClaimPayload);
      return;
    }
    if (!this.authorizeCurrentAction(client, message.actionId)) {
      return;
    }
    const seatIndex = client.userData?.seatIndex;
    if (typeof seatIndex !== "number") {
      this.sendRoomError(client, ROOM_ERRORS.noSeat);
      return;
    }
    const cardId = message.cardId as string | null;

    try {
      const transitioned = this.submitClaim(this.matchEngine, seatIndex, cardId);
      if (transitioned) {
        this.sendPrivateMatchStates();
      } else {
        this.sendPrivateMatchState(client);
      }
    } catch (error) {
      if (error instanceof MatchCommandError) {
        this.sendRoomError(client, { code: error.code, message: error.message });
        return;
      }
      throw error;
    }
  }

  private discardCard(client: Client, message: unknown): void {
    if (!this.matchEngine) {
      this.sendRoomError(client, ROOM_ERRORS.discardPhase);
      return;
    }
    if (
      !isRecordLike(message)
      || typeof message.cardId !== "string"
      || message.cardId.length === 0
      || !Number.isSafeInteger(message.turnNumber)
      || (message.turnNumber as number) <= 0
      || !isActionId(message.actionId)
    ) {
      this.sendRoomError(client, ROOM_ERRORS.invalidDiscardPayload);
      return;
    }
    if (!this.authorizeCurrentAction(client, message.actionId)) {
      return;
    }
    const seatIndex = client.userData?.seatIndex;
    if (typeof seatIndex !== "number") {
      this.sendRoomError(client, ROOM_ERRORS.noSeat);
      return;
    }

    try {
      this.submitDiscard(
        this.matchEngine,
        seatIndex,
        message.cardId,
        message.turnNumber as number,
      );
    } catch (error) {
      if (error instanceof MatchCommandError) {
        this.sendRoomError(client, { code: error.code, message: error.message });
        return;
      }
      throw error;
    }
    this.sendPrivateMatchStates();
  }

  private submitPlay(
    matchEngine: MatchEngine,
    seatIndex: number,
    cardIds: readonly string[],
  ): void {
    matchEngine.playCards(seatIndex, cardIds);
    this.enterMatchPhase(matchEngine, matchEngine.view(seatIndex).publicState);
    this.sendPrivateMatchStates();
  }

  private submitClaim(
    matchEngine: MatchEngine,
    seatIndex: number,
    cardId: string | null,
  ): boolean {
    matchEngine.commitClaim(seatIndex, cardId);
    const publicState = matchEngine.view(seatIndex).publicState;
    if (publicState.phase === "claim_commit") {
      return false;
    }
    this.enterMatchPhase(matchEngine, publicState);
    return true;
  }

  private submitDiscard(
    matchEngine: MatchEngine,
    seatIndex: number,
    cardId: string,
    turnNumber: number,
  ): void {
    matchEngine.discardCard(seatIndex, cardId, turnNumber);
    const publicState = matchEngine.view(seatIndex).publicState;
    if (publicState.phase === "award_discard") {
      this.applyPublicMatchState(publicState);
      return;
    }
    this.enterMatchPhase(matchEngine, publicState);
  }

  private enterMatchPhase(
    matchEngine: MatchEngine,
    publicState: PublicMatchState = matchEngine.view(0).publicState,
  ): void {
    this.clearPhaseTimer();
    this.clearBotTimer();
    if (this.state.actionId >= MAX_ACTION_ID) {
      throw new Error("match exhausted its action id range");
    }
    this.state.actionId += 1;
    this.applyPublicMatchState(publicState);

    const phase = publicState.phase;
    const delayMilliseconds = this.phaseDelayMilliseconds(phase);
    this.state.actionDeadlineAtUnixMs = this.isActionablePhase(phase)
      ? Date.now() + delayMilliseconds!
      : 0;
    if (phase === "finished") {
      this.autoDispose = true;
    }
    if (delayMilliseconds === null) {
      this.scheduleBotAction(matchEngine);
      return;
    }

    const actionId = this.state.actionId;
    const timer = this.clock.setTimeout(() => {
      if (this.phaseTimer !== timer) {
        return;
      }
      this.phaseTimer = null;
      if (
        this.matchEngine !== matchEngine
        || this.state.phase !== phase
        || this.state.actionId !== actionId
      ) {
        return;
      }
      this.resolvePhaseTimer(matchEngine, phase);
    }, delayMilliseconds);
    this.phaseTimer = timer;
    this.scheduleBotAction(matchEngine);
  }

  private scheduleBotAction(matchEngine: MatchEngine): void {
    if (this.botTimer !== null || this.botRandom === null) {
      return;
    }
    const seatIndex = this.nextBotSeatIndex(matchEngine);
    if (seatIndex === null) {
      return;
    }
    const phase = this.state.phase;
    const actionId = this.state.actionId;
    const timer = this.clock.setTimeout(() => {
      if (this.botTimer !== timer) {
        return;
      }
      this.botTimer = null;
      if (
        this.matchEngine !== matchEngine
        || this.state.phase !== phase
        || this.state.actionId !== actionId
        || !this.state.seats[seatIndex]?.bot
      ) {
        return;
      }
      const command = chooseBotCommand(matchEngine.view(seatIndex), this.botRandom!);
      if (command === null) {
        return;
      }
      this.executeBotCommand(matchEngine, seatIndex, command);
      this.scheduleBotAction(matchEngine);
    }, 0);
    this.botTimer = timer;
  }

  private nextBotSeatIndex(matchEngine: MatchEngine): number | null {
    for (const seat of this.state.seats) {
      if (seat.participantId === "" || !seat.bot) {
        continue;
      }
      if (eligibleBotCommandType(matchEngine.view(seat.seatIndex)) !== null) {
        return seat.seatIndex;
      }
    }
    return null;
  }

  private executeBotCommand(
    matchEngine: MatchEngine,
    seatIndex: number,
    command: BotCommand,
  ): void {
    if (command.type === "play_cards") {
      this.submitPlay(matchEngine, seatIndex, command.cardIds);
      return;
    }
    if (command.type === "claim") {
      if (this.submitClaim(matchEngine, seatIndex, command.cardId)) {
        this.sendPrivateMatchStates();
      }
      return;
    }
    if (command.type === "discard") {
      this.submitDiscard(matchEngine, seatIndex, command.cardId, command.turnNumber);
      this.sendPrivateMatchStates();
      return;
    }
  }

  private resolvePhaseTimer(matchEngine: MatchEngine, phase: MatchPhase): void {
    if (phase === "point_contest") {
      matchEngine.completePointContest();
    } else if (phase === "play_reveal") {
      matchEngine.completePlayReveal();
    } else if (phase === "actor_play") {
      const actorSeatIndex = matchEngine.view(0).publicState.actorSeatIndex;
      const cardIds = chooseAutomaticPlayCardIds(matchEngine.view(actorSeatIndex));
      if (cardIds === null) {
        throw new Error("actor deadline has no legal automatic play");
      }
      matchEngine.playCards(actorSeatIndex, cardIds);
    } else if (phase === "claim_commit") {
      matchEngine.resolveClaimsAtDeadline();
    } else if (phase === "claim_reveal") {
      matchEngine.completeClaimReveal();
    } else if (phase === "award_discard") {
      matchEngine.resolveDiscardAtDeadline();
    } else if (phase === "discard_reveal") {
      matchEngine.completeDiscardReveal();
    } else if (phase === "final_reveal") {
      matchEngine.completeFinalReveal();
    } else {
      return;
    }

    this.enterMatchPhase(matchEngine);
    this.sendPrivateMatchStates();
  }

  private phaseDelayMilliseconds(phase: MatchPhase): number | null {
    if (phase === "point_contest") {
      return POINT_CONTEST_DISPLAY_MILLISECONDS;
    }
    if (phase === "play_reveal") {
      return PLAY_REVEAL_DISPLAY_MILLISECONDS;
    }
    if (phase === "claim_reveal") {
      return CLAIM_REVEAL_DISPLAY_MILLISECONDS;
    }
    if (phase === "discard_reveal") {
      return DISCARD_REVEAL_DISPLAY_MILLISECONDS;
    }
    if (phase === "final_reveal") {
      return FINAL_REVEAL_DISPLAY_MILLISECONDS;
    }
    if (this.isActionablePhase(phase)) {
      return this.state.actionDeadlineSeconds * 1000;
    }
    return null;
  }

  private isActionablePhase(phase: MatchPhase): boolean {
    return (
      phase === "actor_play"
      || phase === "claim_commit"
      || phase === "award_discard"
    );
  }

  private clearPhaseTimer(): void {
    this.phaseTimer?.clear();
    this.phaseTimer = null;
  }

  private clearBotTimer(): void {
    this.botTimer?.clear();
    this.botTimer = null;
  }

  private applyPublicMatchState(publicState: PublicMatchState): void {
    this.state.phase = publicState.phase;
    this.state.actorSeatIndex = publicState.actorSeatIndex;
    this.state.firstActorSeatIndex = publicState.firstActorSeatIndex;
    this.state.drawPileCount = publicState.drawPileCount;
    this.state.turnNumber = publicState.turnNumber;
    this.state.playedCards.clear();
    for (const card of publicState.playedCards) {
      this.state.playedCards.push(new PublicCardState(card));
    }
    this.state.playedCategory = publicState.playedCategory ?? "";
    this.state.playedScore = publicState.playedScore;
    this.state.revealedClaims.clear();
    for (const claim of publicState.revealedClaims) {
      this.state.revealedClaims.push(new RevealedClaimState(claim));
    }
    this.state.claimAwards.clear();
    for (const award of publicState.claimAwards) {
      this.state.claimAwards.push(new ClaimAwardState(award));
    }
    this.state.discardedCards.clear();
    for (const card of publicState.discardedCards) {
      this.state.discardedCards.push(new PublicCardState(card));
    }
    this.state.sealedCardCount = publicState.sealedCardCount;
    this.state.pendingDiscardSeatIndexes.clear();
    this.state.pendingDiscardSeatIndexes.push(...publicState.pendingDiscardSeatIndexes);
    this.state.finalResults.clear();
    for (const result of publicState.finalResults) {
      this.state.finalResults.push(new FinalResultState(result));
    }
    this.state.winnerSeatIndexes.clear();
    this.state.winnerSeatIndexes.push(...publicState.winnerSeatIndexes);
    for (const participant of publicState.participants) {
      const seat = this.state.seats[participant.seatIndex];
      if (!seat || seat.participantId !== participant.participantId) {
        throw new Error("match participant does not match the occupied room seat");
      }
      seat.score = participant.score;
      seat.handCount = participant.handCount;
    }
    this.state.contestRounds.clear();
    this.state.playEvents.clear();
    this.state.claimEvents.clear();
    this.state.discardEvents.clear();
    this.state.finalEvents.clear();
    for (const event of publicState.events) {
      if (event.type === "point_contest_round") {
        this.state.contestRounds.push(new PointContestRoundState(event));
      } else if (event.type === "cards_played") {
        this.state.playEvents.push(new PlayEventState(event));
      } else if (event.type === "claims_resolved") {
        this.state.claimEvents.push(new ClaimsResolvedEventState(event));
      } else if (event.type === "card_discarded") {
        this.state.discardEvents.push(new CardDiscardedEventState(event));
      } else {
        this.state.finalEvents.push(new FinalSettlementEventState(event));
      }
    }
  }

  private sendPrivateMatchStates(): void {
    if (!this.matchEngine) {
      throw new Error("cannot send private state before the match starts");
    }
    for (const participantClient of this.clients) {
      const seatIndex = participantClient.userData?.seatIndex;
      if (typeof seatIndex !== "number") {
        continue;
      }
      this.sendPrivateMatchState(participantClient);
    }
  }

  private sendPrivateMatchState(participantClient: Client): void {
    if (!this.matchEngine) {
      throw new Error("cannot send private state before the match starts");
    }
    const seatIndex = participantClient.userData?.seatIndex;
    if (typeof seatIndex !== "number") {
      return;
    }
    const privateState = this.matchEngine.view(seatIndex).privateState;
    if (privateState.participantId !== participantClient.sessionId) {
      throw new Error("private match state does not belong to its recipient");
    }
    participantClient.send("match_private_state", {
      ...privateState,
      actionId: this.state.actionId,
    });
  }

  private authorizeCurrentAction(client: Client, actionId: number): boolean {
    if (actionId !== this.state.actionId) {
      this.sendRoomError(client, ROOM_ERRORS.staleAction);
      return false;
    }
    return true;
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
