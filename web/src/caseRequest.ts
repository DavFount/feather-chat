export class CaseRequestGate {
  private active: { id: string; operation: string } | null = null
  begin(id: string, operation: string) { this.active = { id, operation } }
  accepts(id: string, operation: string) {
    return this.active?.id === id && this.active.operation === operation
  }
  finish(id: string, operation: string) {
    if (!this.accepts(id, operation)) return false
    this.active = null
    return true
  }
  invalidate() { this.active = null }
}

export function caseUpdateAction(selected: string, updated: string, pending: boolean) {
  if (selected && selected !== updated) return 'ignore'
  if (pending) return 'queue'
  return selected ? 'history' : 'list'
}
