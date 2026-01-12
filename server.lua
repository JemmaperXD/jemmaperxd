local modem = peripheral.find("modem") or error("No modem found")
local PORT = 1384
modem.open(PORT)

local online_users = {} -- [computerID] = {name = name, lastSeen = time}
local logs = {}
local msg_id = 0

local function encrypt(text, key)
    local res = ""
    for i = 1, #text do res = res .. string.char((text:byte(i) + key) % 256) end
    return res
end

local function update_stats()
    term.setBackgroundColor(colors.gray)
    term.clear()
    term.setCursorPos(1,1)
    term.setTextColor(colors.white)
    print(" TG-SERVER | Online: " .. #online_users)
    print("--------------------------------")
    for i = math.max(1, #logs-10), #logs do
        print(logs[i])
    end
end

-- Удаление оффлайн пользователей (через 15 сек)
local function cleanup()
    while true do
        local now = os.epoch("utc") / 1000
        for id, data in pairs(online_users) do
            if now - data.lastSeen > 15 then online_users[id] = nil end
        end
        sleep(5)
    end
end

local function main()
    update_stats()
    while true do
        local event, side, chan, reply, msg, dist = os.pullEvent("modem_message")
        if chan == PORT and type(msg) == "table" then
            local now = os.epoch("utc") / 1000
            
            if msg.type == "ping" then
                online_users[reply] = {name = msg.user, lastSeen = now}
                -- Отправляем список всех онлайн пользователей назад
                local list = {}
                for _, v in pairs(online_users) do table.insert(list, v.name) end
                modem.transmit(reply, PORT, {type = "user_list", users = list})

            elseif msg.type == "send" then
                msg_id = msg_id + 1
                local enc = encrypt(msg.text, 7)
                local target_id = nil
                for id, u in pairs(online_users) do
                    if u.name == msg.to then target_id = id break end
                end

                if target_id then
                    modem.transmit(target_id, PORT, {type = "msg", from = msg.user, text = enc, id = msg_id})
                    modem.transmit(reply, PORT, {type = "ack", id = msg_id, status = "Sent"})
                    table.insert(logs, string.format("[%d] %s -> %s", msg_id, msg.user, msg.to))
                else
                    modem.transmit(reply, PORT, {type = "ack", id = msg_id, status = "User Offline"})
                end
                update_stats()
            end
        end
    end
end

parallel.waitForAll(main, cleanup)
