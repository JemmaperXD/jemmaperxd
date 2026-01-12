local PORT = 1384
local modem = peripheral.find("modem") or error("No modem found!")
modem.open(PORT)

local users = {} -- [id] = {name = name, lastSeen = time}
local logs = {}
local msg_count = 0

-- Функция шифрования (Ключ 7)
local function encrypt(text, key)
    local res = ""
    for i = 1, #text do
        res = res .. string.char((text:byte(i) + key) % 256)
    end
    return res
end

local function update_display()
    term.setBackgroundColor(colors.gray)
    term.clear()
    term.setCursorPos(1,1)
    term.setTextColor(colors.white)
    print(" [TG-SERVER] | ID: " .. os.getComputerID())
    print(string.rep("-", 40))
    print(" Msg | From -> To | Status | Online Users: " .. #users)
    print(string.rep("-", 40))
    for i = math.max(1, #logs-10), #logs do print(logs[i]) end
end

-- Автоматическое удаление оффлайн пользователей
local function cleanup()
    while true do
        local now = os.epoch("utc") / 1000
        for id, data in pairs(users) do
            if now - data.lastSeen > 10 then users[id] = nil end
        end
        sleep(5)
    end
end

local function main_loop()
    update_display()
    while true do
        local event, _, channel, replyID, msg = os.pullEvent("modem_message")
        
        if event == "modem_message" and channel == PORT and type(msg) == "table" then
            local now = os.epoch("utc") / 1000

            if msg.type == "handshake" or msg.type == "ping" then
                users[replyID] = {name = msg.user or "Unknown", lastSeen = now}
                local names = {}
                for _, v in pairs(users) do table.insert(names, v.name) end
                
                -- Отправляем статус и список пользователей обратно клиенту
                modem.transmit(replyID, PORT, {type = "status", users = names})

            elseif msg.type == "send" then
                msg_count = msg_count + 1
                local targetID = nil
                for id, u in pairs(users) do if u.name == msg.to then targetID = id break end end

                if targetID then
                    local encrypted_msg = encrypt(msg.text, 7)
                    modem.transmit(targetID, PORT, {type = "msg", from = msg.user, text = encrypted_msg})
                    table.insert(logs, string.format("[%03d] %s -> %s (OK)", msg_count, msg.user, msg.to))
                else
                    table.insert(logs, string.format("[%03d] %s -> %s (OFFLINE)", msg_count, msg.user, msg.to))
                end
                update_display()
            end
        end
    end
end

parallel.waitForAll(main_loop, cleanup)
