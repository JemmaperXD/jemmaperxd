-- Messenger server for ComputerCraft: Tweaked
-- Run: server [--name <name>] [--side <side>]

-- Configuration
local PROTOCOL = "messenger_v2"
local CONFIG_FILE = "messenger_server.cfg"
local DATA_FILE = "messenger_data.dat"
local PING_TIMEOUT = 30 -- seconds
local SAVE_INTERVAL = 60 -- seconds

-- Global variables
local serverName = "Chat Server"
local modemSide = nil
local connectedClients = {}
local messages = {}
local lastPing = {}
local shouldSave = false
local lastSaveTime = os.time()

-- Parse command line arguments
local args = {...}
for i = 1, #args do
    if args[i] == "-n" or args[i] == "--name" then
        serverName = args[i+1] or serverName
    elseif args[i] == "-s" or args[i] == "--side" then
        modemSide = args[i+1]
    elseif args[i] == "-h" or args[i] == "--help" then
        print("Usage: server [options]")
        print("Options:")
        print("  -n, --name <name>    Server name")
        print("  -s, --side <side>    Modem side")
        print("  -h, --help           Show this help")
        return
    end
end

-- File handling functions
local function loadConfig()
    if fs.exists(CONFIG_FILE) then
        local file = fs.open(CONFIG_FILE, "r")
        local data = textutils.unserialize(file.readAll())
        file.close()
        return data or {}
    end
    return {}
end

local function saveConfig(config)
    local file = fs.open(CONFIG_FILE, "w")
    file.write(textutils.serialize(config))
    file.close()
end

local function loadData()
    if fs.exists(DATA_FILE) then
        local file = fs.open(DATA_FILE, "r")
        local data = textutils.unserialize(file.readAll())
        file.close()
        return data or {messages = {}, clients = {}}
    end
    return {messages = {}, clients = {}}
end

local function saveData()
    local data = {
        messages = messages,
        clients = connectedClients,
        timestamp = os.time()
    }
    local file = fs.open(DATA_FILE, "w")
    file.write(textutils.serialize(data))
    file.close()
    shouldSave = false
    lastSaveTime = os.time()
end

-- Find modem
local function findModem()
    if modemSide then
        if peripheral.getType(modemSide) == "modem" then
            return true
        else
            return false
        end
    end
    
    local sides = {"top", "bottom", "left", "right", "front", "back"}
    for _, side in ipairs(sides) do
        if peripheral.getType(side) == "modem" then
            modemSide = side
            return true
        end
    end
    return false
end

-- Validate client
local function validateClient(clientId, clientName)
    if not clientId or not clientName then
        return false
    end
    
    if connectedClients[clientId] then
        return true
    end
    
    -- Check for duplicate name
    for id, client in pairs(connectedClients) do
        if client.name == clientName and id ~= clientId then
            return false
        end
    end
    
    return true
end

-- Message handlers
local function handleRegister(senderId, data)
    if not validateClient(senderId, data.clientName) then
        return {type = "error", message = "Invalid client name"}
    end
    
    connectedClients[senderId] = {
        name = data.clientName,
        lastSeen = os.time(),
        status = "online"
    }
    
    -- Initialize for new clients
    messages[senderId] = messages[senderId] or {
        inbox = {},
        outbox = {},
        unread = 0
    }
    
    lastPing[senderId] = os.time()
    
    -- Notify all about new client
    for clientId, _ in pairs(connectedClients) do
        if clientId ~= senderId then
            rednet.send(clientId, {
                type = "client_online",
                clientId = senderId,
                clientName = data.clientName
            }, PROTOCOL)
        end
    end
    
    return {
        type = "register_ack",
        serverName = serverName,
        clients = connectedClients,
        message = "Registration successful"
    }
end

local function handleSendMessage(senderId, data)
    if not validateClient(senderId, nil) then
        return {type = "error", message = "Client not registered"}
    end
    
    local recipientId = data.recipientId
    if not connectedClients[recipientId] then
        return {type = "error", message = "Recipient not found"}
    end
    
    local message = {
        id = #(messages[recipientId].inbox or {}) + 1,
        senderId = senderId,
        senderName = connectedClients[senderId].name,
        recipientId = recipientId,
        text = data.text,
        timestamp = os.time(),
        read = false
    }
    
    -- Save to sender's outbox
    table.insert(messages[senderId].outbox, message)
    
    -- Save to recipient's inbox
    table.insert(messages[recipientId].inbox, message)
    messages[recipientId].unread = (messages[recipientId].unread or 0) + 1
    
    -- Send to recipient
    rednet.send(recipientId, {
        type = "new_message",
        message = message
    }, PROTOCOL)
    
    shouldSave = true
    
    return {
        type = "message_ack",
        messageId = message.id,
        timestamp = message.timestamp
    }
