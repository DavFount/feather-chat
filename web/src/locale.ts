import { reactive } from 'vue'
import { render } from './localeCore.mjs'

// Lua resolves Core's saved player language and English fallback. NUI only
// renders that bundle; translations/*.lua is the sole translation catalog.
const dictionary = reactive<Record<string, string>>({})
export function setLocale(value: unknown) {
  if (!value || typeof value !== 'object' || Array.isArray(value)) return
  for (const key of Object.keys(dictionary)) delete dictionary[key]
  for (const [key, text] of Object.entries(value)) {
    if (typeof text === 'string' && key !== '__proto__' && key !== 'constructor' && key !== 'prototype') dictionary[key] = text
  }
}
export function t(key: string, variables?: Record<string, unknown>): string {
  return render(dictionary, key, variables)
}
