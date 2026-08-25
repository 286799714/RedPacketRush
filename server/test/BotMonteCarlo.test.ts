import assert from "assert";

import {
  chooseBotCommand,
  type BotStrategy,
} from "../src/match/botPolicy.js";
import {
  MatchEngine,
  type MatchParticipant,
} from "../src/match/MatchEngine.js";
import { SeededRandomSource } from "../src/match/random.js";

const MATCH_COUNT = 1_000;
const SEAT_INDEXES = [0, 1, 2, 3] as const;
const CONSERVATIVE_SEAT_PAIRS = [
  [0, 1],
  [1, 2],
  [2, 3],
  [3, 0],
  [0, 2],
  [1, 3],
] as const;
const CONSERVATIVE_BOT_IDS = ["conservative-a", "conservative-b"] as const;
type ConservativeBotId = (typeof CONSERVATIVE_BOT_IDS)[number];
type AggressiveBotId = "aggressive-a" | "aggressive-b";

interface ConservativeBotDefinition {
  readonly id: ConservativeBotId;
  readonly nickname: string;
  readonly strategy: "conservative";
}

interface AggressiveBotDefinition {
  readonly id: AggressiveBotId;
  readonly nickname: string;
  readonly strategy: "aggressive";
}

type BotDefinition = ConservativeBotDefinition | AggressiveBotDefinition;

const CONSERVATIVE_BOTS: readonly ConservativeBotDefinition[] = [
  { id: "conservative-a", nickname: "Conservative Bot A", strategy: "conservative" },
  { id: "conservative-b", nickname: "Conservative Bot B", strategy: "conservative" },
];
const AGGRESSIVE_BOTS: readonly AggressiveBotDefinition[] = [
  { id: "aggressive-a", nickname: "Aggressive Bot A", strategy: "aggressive" },
  { id: "aggressive-b", nickname: "Aggressive Bot B", strategy: "aggressive" },
];

interface ClaimCounts {
  opportunities: number;
  participations: number;
}

interface MatchReport {
  readonly winnerSeatIndexes: readonly number[];
  readonly conservativeClaims: Readonly<Record<ConservativeBotId, ClaimCounts>>;
}

function emptyConservativeClaimCounts(): Record<ConservativeBotId, ClaimCounts> {
  return {
    "conservative-a": { opportunities: 0, participations: 0 },
    "conservative-b": { opportunities: 0, participations: 0 },
  };
}

function averageConservativeClaimProbability(
  claims: Readonly<Record<ConservativeBotId, ClaimCounts>>,
): number {
  const individualProbabilities = CONSERVATIVE_BOT_IDS.map((botId) => {
    const counts = claims[botId];
    if (counts.opportunities <= 0) {
      throw new Error(`${botId} requires at least one Claim opportunity`);
    }
    return counts.participations / counts.opportunities;
  });
  return individualProbabilities.reduce((sum, probability) => sum + probability, 0)
    / individualProbabilities.length;
}

function botsForMatch(matchIndex: number): readonly BotDefinition[] {
  const conservativeSeats = CONSERVATIVE_SEAT_PAIRS[
    matchIndex % CONSERVATIVE_SEAT_PAIRS.length
  ];
  const conservativeSeatSet = new Set<number>(conservativeSeats);
  const aggressiveSeats = SEAT_INDEXES.filter((seatIndex) => (
    !conservativeSeatSet.has(seatIndex)
  ));
  const swapIdentities = (
    Math.floor(matchIndex / CONSERVATIVE_SEAT_PAIRS.length) % 2 === 1
  );
  const conservativeBots = swapIdentities
    ? [CONSERVATIVE_BOTS[1], CONSERVATIVE_BOTS[0]]
    : CONSERVATIVE_BOTS;
  const aggressiveBots = swapIdentities
    ? [AGGRESSIVE_BOTS[1], AGGRESSIVE_BOTS[0]]
    : AGGRESSIVE_BOTS;
  const botsBySeat = new Array<BotDefinition>(SEAT_INDEXES.length);
  conservativeSeats.forEach((seatIndex, index) => {
    botsBySeat[seatIndex] = conservativeBots[index];
  });
  aggressiveSeats.forEach((seatIndex, index) => {
    botsBySeat[seatIndex] = aggressiveBots[index];
  });
  if (SEAT_INDEXES.some((seatIndex) => botsBySeat[seatIndex] === undefined)) {
    throw new Error("every Monte Carlo seat requires one Bot identity");
  }
  return botsBySeat;
}

