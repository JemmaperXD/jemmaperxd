-- server.lua - ameMessenger Server (Ultimate Edition)
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

-- Инициализация модема
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

-- Глубокое копирование пакета (защита от ошибок сериализации)
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

-- Логирование для контекста репортов
local function add_to_log(id, pkt)
    server_data.chat_logs[id] = server_data.chat_logs[id] or {}
    table.insert(server_data.chat_logs[id], pkt)
    if #server_data.chat_logs[id] > 10 then 
        table.remove(server_data.chat_logs[id], 1) 
    end
end

-- Отрисовка интерфейса сервера
local function draw_stats()
    local w, h = term.getSize()
    local oldX, oldY = term.getCursorPos()
    
    -- Верхняя серая панель
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" ameServer ADMIN | ID: " .. os.getComputerID())

    -- Статистика (черный фон)
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
    term.write(" Modem: " .. (active_side or "None"))

    -- Нижняя синяя панель команд
    term.setCursorPos(1, h-1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write(" Cmd: id, reports, clear_reports, ban, mute")
    
    term.setBackgroundColor(colors.black)
    term.setCursorPos(oldX, oldY)
end

-- Обработка сетевых запросов
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
                if server_data.banned[id] then
                    rednet.send(id, {type = "error", message = "You are banned"}, protocol)
                elseif msg.target then
                    -- Создаем уникальные копии пакета для разных таблиц
                    local pkt_for_history = clone_packet(msg, id)
                    local pkt_for_queue = clone_packet(msg, id)
                    
                    table.insert(server_data.history, pkt_for_history)
                    server_data.messages_queue[msg.target] = server_data.messages_queue[msg.target] or {}
                    table.insert(server_data.messages_queue[msg.target], pkt_for_queue)
                    
                    -- Сохраняем логи контекста (для репортов)
                    add_to_log(id, pkt_for_history)
                    add_to_log(msg.target, pkt_for_history)
                    
                    save_data()
                end

            elseif msg.type == "report" then
                local logs = {}
                if server_data.chat_logs[id] then
                    for _, l in ipairs(server_data.chat_logs[id]) do table.insert(logs, l) end
                end
                table.insert(server_data.reports, {
                    from = id, 
                    reason = msg.reason or "No reason", 
                    logs = logs
                })
                save_data()
                rednet.send(id, {type = "error", message = "Report sent!"}, protocol)

            elseif msg.type == "get_online" then
                local list = {}
                local now = os.epoch("utc")
                for cid, c in pairs(server_data.clients) do
                    -- Не отправляем игроку его собственный ID
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

-- Обработка консольных команд администратора
local function console_handler()
    local w, h = term.getSize()
    term.clear()
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
            for cid, c in pairs(server_data.clients) do
                print("ID: " .. cid .. " | Name: " .. c.name)
            end
            print("\nPress any key to return...")
            os.pullEvent("key")
        elseif cmd == "reports" then
            term.clear()
            term.setCursorPos(1,1)
            print("--- Active Reports ---")
            for i, r in ipairs(server_data.reports) do
                print(i .. ". From: " .. r.from .. " | Reason: " .. r.reason)
                print("   Context (last 10 msgs):")
                for _, m in ipairs(r.logs) do
                    print("   [" .. m.senderName .. "]: " .. m.message)
                end
                print("----------------------")
            end
            print("\nPress any key to return...")
            os.pullEvent("key")
        elseif cmd == "clear_reports" then
            server_data.reports = {}
            save_data()
            print("Reports cleared!")
            os.sleep(1)
        elseif cmd == "ban" then
            local tid = tonumber(tArgs[2])
            if tid then server_data.banned[tid] = true; save_data(); print("Banned ID "..tid) end
        end
    end
end

-- Запуск
if not active_side then error("No modem!") end
load_data()
rednet.host(protocol, server_data.name)
parallel.waitForAny(handle_requests, console_handler)
