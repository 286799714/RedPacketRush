import { randomInt } from "node:crypto";
import { Client, Room } from "colyseus";

import { DECK_MODES, type DeckMode } from "../match/cards.js";
import {
  ACTION_DEADLINES,
  MatchCommandError,
  MatchEngine,
  type ActionDeadlineSeconds,
  type PublicMatchState,
} from "../match/MatchEngine.js";
import { SeededRandomSource } from "../match/random.js";
import {
  CardDiscardedEventState,
  ClaimAwardState,
  ClaimsResolvedEventState,
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
} as const satisfies Record<string, RoomError>;

const POINT_CONTEST_DISPLAY_MILLISECONDS = 900;
const CLAIM_REVEAL_DISPLAY_MILLISECONDS = 900;

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
  private claimDeadlineTimer: { clear(): void } | null = null;
  private claimRevealTimer: { clear(): void } | null = null;
  private discardDeadlineTimer: { clear(): void } | null = null;
  private startInProgress = false;

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
    const waitingMetadata = { ...this.metadata };
    const waitingPrivate = this.matchmakingPrivate;
    try {
      const matchEngine = new MatchEngine(new SeededRandomSource(
        randomInt(1, 0x1_0000_0000),
      ));
      matchEngine.start(
        this.state.seats.map((seat) => ({
          seatIndex: seat.seatIndex,
          participantId: seat.participantId,
          nickname: seat.nickname,
          bot: seat.bot,
        })),
        {
          deckMode: this.state.deckMode,
          actionDeadlineSeconds: this.state.actionDeadlineSeconds,
        },
      );
      const publicMatchState = matchEngine.view(0).publicState;

      try {
        await this.setMatchmaking({
          metadata: { ...waitingMetadata, status: "started" },
          private: true,
          locked: true,
        });
      } catch {
        await this.setMetadata(waitingMetadata, false);
        await this.setPrivate(waitingPrivate, false);
        this.sendRoomError(client, ROOM_ERRORS.startFailed);
        return;
      }

      this.matchEngine = matchEngine;
      this.applyPublicMatchState(publicMatchState);
      this.state.status = "started";
      this.clock.setTimeout(() => {
        this.completePointContest(matchEngine);
      }, POINT_CONTEST_DISPLAY_MILLISECONDS);
    } finally {
      this.startInProgress = false;
    }
  }

  private completePointContest(matchEngine: MatchEngine): void {
    if (
      this.matchEngine !== matchEngine
      || this.state.status !== "started"
      || this.state.phase !== "point_contest"
    ) {
      return;
    }
    matchEngine.completePointContest();
    this.applyPublicMatchState(matchEngine.view(0).publicState);
    this.sendPrivateMatchStates();
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
    ) {
      this.sendRoomError(client, ROOM_ERRORS.invalidPlayPayload);
      return;
    }
    const seatIndex = client.userData?.seatIndex;
    if (typeof seatIndex !== "number") {
      throw new Error("cannot play cards without an occupied seat");
    }

    try {
      this.matchEngine.playCards(seatIndex, message.cardIds);
    } catch (error) {
      if (error instanceof MatchCommandError) {
        this.sendRoomError(client, { code: error.code, message: error.message });
        return;
      }
      throw error;
    }
    this.applyPublicMatchState(this.matchEngine.view(seatIndex).publicState);
    this.sendPrivateMatchState(client);
    this.scheduleClaimDeadline(this.matchEngine);
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
    ) {
      this.sendRoomError(client, ROOM_ERRORS.invalidClaimPayload);
      return;
    }
    const seatIndex = client.userData?.seatIndex;
    if (typeof seatIndex !== "number") {
      this.sendRoomError(client, ROOM_ERRORS.noSeat);
      return;
    }
    const cardId = message.cardId as string | null;

    try {
      this.matchEngine.commitClaim(seatIndex, cardId);
    } catch (error) {
      if (error instanceof MatchCommandError) {
        this.sendRoomError(client, { code: error.code, message: error.message });
        return;
      }
      throw error;
    }
    const publicState = this.matchEngine.view(seatIndex).publicState;
    this.applyPublicMatchState(publicState);
    if (publicState.phase === "claim_commit") {
      this.sendPrivateMatchState(client);
    } else {
      this.clearClaimDeadline();
      this.sendPrivateMatchStates();
      this.scheduleClaimReveal(this.matchEngine);
    }
  }

  private scheduleClaimDeadline(matchEngine: MatchEngine): void {
    this.clearClaimDeadline();
    const timer = this.clock.setTimeout(() => {
      if (this.claimDeadlineTimer !== timer) {
        return;
      }
      this.claimDeadlineTimer = null;
      if (
        this.matchEngine !== matchEngine
        || this.state.phase !== "claim_commit"
      ) {
        return;
      }

      matchEngine.resolveClaimsAtDeadline();
      this.applyPublicMatchState(matchEngine.view(0).publicState);
      this.sendPrivateMatchStates();
      this.scheduleClaimReveal(matchEngine);
    }, this.state.actionDeadlineSeconds * 1000);
    this.claimDeadlineTimer = timer;
  }

  private clearClaimDeadline(): void {
    this.claimDeadlineTimer?.clear();
    this.claimDeadlineTimer = null;
  }

  private scheduleClaimReveal(matchEngine: MatchEngine): void {
    this.clearClaimReveal();
    const timer = this.clock.setTimeout(() => {
      if (this.claimRevealTimer !== timer) {
        return;
      }
      this.claimRevealTimer = null;
      if (
        this.matchEngine !== matchEngine
        || this.state.phase !== "claim_reveal"
      ) {
        return;
      }

      matchEngine.completeClaimReveal();
      const publicState = matchEngine.view(0).publicState;
      this.applyPublicMatchState(publicState);
      this.sendPrivateMatchStates();
      if (publicState.phase === "award_discard") {
        this.scheduleDiscardDeadline(matchEngine);
      }
    }, CLAIM_REVEAL_DISPLAY_MILLISECONDS);
    this.claimRevealTimer = timer;
  }

  private clearClaimReveal(): void {
    this.claimRevealTimer?.clear();
    this.claimRevealTimer = null;
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
    ) {
      this.sendRoomError(client, ROOM_ERRORS.invalidDiscardPayload);
      return;
    }
    const seatIndex = client.userData?.seatIndex;
    if (typeof seatIndex !== "number") {
      this.sendRoomError(client, ROOM_ERRORS.noSeat);
      return;
    }

    try {
      this.matchEngine.discardCard(seatIndex, message.cardId);
    } catch (error) {
      if (error instanceof MatchCommandError) {
        this.sendRoomError(client, { code: error.code, message: error.message });
        return;
      }
      throw error;
    }
    const publicState = this.matchEngine.view(seatIndex).publicState;
    this.applyPublicMatchState(publicState);
    this.sendPrivateMatchStates();
    if (publicState.phase !== "award_discard") {
      this.clearDiscardDeadline();
    }
  }

  private scheduleDiscardDeadline(matchEngine: MatchEngine): void {
    this.clearDiscardDeadline();
    const timer = this.clock.setTimeout(() => {
      if (this.discardDeadlineTimer !== timer) {
        return;
      }
      this.discardDeadlineTimer = null;
      if (
        this.matchEngine !== matchEngine
        || this.state.phase !== "award_discard"
      ) {
        return;
      }

      matchEngine.resolveDiscardAtDeadline();
      this.applyPublicMatchState(matchEngine.view(0).publicState);
      this.sendPrivateMatchStates();
    }, this.state.actionDeadlineSeconds * 1000);
    this.discardDeadlineTimer = timer;
  }

  private clearDiscardDeadline(): void {
    this.discardDeadlineTimer?.clear();
    this.discardDeadlineTimer = null;
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
    this.state.sealedCards.clear();
    for (const card of publicState.sealedCards) {
      this.state.sealedCards.push(new PublicCardState(card));
    }
    this.state.pendingDiscardSeatIndexes.clear();
    this.state.pendingDiscardSeatIndexes.push(...publicState.pendingDiscardSeatIndexes);
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
    for (const event of publicState.events) {
      if (event.type === "point_contest_round") {
        this.state.contestRounds.push(new PointContestRoundState(event));
      } else if (event.type === "cards_played") {
        this.state.playEvents.push(new PlayEventState(event));
      } else if (event.type === "claims_resolved") {
        this.state.claimEvents.push(new ClaimsResolvedEventState(event));
      } else {
        this.state.discardEvents.push(new CardDiscardedEventState(event));
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
    participantClient.send("match_private_state", privateState);
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