function requireBotCommand(
  engine: MatchEngine,
  seatIndex: number,
  strategy: BotStrategy,
) {
  const command = chooseBotCommand(engine.view(seatIndex), strategy);
  if (command === null) {
    throw new Error(`seat ${seatIndex} has no Bot command`);
  }
  return command;
}

function playMatch(seed: number, botsBySeat: readonly BotDefinition[]): MatchReport {
  const engine = new MatchEngine(new SeededRandomSource(seed));
  const participants: readonly MatchParticipant[] = botsBySeat.map((bot, seatIndex) => ({
    seatIndex,
    participantId: bot.id,
    nickname: bot.nickname,
    bot: true,
  }));
  engine.start(participants, {
    deckMode: "one",
    actionDeadlineSeconds: 15,
  });
  engine.completePointContest();
  const conservativeClaims = emptyConservativeClaimCounts();

  for (let step = 0; step < 250; step += 1) {
    const publicState = engine.view(0).publicState;
    if (publicState.phase === "actor_play") {
      const seatIndex = publicState.actorSeatIndex;
      const command = requireBotCommand(engine, seatIndex, botsBySeat[seatIndex].strategy);
      if (command.type !== "play_cards") {
        throw new Error(`Actor seat ${seatIndex} selected ${command.type}`);
      }
      engine.playCards(seatIndex, command.cardIds);
      continue;
    }
    if (publicState.phase === "play_reveal") {
      engine.completePlayReveal();
      continue;
    }
    if (publicState.phase === "claim_commit") {
      for (const seatIndex of SEAT_INDEXES) {
        if (seatIndex === publicState.actorSeatIndex) {
          continue;
        }
        const bot = botsBySeat[seatIndex];
        const command = requireBotCommand(engine, seatIndex, bot.strategy);
        if (command.type !== "claim") {
          throw new Error(`Claimant seat ${seatIndex} selected ${command.type}`);
        }
        if (bot.strategy === "conservative") {
          conservativeClaims[bot.id].opportunities += 1;
          if (command.cardId !== null) {
            conservativeClaims[bot.id].participations += 1;
          }
        }
        engine.commitClaim(seatIndex, command.cardId);
      }
      continue;
    }
    if (publicState.phase === "claim_reveal") {
      engine.completeClaimReveal();
      continue;
    }
    if (publicState.phase === "award_discard") {
      for (const seatIndex of publicState.pendingDiscardSeatIndexes) {
        const command = requireBotCommand(engine, seatIndex, botsBySeat[seatIndex].strategy);
        if (command.type !== "discard") {
          throw new Error(`Award recipient seat ${seatIndex} selected ${command.type}`);
        }
        engine.discardCard(seatIndex, command.cardId, command.turnNumber);
      }
      continue;
    }
    if (publicState.phase === "discard_reveal") {
      engine.completeDiscardReveal();
      continue;
    }
    if (publicState.phase === "final_reveal") {
      assert.strictEqual(publicState.turnNumber, 10);
      assert.ok(publicState.winnerSeatIndexes.length > 0);
      engine.completeFinalReveal();
      continue;
    }
    if (publicState.phase === "finished") {
      return {
        winnerSeatIndexes: publicState.winnerSeatIndexes,
        conservativeClaims,
      };
    }
    throw new Error(`unexpected Monte Carlo Match phase: ${publicState.phase}`);
  }

  throw new Error(`seed ${seed} did not finish within 250 phase steps`);
}

