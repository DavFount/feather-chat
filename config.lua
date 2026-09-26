Config = {
    DevMode = false,
    Input = {
        command = 'chat',
        defaultKey = 'T',
        closeOnSubmit = true
    },
    Channels = {
        oocEnabled = false,
        proximity = { whisper=3.0, say=15.0, roleplay=15.0, shout=35.0 }
    },
    Limits = {
        maxMessageBytes = 500,
        maxMessageLines = 4,
        maxClientBuffer = 100,
        maxInputHistory = 20,
        callbackTimeoutMs = 5000
    },
    RateLimit = {
        windowMs = 10000,
        maxMessages = 5
    },
    Layout = {
        anchor = 'top-left',
        widthVw = 38,
        maxHeightVh = 28,
        density = 'comfortable',
        fadeDelayMs = 7000,
        idleOpacity = 0.75,
        timestamps = true,
        fontScale = 1.0,
        reducedMotion = false
    },
    Theme = {
        default = 'feather.default',
        approved = { 'feather.default', 'feather.high_contrast' }
    },
    Features = { history=false, privateMessages=false, emojiPicker=false }
}
