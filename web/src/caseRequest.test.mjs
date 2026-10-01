import test from 'node:test'
import assert from 'node:assert/strict'
import { CaseRequestGate, caseUpdateAction } from './caseRequest.ts'

test('current matching response accepted', () => {
  const gate = new CaseRequestGate(); gate.begin('A', 'history')
  assert.equal(gate.finish('A', 'history'), true)
})
test('older conversation response rejected', () => {
  const gate = new CaseRequestGate(); gate.begin('A', 'history'); gate.begin('B', 'history')
  assert.equal(gate.finish('A', 'history'), false)
  assert.equal(gate.finish('B', 'history'), true)
})
test('reply cannot complete pending history', () => {
  const gate = new CaseRequestGate(); gate.begin('B', 'history')
  assert.equal(gate.finish('B', 'reply'), false)
})
test('duplicate response ignored', () => {
  const gate = new CaseRequestGate(); gate.begin('A', 'reply')
  assert.equal(gate.finish('A', 'reply'), true)
  assert.equal(gate.finish('A', 'reply'), false)
})
test('unmounted panel rejects late response', () => {
  const gate = new CaseRequestGate(); gate.begin('A', 'reply'); gate.invalidate()
  assert.equal(gate.finish('A', 'reply'), false)
})
test('old timeout cannot invalidate newer request', () => {
  const gate = new CaseRequestGate(); gate.begin('A', 'list'); gate.begin('B', 'reply')
  assert.equal(gate.finish('A', 'list'), false)
  assert.equal(gate.accepts('B', 'reply'), true)
})

test('session reset allows new discovery but rejects prior history', () => {
  const gate = new CaseRequestGate(); gate.begin('old-session', 'history'); gate.invalidate()
  gate.begin('new-session', 'list')
  assert.equal(gate.finish('old-session', 'history'), false)
  assert.equal(gate.finish('new-session', 'list'), true)
})
test('dependency restart discards pending reply acknowledgment', () => {
  const gate = new CaseRequestGate(); gate.begin('before-restart', 'reply'); gate.invalidate()
  gate.begin('after-restart', 'history')
  assert.equal(gate.finish('before-restart', 'reply'), false)
  assert.equal(gate.accepts('after-restart', 'history'), true)
})
test('committed update refreshes the active conversation automatically', () => {
  assert.equal(caseUpdateAction('case-A', 'case-A', false), 'history')
})
test('background conversation does not replace active history', () => {
  assert.equal(caseUpdateAction('case-A', 'case-B', false), 'ignore')
})
test('incoming update is queued while sending and list updates need no click', () => {
  assert.equal(caseUpdateAction('case-A', 'case-A', true), 'queue')
  assert.equal(caseUpdateAction('', 'case-A', false), 'list')
})
