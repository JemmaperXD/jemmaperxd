-- ============================================
-- Мессенджер для ComputerCraft: Tweaked
-- Серверная часть
-- ============================================

-- Настройки
local PROTOCOL = "messenger_v2"
local DATA_FILE = "server_data.dat"
local SAVE_INTERVAL = 300 -- секунд между автосохранениями
local INACTIVE_TIMEOUT = 300 -- секунд до пометки клиента как неактивного

-- Глобальные переменные
local serverName = "Сервер"
local modemSide = nil
local clients = {} -- {[id] = {name, lastActivity, online}}
local messages = {} -- {[targetId] = {сообщения}}
local messageQueue = {} -- {[targetId] = {непрочитанные сообщения}}
local running = true
local lastSaveTime = os.clock()

-- Вспомогательные функции
local function log(message)
    local time = os.time()
    local formattedTime = textutils.formatTime(time, false)
    print("[" .. formattedTime .. "] " .. message)
end

local function saveData()
    local data = {
        serverName = serverName,
        clients = clients,
        messages = messages,
        messageQueue = messageQueue
    }
    
    local file = fs.open(DATA_FILE, "w")
    if file then
        file.write(textutils.serialize(data))
        file.close()
        log("Данные сохранены")
        return true
    else
        log("Ошибка сохранения данных")
        return false
    end
end

local function loadData()
    if fs.exists(DATA_FILE) then
        local file = fs.open(DATA_FILE, "r")
        if file then
            local content = file.readAll()
            file.close()
            
            local data = textutils.unserialize(content)
            if data then
                serverName = data.serverName or serverName
                clients = data.clients or {}
                messages = data.messages or {}
                messageQueue = data.messageQueue or {}
                log("Данные загружены")
                return true
            end
        end
    end
    return false
end

local function findModem()
    -- Поиск модема на всех сторонах
    local sides = {"top", "bottom", "left", "right", "front", "back"}
    
    for _, side in ipairs(sides) do
        if peripheral.getType(side) == "modem" then
            if peripheral.wrap(side).isWireless() then
                return side
            end
        end
    end
    
    return nil
end

local function cleanupInactiveClients()
    local currentTime = os.time()
    local removed = false
    
    for id, client in pairs(clients) do
        if currentTime - client.lastActivity > INACTIVE_TIMEOUT then
            client.online = false
            removed = true
            log("Клиент " .. client.name .. " помечен как оффлайн")
        end
    end
    
    return removed
end

local function handleRegister(senderId, request)
    local clientName = request.name
    
    if not clientName or clientName == "" then
        return {
            type = "register_response",
            success = false,
            error = "Не указано имя"
        }
    end
    
    -- Проверяем, не занято ли имя другим клиентом
    for id, client in pairs(clients) do
        if client.name == clientName and id ~= senderId then
            return {
                type = "register_response",
                success = false,
                error = "Имя уже занято"
            }
        end
    end
    
    -- Регистрируем или обновляем клиента
    if not clients[senderId] then
        clients[senderId] = {
            name = clientName,
            lastActivity = os.time(),
            online = true
        }
        log("Новый клиент: " .. clientName .. " (ID: " .. senderId .. ")")
    else
        clients[senderId].name = clientName
        clients[senderId].lastActivity = os.time()
        clients[senderId].online = true
        log("Клиент обновлен: " .. clientName)
    end
    
    return {
        type = "register_response",
        success = true,
        serverName = serverName
    }
end

local function handleSendMessage(senderId, request)
    local targetId = request.target
    local messageText = request.message
    local senderName = request.senderName or clients[senderId] and clients[senderId].name or "Неизвестно"
    
    if not targetId or not messageText then
        return {
            type = "message_response",
            success = false,
            error = "Не указан получатель или сообщение"
        }
    end
    
    -- Проверяем существование получателя
    if not clients[targetId] then
        return {
            type = "message_response",
            success = false,
            error = "Получатель не найден"
        }
    end
    
    local timestamp = os.epoch("utc")
    local message = {
        sender = senderId,
        senderName = senderName,
        target = targetId,
        message = messageText,
        time = timestamp
    }
    
    -- Сохраняем в историю
    if not messages[targetId] then
        messages[targetId] = {}
    end
    table.insert(messages[targetId], message)
    
    -- Также сохраняем в историю отправителя
    if not messages[senderId] then
        messages[senderId] = {}
    end
    table.insert(messages[senderId], message)
    
    -- Добавляем в очередь непрочитанных
    if not messageQueue[targetId] then
        messageQueue[targetId] = {}
    end
    table.insert(messageQueue[targetId], message)
    
    log("Сообщение от " .. senderName .. " для " .. clients[targetId].name)
    
    return {
        type = "message_response",
        success = true
    }
