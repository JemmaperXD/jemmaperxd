-- server.lua - ameMessenger Server (Final Version)
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
    chat_logs = {} -- Хранит последние 10 сообщений для контекста репортов
}

-- Настройка модема
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

-- Глубокое копирование для исключения ошибок сериализации (repeated entries)
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

-- Логирование для репортов
local function add_to_log(id, pkt)
    server_data.chat_logs[id] = server_data.chat_logs[id] or {}
    table.insert(server_data.chat_logs[id], pkt)
    if #server_data.chat_logs[id] > 10 then table.remove(server_data.chat_logs[id], 1) end
end

-- Интерфейс сервера (без term.clear для стабильности ввода)
local function draw_stats()
    local w, h = term.getSize()
    local oldX, oldY = term.getCursorPos()
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" ameServer ADMIN | ID: " .. os.getComputerID())

    local online = 0
    for id, c in pairs(server_data.clients) do
        if os.epoch("utc") - (c.lastSeen or 0) < 60000 then online = online + 1 end
    end

    term.setBackgroundColor(colors.black)
    term.setCursorPos(1, 3)
    term.clearLine()
    term.setTextColor(colors.green)
    term.write(" Online: " .. online .. " | Reports: " .. #server_data.reports)
    
    term.setCursorPos(1, h-1)
    term.setBackgroundColor(colors.blue)
    term.clearLine()
    term.write(" Cmd: id, ban, mute, reports, clear_reports")
    term.setCursorPos(oldX, oldY)
end

local function handle_requests()
    while true do
        local id, msg = rednet.receive(protocol)
        if type(msg) == "table" then
            if server_data.clients[id] then server_data.clients[id].lastSeen = os.epoch("utc") end

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
                    local pktH = clone_packet(msg, id)
                    local pktQ = clone_packet(msg, id)
                    table.insert(server_data.history, pktH)
                    server_data.messages_queue[msg.target] = server_data.messages_queue[msg.target] or {}
                    table.insert(server_data.messages_queue[msg.target], pktQ)
                    add_to_log(id, pktH)
                    add_to_log(msg.target, pktH)
                    save_data()
                    rednet.send(id, {type = "message_response", success = true}, protocol)
                end
            elseif msg.type == "report" then
                local logs = {}
                if server_data.chat_logs[id] then
                    for _, l in ipairs(server_data.chat_logs[id]) do table.insert(logs, l) end
                end
                table.insert(server_data.reports, {from=id, reason=msg.reason, logs=logs})
                save_data()
                rednet.send(id, {type = "error", message = "Report sent!"}, protocol)
            elseif msg.type == "get_online" then
                local list = {}
                for cid, c in pairs(server_data.clients) do
                    if cid ~= id and os.epoch("utc") - (c.lastSeen or 0) < 60000 then 
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

        if cmd == "reports" then
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
        elseif cmd == "id" then
            term.clear()
            for cid, c in pairs(server_data.clients) do print("ID: "..cid.." | Name: "..c.name) end
            os.pullEvent("key")
        elseif cmd == "ban" or cmd == "mute" then
            local target, dur = tonumber(tArgs[2]), tonumber(tArgs[3]) or 0
            local exp = dur > 0 and (os.epoch("utc") + dur * 60000) or 0
            if target then
                if cmd == "ban" then server_data.banned[target] = {expires=exp}
                else server_data.muted[target] = {expires=exp} end
                save_data()
            end
        end
    end
end

load_data()
if not active_side then error("No modem!") end
rednet.host(protocol, server_data.name)
parallel.waitForAny(handle_requests, console_handler)
