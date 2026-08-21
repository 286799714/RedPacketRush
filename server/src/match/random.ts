export interface RandomSource {
  nextInt(maxExclusive: number): number;
}

export class SeededRandomSource implements RandomSource {
  private state: number;

  public constructor(seed: number) {
    if (!Number.isSafeInteger(seed)) {
      throw new Error("seed must be a safe integer");
    }
    this.state = seed >>> 0;
    if (this.state === 0) {
      this.state = 0x6d2b79f5;
    }
  }

  public nextInt(maxExclusive: number): number {
    if (!Number.isSafeInteger(maxExclusive) || maxExclusive <= 0) {
      throw new Error("maxExclusive must be a positive safe integer");
    }

    let next = this.state;
    next ^= next << 13;
    next ^= next >>> 17;
    next ^= next << 5;
    this.state = next >>> 0;
    return this.state % maxExclusive;
  }
}
