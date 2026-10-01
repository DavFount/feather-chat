export function ignoreAvailability(current, value) {
  return typeof value === 'boolean' ? value : current
}
