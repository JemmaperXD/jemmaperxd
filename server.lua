-- Сервер мессенджера для CC:Tweaked
local VERSION = "1.0"
local PORT = 7777
local MAX_CLIENTS = 20
local MODEM_SIDE = "back"

-- Инициализация
print("=== Сервер мессенджера v" .. VERSION .. " ===")
print("Загрузка...")

local modem = peripheral.find("modem")
if not modem then
    error("Не найден модем!")
end

rednet.open(MODEM_SIDE)
print("Модем открыт на порту " .. PORT)

-- Структуры данных
local clients = {} -- id -> {name, lastSeen}
local messages = {} -- очередь сообщений id -> массив сообщений
local messageHistory = {} -- история всех сообщений

-- Функции
function saveData()
    local data = {
        clients = clients,
        messages = messages
    }
    
    local file = fs.open("server_data.dat", "w")
    file.write(textutils.serialize(data))
    file.close()
    print("Данные сохранены")
end

function loadData()
    if fs.exists("server_data.dat") then
        local file = fs.open("server_data.dat", "r")
        local data = textutils.unserialize(file.readAll())
        file.close()
        
        if data then
            clients = data.clients or clients
            messages = data.messages or messages
            print("Данные загружены")
        end
    end
end

function registerClient(clientId, clientName)
    if not clients[clientId] then
        print("Новый клиент: " .. clientName .. " (" .. clientId .. ")")
    end
    
    clients[clientId] = {
        name = clientName,
        lastSeen = os.epoch("utc"),
        online = true
    }
    
    -- Создаем очередь сообщений если нет
    if not messages[clientId] then
        messages[clientId] = {}
    end
    
    return true
end

function sendMessage(senderId, targetId, message, senderName)
    -- Проверяем существование цели
    if not clients[targetId] then
        return false, "Клиент не найден"
    end
    
    local msg = {
        id = #messageHistory + 1,
        sender = senderId,
        senderName = senderName,
        target = targetId,
        message = message,
        time = os.epoch("utc"),
        delivered = false
    }
    
    -- Добавляем в историю
    table.insert(messageHistory, msg)
    
    -- Добавляем в очередь получателя
    table.insert(messages[targetId], msg)
    
    print("Сообщение от " .. senderName .. " для " .. clients[targetId].name)
    
    -- Автосохранение каждые 10 сообщений
    if #messageHistory % 10 == 0 then
        saveData()
    end
    
    return true, "Сообщение отправлено"
end

function getOnlineClients()
    local online = {}
    for id, client in pairs(clients) do
        if client.online and os.epoch("utc") - client.lastSeen < 30000 then -- 30 секунд
            table.insert(online, {
                id = id,
                name = client.name
            })
        end
    end
    return online
end

function getClientMessages(clientId)
    local clientMsgs = messages[clientId] or {}
    local result = {}
    
    -- Берем последние 50 сообщений
    for i = math.max(1, #clientMsgs - 49), #clientMsgs do
        table.insert(result, clientMsgs[i])
    end
    
    -- Помечаем как доставленные
    for _, msg in ipairs(clientMsgs) do
        msg.delivered = true
    end
    
    return result
end

function processRequest(senderId, request)
    if request.type == "register" then
        local success = registerClient(senderId, request.name)
        return {
            type = "register_response",
            success = success,
            message = success and "Регистрация успешна" or "Ошибка регистрации"
        }
        
    elseif request.type == "send_message" then
        local success, err = sendMessage(senderId, request.target, 
                                        request.message, request.senderName)
        return {
            type = "message_response",
            success = success,
            messageId = #messageHistory,
            error = not success and err or nil
        }
        
    elseif request.type == "get_online" then
        return {
            type = "online_list",
            clients = getOnlineClients()
        }
        
    elseif request.type == "get_messages" then
        return {
            type = "messages",
            messages = getClientMessages(senderId)
        }
        
    elseif request.type == "ping" then
        -- Обновляем время последней активности
        if clients[senderId] then
            clients[senderId].lastSeen = os.epoch("utc")
            clients[senderId].online = true
        end
        return {
            type = "pong",
            time = os.epoch("utc")
        }
        
    elseif request.type == "get_client_info" then
        return {
            type = "client_info",
            client = clients[request.clientId]
        }
    end
    
    return {
        type = "error",
        message = "Неизвестный тип запроса"
    }
end

function cleanupOldClients()
    local now = os.epoch("utc")
    local removed = 0
    
    for id, client in pairs(clients) do
        if now - client.lastSeen > 300000 then -- 5 минут
            client.online = false
            removed = removed + 1
        end
    end
    
    if removed > 0 then
        print("Оффлайн клиентов: " .. removed)
    end
end

function serverStats()
    local online = 0
    local total = 0
    local pending = 0
    
    for id, client in pairs(clients) do
        total = total + 1
        if client.online then
            online = online + 1
        end
    end
    
    for id, queue in pairs(messages) do
        pending = pending + #queue
    end
    
    return {
        online = online,
        total = total,
        pending = pending,
        totalMessages = #messageHistory
    }
end

function displayStats()
    local stats = serverStats()
    print(string.format("Статистика: %d/%d онлайн | %d в очереди | %d сообщений",
        stats.online, stats.total, stats.pending, stats.totalMessages))
end

-- Основной цикл сервера
function main()
    loadData()
    
    print("Сервер запущен. ID: " .. os.getComputerID())
    print("Ожидание подключений...")
    
    while true do
        local senderId, request, protocol = rednet.receive(nil, 2)
        
        if senderId then
            if protocol == "messenger_server" then
                local response = processRequest(senderId, request)
                rednet.send(senderId, response, "messenger_server")
            end
        end
        
        -- Периодические задачи
        local timer = os.startTimer(10)
        local event = os.pullEvent()
        
        if event == "timer" then
            cleanupOldClients()
            displayStats()
            
            -- Автосохранение каждую минуту
            if os.epoch("utc") % 60000 < 100 then
                saveData()
            end
        end
    end
end

-- Обработка ошибок
local ok, err = pcall(main)
if not ok then
    print("Ошибка сервера: " .. err)
    saveData()
end

rednet.close()
print("Сервер остановлен")
