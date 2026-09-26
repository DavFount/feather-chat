ChatContract = {
    Name = 'feather.chat',
    Version = 1,
    Anchors = { ['top-left']=true, ['top-right']=true, ['bottom-left']=true, ['bottom-right']=true },
    Densities = { compact=true, comfortable=true },
    Themes = { ['feather.default']=true, ['feather.high_contrast']=true },
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
    if type(config.Theme) ~= 'table' or not ChatContract.Themes[config.Theme.default]
        or type(config.Theme.approved) ~= 'table' or #config.Theme.approved < 1
        or #config.Theme.approved > 16 then
        return ChatResults.Err('invalid_configuration', 'Chat theme configuration is invalid.')
    end
    for _, theme in ipairs(config.Theme.approved) do
        if not ChatContract.Themes[theme] then
            return ChatResults.Err('invalid_configuration', 'Chat approved theme is invalid.', { theme=theme })
        end
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
