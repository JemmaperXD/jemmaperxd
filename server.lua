local PORT = 1384
local modem = peripheral.find("modem") or error("No modem found")
modem.open(PORT)

local users = {}
local logs = {}

-- Функция шифрования (Ключ 7)
local function encrypt(text, key)
    local res = ""
    for i = 1, #text do
        res = res .. string.char((text:byte(i) + key) % 256)
    end
    return res
end

print("=== SERVER STARTED (DEBUG MODE) ===")
print("My ID: " .. os.getComputerID())
print("Listening on PORT: " .. PORT)
print(string.rep("-", 40))

while true do
    -- Ждем ЛЮБОЕ событие
    local event, p1, p2, p3, p4 = os.pullEvent()

    if event == "modem_message" then
        local channel, replyID, msg = p1, p2, p4 -- p1, p2, p3, p4 изменен на channel, replyID, _, msg для ясности

        -- Дебаг в консоль
        print("Received event on channel " .. channel .. " from ID " .. replyID)
        print("Message Type: " .. (type(msg) == "table" and tostring(msg.type) or "Not a table"))
        
        if type(msg) == "table" and channel == PORT then
            if msg.type == "handshake" or msg.type == "ping" then
                users[replyID] = msg.user or "Unknown"
                
                local names = {}
                for _, name in pairs(users) do table.insert(names, name) end
                
                -- Отправляем ответ, который ЖДЕТ клиент
                modem.transmit(replyID, PORT, {
                    type = "status",
                    users = names
                })
                print("-> Sent STATUS reply to " .. replyID)

            elseif msg.type == "send" then
                local targetID = nil
                for id, name in pairs(users) do
                    if name == msg.to then targetID = id break end
                end

                if targetID then
                    local encrypted_msg = encrypt(msg.text, 7)
                    modem.transmit(targetID, PORT, {
                        type = "msg",
                        from = msg.user,
                        text = encrypted_msg
                    })
                    print("-> Forwarded MSG to " .. msg.to)
                end
            end
        end
    end
end
