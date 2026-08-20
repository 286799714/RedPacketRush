import { LobbyRoom, matchMaker } from "colyseus";
import { subscribeLobby } from "@colyseus/core/matchmaker/Lobby";

import type { GameRoomMetadata } from "./GameRoom.js";

interface LobbyFilter {
  name?: string;
  metadata?: Record<string, unknown>;
}

export class LiveLobby extends LobbyRoom<GameRoomMetadata> {
  public async onCreate(): Promise<void> {
    this["_listing"].unlisted = true;

    this.unsubscribeLobby = await subscribeLobby((roomId, listing) => {
      this.updateListing(roomId, listing);
    });

    const initialRooms = await matchMaker.query({
      private: false,
      unlisted: false,
    });
    this.rooms = initialRooms.map((room) => this.cloneListing(room));
  }

  protected filterItemsForClient(
    options: { filter?: LobbyFilter },
  ): LiveLobby["rooms"] {
    return this.rooms.filter((room) => (
      this.filterItemForClient(room, options.filter)
    ));
  }

  protected filterItemForClient(
    room: LiveLobby["rooms"][number],
    filter?: LobbyFilter,
  ): boolean {
    const participantCount = room.metadata?.participantCount ?? room.clients;
    const isJoinableGame = (
      room.name === "game"
      && room.locked === false
      && room.private === false
      && participantCount < room.maxClients
      && room.metadata?.status === "waiting"
    );

    return isJoinableGame && super.filterItemForClient(room, filter);
  }

  private updateListing(
    roomId: string,
    listing: LiveLobby["rooms"][number] | null,
  ): void {
    const roomIndex = this.rooms.findIndex((room) => room.roomId === roomId);
    const previous = roomIndex === -1 ? null : this.rooms[roomIndex];
    const next = listing === null ? null : this.cloneListing(listing);

    if (next === null) {
      if (roomIndex !== -1) {
        this.rooms.splice(roomIndex, 1);
      }
    } else if (roomIndex === -1) {
      this.rooms.push(next);
    } else {
      this.rooms[roomIndex] = next;
    }

    for (const client of this.clients) {
      const clientOptions = this.clientOptions[client.sessionId];
      if (!clientOptions) {
        continue;
      }

      const wasVisible = previous !== null
        && this.filterItemForClient(previous, clientOptions.filter);
      const isVisible = next !== null
        && this.filterItemForClient(next, clientOptions.filter);

      if (wasVisible && !isVisible) {
        client.send("-", roomId);
      } else if (isVisible) {
        client.send("+", [roomId, next]);
      }
    }
  }

  private cloneListing(
    listing: LiveLobby["rooms"][number],
  ): LiveLobby["rooms"][number] {
    return {
      ...listing,
      metadata: listing.metadata === undefined
        ? listing.metadata
        : { ...listing.metadata },
    };
  }
}
