local resourceName = GetCurrentResourceName()
local state = { open=false, visible=true, uiReady=false, messages={}, seen={}, submission=0,
    channels={}, aliases={}, suggestions={} }
local RefreshDirectory

local function Ui(message) SendNUIMessage(message) end
local function Snapshot()
    return { open=state.open, visible=state.visible, uiReady=state.uiReady,
        messageCount=#state.messages }
end

local function ApplyFocus(open)
    state.open = open == true and state.visible == true
    SetNuiFocus(state.open, state.open)
    Ui({ type=state.open and 'chat:open' or 'chat:close' })
    return ChatResults.Ok(Snapshot())
end

local function OpenChat()
    if not state.visible then return ChatResults.Err('not_visible', 'Chat is currently hidden.') end
    if RefreshDirectory then RefreshDirectory() end
    return ApplyFocus(true)
end

local function CloseChat() return ApplyFocus(false) end

local function SetChatVisible(visible)
    if type(visible) ~= 'boolean' then
        return ChatResults.Err('invalid_input', 'Chat visibility must be a boolean.')
    end
    state.visible = visible
    if not visible then ApplyFocus(false) end
    Ui({ type='chat:visibility', visible=visible })
    return ChatResults.Ok(Snapshot())
end

exports('OpenChat', OpenChat)
exports('CloseChat', CloseChat)
exports('SetChatVisible', SetChatVisible)
exports('GetChatState', function() return ChatResults.Ok(Snapshot()) end)

RegisterCommand(Config.Input.command, function()
    if state.open then CloseChat() else OpenChat() end
end, false)
RegisterKeyMapping(Config.Input.command, 'Open Feather Chat', 'keyboard', Config.Input.defaultKey)

RegisterNUICallback('chat:ready', function(_, callback)
    state.uiReady = true
    Ui({
        type='chat:bootstrap',
        config={ layout=Config.Layout, theme=Config.Theme.default, limits=Config.Limits },
        messages=state.messages, channels=state.channels, suggestions=state.suggestions
    })
    callback({ ok=true })
end)

local function Submit(channelKey, text)
    state.submission = state.submission + 1
    local submissionId = ('%s:%s:%s'):format(GetPlayerServerId(PlayerId()),
        GetGameTimer(), state.submission)
    local result, transportError = exports['feather-core']:CallRPCAsync(
        'chat.message.submit.v1', {
            channelKey=channelKey, text=text, submissionId=submissionId
        }, nil, Config.Limits.callbackTimeoutMs)
    if type(result) ~= 'table' then
        return ChatResults.Err(transportError and transportError.code or 'transport_failed',
            transportError and transportError.message or 'Chat submission failed.')
    end
    return result
end

local inputAliases = {
    say='local.say', whisper='local.whisper', shout='local.shout',
    me='roleplay.me', ['do']='roleplay.do'
}

local function ResolveInput(channelKey, text)
    if type(text) ~= 'string' or text:sub(1, 1) ~= '/' then
        return ChatResults.Ok({ channelKey=channelKey, text=text })
    end
    local command, body = text:match('^/([^%s]+)%s*(.*)$')
    command = command and command:lower() or nil
    local resolved = command and (state.aliases['/' .. command] or inputAliases[command]) or nil
    if not resolved then
        local commandLine = text:sub(2):gsub('^%s+', ''):gsub('%s+$', '')
        if commandLine == '' then
            return ChatResults.Err('invalid_command', 'Enter a command after the slash.')
        end
        return ChatResults.Ok({ command=commandLine })
    end
    if body == '' then
        return ChatResults.Err('invalid_message', 'Enter a message after the chat command.')
    end
    return ChatResults.Ok({ channelKey=resolved, text=body })
end

RefreshDirectory = function()
    local result = exports['feather-core']:CallRPCAsync(
        'chat.channel.list.v1', {}, nil, Config.Limits.callbackTimeoutMs)
    if type(result) ~= 'table' or not result.ok or type(result.value) ~= 'table'
        or type(result.value.channels) ~= 'table' then return result end
    state.channels, state.suggestions, state.aliases = result.value.channels,
        type(result.value.suggestions) == 'table' and result.value.suggestions or {}, {}
    for _, channel in ipairs(state.channels) do
        local input = type(channel) == 'table' and channel.input or nil
        for _, alias in ipairs(type(input) == 'table' and input.aliases or {}) do
            state.aliases[alias] = channel.channelKey
        end
    end
    Ui({ type='chat:directory', channels=state.channels,
        suggestions=state.suggestions, revision=result.value.revision })
    return result
end

RegisterNetEvent('feather-chat:directory:v1', function()
    if state.open then RefreshDirectory() end
end)

RegisterNUICallback('chat:submit', function(payload, callback)
    local function Reject(result)
        callback(result)
        CloseChat()
        Ui({ type='chat:error', message=result.message or 'Message was not accepted.' })
    end
    if type(payload) ~= 'table' or type(payload.channelKey) ~= 'string'
        or type(payload.text) ~= 'string' then
        Reject(ChatResults.Err('invalid_input', 'Chat submission is invalid.'))
        return
    end
    local resolved = ResolveInput(payload.channelKey, payload.text)
    if not resolved.ok then
        Reject(resolved)
        return
    end
    if resolved.value.command then
        ExecuteCommand(resolved.value.command)
        callback(ChatResults.Ok({ executed=true }))
        CloseChat()
        return
    end
    local result = Submit(resolved.value.channelKey, resolved.value.text)
    if not result.ok then
        Reject(result)
        return
    end
    callback(result)
    if Config.Input.closeOnSubmit then CloseChat() end
end)

RegisterNetEvent('feather-chat:message:v1', function(message)
    if type(message) ~= 'table' or type(message.messageId) ~= 'string'
        or state.seen[message.messageId] then return end
    state.seen[message.messageId] = true
    state.messages[#state.messages + 1] = message
    while #state.messages > Config.Limits.maxClientBuffer do
        local removed = table.remove(state.messages, 1)
        if removed and removed.messageId then state.seen[removed.messageId] = nil end
    end
    Ui({ type='chat:message', message=message })
end)

for command, channelKey in pairs(inputAliases) do
    RegisterCommand(command, function(_, args)
        local text = table.concat(args or {}, ' ')
        if text == '' then return OpenChat() end
        local result = Submit(channelKey, text)
        if not result.ok then
            Ui({ type='chat:error', message=result.message or 'Message was not accepted.' })
        end
    end, false)
end

RegisterNUICallback('chat:close', function(_, callback)
    CloseChat()
    callback({ ok=true })
end)

CreateThread(function()
    while true do
        Wait(250)
        if state.open and (IsPauseMenuActive() or IsScreenFadedOut()) then CloseChat() end
    end
end)

RegisterCommand('ChatClientFoundationSmokeTest', function()
    local before = Snapshot()
    local hidden = SetChatVisible(false)
    local refused = OpenChat()
    local restored = SetChatVisible(true)
    local opened = OpenChat()
    local closed = CloseChat()
    print(('[ChatClientFoundationSmokeTest] initial=%s hidden=%s refused=%s restored=%s opened=%s closed=%s uiReady=%s'):format(
        tostring(before.open == false), tostring(hidden.ok),
        tostring(refused.ok == false and refused.code == 'not_visible'),
        tostring(restored.ok), tostring(opened.ok), tostring(closed.ok), tostring(state.uiReady)))
end, false)

AddEventHandler('onResourceStop', function(stoppedResource)
    if stoppedResource ~= resourceName then return end
    state.open = false
    SetNuiFocus(false, false)
end)
