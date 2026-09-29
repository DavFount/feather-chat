ChatContract = {
    Name = 'feather.chat',
    Version = 1,
    Anchors = { ['top-left']=true, ['top-right']=true, ['bottom-left']=true, ['bottom-right']=true },
    Densities = { compact=true, comfortable=true },
    Themes = { ['feather.default']=true, ['feather.high_contrast']=true },
    ThemeFamilies = { default=true, system=true },
    ThemeTokenKeys = { 'speech', 'whisper', 'shout', 'action', 'scene',
        'organization', 'job', 'ooc', 'staff', 'system' },
    Channels = {
        ['local.say'] = { kind='player', radius='say', variant='speech' },
        ['local.whisper'] = { kind='player', radius='whisper', variant='whisper' },
        ['local.shout'] = { kind='player', radius='shout', variant='shout' },
        ['roleplay.me'] = { kind='action', radius='roleplay', variant='action' },
        ['roleplay.do'] = { kind='scene', radius='roleplay', variant='scene' }
    }
}

local function NumberInRange(value, minimum, maximum)
    return type(value) == 'number' and value >= minimum and value <= maximum
end

local function PositiveInteger(value, maximum)
    return type(value) == 'number' and value % 1 == 0 and value >= 1 and value <= maximum
end

local function ThemeKey(value)
    return type(value) == 'string' and #value >= 3 and #value <= 96
        and value:match('^[a-z][a-z0-9_.%-]+$') ~= nil
        and value:find('.', 1, true) ~= nil
end

local function Color(value)
    return type(value) == 'string'
        and (value:match('^#%x%x%x%x%x%x$') ~= nil or value:match('^#%x%x%x%x%x%x%x%x$') ~= nil)
end

local function ExactKeys(value, keys)
    if type(value) ~= 'table' then return false end
    local allowed = {}
    for _, key in ipairs(keys) do allowed[key] = true end
    for key in pairs(value) do if not allowed[key] then return false end end
    for _, key in ipairs(keys) do if value[key] == nil then return false end end
    return true
end

function ChatContract.ValidateTheme(theme)
    if type(theme) ~= 'table' or not ThemeKey(theme.themeKey) or theme.schemaVersion ~= 1
        or not ExactKeys(theme, { 'themeKey', 'schemaVersion', 'typography', 'surface',
            'text', 'channelTokens', 'shape', 'motion' })
        or not ExactKeys(theme.typography, { 'family', 'lineHeight' })
        or not ChatContract.ThemeFamilies[theme.typography.family]
        or not NumberInRange(theme.typography.lineHeight, 1.1, 2.0)
        or not ExactKeys(theme.surface, { 'background', 'panel', 'border' })
        or not Color(theme.surface.background) or not Color(theme.surface.panel)
        or not Color(theme.surface.border)
        or not ExactKeys(theme.text, { 'primary', 'muted', 'danger' })
        or not Color(theme.text.primary) or not Color(theme.text.muted)
        or not Color(theme.text.danger)
        or not ExactKeys(theme.channelTokens, ChatContract.ThemeTokenKeys)
        or not ExactKeys(theme.shape, { 'radius', 'borderWidth' })
        or not NumberInRange(theme.shape.radius, 0, 16)
        or not NumberInRange(theme.shape.borderWidth, 1, 3)
        or not ExactKeys(theme.motion, { 'enabled', 'durationMs' })
        or type(theme.motion.enabled) ~= 'boolean'
        or not NumberInRange(theme.motion.durationMs, 0, 500) then
        return false, ChatResults.Err('invalid_theme', 'Theme document is invalid.')
    end
    for _, key in ipairs(ChatContract.ThemeTokenKeys) do
        if not Color(theme.channelTokens[key]) then
            return false, ChatResults.Err('invalid_theme', 'Theme channel token is invalid.', { token=key })
        end
    end
    return true
end