describe("Bot strategy Monte Carlo", () => {
  it("averages each conservative Bot's Claim probability instead of pooling counts", () => {
    const claims: Record<ConservativeBotId, ClaimCounts> = {
      "conservative-a": { opportunities: 1, participations: 1 },
      "conservative-b": { opportunities: 3, participations: 0 },
    };

    assert.strictEqual(averageConservativeClaimProbability(claims), 0.5);
    assert.notStrictEqual(averageConservativeClaimProbability(claims), 0.25);
  });

  it("reports win rates and conservative Claim participation over 1,000 Matches", () => {
    const winCredits: Record<BotStrategy, number> = {
      conservative: 0,
      aggressive: 0,
    };
    const conservativeClaims = emptyConservativeClaimCounts();
    const conservativeSeatVisits: Record<ConservativeBotId, number[]> = {
      "conservative-a": [0, 0, 0, 0],
      "conservative-b": [0, 0, 0, 0],
    };

    for (let matchIndex = 0; matchIndex < MATCH_COUNT; matchIndex += 1) {
      const botsBySeat = botsForMatch(matchIndex);
      assert.strictEqual(new Set(botsBySeat.map((bot) => bot.id)).size, 4);
      assert.strictEqual(botsBySeat.filter((bot) => bot.strategy === "conservative").length, 2);
      assert.strictEqual(botsBySeat.filter((bot) => bot.strategy === "aggressive").length, 2);
      botsBySeat.forEach((bot, seatIndex) => {
        if (bot.strategy === "conservative") {
          conservativeSeatVisits[bot.id][seatIndex] += 1;
        }
      });
      const report = playMatch(matchIndex + 1, botsBySeat);
      for (const botId of CONSERVATIVE_BOT_IDS) {
        conservativeClaims[botId].opportunities += report.conservativeClaims[botId].opportunities;
        conservativeClaims[botId].participations += report.conservativeClaims[botId].participations;
      }
      const sharedCredit = 1 / report.winnerSeatIndexes.length;
      for (const winnerSeatIndex of report.winnerSeatIndexes) {
        winCredits[botsBySeat[winnerSeatIndex].strategy] += sharedCredit;
      }
    }

    const conservativeRate = winCredits.conservative / MATCH_COUNT;
    const aggressiveRate = winCredits.aggressive / MATCH_COUNT;
    assert.ok(Math.abs(winCredits.conservative + winCredits.aggressive - MATCH_COUNT) < 1e-9);
    assert.ok(conservativeRate >= 0 && conservativeRate <= 1);
    assert.ok(aggressiveRate >= 0 && aggressiveRate <= 1);
    assert.ok(Math.abs(conservativeRate + aggressiveRate - 1) < 1e-12);
    for (const botId of CONSERVATIVE_BOT_IDS) {
      assert.ok(conservativeClaims[botId].opportunities > 0);
      assert.ok(conservativeClaims[botId].participations > 0);
      assert.ok(
        conservativeClaims[botId].participations <= conservativeClaims[botId].opportunities,
      );
      assert.deepStrictEqual(
        conservativeSeatVisits[botId],
        SEAT_INDEXES.map(() => MATCH_COUNT / SEAT_INDEXES.length),
      );
    }
    const conservativeBotAProbability = (
      conservativeClaims["conservative-a"].participations
      / conservativeClaims["conservative-a"].opportunities
    );
    const conservativeBotBProbability = (
      conservativeClaims["conservative-b"].participations
      / conservativeClaims["conservative-b"].opportunities
    );
    const averageClaimProbability = averageConservativeClaimProbability(conservativeClaims);

    console.info(
      `Bot Monte Carlo (${MATCH_COUNT} Matches; co-winners split equally): `
      + `conservative ${(conservativeRate * 100).toFixed(2)}%, `
      + `aggressive ${(aggressiveRate * 100).toFixed(2)}%`,
    );
    console.info(
      `Conservative Bot A Claim participation probability: `
      + `${(conservativeBotAProbability * 100).toFixed(4)}% `
      + `(${conservativeClaims["conservative-a"].participations}`
      + `/${conservativeClaims["conservative-a"].opportunities} opportunities)`,
    );
    console.info(
      `Conservative Bot B Claim participation probability: `
      + `${(conservativeBotBProbability * 100).toFixed(4)}% `
      + `(${conservativeClaims["conservative-b"].participations}`
      + `/${conservativeClaims["conservative-b"].opportunities} opportunities)`,
    );
    console.info(
      `Average conservative Bot Claim participation probability: `
      + `${(averageClaimProbability * 100).toFixed(4)}%`,
    );
  });
});
