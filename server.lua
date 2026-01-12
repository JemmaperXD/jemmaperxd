local PORT = 1384
local modem = peripheral.find("modem") or error("No modem found")
modem.open(PORT)

local users = {} -- [id] = name

-- Функция шифрования (Ключ 7, чтобы клиент смог расшифровать)
local function encrypt(text, key)
    local res = ""
    for i = 1, #text do
        res = res .. string.char((text:byte(i) + key) % 256)
    end
    return res
end

print("=== SERVER STARTED ===")
print("My ID: " .. os.getComputerID())
print("Waiting for clients...")

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
                -- ШИФРУЕМ сообщение перед пересылкой (Ключ 7)
                local encrypted_msg = encrypt(msg.text, 7)
                
                modem.transmit(targetID, PORT, {
                    type = "msg",
                    from = msg.user,
                    text = encrypted_msg
                })
                print("Msg: " .. msg.user .. " -> " .. msg.to .. " (Encrypted)")
            else
                print("Error: Target " .. tostring(msg.to) .. " not found!")
            end
        end
    end
end
