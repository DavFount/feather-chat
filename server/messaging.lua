ChatMessaging = {}

local sequence = 0
local rates = {}
local submissions = {}
local ready = false

local function Callable(value)
    return type(value) == 'function' or (type(value) == 'table'
        and type(rawget(value, '__cfx_functionReference')) == 'string')
end

local function NewUuid()
    local template = 'xxxxxxxx-xxxx-4xxx-yxxx-xxxxxxxxxxxx'
    return (template:gsub('[xy]', function(token)
        local value = token == 'x' and math.random(0, 15) or math.random(8, 11)
        return ('%x'):format(value)
    end))
end

local function NormalizeText(text)
    text = text:gsub('\r\n', '\n'):gsub('\r', '\n')
    text = text:gsub('^[ \t\n]+', ''):gsub('[ \t\n]+$', '')
    if text == '' then return nil, 'Message cannot be empty.' end

    local lineCount = 1
    for _ in text:gmatch('\n') do lineCount = lineCount + 1 end
    if lineCount > Config.Limits.maxMessageLines then
        return nil, 'Message contains too many lines.'
    end

    local valid, failure = pcall(function()
        for _, codepoint in utf8.codes(text) do
            if (codepoint < 32 and codepoint ~= 9 and codepoint ~= 10)
                or codepoint == 127
                or (codepoint >= 0x202A and codepoint <= 0x202E)
                or (codepoint >= 0x2066 and codepoint <= 0x2069) then
                error('unsafe_character', 0)
            end
        end
    end)
    if not valid then
        return nil, failure == 'unsafe_character' and 'Message contains unsupported characters.'
            or 'Message is not valid UTF-8.'
    end
    return text
end

local function RateAllowed(source)
    local now = GetGameTimer()
    local window = rates[source]
    if not window or now - window.startedAt >= Config.RateLimit.windowMs then
        rates[source] = { startedAt=now, count=1 }
        return true
    end
    if window.count >= Config.RateLimit.maxMessages then return false end
    window.count = window.count + 1
    return true
end

local function Profile(characterId)
    local provider = exports['feather-core']:GetProvider('character-profile', nil, 1)
    local implementation = type(provider) == 'table' and provider.ok == true
        and type(provider.value) == 'table' and provider.value.implementation or nil
    if type(implementation) ~= 'table' or not Callable(implementation.GetProfile) then
        return ChatResults.Err('identity_unavailable', 'Character identity is unavailable.')
    end
    local called, result = pcall(implementation.GetProfile, characterId)
    if not called or type(result) ~= 'table' or result.ok ~= true
        or type(result.value) ~= 'table' then
        return ChatResults.Err('identity_unavailable', 'Character identity is unavailable.')
    end
    local first = type(result.value.firstName) == 'string' and result.value.firstName or ''
    local last = type(result.value.lastName) == 'string' and result.value.lastName or ''
    local displayName = (first .. ' ' .. last):gsub('^%s+', ''):gsub('%s+$', '')
    if displayName == '' or #displayName > 96 then
        return ChatResults.Err('identity_unavailable', 'Character display name is unavailable.')
    end
    return ChatResults.Ok({ characterId=characterId, displayName=displayName })
end

local function AuthoritativePosition(source)
    local ped = GetPlayerPed(source)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return nil end
    local coords = GetEntityCoords(ped)
    if not coords then return nil end
    return coords, GetPlayerRoutingBucket(source)
end

