-- server.lua - Messenger V2 Server (STABLE)
local protocol = "messenger_v2"
local data_file = "server_data.dat"
local args = {...}

-- Структура данных по умолчанию
local server_data = {
    name = "Default Server",
    clients = {}, -- [id] = {name = string, lastSeen = timestamp}
    history = {}, -- { {sender, senderName, target, message, time}, ... }
    messages_queue = {} -- [targetID] = { {msg}, {msg} }
}

-- Утилиты
local function log(msg)
    print(("[%s] %s"):format(os.date("%H:%M:%S"), tostring(msg)))
end

local function save_data()
    -- Используем pcall для защиты от краша при сохранении
    local success, err = pcall(function()
        local f = fs.open(data_file, "w")
        f.write(textutils.serialize(server_data))
        f.close()
    end)
    if not success then
        log("Error saving data: " .. tostring(err))
    end
end

local function load_data()
    if fs.exists(data_file) then
        local f = fs.open(data_file, "r")
        local content = f.readAll()
        f.close()
        
        if content and content ~= "" then
            local data = textutils.unserialize(content)
            if type(data) == "table" then
                -- Безопасное объединение данных. Не заменяем таблицу целиком!
                server_data.name = data.name or server_data.name
                server_data.clients = data.clients or {}
                server_data.history = data.history or {}
                server_data.messages_queue = data.messages_queue or {}
                log("Data loaded successfully.")
            else
                log("Warning: Save file corrupted or empty. Starting fresh.")
            end
        end
    end
end

-- Инициализация модема
local function init_modem(side)
    if side then
        if peripheral.getType(side) == "modem" then
            rednet.open(side)
            return side
        end
    else
        for _, s in ipairs(peripheral.getNames()) do
            if peripheral.getType(s) == "modem" and peripheral.call(s, "isWireless") then
                rednet.open(s)
                return s
            end
        end
    end
    return nil
end

-- Обработка аргументов
local modem_side = nil
for i=1, #args do
    if args[i] == "--side" or args[i] == "-s" then modem_side = args[i+1] end
    if args[i] == "--name" or args[i] == "-n" then server_data.name = args[i+1] end
end

local active_side = init_modem(modem_side)
if not active_side then
    error("No wireless modem found! Use --side <side>")
end

rednet.host(protocol, server_data.name)
load_data()
log("Server '" .. server_data.name .. "' started on ID " .. os.getComputerID())

-- Основной цикл обработки
local function handle_requests()
    while true do
        local id, msg = rednet.receive(protocol)
        if type(msg) == "table" then
            
            -- РЕГИСТРАЦИЯ
            if msg.type == "register" then
                local cName = msg.name or "Unknown"
                server_data.clients[id] = {name = cName, lastSeen = os.epoch("utc")}
                rednet.send(id, {type = "register_response", success = true, serverName = server_data.name}, protocol)
                log("Registered: " .. cName .. " (" .. id .. ")")
                save_data()

            -- СПИСОК ОНЛАЙН
            elseif msg.type == "get_online" then
                local list = {}
                local now = os.epoch("utc")
                for cid, cdata in pairs(server_data.clients) do
                    if now - (cdata.lastSeen or 0) < 120000 then -- 2 min timeout
                        table.insert(list, {id = cid, name = cdata.name})
                    end
                end
                rednet.send(id, {type = "online_list", clients = list, serverName = server_data.name}, protocol)

            -- ОТПРАВКА СООБЩЕНИЯ (ИСПРАВЛЕНО ДУБЛИРОВАНИЕ)
            elseif msg.type == "send_message" then
                if msg.target and type(msg.target) == "number" then
                    -- 1. Объект для истории
                    local history_packet = {
                        sender = id,
                        senderName = msg.senderName or "Anon",
                        target = msg.target,
                        message = msg.message or "",
                        time = os.epoch("utc")
                    }
                    table.insert(server_data.history, history_packet)
                    
                    -- 2. НОВЫЙ объект для очереди (Deep Copy)
                    -- Это решает проблему "serialize table with repeated entries"
                    local queue_packet = {
                        sender = history_packet.sender,
                        senderName = history_packet.senderName,
                        target = history_packet.target,
                        message = history_packet.message,
                        time = history_packet.time
                    }
                    
                    -- Инициализация очереди и вставка
                    server_data.messages_queue[msg.target] = server_data.messages_queue[msg.target] or {}
                    table.insert(server_data.messages_queue[msg.target], queue_packet)
                    
                    rednet.send(id, {type = "message_response", success = true}, protocol)
                    log("Msg: " .. tostring(msg.senderName) .. " -> " .. tostring(msg.target))
                    save_data()
                else
                    rednet.send(id, {type = "message_response", success = false, error = "Invalid target"}, protocol)
                    log("Error: Msg from " .. id .. " has invalid target")
                end

            -- ПОЛУЧЕНИЕ СООБЩЕНИЙ
            elseif msg.type == "get_messages" then
                local queue = server_data.messages_queue[id] or {}
                if #queue > 0 then
                    rednet.send(id, {type = "messages", messages = queue}, protocol)
                    server_data.messages_queue[id] = {} -- Очищаем очередь
                    save_data()
                end

            -- PING
            elseif msg.type == "ping" then
                if server_data.clients[id] then 
                    server_data.clients[id].lastSeen = os.epoch("utc") 
                end
                rednet.send(id, {type = "pong", time = os.epoch("utc")}, protocol)
            end
        end
    end
end

-- Автосохранение
local function auto_save()
    while true do
        os.sleep(60)
        save_data()
    end
end

parallel.waitForAny(handle_requests, auto_save)
