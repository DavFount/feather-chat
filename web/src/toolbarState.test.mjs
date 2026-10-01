import test from 'node:test'
import assert from 'node:assert/strict'
import { ignoreAvailability } from './toolbarState.mjs'
test('opening recovers enabled ignore control without a bootstrap', () => {
  assert.equal(ignoreAvailability(false, true), true)
})
test('owner-disabled ignore remains disabled', () => {
  assert.equal(ignoreAvailability(true, false), false)
})
test('missing or malformed updates retain the current policy', () => {
  for (const value of [undefined, null, 'true', 1]) {
    assert.equal(ignoreAvailability(true, value), true)
    assert.equal(ignoreAvailability(false, value), false)
  }
})
