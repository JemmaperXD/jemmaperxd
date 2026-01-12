local PORT = 1384
local modem = peripheral.find("modem") or error("No modem found")
modem.open(PORT)

local users = {}
local logs = {}

local function encrypt(text, key)
    local res = ""
    for i = 1, #text do res = res .. string.char((text:byte(i) + key) % 256) end
    return res
end

print("Server Started. ID: "..os.getComputerID())
print("Waiting for messages...")

while true do
    local _, _, channel, replyChannel, msg = os.pullEvent("modem_message")
    
    -- Дебаг в консоль сервера
    print("Received from "..replyChannel..": type="..(type(msg) == "table" and tostring(msg.type) or "not a table"))

    if type(msg) == "table" then
        if msg.type == "handshake" or msg.type == "ping" then
            users[replyChannel] = msg.user or "Unknown"
            
            local list = {}
            for _, name in pairs(users) do table.insert(list, name) end
            
            -- Отправляем ответ, который ЖДЕТ клиент
            modem.transmit(replyChannel, PORT, {
                type = "status",
                online = true,
                users = list
            })
            print("Sent Status to "..replyChannel)

        elseif msg.type == "send" then
            local target_id = nil
            for id, name in pairs(users) do
                if name == msg.to then target_id = id break end
            end

            if target_id then
                modem.transmit(target_id, PORT, {
                    type = "msg",
                    from = msg.user,
                    text = encrypt(msg.text, 7)
                })
                table.insert(logs, msg.user.." -> "..msg.to)
                print("Forwarded msg to "..msg.to)
            end
        end
    end
end
