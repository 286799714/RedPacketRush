export function combinationsOfThree<T>(items: readonly T[]): T[][] {
  const combinations: T[][] = [];
  for (let first = 0; first < items.length - 2; first += 1) {
    for (let second = first + 1; second < items.length - 1; second += 1) {
      for (let third = second + 1; third < items.length; third += 1) {
        combinations.push([items[first], items[second], items[third]]);
      }
    }
  }
  return combinations;
}