end

local function handleGetOnline(senderId)
    local onlineList = {}
    
    for id, client in pairs(clients) do
        if client.online and id ~= senderId then
            table.insert(onlineList, {
                id = id,
                name = client.name
            })
        end
    end
    
    return {
        type = "online_list",
        clients = onlineList,
        serverName = serverName
    }
end

local function handleGetMessages(senderId)
    local userMessages = messageQueue[senderId] or {}
    
    -- Очищаем очередь после отправки
    messageQueue[senderId] = {}
    
    -- Обновляем время активности
    if clients[senderId] then
        clients[senderId].lastActivity = os.time()
    end
    
    return {
        type = "messages",
        messages = userMessages
    }
end

local function handlePing()
    return {
        type = "pong",
        time = os.epoch("utc")
    }
end

local function processRequest(senderId, message, protocol)
    if protocol ~= PROTOCOL then
        return nil
    end
    
    local request = textutils.unserialize(message)
    if not request or type(request) ~= "table" then
        return nil
    end
    
    local response = nil
    
    if request.type == "register" then
        response = handleRegister(senderId, request)
    elseif request.type == "send_message" then
        response = handleSendMessage(senderId, request)
    elseif request.type == "get_online" then
        response = handleGetOnline(senderId)
    elseif request.type == "get_messages" then
        response = handleGetMessages(senderId)
    elseif request.type == "ping" then
        response = handlePing()
    end
    
    if response then
        return textutils.serialize(response)
    end
    
    return nil
end

local function printHelp()
    print("Использование: server [опции]")
    print("Опции:")
    print("  -n, --name <имя>   Имя сервера")
    print("  -s, --side <сторона> Сторона модема")
    print("  -h, --help        Показать эту справку")
    print()
    print("Примеры:")
    print("  server --name \"Главный чат\" --side right")
    print("  server -n \"Чатовичок\" -s top")
end

local function parseArguments()
    local args = {...}
    local i = 1
    while i <= #args do
        local arg = args[i]
        
        if arg == "-n" or arg == "--name" then
            i = i + 1
            if args[i] then
                serverName = args[i]
            end
        elseif arg == "-s" or arg == "--side" then
            i = i + 1
            if args[i] then
                modemSide = args[i]
            end
        elseif arg == "-h" or arg == "--help" then
            printHelp()
            return false
        end
        
        i = i + 1
    end
    
    return true
end

-- Основная функция
local function main()
    -- Обработка аргументов командной строки
    if not parseArguments() then
        return
    end
    
    -- Поиск модема
    if not modemSide then
        modemSide = findModem()
    end
    
    if not modemSide then
        print("Не найден беспроводной модем!")
        print("Доступные стороны: top, bottom, left, right, front, back")
        print("Укажите сторону через --side <сторона>")
        return
    end
    
    -- Инициализация модема
    rednet.open(modemSide)
    
    -- Загрузка данных
    loadData()
    
    -- Регистрация сервера
    rednet.host(PROTOCOL, serverName)
    
    -- Вывод информации
    term.clear()
    term.setCursorPos(1, 1)
    print("=== Сервер мессенджера ===")
    print("Имя сервера: " .. serverName)
    print("ID сервера: " .. os.getComputerID())
    print("Модем: " .. modemSide)
    print("Протокол: " .. PROTOCOL)
    print("Клиентов: " .. #clients)
    print("---------------------------")
    print("Сервер запущен. Ожидание подключений...")
    print("Ctrl+T для завершения")
    print()
    
    -- Главный цикл
    while running do
        local currentTime = os.clock()
        
        -- Автосохранение
        if currentTime - lastSaveTime > SAVE_INTERVAL then
            if saveData() then
                lastSaveTime = currentTime
            end
        end
        
        -- Очистка неактивных клиентов
        cleanupInactiveClients()
        
        -- Обработка входящих сообщений с таймаутом
        local event, senderId, message, protocol = os.pullEvent("rednet_message")
        
        if event == "rednet_message" then
            local response = processRequest(senderId, message, protocol)
            if response then
                rednet.send(senderId, response, PROTOCOL)
            end
        end
        
        -- Проверка события завершения
        local event = os.pullEventRaw()
        if event == "terminate" then
            running = false
            break
        end
    end
    
    -- Корректное завершение
    log("Завершение работы сервера...")
    saveData()
    rednet.unhost(PROTOCOL)
    rednet.close(modemSide)
    print("Сервер остановлен.")
end

-- Обработка ошибок
local ok, err = pcall(main)
if not ok then
    print("Ошибка в сервере: " .. err)
    print("Подробности: " .. debug.traceback())
end
