<script setup lang="ts">
import { onBeforeUnmount, onMounted, ref } from 'vue'
import { nui } from './api'
import { t } from './locale'
import { CaseRequestGate, caseUpdateAction } from './caseRequest'
type Row = { conversationId: string; status: string; targetName?: string }
type Message = { messageId: string; text: string; authorRole: string; createdAt: string }
const rows = ref<Row[]>([])
const selected = ref('')
const status = ref('')
const targetName = ref('')
const messages = ref<Message[]>([])
const draft = ref('')
const error = ref('')
const pending = ref(false)
const pendingOperation = ref('')
let updateQueued = false
const more = ref(false)
const cursor = ref(0)
const offset = ref(0)
let retry: { conversationId: string; submissionId: string; text: string } | null = null
let timer: ReturnType<typeof setTimeout> | undefined
const gate = new CaseRequestGate()
let sentDraft = ''
async function request(operation: string, payload: unknown) {
  const requestId = crypto.randomUUID()
  gate.begin(requestId, operation)
  error.value = ''
  pending.value = true
  pendingOperation.value = operation
  clearTimeout(timer)
  timer = setTimeout(() => {
    if (!gate.finish(requestId, operation)) return
    pending.value = false; error.value = t('ui_request_timed_out_you_may_retry')
  }, 15000)
  try {
    const result = await nui<{ ok: boolean }>('chat:case', { operation, payload, requestId })
    if (!result?.ok && gate.finish(requestId, operation)) {
      clearTimeout(timer); pending.value = false; error.value = t('ui_staff_conversation_service_unavailable')
    }
  } catch {
    if (gate.finish(requestId, operation)) {
      clearTimeout(timer); pending.value = false; error.value = t('ui_staff_conversation_service_unavailable')
    }
  }
}
function history(afterSequence = 0) {
  void request('history', { conversationId: selected.value, afterSequence, limit: 20 })
}
function choose(row: Row) {
  selected.value = row.conversationId
  status.value = row.status
  targetName.value = row.targetName || t('ui_earlier_conversation')
  draft.value = ''; retry = null
  history()
}
function send() {
  if (!draft.value.trim() || pending.value) return
  if (!retry || retry.text !== draft.value || retry.conversationId !== selected.value) {
    retry = { conversationId: selected.value, submissionId: crypto.randomUUID(), text: draft.value }
  }
  void request('reply', retry)
  sentDraft = draft.value
}
function receive(event: MessageEvent) {
  const data = event.data
  if (data?.type === 'chat:case:updated') {
    const action = caseUpdateAction(selected.value, data.hint?.conversationId, pending.value)
    if (action === 'queue') updateQueued = true
    else if (action === 'history') history()
    else if (action === 'list') void request('list', { offset: 0 })
    return
  }
  if (data?.type !== 'chat:case:result') return
  if (!gate.finish(data.requestId, data.operation)) return
  clearTimeout(timer); pending.value = false
  const result = data.result
  if (!result?.ok) { error.value = t('ui_conversation_action_failed_code', { code: result?.code || 'unavailable' }); return }
  if (data.operation === 'list') {
    rows.value = result.conversations || []; more.value = result.hasMore; offset.value = result.nextOffset
  } else if (data.operation === 'history' && result.conversationId === selected.value) {
    messages.value = result.messages || []; status.value = result.status
    targetName.value = result.targetName || t('ui_earlier_conversation')
    more.value = result.hasMore; cursor.value = result.nextSequence
  } else if (data.operation === 'reply') {
    if (draft.value === sentDraft) draft.value = ''
    retry = null; history()
  }
  if (updateQueued && !pending.value) {
    updateQueued = false
    if (selected.value) history()
    else void request('list', { offset: 0 })
  }
}
onMounted(() => { window.addEventListener('message', receive); void request('list', { offset: 0 }) })
onBeforeUnmount(() => { gate.invalidate(); window.removeEventListener('message', receive); clearTimeout(timer) })
</script>

