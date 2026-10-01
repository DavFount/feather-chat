import test from 'node:test'
import assert from 'node:assert/strict'
import { resolve, render } from './localeCore.mjs'
import { readFileSync, readdirSync } from 'node:fs'

test('single Lua catalog resolves all literal Lua and NUI references', () => {
  const root = new URL('../../', import.meta.url)
  const lua = readFileSync(new URL('translations/en_us.lua', root), 'utf8')
  const english = Object.fromEntries([...lua.matchAll(/\['feather_chat_([^']+)'\]\s*=\s*("(?:\\.|[^"\\])*")/g)]
    .map((match) => [match[1], JSON.parse(match[2])]))
  assert.ok(Object.keys(english).length > 150)
  for (const folder of ['client', 'server', 'shared', 'web/src']) {
    for (const file of readdirSync(new URL(folder + '/', root))) {
      if (!/\.(lua|vue)$/.test(file)) continue
      const text = readFileSync(new URL(folder + '/' + file, root), 'utf8')
      for (const match of text.matchAll(/(?:ChatLocale\.(?:T|Format)|\bt)\('([^']+)'\s*(?:,|\))/g)) {
        assert.ok(Object.hasOwn(english, match[1]) || match[1] === 'missing.smoke', `${file}: ${match[1]}`)
      }
    }
  }
})

test('partial locale merges with English fallback', () => {
  assert.deepEqual(resolve({ a: 'English', b: 'Fallback' }, { a: 'Translated' }),
    { a: 'Translated', b: 'Fallback' })
})
test('invalid and empty translations fall back', () => {
  for (const value of [null, '', false, 12, {}]) {
    assert.equal(resolve({ a: 'English' }, { a: value }).a, 'English')
  }
})
test('missing catalog and unknown key remain readable', () => {
  assert.equal(render(resolve({ a: 'English' }, null), 'a'), 'English')
  assert.equal(render({}, 'unknown'), 'unknown')
})
test('interpolation preserves literal text and missing placeholders', () => {
  assert.equal(render({ a: '{name} {count}' }, 'a', { name: '$& <b>100%</b>' }), '$& <b>100%</b> {count}')
})
test('resolving does not mutate catalogs', () => {
  const base = { a: 'English' }; const override = { a: 'Translated' }
  resolve(base, override).a = 'Changed'
  assert.equal(base.a, 'English'); assert.equal(override.a, 'Translated')
})
