# Feather Chat

Feather Chat is the official server-authoritative text communication resource
for Feather Framework. The current `0.1.0` development slice contains the
Contract 1 lifecycle, validated operator configuration, health/capability
exports, focus recovery, a themed Vue NUI, and server-authoritative local chat.

## Server-owner setup

Start Chat after Core:

```cfg
ensure feather-core
ensure feather-chat
```

`feather-core` is the only hard dependency in the foundation. Chat does not
require BCC Chat, VORP, Discord, MySQL, or Feather Menu.

### Configuration

Most servers should retain the safe defaults in `config.lua`.

| Section | Purpose |
| --- | --- |
| `Input` | Open command, default key, and eventual submit-focus behavior. |
| `Channels` | OOC availability and local proximity radii. |
| `Limits` | Message, line, client-buffer, input-history, and callback bounds. |
| `RateLimit` | Per-player local message window and accepted-message ceiling. |
| `Layout` | Anchor, size, density, fade, timestamps, font scale, and reduced motion. |
| `Theme` | Default and approved built-in theme keys. |
| `Preferences` | Which bounded presentation controls players may change through `feather-settings`. |
| `Features` | Explicitly disabled deferred features such as history and staff cases. |

`feather-settings` is optional. When it is running, Chat registers controls for
the approved theme, density, timestamps, reduced motion, text scale, and faded
feed opacity according to `Config.Preferences`. Chat validates, stores, and
applies those local presentation preferences; Settings only renders the
controls. Restarting either resource safely re-registers them.

### Local chat

Press `T` or run `/chat`, choose a local mode, and press Enter to submit.
Shift+Enter inserts a new line. Built-in command aliases are also available:

```text
/say message
/whisper message
/shout message
/me action
/do scene description
```

These slash commands work both as registered game commands and when typed
directly into the `T` composer.

Other slash-prefixed composer input uses the normal client command system with
the same authority it has in F8. For example, `/logout` invokes Feather
Character's registered client command; Chat does not reimplement or authorize
that command.

The server derives the character name from the active Core session, uses
server-side ped coordinates and routing buckets for recipients, accepts plain
text only, and applies the configured message and rate limits.
Rejected composer submissions release input focus automatically and leave the
safe error message visible in the temporary feed.

Security-sensitive configuration is validated during startup. Invalid values
leave Chat unavailable instead of silently applying unsafe fallbacks.

### Current validation

Server console:

```text
ChatFoundationSmokeTest
```

Client F8:

```text
ChatClientFoundationSmokeTest
```

Press `T` or run `/chat` to inspect the chat shell. It must open, focus, close
with Escape, release focus when the pause menu or fade appears, and release
focus when the resource stops.

Phase C2 contract validation is available from the server console:

```text
ChatMessageContractSmokeTest
ChatMessageConcurrencySmokeTest
ChatThemeContractSmokeTest
```

Client F8 presentation validation:

```text
ChatPresentationSmokeTest
```

The concurrency smoke test is deterministic and does not require connected
players. It verifies that overlapping and completed retries with the same
submission ID produce one delivery, and that a character-session change during
submission processing rejects before delivery.

## Developer API reference

### Server exports

```lua
exports['feather-chat']:GetCapabilities()
exports['feather-chat']:GetHealth()
exports['feather-chat']:AwaitReady(timeoutMs)
exports['feather-chat']:RegisterChannel(definition)
exports['feather-chat']:UpdateChannel(channelKey, patch, expectedRevision)
exports['feather-chat']:UnregisterChannel(channelKey)
exports['feather-chat']:RegisterChannelAccessProvider(name, implementation)
exports['feather-chat']:UnregisterChannelAccessProvider(name)
exports['feather-chat']:RegisterSuggestion(definition)
exports['feather-chat']:RemoveSuggestion(key)
exports['feather-chat']:RegisterTheme(definition)
exports['feather-chat']:UpdateTheme(themeKey, definition, expectedRevision)
exports['feather-chat']:UnregisterTheme(themeKey)
```

All exports return the Feather result envelope:

```lua
{ ok = true, value = value, meta = optionalMeta }
{ ok = false, code = 'stable_code', message = 'Safe summary', details = optionalDetails }
```

The resource advertises Contract `feather.chat` version `1`. Built-in local
messaging, proximity routing, registered channels/suggestions, access providers,
validated themes, and presentation preferences are available. General history,
staff cases, player-to-player private messages, and moderation are unavailable;
player private messaging is intentionally outside Chat's scope.

### Client exports

```lua
exports['feather-chat']:OpenChat()
exports['feather-chat']:CloseChat()
exports['feather-chat']:SetChatVisible(visible)
exports['feather-chat']:GetChatState()
exports['feather-chat']:GetPresentation()
exports['feather-chat']:SetPresentationPreference(key, value)
```

These exports control local presentation only. They never authorize message
delivery or channel access.

Theme registration is server-only and owner-scoped. Documents use schema
version `1` and accept only bounded typography, surface, text, semantic channel,
shape, and motion tokens. Raw CSS, HTML, JavaScript, URLs, and arbitrary font
names are rejected. A registered theme is offered to players only when its key
is present in `Config.Theme.approved`; removing or invalidating the selected
theme falls back to the configured default and publishes a live revision.

Channel and suggestion registrations are server-only and owned by the invoking
resource. Duplicate keys and aliases are rejected, foreign updates/removals are
forbidden, revisions protect updates, and registrations are removed when their
owner stops. Protected channels use a named Core-backed access provider instead
of copying membership into Chat.

A resource that owns a client command may advertise it in Chat from its server
script:

```lua
exports['feather-chat']:RegisterSuggestion({
    key = 'feather-character.logout',
    trigger = '/logout',
    description = 'Return to character selection'
})
```

Chat removes that suggestion automatically when its owning resource stops.

## UI development

The source is in `web/`; production output is generated into `ui/`.

```text
cd web
pnpm install
pnpm check
```

The NUI has no runtime CDN dependencies and does not render caller-provided
HTML. Commit or package the built `ui/` output with releases.
