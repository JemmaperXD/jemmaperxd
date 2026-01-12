local modem = peripheral.find("modem") or error("No modem found")
local PORT = 1384
modem.open(PORT)

local users = {} -- [id] = name
local message_log = {} -- Таблица статистики
local msg_count = 0

local function encrypt(text, key)
    local result = ""
    for i = 1, #text do
        result = result .. string.char((text:byte(i) + key) % 256)
    end
    return result
end

local function draw_stats()
    term.clear()
    term.setCursorPos(1,1)
    print("=== TG-CC Server (ID: "..os.getComputerID()..") ===")
    print("Msg ID | From -> To | Status")
    print("----------------------------")
    for i = math.max(1, #message_log - 10), #message_log do
        local m = message_log[i]
        print(string.format("%04d | %s -> %s | OK", m.id, m.from, m.to))
    end
end

draw_stats()

while true do
    local _, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
    
    if type(message) == "table" and channel == PORT then
        if message.type == "handshake" then
            users[replyChannel] = message.user
            modem.transmit(replyChannel, PORT, {type = "system", data = "Connected"})
            
        elseif message.type == "send" then
            msg_count = msg_count + 1
            local encrypted_data = encrypt(message.text, 5) -- Простейшее шифрование
            
            local target_id = nil
            for id, name in pairs(users) do
                if name == message.to then target_id = id break end
            end
            
            if target_id then
                modem.transmit(target_id, PORT, {
                    type = "msg",
                    from = message.user,
                    id = msg_count,
                    text = encrypted_data
                })
                -- Подтверждение отправителю
                modem.transmit(replyChannel, PORT, {type = "ack", id = msg_count})
            end
            
            table.insert(message_log, {id = msg_count, from = message.user, to = message.to})
            draw_stats()
        end
    end
end
