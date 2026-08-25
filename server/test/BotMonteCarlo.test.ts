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
const PARTICIPANTS: readonly MatchParticipant[] = SEAT_INDEXES.map((seatIndex) => ({
  seatIndex,
  participantId: `bot-${seatIndex}`,
  nickname: `Bot ${seatIndex + 1}`,
  bot: true,
}));

interface MatchReport {
  readonly winnerSeatIndexes: readonly number[];
  readonly conservativeClaimOpportunities: number;
  readonly conservativeClaimParticipations: number;
}

function strategiesForMatch(matchIndex: number): readonly BotStrategy[] {
  const conservativeSeats = new Set(
    CONSERVATIVE_SEAT_PAIRS[matchIndex % CONSERVATIVE_SEAT_PAIRS.length],
  );
  return SEAT_INDEXES.map((seatIndex) => (
    conservativeSeats.has(seatIndex) ? "conservative" : "aggressive"
  ));
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

function playMatch(seed: number, strategies: readonly BotStrategy[]): MatchReport {
  const engine = new MatchEngine(new SeededRandomSource(seed));
  engine.start(PARTICIPANTS, {
    deckMode: "one",
    actionDeadlineSeconds: 15,
  });
  engine.completePointContest();
  let conservativeClaimOpportunities = 0;
  let conservativeClaimParticipations = 0;

  for (let step = 0; step < 250; step += 1) {
    const publicState = engine.view(0).publicState;
    if (publicState.phase === "actor_play") {
      const seatIndex = publicState.actorSeatIndex;
      const command = requireBotCommand(engine, seatIndex, strategies[seatIndex]);
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
        const command = requireBotCommand(engine, seatIndex, strategies[seatIndex]);
        if (command.type !== "claim") {
          throw new Error(`Claimant seat ${seatIndex} selected ${command.type}`);
        }
        if (strategies[seatIndex] === "conservative") {
          conservativeClaimOpportunities += 1;
          if (command.cardId !== null) {
            conservativeClaimParticipations += 1;
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
        const command = requireBotCommand(engine, seatIndex, strategies[seatIndex]);
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
        conservativeClaimOpportunities,
        conservativeClaimParticipations,
      };
    }
    throw new Error(`unexpected Monte Carlo Match phase: ${publicState.phase}`);
  }

  throw new Error(`seed ${seed} did not finish within 250 phase steps`);
}

describe("Bot strategy Monte Carlo", () => {
  it("reports win rates and conservative Claim participation over 1,000 Matches", () => {
    const winCredits: Record<BotStrategy, number> = {
      conservative: 0,
      aggressive: 0,
    };
    let conservativeClaimOpportunities = 0;
    let conservativeClaimParticipations = 0;

    for (let matchIndex = 0; matchIndex < MATCH_COUNT; matchIndex += 1) {
      const strategies = strategiesForMatch(matchIndex);
      assert.strictEqual(strategies.filter((strategy) => strategy === "conservative").length, 2);
      assert.strictEqual(strategies.filter((strategy) => strategy === "aggressive").length, 2);
      const report = playMatch(matchIndex + 1, strategies);
      conservativeClaimOpportunities += report.conservativeClaimOpportunities;
      conservativeClaimParticipations += report.conservativeClaimParticipations;
      const sharedCredit = 1 / report.winnerSeatIndexes.length;
      for (const winnerSeatIndex of report.winnerSeatIndexes) {
        winCredits[strategies[winnerSeatIndex]] += sharedCredit;
      }
    }

    const conservativeRate = winCredits.conservative / MATCH_COUNT;
    const aggressiveRate = winCredits.aggressive / MATCH_COUNT;
    assert.ok(Math.abs(winCredits.conservative + winCredits.aggressive - MATCH_COUNT) < 1e-9);
    assert.ok(conservativeRate >= 0 && conservativeRate <= 1);
    assert.ok(aggressiveRate >= 0 && aggressiveRate <= 1);
    assert.ok(Math.abs(conservativeRate + aggressiveRate - 1) < 1e-12);
    assert.ok(conservativeClaimOpportunities > 0);
    assert.ok(conservativeClaimParticipations > 0);
    assert.ok(conservativeClaimParticipations <= conservativeClaimOpportunities);
    const conservativeClaimParticipationProbability = (
      conservativeClaimParticipations / conservativeClaimOpportunities
    );

    console.info(
      `Bot Monte Carlo (${MATCH_COUNT} Matches; co-winners split equally): `
      + `conservative ${(conservativeRate * 100).toFixed(2)}%, `
      + `aggressive ${(aggressiveRate * 100).toFixed(2)}%`,
    );
    console.info(
      `Conservative Bot Claim participation probability: `
      + `${(conservativeClaimParticipationProbability * 100).toFixed(2)}% `
      + `(${conservativeClaimParticipations}/${conservativeClaimOpportunities} opportunities)`,
    );
  });
});
