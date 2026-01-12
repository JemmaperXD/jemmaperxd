local component = require("component")
local event = require("event")
local modem = component.modem
local fs = require("filesystem")
local serialization = require("serialization")

-- Конфигурация
local SERVER_ID = 1384
local PORT = 4000
local ENCRYPTION_KEY = "supersecretkey123"
local USERS_DIR = "/.user/"

-- Хранилище данных
local messages = {}
local users = {}
local messageCounter = 0
local onlineUsers = {}

-- Создание директорий
if not fs.exists(USERS_DIR) then
    fs.makeDirectory(USERS_DIR)
end

-- Простое XOR шифрование
local function encrypt(text, key)
    local result = ""
    for i = 1, #text do
        local char = string.byte(text:sub(i,i))
        local keyChar = string.byte(key:sub((i-1)%#key+1,(i-1)%#key+1))
        result = result .. string.char(char ~ keyChar)
    end
    return result
end

local function decrypt(text, key)
    return encrypt(text, key) -- XOR симметричный
end

-- Генерация ID сообщения
local function generateMessageId()
    messageCounter = messageCounter + 1
    return "MSG" .. os.time() .. "_" .. messageCounter
end

-- Получение имени пользователя
local function getUsername(address)
    local userFile = USERS_DIR .. address
    if fs.exists(userFile) then
        local file = io.open(userFile, "r")
        if file then
            local username = file:read("*l")
            file:close()
            return username or "Unknown"
        end
    end
    return "Unknown"
end

-- Регистрация пользователя
local function registerUser(address, username)
    local userFile = USERS_DIR .. address
    local file = io.open(userFile, "w")
    if file then
        file:write(username)
        file:close()
        users[address] = username
        return true
    end
    return false
end

-- Загрузка пользователей
local function loadUsers()
    if fs.exists(USERS_DIR) then
        local list = fs.list(USERS_DIR)
        for filename in list do
            local address = filename
            local file = io.open(USERS_DIR .. filename, "r")
            if file then
                local username = file:read("*l")
                file:close()
                users[address] = username
            end
        end
    end
end

-- Отправка сообщения
local function sendMessage(toAddress, fromAddress, message, messageId)
    local encryptedMessage = encrypt(message, ENCRYPTION_KEY)
    local fromUsername = getUsername(fromAddress)
    
    modem.send(toAddress, PORT, "message", {
        id = messageId,
        from = fromAddress,
        fromName = fromUsername,
        content = encryptedMessage,
        timestamp = os.time()
    })
end

-- Отправка подтверждения получения
local function sendAck(address, messageId)
    modem.send(address, PORT, "ack", {id = messageId})
end

-- Обработка входящих сообщений
local function handleMessage(senderAddress, recipientAddress, messageContent, messageId)
    -- Сохраняем сообщение
    table.insert(messages, {
        id = messageId,
        from = senderAddress,
        to = recipientAddress,
        content = messageContent,
        timestamp = os.time(),
        status = "sent"
    })
    
    -- Отправляем сообщение получателю
    if onlineUsers[recipientAddress] then
        sendMessage(recipientAddress, senderAddress, messageContent, messageId)
        return "delivered"
    else
        return "sent"
    end
end

-- Обновление статуса онлайн
local function updateUserStatus(address, status)
    onlineUsers[address] = status
end

-- Вывод статистики
local function printStats()
    print("--- Server Statistics ---")
    print("Online users: " .. tostring(table.size(onlineUsers)))
    print("Total messages: " .. tostring(#messages))
    print("Registered users: " .. tostring(table.size(users)))
    print("\nOnline users:")
    for address, _ in pairs(onlineUsers) do
        print("  " .. address .. " (" .. getUsername(address) .. ")")
    end
    print("\nRecent messages:")
    local count = 0
    for i = #messages, 1, -1 do
        if count >= 5 then break end
        local msg = messages[i]
        print("  [" .. msg.id .. "] " .. getUsername(msg.from) .. " -> " .. (users[msg.to] or msg.to) .. ": " .. msg.content:sub(1, 30) .. "...")
        count = count + 1
    end
end

-- Основной цикл сервера
local function startServer()
    modem.open(PORT)
    loadUsers()
    print("Telegram server started on port " .. PORT)
    print("Server ID: " .. SERVER_ID)
    
    while true do
        local _, _, sender, _, protocol, data = event.pull("modem_message")
        
        if protocol == "register" and type(data) == "table" then
            local success = registerUser(sender, data.username)
            modem.send(sender, PORT, "register_response", {success = success})
            if success then
                updateUserStatus(sender, true)
                print("New user registered: " .. data.username .. " (" .. sender .. ")")
            end
            
        elseif protocol == "message_request" and type(data) == "table" then
            local messageId = generateMessageId()
            local status = handleMessage(sender, data.to, data.content, messageId)
            
            -- Подтверждаем получение запроса
            modem.send(sender, PORT, "message_status", {
                originalId = data.id,
                serverId = messageId,
                status = status
            })
            
        elseif protocol == "ping" then
            modem.send(sender, PORT, "pong")
            updateUserStatus(sender, true)
            
        elseif protocol == "disconnect" then
            updateUserStatus(sender, false)
            
        elseif protocol == "get_users" then
            modem.send(sender, PORT, "users_list", users)
            
        elseif protocol == "stats" then
            printStats()
        end
    end
end

startServer()
