export async function nui<T>(route: string, payload: unknown = {}): Promise<T | null> {
  if (typeof window.GetParentResourceName !== 'function') return null
  const response = await fetch(`https://${window.GetParentResourceName()}/${route}`, {
    method: 'POST',
    headers: { 'Content-Type': 'application/json; charset=UTF-8' },
    body: JSON.stringify(payload),
  })
  return response.json() as Promise<T>
}

declare global {
  interface Window {
    GetParentResourceName?: () => string
  }
}
