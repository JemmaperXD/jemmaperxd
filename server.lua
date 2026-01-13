-- server.lua - ameMessenger Server (Final Fix)
local protocol = "messenger_v2"
local data_file = ".server_data.dat"

local server_data = {
    name = "ameServer",
    clients = {}, 
    history = {}, 
    messages_queue = {},
    banned = {},
    muted = {},
    reports = {},
    chat_logs = {}
}

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

local function clone_packet(msg, senderID)
    return {
        sender = tonumber(senderID),
        senderName = tostring(msg.senderName or "Unknown"),
        target = tonumber(msg.target),
        message = tostring(msg.message or ""),
        time = os.epoch("utc")
    }
end

local function save_data()
    local f = fs.open(data_file, "w")
    if f then
        f.write(textutils.serialize(server_data))
        f.close()
    end
end

local function load_data()
    if fs.exists(data_file) then
        local f = fs.open(data_file, "r")
        local data = textutils.unserialize(f.readAll())
        f.close()
        if type(data) == "table" then
            for k, v in pairs(data) do server_data[k] = v end
        end
    end
end

local function draw_stats()
    local w, h = term.getSize()
    local oldX, oldY = term.getCursorPos()
    
    -- Верхняя панель (остается серой)
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" ameServer ADMIN | ID: " .. os.getComputerID())

    -- Основной текст (теперь без серого фона)
    term.setBackgroundColor(colors.black)
    
    local online = 0
    local now = os.epoch("utc")
    for id, c in pairs(server_data.clients) do
        if now - (c.lastSeen or 0) < 60000 then online = online + 1 end
    end

    term.setCursorPos(1, 3)
    term.clearLine()
    term.setTextColor(colors.green)
    term.write(" Online: " .. online .. " | Reports: " .. #server_data.reports)
    
    term.setCursorPos(1, 4)
    term.clearLine()
    term.setTextColor(colors.white)
    term.write(" Server status: Running")

    -- Командная панель
    term.setCursorPos(1, h-1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" Cmd: id, ban, mute, reports, clear_reports")
    
    term.setBackgroundColor(colors.black)
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
                    local pkt = clone_packet(msg, id)
                    table.insert(server_data.history, pkt)
                    server_data.messages_queue[msg.target] = server_data.messages_queue[msg.target] or {}
                    table.insert(server_data.messages_queue[msg.target], pkt)
                    save_data()
                    rednet.send(id, {type = "message_response", success = true}, protocol)
                end
            elseif msg.type == "get_online" then
                local list = {}
                local now = os.epoch("utc")
                for cid, c in pairs(server_data.clients) do
                    -- Исправлено: жесткая проверка на онлайн (последняя активность < 60 сек)
                    if cid ~= id and (now - (c.lastSeen or 0) < 60000) then 
                        table.insert(list, {id = cid, name = c.name})
                    end
                end
                rednet.send(id, {type = "online_list", clients = list}, protocol)
            elseif msg.type == "get_messages" then
                local q = server_data.messages_queue[id] or {}
                if #q > 0 then
                    rednet.send(id, {type = "messages", messages = q}, protocol)
                    server_data.messages_queue[id] = {}
                    save_data()
                end
            end
            draw_stats()
        end
    end
end

-- Консоль управления
local function console_handler()
    local h = select(2, term.getSize())
    while true do
        draw_stats()
        term.setCursorPos(1, h)
        term.write("> ")
        local input = read()
        local tArgs = {}
        for s in input:gmatch("%S+") do table.insert(tArgs, s) end
        local cmd = tArgs[1]

        if cmd == "id" then
            term.clear()
            term.setCursorPos(1,1)
            print("--- Registered Users ---")
            for cid, c in pairs(server_data.clients) do print("ID: "..cid.." | Name: "..c.name) end
            print("\nPress any key...")
            os.pullEvent("key")
        elseif cmd == "reports" then
            term.clear()
            term.setCursorPos(1,1)
            for i, r in ipairs(server_data.reports) do print(i..". From "..r.from..": "..r.reason) end
            os.pullEvent("key")
        elseif cmd == "clear_reports" then
            server_data.reports = {}
            save_data()
        end
    end
end

load_data()
if not active_side then error("No modem!") end
rednet.host(protocol, server_data.name)
parallel.waitForAny(handle_requests, console_handler)
