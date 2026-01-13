-- server.lua - ameMessenger Server (Stable History Edition)
local protocol = "messenger_v2"
local data_file = ".server_data.dat"

local server_storage = {
    clients = {}, 
    messages_queue = {}, -- Очередь для доставки сообщений клиентам
    banned = {},
    muted = {},
    reports = {}
}

local chat_logs = {} -- Временные логи для репортов (в RAM)

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

-- Функция глубокого копирования (разрывает связи между таблицами)
local function copy_table(obj)
    if type(obj) ~= 'table' then return obj end
    local res = {}
    for k, v in pairs(obj) do res[k] = copy_table(v) end
    return res
end

local function save_data()
    local f = fs.open(data_file, "w")
    if f then
        f.write(textutils.serialize(copy_table(server_storage)))
        f.close()
    end
end

local function load_data()
    if fs.exists(data_file) then
        local f = fs.open(data_file, "r")
        local data = textutils.unserialize(f.readAll())
        f.close()
        if type(data) == "table" then
            for k, v in pairs(data) do server_storage[k] = v end
        end
    end
end

-- Логи для контекста репортов
local function add_to_log(id, pkt)
    chat_logs[id] = chat_logs[id] or {}
    table.insert(chat_logs[id], copy_table(pkt))
    if #chat_logs[id] > 10 then table.remove(chat_logs[id], 1) end
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
    for id, c in pairs(server_storage.clients) do
        if now - (c.lastSeen or 0) < 60000 then online = online + 1 end
    end

    term.setCursorPos(1, 3)
    term.setTextColor(colors.green)
    term.clearLine()
    term.write(" Online: " .. online .. " | Reports: " .. #server_storage.reports)
    
    term.setCursorPos(1, h-1)
    term.setBackgroundColor(colors.blue)
    term.clearLine()
    term.write(" Cmd: id, reports, clear_reports, ban")
    term.setBackgroundColor(colors.black)
    term.setCursorPos(oldX, oldY)
end

local function handle_requests()
    while true do
        local id, msg = rednet.receive(protocol)
        if type(msg) == "table" then
            if server_storage.clients[id] then
                server_storage.clients[id].lastSeen = os.epoch("utc")
            end

            if msg.type == "register" then
                server_storage.clients[id] = {name = tostring(msg.name or "User"..id), lastSeen = os.epoch("utc")}
                save_data()

            elseif msg.type == "send_message" then
                if not server_storage.banned[id] and msg.target then
                    local pkt = {
                        sender = id,
                        senderName = tostring(msg.senderName or "Unknown"),
                        target = tonumber(msg.target),
                        message = tostring(msg.message or ""),
                        time = os.epoch("utc")
                    }
                    
                    -- Добавляем в очередь получателя (для загрузки на его клиент)
                    server_storage.messages_queue[msg.target] = server_storage.messages_queue[msg.target] or {}
                    table.insert(server_storage.messages_queue[msg.target], copy_table(pkt))
                    
                    add_to_log(id, pkt)
                    add_to_log(msg.target, pkt)
                    save_data()
                end

            elseif msg.type == "report" then
                local logs = copy_table(chat_logs[id] or {})
                table.insert(server_storage.reports, {from=id, reason=tostring(msg.reason), logs=logs})
                save_data()
                rednet.send(id, {type = "error", message = "Report sent!"}, protocol)

            elseif msg.type == "get_online" then
                local list = {}
                local now = os.epoch("utc")
                for cid, c in pairs(server_storage.clients) do
                    if cid ~= id and (now - (c.lastSeen or 0) < 60000) then 
                        table.insert(list, {id = cid, name = c.name})
                    end
                end
                rednet.send(id, {type = "online_list", clients = list}, protocol)

            elseif msg.type == "get_messages" then
                -- Клиент вызывает это, чтобы скачать свою историю
                local q = server_storage.messages_queue[id] or {}
                if #q > 0 then
                    rednet.send(id, {type = "messages", messages = copy_table(q)}, protocol)
                    server_storage.messages_queue[id] = {} -- Очищаем после выдачи
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
        local args = {}
        for s in input:gmatch("%S+") do table.insert(args, s) end
        local cmd = args[1]

        if cmd == "id" then
            term.clear()
            term.setCursorPos(1,1)
            for cid, c in pairs(server_storage.clients) do print(cid .. ": " .. c.name) end
            print("\nAny key...")
            os.pullEvent("key")
        elseif cmd == "reports" then
            term.clear()
            term.setCursorPos(1,1)
            for i, r in ipairs(server_storage.reports) do
                print(i .. ". From " .. r.from .. ": " .. r.reason)
                for _, m in ipairs(r.logs) do print(" [" .. m.senderName .. "]: " .. m.message) end
            end
            os.pullEvent("key")
        elseif cmd == "clear_reports" then
            server_storage.reports = {}
            save_data()
        end
    end
end

load_data()
if not active_side then error("No modem!") end
rednet.host(protocol, "ameServer")
parallel.waitForAny(handle_requests, console_handler)
