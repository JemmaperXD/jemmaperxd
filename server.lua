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
    print("Data saved to " .. DATA_FILE)
end

-- Find modem
local function findModem()
    if modemSide then
        if peripheral.getType(modemSide) == "modem" then
            return true
        else
            print("Error: No modem found on side: " .. modemSide)
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
    
    print("Error: No wireless modem found!")
    print("Attach a modem to any side of the computer.")
    return false
end

-- Validate client
local function validateClient(clientId, clientName)
    if not clientId then
        return false, "Invalid client ID"
    end
    
    if not clientName or clientName == "" then
        return false, "Client name cannot be empty"
    end
    
    if #clientName > 20 then
        return false, "Client name too long (max 20 chars)"
    end
    
    -- Check for duplicate name
    for id, client in pairs(connectedClients) do
        if client.name == clientName and id ~= clientId then
            return false, "Client name already in use"
        end
    end
    
    return true
end

-- Message handlers
local function handleRegister(senderId, data)
    local valid, errorMsg = validateClient(senderId, data.clientName)
    if not valid then
        print("Registration failed for " .. senderId .. ": " .. errorMsg)
        return {
            type = "register_error",
            message = errorMsg
        }
    end
    
    -- Check if client already registered
    if connectedClients[senderId] then
        -- Update existing client
        connectedClients[senderId].name = data.clientName
        connectedClients[senderId].lastSeen = os.time()
        connectedClients[senderId].status = "online"
        
        print("Client reconnected: " .. data.clientName .. " (" .. senderId .. ")")
        
        return {
            type = "register_ack",
            serverName = serverName,
            clients = connectedClients,
            message = "Reconnected successfully"
        }
    end
    
    -- Register new client
    connectedClients[senderId] = {
        name = data.clientName,
        lastSeen = os.time(),
        status = "online"
    }
    
    -- Initialize for new clients
    if not messages[senderId] then
        messages[senderId] = {
            inbox = {},
            outbox = {},
            unread = 0
        }
    end
    
    lastPing[senderId] = os.time()
    
    print("New client registered: " .. data.clientName .. " (" .. senderId .. ")")
    
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
    if not connectedClients[senderId] then
        return {
            type = "error",
            message = "Client not registered. Please register first."
        }
    end
    
    local recipientId = data.recipientId
    if not recipientId then
        return {
            type = "error",
            message = "No recipient specified"
        }
    end
    
    if not connectedClients[recipientId] then
        return {
            type = "error", 
            message = "Recipient not found"
        }
    end
    
    if not data.text or data.text == "" then
        return {
            type = "error",
            message = "Message text cannot be empty"
        }
    end
    
    -- Initialize message storage if needed
    if not messages[senderId] then
        messages[senderId] = {inbox = {}, outbox = {}, unread = 0}
    end
    
    if not messages[recipientId] then
        messages[recipientId] = {inbox = {}, outbox = {}, unread = 0}
    end
    
    local message = {
        id = #messages[recipientId].inbox + 1,
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
    
    print("Message from " .. connectedClients[senderId].name .. 
          " to " .. connectedClients[recipientId].name .. 
          ": " .. (data.text:sub(1, 20) .. (#data.text > 20 and "..." or "")))
    
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
    if not connectedClients[senderId] then
        return {
            type = "error",
            message = "Client not registered"
        }
    end
    
    return {
        type = "online_list",
        clients = connectedClients,
        count = #connectedClients
    }
end

local function handleGetMessages(senderId, data)
    if not connectedClients[senderId] then
        return {
            type = "error",
            message = "Client not registered"
        }
    end
    
    local clientMessages = messages[senderId]
    if not clientMessages then
        clientMessages = {inbox = {}, outbox = {}, unread = 0}
        messages[senderId] = clientMessages
    end
    
    local unreadOnly = data.unreadOnly
    local result = {}
    
    if unreadOnly then
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
        connectedClients[senderId].status = "online"
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
    
    if not message or not message.type then
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
            message = "Unknown message type: " .. tostring(message.type)
        }
    end
    
    if response then
        local success = rednet.send(senderId, response, PROTOCOL)
        if not success then
            print("Failed to send response to client " .. senderId)
        end
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
            
            print("Client timed out: " .. clientName .. " (" .. clientId .. ")")
            
            -- Notify about client disconnect
            for otherId, _ in pairs(connectedClients) do
                rednet.send(otherId, {
                    type = "client_offline",
                    clientId = clientId,
                    clientName = clientName
                }, PROTOCOL)
            end
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
    print("For exit press Ctrl+T")
    print()
    
    -- Load data
    local loadedData = loadData()
    messages = loadedData.messages or {}
    connectedClients = loadedData.clients or {}
    
    -- Restore lastPing and mark as offline initially
    for clientId, client in pairs(connectedClients) do
        lastPing[clientId] = client.lastSeen or os.time()
        client.status = "offline" -- Mark as offline until they ping
        print("Loaded client: " .. (client.name or "Unknown") .. " (offline)")
    end
    
    print("Server ready. Waiting for connections...")
    
    -- Main event loop
    local cleanupTimer = os.startTimer(10)
    local saveTimer = os.startTimer(SAVE_INTERVAL)
    
    while true do
        local event, param1, param2, param3 = os.pullEvent()
        
        if event == "rednet_message" then
            local senderId, message, protocol = param1, param2, param3
            handleMessage(senderId, message, protocol)
            
        elseif event == "timer" then
            local timerId = param1
            
            if timerId == cleanupTimer then
                cleanupClients()
                cleanupTimer = os.startTimer(10)
                
            elseif timerId == saveTimer then
                if shouldSave and os.time() - lastSaveTime > SAVE_INTERVAL then
                    saveData()
                end
                saveTimer = os.startTimer(SAVE_INTERVAL)
            end
            
        elseif event == "key" and param1 == 20 then -- Ctrl+T
            break
        end
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