end

local function handleGetOnline(senderId, data)
    if not validateClient(senderId, nil) then
        return {type = "error", message = "Client not registered"}
    end
    
    return {
        type = "online_list",
        clients = connectedClients,
        count = #connectedClients
    }
end

local function handleGetMessages(senderId, data)
    if not validateClient(senderId, nil) then
        return {type = "error", message = "Client not registered"}
    end
    
    local clientMessages = messages[senderId] or {inbox = {}, outbox = {}}
    local unread = data.unreadOnly
    
    local result = {}
    if unread then
        for _, msg in ipairs(clientMessages.inbox) do
            if not msg.read then
                table.insert(result, msg)
                msg.read = true
            end
        end
        clientMessages.unread = 0
    else
        result = clientMessages.inbox
    end
    
    shouldSave = true
    
    return {
        type = "messages",
        messages = result,
        unread = clientMessages.unread or 0
    }
end

local function handlePing(senderId, data)
    if connectedClients[senderId] then
        lastPing[senderId] = os.time()
        connectedClients[senderId].lastSeen = os.time()
    end
    
    return {
        type = "pong",
        timestamp = os.time(),
        serverTime = os.time()
    }
end

-- Main message handler
local function handleMessage(senderId, message, protocol)
    if protocol ~= PROTOCOL then
        return
    end
    
    if not message.type then
        rednet.send(senderId, {
            type = "error",
            message = "Invalid message format"
        }, PROTOCOL)
        return
    end
    
    local response
    
    if message.type == "register" then
        response = handleRegister(senderId, message)
    elseif message.type == "send_message" then
        response = handleSendMessage(senderId, message)
    elseif message.type == "get_online" then
        response = handleGetOnline(senderId, message)
    elseif message.type == "get_messages" then
        response = handleGetMessages(senderId, message)
    elseif message.type == "ping" then
        response = handlePing(senderId, message)
    else
        response = {
            type = "error",
            message = "Unknown message type"
        }
    end
    
    if response then
        rednet.send(senderId, response, PROTOCOL)
    end
end

-- Cleanup inactive clients
local function cleanupClients()
    local currentTime = os.time()
    local toRemove = {}
    
    for clientId, lastSeen in pairs(lastPing) do
        if currentTime - lastSeen > PING_TIMEOUT then
            table.insert(toRemove, clientId)
        end
    end
    
    for _, clientId in ipairs(toRemove) do
        if connectedClients[clientId] then
            local clientName = connectedClients[clientId].name
            connectedClients[clientId] = nil
            lastPing[clientId] = nil
            
            -- Notify about client disconnect
            for otherId, _ in pairs(connectedClients) do
                rednet.send(otherId, {
                    type = "client_offline",
                    clientId = clientId,
                    clientName = clientName
                }, PROTOCOL)
            end
            
            print("Client disconnected: " .. clientName)
        end
    end
end

-- Main loop
local function main()
    -- Check modem
    if not findModem() then
        print("Error: Wireless modem not found!")
        print("Place modem on any side of computer")
        return
    end
    
    -- Initialize modem
    rednet.open(modemSide)
    rednet.host(PROTOCOL, serverName)
    
    print("Messenger server started")
    print("Server name: " .. serverName)
    print("Protocol: " .. PROTOCOL)
    print("Modem side: " .. modemSide)
    print("Press Ctrl+T to exit")
    print()
    
    -- Load data
    local loadedData = loadData()
    messages = loadedData.messages or {}
    connectedClients = loadedData.clients or {}
    
    -- Restore lastPing
    for clientId, client in pairs(connectedClients) do
        lastPing[clientId] = client.lastSeen or os.time()
    end
    
    -- Main event loop
    while true do
        local event, param1, param2, param3 = os.pullEvent()
        
        if event == "rednet_message" then
            local senderId, message, protocol = param1, param2, param3
            handleMessage(senderId, message, protocol)
            
        elseif event == "timer" then
            cleanupClients()
            
            -- Auto-save
            if shouldSave and os.time() - lastSaveTime > SAVE_INTERVAL then
                saveData()
                print("Data saved")
            end
            
        elseif event == "key" and param1 == 20 then -- Ctrl+T
            break
        end
        
        -- Set timer for cleanup
        os.startTimer(10)
    end
    
    -- Clean shutdown
    print("Shutting down server...")
    saveData()
    rednet.unhost(PROTOCOL, serverName)
    rednet.close(modemSide)
    print("Server stopped")
end

-- Start
main()
