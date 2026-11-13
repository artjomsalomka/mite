export function updatedStationProgress(
  orders: number[], previous: number[], stationOrder: unknown, completed: unknown,
): number[] {
  if (!Number.isInteger(stationOrder) || !orders.includes(stationOrder as number) || typeof completed !== "boolean") {
    throw new Error("Ungültige Station.");
  }
  const selected = stationOrder as number;
  const clean = new Set(previous.filter((order) => orders.includes(order)));
  if (completed) clean.add(selected);
  else clean.delete(selected);
  return [...clean].sort((a, b) => a - b);
}
