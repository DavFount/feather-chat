<script setup lang="ts">
import { computed, nextTick, onBeforeUnmount, onMounted, reactive, ref } from 'vue'
import { nui } from './api'

type Layout = {
  anchor: string
  widthVw: number
  maxHeightVh: number
  fadeDelayMs: number
  idleOpacity: number
  density: string
  fontScale: number
  reducedMotion: boolean
}

type ChatMessage = {
  messageId: string
  channelKey: string
  channelLabel?: string
  kind: string
  author: { characterId: string; displayName: string }
  body: { text: string; format: string }
  presentation: { variant: string; accentToken: string }
  createdAt: string
  sequence: number
}

type SubmitResult = { ok: boolean; message?: string }
type Channel = { channelKey: string; label: string }
type Suggestion = { key: string; trigger: string; description: string; channelKey?: string }

const open = ref(false)
const visible = ref(true)
const feedVisible = ref(false)
const input = ref('')
const selectedFilter = ref('all')
const selectedChannel = ref('local.say')
const messages = ref<ChatMessage[]>([])
const error = ref('')
const submitting = ref(false)
const channels = ref<Channel[]>([
  { channelKey: 'local.say', label: 'Say' },
  { channelKey: 'local.whisper', label: 'Whisper' },
  { channelKey: 'local.shout', label: 'Shout' },
  { channelKey: 'roleplay.me', label: '/me' },
  { channelKey: 'roleplay.do', label: '/do' },
])
const suggestions = ref<Suggestion[]>([])
let feedTimer: number | undefined
let errorTimer: number | undefined
const composer = ref<HTMLTextAreaElement | null>(null)
const state = reactive({
  theme: 'feather.default',
  layout: {
    anchor: 'top-left', widthVw: 38, maxHeightVh: 28,
    density: 'comfortable', fadeDelayMs: 7000, idleOpacity: 0.75,
    fontScale: 1, reducedMotion: false,
  } as Layout,
})

const shellStyle = computed(() => ({
  '--chat-width': `${state.layout.widthVw}vw`,
  '--chat-height': `${state.layout.maxHeightVh}vh`,
  '--chat-font-scale': String(state.layout.fontScale),
  '--chat-idle-opacity': String(state.layout.idleOpacity),
}))
const matchingSuggestions = computed(() => {
  if (!input.value.startsWith('/')) return []
  const token = input.value.split(/\s/, 1)[0].toLowerCase()
  return suggestions.value.filter((item) => item.trigger.startsWith(token))
})
const filteredMessages = computed(() => selectedFilter.value === 'all'
  ? messages.value
  : messages.value.filter((message) => message.channelKey === selectedFilter.value))
const selectedFilterLabel = computed(() => channels.value
  .find((channel) => channel.channelKey === selectedFilter.value)?.label)

function selectFilter(channelKey: string) {
  selectedFilter.value = channelKey
  selectedChannel.value = channelKey === 'all' ? 'local.say' : channelKey
}

function messageChannelLabel(message: ChatMessage) {
  return message.channelLabel
    || channels.value.find((channel) => channel.channelKey === message.channelKey)?.label
    || message.channelKey
}

async function chooseSuggestion(suggestion: Suggestion) {
  input.value = `${suggestion.trigger} `
  await nextTick()
  const field = composer.value
  if (!field) return
  field.focus()
  field.setSelectionRange(input.value.length, input.value.length)
}

function receive(event: MessageEvent) {
  const message = event.data
  if (!message || typeof message.type !== 'string') return
  if (message.type === 'chat:open') {
    open.value = true
    requestAnimationFrame(() => composer.value?.focus())
  } else if (message.type === 'chat:close') {
    open.value = false
    input.value = ''
    error.value = ''
    window.clearTimeout(errorTimer)
  } else if (message.type === 'chat:visibility') {
    visible.value = message.visible === true
  } else if (message.type === 'chat:bootstrap' && message.config) {
    if (message.config.layout) state.layout = message.config.layout
    if (typeof message.config.theme === 'string') state.theme = message.config.theme
    if (Array.isArray(message.messages)) messages.value = message.messages
    if (Array.isArray(message.channels) && message.channels.length > 0) channels.value = message.channels
    if (Array.isArray(message.suggestions)) suggestions.value = message.suggestions
  } else if (message.type === 'chat:directory' && Array.isArray(message.channels)) {
    channels.value = message.channels
    suggestions.value = Array.isArray(message.suggestions) ? message.suggestions : []
    if (selectedFilter.value !== 'all'
      && !channels.value.some((channel) => channel.channelKey === selectedFilter.value)) {
      selectedFilter.value = 'all'
    }
    if (!channels.value.some((channel) => channel.channelKey === selectedChannel.value)) {
      selectedChannel.value = channels.value.some((channel) => channel.channelKey === 'local.say')
        ? 'local.say'
        : channels.value[0]?.channelKey || 'local.say'
    }
  } else if (message.type === 'chat:message' && message.message) {
    error.value = ''
    window.clearTimeout(errorTimer)
    if (!messages.value.some((item) => item.messageId === message.message.messageId)) {
      messages.value.push(message.message)
      while (messages.value.length > 100) messages.value.shift()
    }
    feedVisible.value = true
    window.clearTimeout(feedTimer)
    feedTimer = window.setTimeout(() => {
      if (!open.value) feedVisible.value = false
    }, state.layout.fadeDelayMs)
  } else if (message.type === 'chat:error') {
    error.value = typeof message.message === 'string' ? message.message : 'Message was not accepted.'
    window.clearTimeout(errorTimer)
    errorTimer = window.setTimeout(() => {
      error.value = ''
    }, Math.min(state.layout.fadeDelayMs, 5000))
    feedVisible.value = true
    window.clearTimeout(feedTimer)
    feedTimer = window.setTimeout(() => {
      if (!open.value) feedVisible.value = false
    }, state.layout.fadeDelayMs)
  }
}

