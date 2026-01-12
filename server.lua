-- Messenger Server for CC:Tweaked
local VERSION = "1.0"
local PORT = 7777
local MAX_CLIENTS = 20
local MODEM_SIDE = "back"

-- Initialization
print("=== Messenger Server v" .. VERSION .. " ===")
print("Loading...")

local modem = peripheral.find("modem")
if not modem then
    print("ERROR: Modem not found!")
    print("Please attach a wireless modem")
    return
end

rednet.open(MODEM_SIDE)
print("Modem opened on side: " .. MODEM_SIDE)

-- Data structures
local clients = {} -- id -> {name, lastSeen}
local messages = {} -- queue: id -> array of messages
local messageHistory = {} -- all messages

-- Functions
function saveData()
    local data = {
        clients = clients,
        messages = messages
    }
    
    local file = fs.open("server_data.dat", "w")
    file.write(textutils.serialize(data))
    file.close()
    print("Data saved")
end

function loadData()
    if fs.exists("server_data.dat") then
        local file = fs.open("server_data.dat", "r")
        local data = textutils.unserialize(file.readAll())
        file.close()
        
        if data then
            clients = data.clients or clients
            messages = data.messages or messages
            print("Data loaded")
        end
    end
end

function registerClient(clientId, clientName)
    if not clients[clientId] then
        print("New client: " .. clientName .. " (" .. clientId .. ")")
    end
    
    clients[clientId] = {
        name = clientName,
        lastSeen = os.epoch("utc"),
        online = true
    }
    
    if not messages[clientId] then
        messages[clientId] = {}
    end
    
    return true
end

function sendMessage(senderId, targetId, message, senderName)
    if not clients[targetId] then
        return false, "Client not found"
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
    
    table.insert(messageHistory, msg)
    table.insert(messages[targetId], msg)
    
    print("Message from " .. senderName .. " to " .. clients[targetId].name)
    
    if #messageHistory % 10 == 0 then
        saveData()
    end
    
    return true, "Message sent"
end

function getOnlineClients()
    local online = {}
    for id, client in pairs(clients) do
        if client.online and os.epoch("utc") - client.lastSeen < 30000 then
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
    
    for i = math.max(1, #clientMsgs - 49), #clientMsgs do
        table.insert(result, clientMsgs[i])
    end
    
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
            message = success and "Registration successful" or "Registration failed"
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
        message = "Unknown request type"
    }
end

function cleanupOldClients()
    local now = os.epoch("utc")
    local removed = 0
    
    for id, client in pairs(clients) do
        if now - client.lastSeen > 300000 then
            client.online = false
            removed = removed + 1
        end
    end
    
    if removed > 0 then
        print("Offline clients: " .. removed)
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
    print(string.format("Stats: %d/%d online | %d pending | %d messages",
        stats.online, stats.total, stats.pending, stats.totalMessages))
end

-- Main server loop
function main()
    loadData()
    
    print("Server started. ID: " .. os.getComputerID())
    print("Waiting for connections...")
    
    while true do
        local senderId, request, protocol = rednet.receive(nil, 2)
        
        if senderId then
            if protocol == "messenger_server" then
                local response = processRequest(senderId, request)
                rednet.send(senderId, response, "messenger_server")
            end
        end
        
        local timer = os.startTimer(10)
        local event = os.pullEvent()
        
        if event == "timer" then
            cleanupOldClients()
            displayStats()
            
            if os.epoch("utc") % 60000 < 100 then
                saveData()
            end
        end
    end
end

-- Error handling
local ok, err = pcall(main)
if not ok then
    print("Server error: " .. err)
    saveData()
end

rednet.close()
print("Server stopped")
