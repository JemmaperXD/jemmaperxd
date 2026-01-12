local modem = peripheral.find("modem") or error("No modem found")
local PORT = 1384
modem.open(PORT)

local online_users = {} 
local logs = {}
local msg_id = 0

local function encrypt(text, key)
    local res = ""
    for i = 1, #text do res = res .. string.char((text:byte(i) + key) % 256) end
    return res
end

local function update_display()
    term.setBackgroundColor(colors.gray)
    term.clear()
    term.setCursorPos(1,1)
    term.setTextColor(colors.white)
    print(" [TG-SERVER 2026] | Online: " .. #online_users)
    print(string.rep("-", 40))
    for i = math.max(1, #logs-12), #logs do print(logs[i]) end
end

local function main()
    update_display()
    while true do
        local _, _, chan, reply, msg = os.pullEvent("modem_message")
        if chan == PORT and type(msg) == "table" then
            local now = os.epoch("utc") / 1000
            if msg.type == "handshake" or msg.type == "ping" then
                online_users[reply] = {name = msg.user, lastSeen = now}
                local list = {}
                for _, v in pairs(online_users) do table.insert(list, v.name) end
                modem.transmit(reply, PORT, {type = "status", online = true, users = list})
            elseif msg.type == "send" then
                msg_id = msg_id + 1
                local target_id = nil
                for id, u in pairs(online_users) do if u.name == msg.to then target_id = id break end end
                if target_id then
                    modem.transmit(target_id, PORT, {type = "msg", from = msg.user, text = encrypt(msg.text, 7)})
                    table.insert(logs, string.format("[%03d] %s -> %s", msg_id, msg.user, msg.to))
                end
                update_display()
            end
        end
    end
end

parallel.waitForAll(main, function() 
    while true do
        local now = os.epoch("utc") / 1000
        for id, data in pairs(online_users) do if now - data.lastSeen > 10 then online_users[id] = nil end end
        sleep(5)
    end
end)
