local PORT = 1384
local modem = peripheral.find("modem") or error("No modem found")
modem.open(PORT)

local users = {} -- [id] = name

print("=== SERVER STARTED ===")
print("My ID: " .. os.getComputerID())

while true do
    local _, _, channel, replyID, msg = os.pullEvent("modem_message")
    
    if type(msg) == "table" and channel == PORT then
        -- Логируем в консоль для проверки
        print("Got " .. tostring(msg.type) .. " from ID " .. replyID)

        if msg.type == "handshake" or msg.type == "ping" then
            users[replyID] = msg.user or "Unknown"
            
            local names = {}
            for _, name in pairs(users) do table.insert(names, name) end
            
            -- Шлем ответ прямо отправителю
            modem.transmit(replyID, PORT, {
                type = "status",
                users = names
            })

        elseif msg.type == "send" then
            local targetID = nil
            for id, name in pairs(users) do
                if name == msg.to then targetID = id break end
            end

            if targetID then
                modem.transmit(targetID, PORT, {
                    type = "msg",
                    from = msg.user,
                    text = msg.text -- Шифрование добавим когда заработает связь
                })
                print("Msg: " .. msg.user .. " -> " .. msg.to)
            end
        end
    end
end
