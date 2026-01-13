-- server.lua - ameMessenger Server (English/Stable)
local protocol = "messenger_v2"
local data_file = "server_data.dat"

local server_data = {
    name = "ameServer",
    clients = {}, 
    history = {}, 
    messages_queue = {},
    banned = {}, -- [id] = {expires = timestamp, reason = string}
    muted = {}   -- [id] = {expires = timestamp, reason = string}
}

-- Modem Init
local function get_modem()
    for _, s in ipairs(peripheral.getNames()) do
        if peripheral.getType(s) == "modem" then
            rednet.open(s)
            return s
        end
    end
    return nil
end

local active_side = get_modem()

local function save_data()
    local f = fs.open(data_file, "w")
    f.write(textutils.serialize(server_data))
    f.close()
end

local function load_data()
    if fs.exists(data_file) then
        local f = fs.open(data_file, "r")
        local data = textutils.unserialize(f.readAll())
        f.close()
        if type(data) == "table" then
            for k, v in pairs(data) do server_data[k] = v end
            server_data.banned = server_data.banned or {}
            server_data.muted = server_data.muted or {}
        end
    end
end

local function check_penalty(penalty_table, id)
    local p = penalty_table[id]
    if not p then return nil end
    if p.expires ~= 0 and os.epoch("utc") > p.expires then
        penalty_table[id] = nil
        save_data()
        return nil
    end
    return p
end

local function draw_dashboard()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()
    
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.gray)
    term.clearLine()
    term.setTextColor(colors.white)
    term.write(" ameServer ADMIN | ID: " .. os.getComputerID())

    local total, online = 0, 0
    local now = os.epoch("utc")
    for id, c in pairs(server_data.clients) do
        total = total + 1
        if now - (c.lastSeen or 0) < 60000 then online = online + 1 end
    end

    term.setBackgroundColor(colors.black)
    term.setCursorPos(2, 3)
    term.setTextColor(colors.green)
    term.write("Online: " .. online)
    term.setCursorPos(2, 4)
    term.setTextColor(colors.lightGray)
    term.write("Total: " .. total)

    term.setCursorPos(1, h-1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write("Cmd: ban/mute <id> <min> <reason>")
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.black)
    term.write("> ")
end

local function handle_requests()
    while true do
        local id, msg = rednet.receive(protocol)
        if type(msg) == "table" then
            
            local ban = check_penalty(server_data.banned, id)
            if ban then
                local timeLeft = ban.expires == 0 and "permanent" or math.ceil((ban.expires - os.epoch("utc"))/60000).."m"
                rednet.send(id, {type = "error", message = "BANNED ("..timeLeft.."). Reason: "..ban.reason}, protocol)
            
            elseif msg.type == "register" then
                server_data.clients[id] = {name = msg.name or "User"..id, lastSeen = os.epoch("utc")}
                rednet.send(id, {type = "register_response", success = true}, protocol)
                save_data()

            elseif msg.type == "send_message" then
                local mute = check_penalty(server_data.muted, id)
                if mute then
                    rednet.send(id, {type = "error", message = "MUTED. Reason: "..mute.reason}, protocol)
                elseif msg.target and type(msg.target) == "number" then
                    local pkt = {sender = id, senderName = msg.senderName, target = msg.target, message = msg.message, time = os.epoch("utc")}
                    server_data.messages_queue[msg.target] = server_data.messages_queue[msg.target] or {}
                    table.insert(server_data.messages_queue[msg.target], pkt)
                    rednet.send(id, {type = "message_response", success = true}, protocol)
                end

            elseif msg.type == "get_online" then
                local list = {}
                for cid, c in pairs(server_data.clients) do
                    if os.epoch("utc") - (c.lastSeen or 0) < 60000 then 
                        table.insert(list, {id = cid, name = c.name})
                    end
                end
                rednet.send(id, {type = "online_list", clients = list}, protocol)

            elseif msg.type == "get_messages" then
                local q = server_data.messages_queue[id] or {}
                rednet.send(id, {type = "messages", messages = q}, protocol)
                server_data.messages_queue[id] = {}
            end
        end
        draw_dashboard()
    end
end

local function console_handler()
    while true do
        draw_dashboard()
        local input = read()
        local tArgs = {}
        for s in input:gmatch("%S+") do table.insert(tArgs, s) end
        
        local cmd, target, duration = tArgs[1], tonumber(tArgs[2]), tonumber(tArgs[3])
        local reason_parts = {}
        for i=4, #tArgs do table.insert(reason_parts, tArgs[i]) end
        local reason = #reason_parts > 0 and table.concat(reason_parts, " ") or "No reason"

        if cmd and target then
            local expiry = 0
            if duration and duration > 0 then expiry = os.epoch("utc") + (duration * 60000) end

            if cmd == "ban" then
                server_data.banned[target] = {expires = expiry, reason = reason}
            elseif cmd == "mute" then
                server_data.muted[target] = {expires = expiry, reason = reason}
            elseif cmd == "unban" then
                server_data.banned[target] = nil
            elseif cmd == "unmute" then
                server_data.muted[target] = nil
            end
            save_data()
        end
    end
end

if not active_side then error("No modem found!") end
load_data()
rednet.host(protocol, server_data.name)
parallel.waitForAny(handle_requests, console_handler)
