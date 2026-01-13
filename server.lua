-- server.lua - ameMessenger Server (Persistence Edition)
local protocol = "messenger_v2"
local data_file = ".server_data.dat" -- Скрытый файл данных

local server_data = {
    name = "ameServer",
    clients = {}, 
    history = {}, 
    messages_queue = {}, -- Здесь хранятся сообщения для оффлайн игроков
    banned = {},
    muted = {}
}

-- Modem setup
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
    -- Миграция со старого файла, если он был
    if fs.exists("server_data.dat") then fs.move("server_data.dat", data_file) end

    if fs.exists(data_file) then
        local f = fs.open(data_file, "r")
        local data = textutils.unserialize(f.readAll())
        f.close()
        if type(data) == "table" then
            for k, v in pairs(data) do server_data[k] = v end
        end
    end
end

local function clone_packet(msg, senderID)
    return {
        sender = senderID,
        senderName = tostring(msg.senderName or "Unknown"),
        target = tonumber(msg.target),
        message = tostring(msg.message or ""),
        time = os.epoch("utc")
    }
end

local function draw_stats()
    local w, h = term.getSize()
    local oldX, oldY = term.getCursorPos()
    
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" ameServer | ID: " .. os.getComputerID() .. " | Persistent Queue")

    local total, online = 0, 0
    local now = os.epoch("utc")
    for id, c in pairs(server_data.clients) do
        total = total + 1
        if now - (c.lastSeen or 0) < 60000 then online = online + 1 end
    end

    term.setBackgroundColor(colors.black)
    term.setCursorPos(1, 3)
    term.clearLine()
    term.setTextColor(colors.green)
    term.write(" Online: " .. online)
    term.setCursorPos(1, 4)
    term.clearLine()
    term.setTextColor(colors.lightGray)
    term.write(" Registered: " .. total)

    term.setCursorPos(1, h-1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" Commands: id, ban, mute, unban, unmute")
    term.setCursorPos(oldX, oldY)
end

local function handle_requests()
    while true do
        local id, msg = rednet.receive(protocol)
        if type(msg) == "table" then
            if server_data.clients[id] then
                server_data.clients[id].lastSeen = os.epoch("utc")
            end

            if msg.type == "register" then
                server_data.clients[id] = {name = msg.name or "User"..id, lastSeen = os.epoch("utc")}
                rednet.send(id, {type = "register_response", success = true}, protocol)
                save_data()

            elseif msg.type == "send_message" then
                if server_data.banned[id] then
                    rednet.send(id, {type = "error", message = "Banned"}, protocol)
                elseif server_data.muted[id] then
                    rednet.send(id, {type = "error", message = "Muted"}, protocol)
                elseif msg.target then
                    -- Сохраняем в историю и в очередь для получения
                    local pkt = clone_packet(msg, id)
                    table.insert(server_data.history, pkt)
                    
                    server_data.messages_queue[msg.target] = server_data.messages_queue[msg.target] or {}
                    table.insert(server_data.messages_queue[msg.target], pkt)
                    
                    save_data() -- Сразу на диск, чтобы не потерять оффлайн-сообщение
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
                if #q > 0 then
                    rednet.send(id, {type = "messages", messages = q}, protocol)
                    server_data.messages_queue[id] = {} -- Очищаем очередь, так как клиент их забрал
                    save_data() -- Сохраняем факт получения
                end
            end
            draw_stats()
        end
    end
end

-- Консоль (id, ban, mute) остается без изменений
local function console_handler()
    local w, h = term.getSize()
    while true do
        draw_stats()
        term.setCursorPos(1, h)
        term.write("> ")
        local input = read()
        local tArgs = {}
        for s in input:gmatch("%S+") do table.insert(tArgs, s) end
        local cmd = tArgs[1]

        if cmd == "id" then
            term.setBackgroundColor(colors.black)
            term.clear()
            term.setCursorPos(1,1)
            for cid, cdata in pairs(server_data.clients) do
                print("ID: "..cid.." | Name: "..cdata.name)
            end
            print("\nPress any key...")
            os.pullEvent("key")
        elseif cmd == "ban" or cmd == "mute" then
            local target = tonumber(tArgs[2])
            local duration = tonumber(tArgs[3]) or 0
            local reason = tArgs[4] or "No reason"
            local expiry = (duration > 0) and (os.epoch("utc") + duration * 60000) or 0
            
            if target then
                if cmd == "ban" then server_data.banned[target] = {expires=expiry, reason=reason}
                else server_data.muted[target] = {expires=expiry, reason=reason} end
                save_data()
            end
        elseif cmd == "unban" or cmd == "unmute" then
            local target = tonumber(tArgs[2])
            if target then
                if cmd == "unban" then server_data.banned[target] = nil
                else server_data.muted[target] = nil end
                save_data()
            end
        end
    end
end

if not active_side then error("No modem!") end
load_data()
rednet.host(protocol, server_data.name)
parallel.waitForAny(handle_requests, console_handler)