async function close() {
  open.value = false
  input.value = ''
  await nui('chat:close')
}

async function submit() {
  const text = input.value.trim()
  if (!text || submitting.value) return
  submitting.value = true
  error.value = ''
  const result = await nui<SubmitResult>('chat:submit', {
    channelKey: selectedChannel.value,
    text,
  })
  submitting.value = false
  if (!result?.ok) {
    error.value = result?.message || 'Message was not accepted.'
    return
  }
  input.value = ''
}

function composerKeydown(event: KeyboardEvent) {
  if (event.key === 'Enter' && !event.shiftKey) {
    event.preventDefault()
    void submit()
  }
}

function keydown(event: KeyboardEvent) {
  if (event.key === 'Escape' && open.value) {
    event.preventDefault()
    void close()
  }
}

onMounted(() => {
  window.addEventListener('message', receive)
  window.addEventListener('keydown', keydown)
  void nui('chat:ready')
})

onBeforeUnmount(() => {
  window.clearTimeout(feedTimer)
  window.clearTimeout(errorTimer)
  window.removeEventListener('message', receive)
  window.removeEventListener('keydown', keydown)
})
</script>

<template>
  <main
    v-if="visible && (open || feedVisible)"
    class="chat-root"
    :class="[state.layout.anchor, state.layout.density, { open, 'reduced-motion': state.layout.reducedMotion }]"
    :data-theme="state.theme"
    :style="shellStyle"
  >
    <section class="chat-panel" aria-label="Chat messages" aria-live="polite">
      <nav class="channel-tabs" aria-label="Chat channels">
        <button
          class="channel"
          :class="{ active: selectedFilter === 'all' }"
          type="button"
          @click="selectFilter('all')"
        >
          All
        </button>
        <button
          v-for="channel in channels"
          :key="channel.channelKey"
          class="channel"
          :class="{ active: selectedFilter === channel.channelKey }"
          type="button"
          @click="selectFilter(channel.channelKey)"
        >
          {{ channel.label }}
        </button>
      </nav>
      <div v-if="filteredMessages.length === 0" class="empty-state">
        <strong>Feather Chat</strong>
        <span>{{ selectedFilter === 'all' ? 'No messages yet.' : `No ${selectedFilterLabel || 'channel'} messages yet.` }}</span>
      </div>
      <ol v-else class="message-list" aria-label="Recent messages">
        <li
          v-for="message in filteredMessages"
          :key="message.messageId"
          class="message"
          :data-variant="message.presentation.variant"
        >
          <span class="author">{{ message.author.displayName }}</span>
          <span v-if="selectedFilter === 'all'" class="message-channel">
            {{ messageChannelLabel(message) }}
          </span>
          <span class="body">{{ message.body.text }}</span>
        </li>
      </ol>
      <div v-if="error" class="error" role="alert">
        {{ error }}
      </div>
    </section>

    <section v-if="open" class="composer" aria-label="Chat input">
      <span class="channel-label">
        {{ channels.find((channel) => channel.channelKey === selectedChannel)?.label }}
      </span>
      <textarea
        ref="composer"
        v-model="input"
        rows="1"
        maxlength="500"
        aria-label="Message"
        placeholder="Type a local message"
        :disabled="submitting"
        @keydown="composerKeydown"
      />
      <button type="button" class="close" aria-label="Close chat" @click="close">
        Esc
      </button>
      <ul v-if="matchingSuggestions.length" class="suggestions" aria-label="Chat suggestions">
        <li v-for="suggestion in matchingSuggestions" :key="suggestion.key">
          <button type="button" @click="chooseSuggestion(suggestion)">
            <strong>{{ suggestion.trigger }}</strong>
            <span>{{ suggestion.description }}</span>
          </button>
        </li>
      </ul>
    </section>
  </main>
</template>