function ChatContract.ValidateConfig(config)
    if type(config) ~= 'table' then
        return ChatResults.Err('invalid_configuration', 'Chat configuration must be a table.')
    end
    if type(config.Input) ~= 'table' or type(config.Input.command) ~= 'string'
        or config.Input.command == '' or #config.Input.command > 32
        or type(config.Input.defaultKey) ~= 'string' or config.Input.defaultKey == ''
        or #config.Input.defaultKey > 32 or type(config.Input.closeOnSubmit) ~= 'boolean' then
        return ChatResults.Err('invalid_configuration', 'Chat input configuration is invalid.')
    end
    if type(config.Channels) ~= 'table' or type(config.Channels.oocEnabled) ~= 'boolean'
        or type(config.Channels.proximity) ~= 'table' then
        return ChatResults.Err('invalid_configuration', 'Chat channel configuration is invalid.')
    end
    for _, key in ipairs({ 'whisper', 'say', 'roleplay', 'shout' }) do
        if not NumberInRange(config.Channels.proximity[key], 1.0, 100.0) then
            return ChatResults.Err('invalid_configuration', 'Chat proximity configuration is invalid.', {
                field = 'Channels.proximity.' .. key
            })
        end
    end
    if type(config.Limits) ~= 'table'
        or not PositiveInteger(config.Limits.maxMessageBytes, 4000)
        or not PositiveInteger(config.Limits.maxMessageLines, 20)
        or not PositiveInteger(config.Limits.maxClientBuffer, 500)
        or not PositiveInteger(config.Limits.maxInputHistory, 100)
        or not PositiveInteger(config.Limits.callbackTimeoutMs, 30000) then
        return ChatResults.Err('invalid_configuration', 'Chat limit configuration is invalid.')
    end
    if type(config.RateLimit) ~= 'table'
        or not PositiveInteger(config.RateLimit.windowMs, 60000)
        or not PositiveInteger(config.RateLimit.maxMessages, 100) then
        return ChatResults.Err('invalid_configuration', 'Chat rate-limit configuration is invalid.')
    end
    if type(config.Layout) ~= 'table' or not ChatContract.Anchors[config.Layout.anchor]
        or not ChatContract.Densities[config.Layout.density]
        or not NumberInRange(config.Layout.widthVw, 20, 80)
        or not NumberInRange(config.Layout.maxHeightVh, 15, 80)
        or not NumberInRange(config.Layout.fadeDelayMs, 0, 60000)
        or not NumberInRange(config.Layout.idleOpacity, 0, 1)
        or not NumberInRange(config.Layout.fontScale, 0.75, 1.5)
        or type(config.Layout.timestamps) ~= 'boolean'
        or type(config.Layout.reducedMotion) ~= 'boolean' then
        return ChatResults.Err('invalid_configuration', 'Chat layout configuration is invalid.')
    end
    if type(config.Theme) ~= 'table' or not ThemeKey(config.Theme.default)
        or type(config.Theme.approved) ~= 'table' or #config.Theme.approved < 1
        or #config.Theme.approved > 16 then
        return ChatResults.Err('invalid_configuration', 'Chat theme configuration is invalid.')
    end
    local approvedThemes = {}
    for _, theme in ipairs(config.Theme.approved) do
        if not ThemeKey(theme) or approvedThemes[theme] then
            return ChatResults.Err('invalid_configuration', 'Chat approved theme is invalid.', { theme=theme })
        end
        approvedThemes[theme] = true
    end
    if not approvedThemes[config.Theme.default] then
        return ChatResults.Err('invalid_configuration', 'Chat default theme must be approved.')
    end
    local preferences = config.Preferences
    if type(preferences) ~= 'table' or type(preferences.theme) ~= 'boolean'
        or type(preferences.density) ~= 'boolean' or type(preferences.timestamps) ~= 'boolean'
        or type(preferences.reducedMotion) ~= 'boolean'
        or type(preferences.fontScale) ~= 'table'
        or type(preferences.fontScale.enabled) ~= 'boolean'
        or not NumberInRange(preferences.fontScale.minimum, 0.75, 1.5)
        or not NumberInRange(preferences.fontScale.maximum, 0.75, 1.5)
        or preferences.fontScale.minimum > preferences.fontScale.maximum
        or not NumberInRange(preferences.fontScale.step, 0.01, 0.25)
        or type(preferences.idleOpacity) ~= 'table'
        or type(preferences.idleOpacity.enabled) ~= 'boolean'
        or not NumberInRange(preferences.idleOpacity.minimum, 0.1, 1.0)
        or not NumberInRange(preferences.idleOpacity.maximum, 0.1, 1.0)
        or preferences.idleOpacity.minimum > preferences.idleOpacity.maximum
        or not NumberInRange(preferences.idleOpacity.step, 0.01, 0.25) then
        return ChatResults.Err('invalid_configuration', 'Chat preference configuration is invalid.')
    end
    if type(config.Features) ~= 'table' or type(config.Features.history) ~= 'boolean'
        or type(config.Features.privateMessages) ~= 'boolean'
        or type(config.Features.emojiPicker) ~= 'boolean' then
        return ChatResults.Err('invalid_configuration', 'Chat feature configuration is invalid.')
    end
    return ChatResults.Ok(true)
end

function ChatContract.ValidateSubmission(payload, limits)
    local allowed = { channelKey=true, text=true, submissionId=true }
    if type(payload) ~= 'table' or type(payload.channelKey) ~= 'string'
        or #payload.channelKey < 3 or #payload.channelKey > 96
        or payload.channelKey:match('^[a-z][a-z0-9_.%-]+$') == nil
        or payload.channelKey:find('.', 1, true) == nil
        or type(payload.text) ~= 'string' or type(payload.submissionId) ~= 'string'
        or #payload.submissionId < 1 or #payload.submissionId > 64
        or payload.submissionId:match('^[%w:_%-]+$') == nil then
        return false, ChatResults.Err('invalid_input', 'Chat submission is invalid.')
    end
    for key in pairs(payload) do
        if allowed[key] ~= true then
            return false, ChatResults.Err('invalid_input', 'Chat submission contains an unknown field.')
        end
    end
    if #payload.text < 1 or #payload.text > limits.maxMessageBytes then
        return false, ChatResults.Err('invalid_message', 'Message length is invalid.')
    end
    return true
end
