-- server.lua
-- Сервер для "телеграмма" на CC:Tweaked
-- Использует modem channel 1384 для приёма регистраций и команд
-- Модифицируйте server_key по необходимости

local modem_channel = 1384
local server_key = "s3rv3r_secret_key" -- простой общий ключ для XOR-шифрования
local modem = nil
local json = textutils.serialize and {
    encode = function(t) return textutils.serialize(t) end,
    decode = function(s) return textutils.unserialize(s) end
} or error("No textutils.serialize present")

-- Структуры
local clients = {} -- [username] = {channel=..., lastSeen=os.time(), address=remoteAddress}
local msg_counter = 0
local stats = {
    total_sent = 0,
    total_failed = 0,
    total_received = 0,
    per_client = {}, -- [username] = {sent=, received=, failed=}
}
local pending = {} -- [msgid] = {to=, from=, encrypted_payload=, attempts=, time=}

-- Найти модем
local function find_modem()
    local p = peripheral.find("modem")
    if not p then
        error("No modem peripheral found on this computer")
    end
    return p
end

modem = find_modem()
-- Открыть канал сервера
modem.open(modem_channel)

local function xor_crypt(data, key)
    local out = {}
    for i = 1, #data do
        local a = data:byte(i)
        local b = key:byte(((i-1) % #key) + 1)
        out[i] = string.char(bit32.bxor(a, b))
    end
    return table.concat(out)
end

local function new_msg_id()
    msg_counter = msg_counter + 1
    return tostring(os.time()) .. "-" .. tostring(msg_counter)
end

local function ensure_client_stats(name)
    stats.per_client[name] = stats.per_client[name] or {sent=0, received=0, failed=0}
end

-- пересылаем зашифрованное сообщение на целевой канал
local function forward_message(msgid, from, to, plaintext)
    local target = clients[to]
    if not target then
        print("Target not registered: " .. tostring(to))
        ensure_client_stats(from)
        stats.per_client[from].failed = stats.per_client[from].failed + 1
        stats.total_failed = stats.total_failed + 1
        return
    end
    local encrypted = xor_crypt(plaintext, server_key)
    local payload = {
        type = "deliver",
        id = msgid,
        from = from,
        data = encrypted
    }
    local packed = json.encode(payload)
    -- отправляем на канал клиента
    modem.transmit(target.channel, modem_channel, packed)
    pending[msgid] = {to=to, from=from, encrypted_payload=encrypted, attempts=1, time=os.time()}
    stats.total_sent = stats.total_sent + 1
    ensure_client_stats(from)
    stats.per_client[from].sent = stats.per_client[from].sent + 1
    print("Forwarded msg " .. msgid .. " -> " .. to .. " (channel " .. tostring(target.channel) .. ")")
end

local function handle_register(payload, remoteAddr)
    -- payload: {type="register", username=..., channel=...}
    if not payload.username or not payload.channel then
        return
    end
    clients[payload.username] = {channel = payload.channel, lastSeen = os.time(), address = remoteAddr}
    print("Registered: " .. payload.username .. " @ channel " .. tostring(payload.channel))
    -- reply ack
    modem.transmit(payload.channel, modem_channel, json.encode({type="reg_ack", msg="ok"}))
end

local function handle_send(payload, remoteAddr)
    -- payload: {type="send", to=..., from=..., text=...}
    if not payload.to or not payload.from or not payload.text then return end
    local id = new_msg_id()
    stats.total_received = stats.total_received + 1
    ensure_client_stats(payload.from)
    stats.per_client[payload.from].received = stats.per_client[payload.from].received + 1
    forward_message(id, payload.from, payload.to, payload.text)
end

local function handle_ack(payload, remoteAddr)
    -- payload: {type="ack", id=...}
    if not payload.id then return end
    local rec = pending[payload.id]
    if rec then
        pending[payload.id] = nil
        print("Received ACK for " .. payload.id .. " (to " .. rec.to .. ")")
    end
end

local function handle_client_ping(payload, remoteAddr)
    if not payload.username then return end
    if clients[payload.username] then
        clients[payload.username].lastSeen = os.time()
        clients[payload.username].address = remoteAddr
    end
end

local function handle_stats_request(payload, remoteAddr)
    -- reply with stats (non-encrypted)
    local reply = {type="stats", stats=stats, clients=clients}
    local packed = json.encode(reply)
    -- send back to requester via modem.transmit using their channel if provided
    if payload.reply_channel then
        modem.transmit(payload.reply_channel, modem_channel, packed)
    else
        -- if no channel provided, try to send to remoteAddr (best-effort)
        modem.transmit(modem_channel, modem_channel, packed)
    end
end

-- Обработчик входящих сообщений на сервере
local function server_event_loop()
    while true do
        local event = {os.pullEvent()}
        if event[1] == "modem_message" then
            local side, senderChannel, replyChannel, message, distance = event[2], event[3], event[4], event[5], event[6]
            local ok, payload = pcall(json.decode, message)
            if not ok or type(payload) ~= "table" then
                print("Received invalid payload from " .. tostring(replyChannel))
            else
                local t = payload.type
                if t == "register" then
                    handle_register(payload, senderChannel)
                elseif t == "send" then
                    handle_send(payload, senderChannel)
                elseif t == "ack" then
                    handle_ack(payload, senderChannel)
                elseif t == "ping" then
                    handle_client_ping(payload, senderChannel)
                elseif t == "req_stats" then
                    handle_stats_request(payload, senderChannel)
                else
                    print("Unknown message type: " .. tostring(t))
                end
            end
        end
        -- Таймауты ожидания ACK — простая обработка: если прошло >30 сек — пометить failed
        local now = os.time()
        for id, rec in pairs(pending) do
            if now - rec.time > 30 then
                print("Message " .. id .. " timed out")
                stats.total_failed = stats.total_failed + 1
                ensure_client_stats(rec.from)
                stats.per_client[rec.from].failed = stats.per_client[rec.from].failed + 1
                pending[id] = nil
            end
        end
    end
end

-- Запуск
print("Server starting on channel " .. tostring(modem_channel))
server_event_loop()