local function Recipients(source, radius)
    local origin, bucket = AuthoritativePosition(source)
    if not origin then
        return nil, ChatResults.Err('position_unavailable', 'Authoritative player position is unavailable.')
    end
    local selected, radiusSquared = {}, radius * radius
    for _, rawTarget in ipairs(GetPlayers()) do
        local target = tonumber(rawTarget)
        if target and GetPlayerRoutingBucket(target) == bucket then
            local session = exports['feather-core']:GetSessionContext(target)
            local coords = type(session) == 'table' and session.ok == true
                and select(1, AuthoritativePosition(target)) or nil
            if coords then
                local dx, dy, dz = coords.x-origin.x, coords.y-origin.y, coords.z-origin.z
                if dx*dx + dy*dy + dz*dz <= radiusSquared then selected[#selected + 1] = target end
            end
        end
    end
    return selected
end

local function ConnectedSessions()
    local connected = {}
    for _, rawTarget in ipairs(GetPlayers()) do
        local target = tonumber(rawTarget)
        local session = target and exports['feather-core']:GetSessionContext(target) or nil
        if type(session) == 'table' and session.ok == true then
            connected[#connected + 1] = {
                source=target, accountId=session.value.accountId,
                characterId=session.value.characterId, sessionId=session.value.sessionId
            }
        end
    end
    return connected
end

local function Remember(source, submissionId, result)
    submissions[source] = submissions[source] or { order={}, values={} }
    local cache = submissions[source]
    cache.values[submissionId] = result
    cache.order[#cache.order + 1] = submissionId
    while #cache.order > 32 do cache.values[table.remove(cache.order, 1)] = nil end
end

local function Submit(payload, source, context)
    local cached = submissions[source] and submissions[source].values[payload.submissionId]
    if cached then return cached end
    if not exports['feather-core']:IsSessionCurrent(source, context.sessionId, context.characterId) then
        return ChatResults.Err('session_stale', 'Character session changed.')
    end
    local text, textError = NormalizeText(payload.text)
    if not text then return ChatResults.Err('invalid_message', textError) end
    if not RateAllowed(source) then
        return ChatResults.Err('rate_limited', 'You are sending messages too quickly.')
    end
    local identity = Profile(context.characterId)
    if not identity.ok then return identity end
    local channel = ChatChannels.Get(payload.channelKey)
    if not channel or channel.visibility == 'system' then
        return ChatResults.Err('channel_unavailable', 'That channel is unavailable.')
    end
    if #text > channel.input.maximumLength then
        return ChatResults.Err('invalid_message', 'Message is too long for that channel.')
    end
    local actor = { source=source, accountId=context.accountId,
        characterId=context.characterId, sessionId=context.sessionId }
    local access = ChatChannels.CanSend(channel, actor)
    if not access.ok or type(access.value) ~= 'table'
        or (access.value.allowed ~= true and access.value.canSend ~= true) then
        return ChatResults.Err(access.code or 'forbidden', access.message or 'You cannot send to that channel.')
    end
    local recipients, routingError
    if channel.routing == 'proximity' then
        recipients, routingError = Recipients(source, Config.Channels.proximity[channel.radius])
    else
        local audience = ChatChannels.ResolveAudience(channel, actor, ConnectedSessions())
        if audience.ok and type(audience.value) == 'table' and type(audience.value.sources) == 'table' then
            recipients = {}
            local allowed = {}
            for _, session in ipairs(ConnectedSessions()) do allowed[session.source] = true end
            for _, target in ipairs(audience.value.sources) do
                target = tonumber(target)
                if target and allowed[target] and #recipients < 256 then recipients[#recipients + 1] = target end
            end
        else
            routingError = ChatResults.Err(audience.code or 'provider_unavailable',
                audience.message or 'Channel audience is unavailable.')
        end
    end
    if not recipients then return routingError end

    sequence = sequence + 1
    local message = {
        messageId=NewUuid(), channelKey=payload.channelKey,
        channelLabel=channel.shortLabel or channel.label, kind=channel.kind or 'player',
        author=identity.value, body={ text=text, format='plain' },
        presentation=channel.presentation,
        createdAt=os.date('!%Y-%m-%dT%H:%M:%SZ'), sequence=sequence
    }
    for _, target in ipairs(recipients) do
        TriggerClientEvent('feather-chat:message:v1', target, message)
    end
    local result = ChatResults.Ok({
        messageId=message.messageId, submissionId=payload.submissionId, recipientCount=#recipients
    })
    Remember(source, payload.submissionId, result)
    return result
end

function ChatMessaging.Start()
    if ready then return ChatResults.Ok(true) end
    local registered = exports['feather-core']:RegisterContractRPC('chat.message.submit.v1', Submit, {
        contract=1, direction='client_to_server', requireCharacter=true,
        windowMs=3000, maxCalls=6, maxPayloadBytes=Config.Limits.maxMessageBytes + 256,
        maxDepth=4, maxNodes=16,
        validatePayload=function(payload)
            return ChatContract.ValidateSubmission(payload, Config.Limits)
        end
    })
    if type(registered) ~= 'table' or registered.ok ~= true then return registered end
    ready = true
    return ChatResults.Ok(true)
end

function ChatMessaging.IsReady() return ready end
function ChatMessaging.NormalizeText(text) return NormalizeText(text) end

AddEventHandler('playerDropped', function()
    rates[source], submissions[source] = nil, nil
end)

