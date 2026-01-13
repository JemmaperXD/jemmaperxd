-- server.lua - ameMessenger Server (Final Stable)
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

-- Глубокое клонирование для разрыва всех связей между таблицами
local function deep_copy(obj)
    if type(obj) ~= 'table' then return obj end
    local res = {}
    for k, v in pairs(obj) do res[k] = deep_copy(v) end
    return res
end

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
    if f then
        -- Создаем чистую копию данных для сериализации
        local clean_data = deep_copy(server_data)
        f.write(textutils.serialize(clean_data))
        f.close()
    end
end

local function load_data()
    if fs.exists(data_file) then
        local f = fs.open(data_file, "r")
        local content = f.readAll()
        f.close()
        local data = textutils.unserialize(content)
        if type(data) == "table" then
            for k, v in pairs(data) do server_data[k] = v end
        end
    end
end

local function add_to_log(id, pkt)
    server_data.chat_logs[id] = server_data.chat_logs[id] or {}
    table.insert(server_data.chat_logs[id], deep_copy(pkt)) -- Клонируем в лог
    if #server_data.chat_logs[id] > 10 then table.remove(server_data.chat_logs[id], 1) end
end

local function draw_stats()
    local w, h = term.getSize()
    local oldX, oldY = term.getCursorPos()
    
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" ameServer ADMIN | ID: " .. os.getComputerID())

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
    
    term.setCursorPos(1, h-1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" Cmd: id, reports, clear_reports, ban")
    
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
                save_data()
            elseif msg.type == "send_message" then
                if not server_data.banned[id] and msg.target then
                    local pkt = {
                        sender = id,
                        senderName = tostring(msg.senderName or "Unknown"),
                        target = tonumber(msg.target),
                        message = tostring(msg.message or ""),
                        time = os.epoch("utc")
                    }
                    
                    table.insert(server_data.history, deep_copy(pkt))
                    server_data.messages_queue[msg.target] = server_data.messages_queue[msg.target] or {}
                    table.insert(server_data.messages_queue[msg.target], deep_copy(pkt))
                    
                    add_to_log(id, pkt)
                    add_to_log(msg.target, pkt)
                    save_data()
                end
            elseif msg.type == "report" then
                local logs = deep_copy(server_data.chat_logs[id] or {})
                table.insert(server_data.reports, {from=id, reason=msg.reason, logs=logs})
                save_data()
                rednet.send(id, {type = "error", message = "Report sent!"}, protocol)
            elseif msg.type == "get_online" then
                local list = {}
                local now = os.epoch("utc")
                for cid, c in pairs(server_data.clients) do
                    if cid ~= id and (now - (c.lastSeen or 0) < 60000) then 
                        table.insert(list, {id = cid, name = c.name})
                    end
                end
                rednet.send(id, {type = "online_list", clients = list}, protocol)
            elseif msg.type == "get_messages" then
                local q = server_data.messages_queue[id] or {}
                if #q > 0 then
                    rednet.send(id, {type = "messages", messages = deep_copy(q)}, protocol)
                    server_data.messages_queue[id] = {}
                    save_data()
                end
            end
            draw_stats()
        end
    end
end

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
            for cid, c in pairs(server_data.clients) do print("ID: "..cid.." | Name: "..c.name) end
            os.pullEvent("key")
        elseif cmd == "reports" then
            term.clear()
            term.setCursorPos(1,1)
            for i, r in ipairs(server_data.reports) do
                print(i..". From "..r.from..": "..r.reason)
                for _, m in ipairs(r.logs) do print("  ["..m.senderName.."]: "..m.message) end
            end
            os.pullEvent("key")
        elseif cmd == "clear_reports" then
            server_data.reports = {}
            save_data()
        elseif cmd == "ban" then
            local tid = tonumber(tArgs[2])
            if tid then server_data.banned[tid] = true; save_data() end
        end
    end
end

load_data()
if not active_side then error("No modem!") end
rednet.host(protocol, server_data.name)
parallel.waitForAny(handle_requests, console_handler)
