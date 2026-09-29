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
  timestamps: boolean
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

type Theme = {
  themeKey: string
  schemaVersion: number
  typography: { family: 'default' | 'system'; lineHeight: number }
  surface: { background: string; panel: string; border: string }
  text: { primary: string; muted: string; danger: string }
  channelTokens: Record<string, string>
  shape: { radius: number; borderWidth: number }
  motion: { enabled: boolean; durationMs: number }
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
const unreadMessages = ref(0)
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
const messageList = ref<HTMLOListElement | null>(null)
const state = reactive({
  theme: 'feather.default',
  themeDocument: undefined as Theme | undefined,
  layout: {
    anchor: 'top-left', widthVw: 38, maxHeightVh: 28,
    density: 'comfortable', fadeDelayMs: 7000, idleOpacity: 0.75,
    fontScale: 1, reducedMotion: false, timestamps: true,
  } as Layout,
})

const shellStyle = computed(() => {
  const theme = state.themeDocument
  return {
    '--chat-width': `${state.layout.widthVw}vw`,
    '--chat-height': `${state.layout.maxHeightVh}vh`,
    '--chat-font-scale': String(state.layout.fontScale),
    '--chat-idle-opacity': String(state.layout.idleOpacity),
    '--surface': theme?.surface.background,
    '--panel': theme?.surface.panel,
    '--border': theme?.surface.border,
    '--text': theme?.text.primary,
    '--muted': theme?.text.muted,
    '--danger': theme?.text.danger,
    '--chat-radius': theme ? `${theme.shape.radius}px` : undefined,
    '--chat-border-width': theme ? `${theme.shape.borderWidth}px` : undefined,
    '--chat-motion-duration': theme ? `${theme.motion.durationMs}ms` : undefined,
    '--chat-line-height': theme ? String(theme.typography.lineHeight) : undefined,
    '--chat-body-family': theme?.typography.family === 'system'
      ? 'system-ui, sans-serif'
      : "Georgia, 'Times New Roman', serif",
  }
})
const motionReduced = computed(() => state.layout.reducedMotion
  || state.themeDocument?.motion.enabled === false)
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
  unreadMessages.value = 0
  void scrollFeedToBottom()
}

function messageChannelLabel(message: ChatMessage) {
  return message.channelLabel
    || channels.value.find((channel) => channel.channelKey === message.channelKey)?.label
    || message.channelKey
}

function messageStyle(message: ChatMessage) {
  const token = message.presentation?.accentToken?.replace(/^channel\./, '')
  const accent = token && state.themeDocument?.channelTokens[token]
  return accent ? { '--message-accent': accent } : undefined
}

function applyPresentation(presentation: unknown) {
  if (!presentation || typeof presentation !== 'object') return
  const next = presentation as { layout?: Layout; theme?: string; themeDocument?: Theme }
  if (next.layout) state.layout = next.layout
  if (typeof next.theme === 'string') state.theme = next.theme
  if (next.themeDocument) state.themeDocument = next.themeDocument
}

function messageTimestamp(message: ChatMessage) {
  const createdAt = new Date(message.createdAt)
  if (Number.isNaN(createdAt.getTime())) return ''
  return createdAt.toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
}

function messageTimestampLabel(message: ChatMessage) {
  const createdAt = new Date(message.createdAt)
  if (Number.isNaN(createdAt.getTime())) return ''
  return createdAt.toLocaleString([], { dateStyle: 'medium', timeStyle: 'medium' })
}

function feedIsAtBottom() {
  const feed = messageList.value
  if (!feed) return true
  return feed.scrollHeight - feed.scrollTop - feed.clientHeight <= 8
}

async function scrollFeedToBottom() {
  await nextTick()
  await new Promise<void>((resolve) => window.requestAnimationFrame(() => resolve()))
  const feed = messageList.value
  if (feed) feed.scrollTop = feed.scrollHeight
  unreadMessages.value = 0
}

function handleFeedScroll() {
  if (feedIsAtBottom()) unreadMessages.value = 0
}

function scheduleFeedFade() {
  window.clearTimeout(feedTimer)
  feedTimer = window.setTimeout(() => {
    if (!open.value) feedVisible.value = false
  }, state.layout.fadeDelayMs)
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
    void scrollFeedToBottom()
    requestAnimationFrame(() => composer.value?.focus())
  } else if (message.type === 'chat:close') {
    open.value = false
    input.value = ''
    error.value = ''
    void scrollFeedToBottom()
    if (feedVisible.value) scheduleFeedFade()
    window.clearTimeout(errorTimer)
  } else if (message.type === 'chat:visibility') {
    visible.value = message.visible === true
  } else if (message.type === 'chat:bootstrap' && message.config) {
    applyPresentation(message.config)
    if (Array.isArray(message.messages)) {
      messages.value = message.messages
      void scrollFeedToBottom()
    }
    if (Array.isArray(message.channels) && message.channels.length > 0) channels.value = message.channels
    if (Array.isArray(message.suggestions)) suggestions.value = message.suggestions
  } else if (message.type === 'chat:presentation') {
    applyPresentation(message.presentation)
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
    const visibleInFilter = selectedFilter.value === 'all'
      || selectedFilter.value === message.message.channelKey
    const followNewMessage = !open.value || feedIsAtBottom()
    feedVisible.value = true
    if (!messages.value.some((item) => item.messageId === message.message.messageId)) {
      messages.value.push(message.message)
      while (messages.value.length > 100) messages.value.shift()
      if (visibleInFilter) {
        if (followNewMessage) void scrollFeedToBottom()
        else unreadMessages.value += 1
      }
    }
    scheduleFeedFade()
  } else if (message.type === 'chat:error') {
    error.value = typeof message.message === 'string' ? message.message : 'Message was not accepted.'
    window.clearTimeout(errorTimer)
    errorTimer = window.setTimeout(() => {
      error.value = ''
    }, Math.min(state.layout.fadeDelayMs, 5000))
    feedVisible.value = true
    scheduleFeedFade()
  }
}

async function close() {
  open.value = false
  input.value = ''
  void scrollFeedToBottom()
  if (feedVisible.value) scheduleFeedFade()
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
    :class="[state.layout.anchor, state.layout.density, { open, 'reduced-motion': motionReduced }]"
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
      <ol
        v-else
        ref="messageList"
        class="message-list"
        aria-label="Recent messages"
        @scroll.passive="handleFeedScroll"
      >
        <li
          v-for="message in filteredMessages"
          :key="message.messageId"
          class="message"
          :data-variant="message.presentation.variant"
          :style="messageStyle(message)"
        >
          <span class="author">{{ message.author.displayName }}</span>
          <span v-if="selectedFilter === 'all'" class="message-channel">
            {{ messageChannelLabel(message) }}
          </span>
          <span class="body">{{ message.body.text }}</span>
          <time
            v-if="state.layout.timestamps && messageTimestamp(message)"
            class="timestamp"
            :datetime="message.createdAt"
            :title="messageTimestampLabel(message)"
          >
            {{ messageTimestamp(message) }}
          </time>
        </li>
      </ol>
      <button
        v-if="unreadMessages > 0"
        type="button"
        class="new-message-indicator"
        :aria-label="`${unreadMessages} new ${unreadMessages === 1 ? 'message' : 'messages'}. Scroll to latest.`"
        @click="scrollFeedToBottom"
      >
        {{ unreadMessages === 1 ? 'New message' : `${unreadMessages} new messages` }} ↓
      </button>
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
