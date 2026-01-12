local component = require("component")
local event = require("event")
local modem = component.modem
local fs = require("filesystem")
local serialization = require("serialization")

-- Конфигурация
local SERVER_ID = 1384
local PORT = 4000
local USERS_FILE = "/users.dat"
local MESSAGES_FILE = "/messages.dat"

-- Данные
local users = {}
local messages = {}
local messageCounter = 0

-- Загрузка данных
local function loadData()
    if fs.exists(USERS_FILE) then
        local file = io.open(USERS_FILE, "r")
        if file then
            local content = file:read("*all")
            users = serialization.unserialize(content) or {}
            file:close()
        end
    end
    
    if fs.exists(MESSAGES_FILE) then
        local file = io.open(MESSAGES_FILE, "r")
        if file then
            local content = file:read("*all")
            messages = serialization.unserialize(content) or {}
            messageCounter = #messages
            file:close()
        end
    end
end

-- Сохранение данных
local function saveData()
    local userFile = io.open(USERS_FILE, "w")
    if userFile then
        userFile:write(serialization.serialize(users))
        userFile:close()
    end
    
    local msgFile = io.open(MESSAGES_FILE, "w")
    if msgFile then
        msgFile:write(serialization.serialize(messages))
        msgFile:close()
    end
end

-- Шифрование (простой XOR)
local function encrypt(text, key)
    local result = ""
    for i = 1, #text do
        local char = string.byte(text, i)
        local keyChar = string.byte(key, (i % #key) + 1)
        result = result .. string.char(bit32.bxor(char, keyChar))
    end
    return result
end

local function decrypt(text, key)
    return encrypt(text, key) -- XOR симметричен
end

-- Регистрация пользователя
local function registerUser(address, username)
    users[address] = {
        username = username,
        lastSeen = os.time()
    }
    saveData()
end

-- Получение адреса по имени пользователя
local function getAddressByUsername(username)
    for address, data in pairs(users) do
        if data.username == username then
            return address
        end
    end
    return nil
end

-- Отправка сообщения
local function sendMessage(toAddress, fromUsername, messageText, replyAddress)
    messageCounter = messageCounter + 1
    local messageId = messageCounter
    
    local encryptedMessage = encrypt(messageText, "secret_key_" .. messageId)
    
    local messageData = {
        id = messageId,
        from = fromUsername,
        text = encryptedMessage,
        timestamp = os.time(),
        delivered = false
    }
    
    table.insert(messages, messageData)
    saveData()
    
    -- Отправляем сообщение получателю
    modem.send(toAddress, PORT, "message", messageId, fromUsername, encryptedMessage)
    
    -- Подтверждаем получение клиенту
    if replyAddress then
        modem.send(replyAddress, PORT, "sent", messageId)
    end
    
    return messageId
end

-- Обработка входящих сообщений
local function handleMessage(_, _, fromAddress, _, _, messageType, ...)
    if messageType == "register" then
        local username = ...
        registerUser(fromAddress, username)
        modem.send(fromAddress, PORT, "registered")
        
    elseif messageType == "send" then
        local toUsername, messageText = ...
        local toAddress = getAddressByUsername(toUsername)
        
        if toAddress then
            local fromData = users[fromAddress]
            local messageId = sendMessage(toAddress, fromData.username, messageText, fromAddress)
        else
            modem.send(fromAddress, PORT, "error", "User not found")
        end
        
    elseif messageType == "ack" then
        local messageId = ...
        -- Помечаем сообщение как доставленное
        for _, msg in ipairs(messages) do
            if msg.id == messageId then
                msg.delivered = true
                break
            end
        end
        saveData()
        
    elseif messageType == "get_users" then
        local userList = {}
        for addr, data in pairs(users) do
            table.insert(userList, {username = data.username, address = addr})
        end
        modem.send(fromAddress, PORT, "users_list", userList)
    end
end

-- Основной цикл сервера
local function startServer()
    modem.open(PORT)
    loadData()
    print("Telegram Server started on port " .. PORT)
    print("Server ID: " .. SERVER_ID)
    
    while true do
        local _, _, fromAddress, _, _, messageType = event.pull("modem_message")
        handleMessage(_, _, fromAddress, _, _, messageType)
    end
end

-- Статистика
local function showStats()
    print("=== Telegram Server Statistics ===")
    print("Total Users: " .. #(users))
    print("Total Messages: " .. #messages)
    
    print("\nUsers:")
    for address, data in pairs(users) do
        print("  " .. data.username .. " (" .. address:sub(1, 8) .. ")")
    end
    
    print("\nRecent Messages:")
    local count = 0
    for i = #messages, 1, -1 do
        if count >= 10 then break end
        local msg = messages[i]
        print(string.format("  [%d] %s -> %s (%s)", msg.id, msg.from, msg.text:sub(1, 20), msg.delivered and "Delivered" or "Pending"))
        count = count + 1
    end
end

-- Команды сервера
if ... == "stats" then
    loadData()
    showStats()
else
    startServer()
end