<template>
  <div class="staff-cases" :aria-label="t('ui_staff_conversations')">
    <p v-if="pending" role="status" aria-live="polite">
      {{ pendingOperation === 'reply' ? t('ui_sending') : t('ui_loading') }}
    </p>
    <div v-if="!selected" class="case-directory">
      <div class="case-heading">
        <strong>{{ t('ui_staff_conversations') }}</strong><span>{{ t('ui_private_support') }}</span>
      </div>
      <div v-if="!rows.length" class="case-empty">
        <span>{{ pending ? t('ui_loading_conversations') : t('ui_no_staff_conversations') }}</span>
        <small v-if="!pending">{{ t('ui_when_staff_opens_a_conversation_with_you_it_will_appear_here') }}</small>
      </div>
      <button v-for="row in rows" :key="row.conversationId" class="case-row" type="button" @click="choose(row)">
        <span>{{ row.targetName || t('ui_earlier_conversation') }}</span><small>{{ t('status_' + row.status) }}</small>
      </button>
      <button v-if="more" type="button" :disabled="pending" @click="request('list', { offset })">
        {{ t('ui_next') }}
      </button>
    </div>
    <div v-else class="case-detail">
      <button type="button" @click="selected = ''; request('list', { offset: 0 })">
        {{ t('ui_conversations') }}
      </button>
      <span>{{ targetName }} · {{ t('status_' + status) }}</span>
      <button type="button" :disabled="pending" @click="history()">
        {{ t('ui_refresh') }}
      </button>
      <ol class="case-messages">
        <li v-for="message in messages" :key="message.messageId">
          <small>{{ t('role_' + message.authorRole) }} · {{ message.createdAt }}</small>
          <p>{{ message.text }}</p>
        </li>
      </ol>
      <button v-if="more" type="button" :disabled="pending" @click="history(cursor)">
        {{ t('ui_next_messages') }}
      </button>
      <div v-if="status === 'open'" class="case-reply">
        <textarea v-model="draft" maxlength="500" :aria-label="t('ui_staff_conversation_reply')" :placeholder="t('ui_reply_to_this_staff_conversation')" />
        <button type="button" :disabled="pending || !draft.trim()" @click="send">
          {{ t('ui_send_reply') }}
        </button>
      </div>
      <p v-else>
        {{ t('ui_read_only_history') }}
      </p>
    </div>
    <p v-if="error" role="alert">
      {{ error }}
    </p>
  </div>
</template>

<style scoped>
.staff-cases { padding: .85rem 1rem; color: var(--text); max-height: 35vh; overflow-y: auto; scrollbar-color: var(--border) var(--surface); scrollbar-width: thin; }
.case-heading { display: flex; align-items: baseline; justify-content: space-between; gap: 1rem; }
.case-heading strong { color: var(--accent); }
.case-heading span, small { color: var(--muted); font-size: .8em; }
.case-empty { display: flex; flex-direction: column; gap: .35rem; padding: 1.1rem 0 .6rem; }
.case-empty > span { color: var(--text); }
button, textarea { font: inherit; color: var(--text); background: var(--surface); border: 1px solid var(--border); border-radius: var(--chat-radius); padding: .4rem .6rem; }
button { cursor: pointer; margin: .2rem .3rem .2rem 0; }
button:hover, button:focus-visible, textarea:focus-visible { border-color: var(--accent); outline: 1px solid var(--accent); outline-offset: 1px; }
button:disabled { opacity: .5; cursor: default; }
.case-row { display: flex; justify-content: space-between; align-items: center; width: 100%; text-align: left; margin-top: .6rem; }
.case-row small { text-transform: capitalize; }
.case-reply { display: flex; gap: .5rem; align-items: flex-end; padding-top: .6rem; border-top: 1px solid var(--border); }
textarea { flex: 1; min-width: 0; min-height: 3rem; resize: vertical; }
ol { padding: .5rem 0; margin: .5rem 0; list-style: none; }
li { padding: .5rem 0; border-bottom: 1px solid var(--border); }
.staff-cases::-webkit-scrollbar { width: .65rem; }
.staff-cases::-webkit-scrollbar-track { border-radius: 999px; background: var(--surface); }
.staff-cases::-webkit-scrollbar-thumb { border: 2px solid var(--surface); border-radius: 999px; background: var(--border); }
.staff-cases::-webkit-scrollbar-thumb:hover { background: var(--accent); }
p { white-space: pre-wrap; overflow-wrap: anywhere; margin: .3rem 0; }
</style>
