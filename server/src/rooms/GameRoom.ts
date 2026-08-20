import { Room } from "colyseus";

export const DECK_MODES = ["one", "two"] as const;
export type DeckMode = (typeof DECK_MODES)[number];

export const ACTION_DEADLINES = [15, 30, 60] as const;
export type ActionDeadlineSeconds = (typeof ACTION_DEADLINES)[number];

export type GameRoomStatus = "waiting" | "started";

export interface GameRoomMetadata {
  displayName: string;
  deckMode: DeckMode;
  actionDeadlineSeconds: ActionDeadlineSeconds;
  status: GameRoomStatus;
}

export interface GameRoomOptions {
  displayName?: unknown;
  deckMode?: unknown;
  actionDeadlineSeconds?: unknown;
}

type RecordLike = Record<string, unknown>;

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

export function parseGameRoomOptions(options: unknown): GameRoomMetadata {
  if (!isRecordLike(options)) {
    throw new Error("game room options must be an object");
  }

  return {
    displayName: parseDisplayName(options.displayName),
    deckMode: parseDeckMode(options.deckMode),
    actionDeadlineSeconds: parseActionDeadline(options.actionDeadlineSeconds),
    status: "waiting",
  };
}

export class GameRoom extends Room<{ metadata: GameRoomMetadata }> {
  public maxClients = 4;

  public onCreate(options: GameRoomOptions): void {
    this.metadata = parseGameRoomOptions(options);
  }
}
