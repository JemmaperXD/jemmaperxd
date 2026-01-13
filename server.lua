-- Messenger Server for CC:Tweaked
local VERSION = "1.0"
local PROTOCOL = "messenger_v2"

-- Parse command line arguments
local args = {...}
local serverName = nil
local modemSide = nil

for i = 1, #args do
    local arg = args[i]
    if arg == "-n" or arg == "--name" then
        serverName = args[i + 1]
    elseif arg == "-s" or arg == "--side" then
        modemSide = args[i + 1]
    elseif arg == "-h" or arg == "--help" then
        print("Messenger Server v" .. VERSION)
        print("Usage: server [options]")
        print()
        print("Options:")
        print("  -n, --name <name>    Set server display name")
        print("  -s, --side <side>    Specify modem side (left/right/top/bottom/back/front)")
        print("  -h, --help           Show this help message")
        return
    end
end

-- Initialization
print("=== Messenger Server v" .. VERSION .. " ===")
print("Loading...")

-- Function to find wireless modem
function findWirelessModem(specifiedSide)
    print("Looking for modem...")
    
    if specifiedSide then
        local modem = peripheral.wrap(specifiedSide)
        if modem and modem.isWireless and modem.isWireless() then
            print("Found modem on side: " .. specifiedSide)
            return specifiedSide
        else
            print("No modem found on: " .. specifiedSide)
        end
    end
    
    local sides = peripheral.getNames()
    
    for _, side in ipairs(sides) do
        local type = peripheral.getType(side)
        if type == "modem" then
            local modem = peripheral.wrap(side)
            if modem and modem.isWireless and modem.isWireless() then
                print("Found modem on side: " .. side)
                return side
            end
        end
    end
    
    print("No modem found!")
    print("Available sides:")
    for _, side in ipairs(sides) do
        print("  " .. side .. " - " .. peripheral.getType(side))
    end
    
    print("\nEnter modem side:")
    local input = read()
    
    if input then
        local modem = peripheral.wrap(input)
        if modem and modem.isWireless and modem.isWireless() then
            print("Using modem on side: " .. input)
            return input
        else
            print("No modem on side: " .. input)
        end
    end
    
    return nil
end

-- Find modem
local MODEM_SIDE = findWirelessModem(modemSide)
if not MODEM_SIDE then
    print("ERROR: No wireless modem found!")
    print("Attach a wireless modem and try again")
    return
end

local modem = peripheral.wrap(MODEM_SIDE)
if not modem then
    print("ERROR: Cannot use modem on side: " .. MODEM_SIDE)
    return
end

rednet.open(MODEM_SIDE)
print("Modem opened on side: " .. MODEM_SIDE)

-- Set server name
local SERVER_DISPLAY_NAME = serverName or os.getComputerLabel() or "Server" .. os.getComputerID()
rednet.host(PROTOCOL, SERVER_DISPLAY_NAME)

print("Server Name: " .. SERVER_DISPLAY_NAME)
print("Server ID: " .. os.getComputerID())
print("Protocol: " .. PROTOCOL)

-- Data storage
local clients = {}
local messages = {}
local messageHistory = {}

-- Functions
function saveData()
    local data = {
        clients = clients,
        messages = messages,
        serverName = SERVER_DISPLAY_NAME
    }
    
    local file = fs.open("server_data.dat", "w")
    if file then
        file.write(textutils.serialize(data))
        file.close()
        print("Data saved")
    end
end

function loadData()
    if fs.exists("server_data.dat") then
        local file = fs.open("server_data.dat", "r")
        if file then
            local data = textutils.unserialize(file.readAll())
            file.close()
            
            if data then
                clients = data.clients or clients
                messages = data.messages or messages
                SERVER_DISPLAY_NAME = data.serverName or SERVER_DISPLAY_NAME
                print("Data loaded")
            end
        end
    end
end

function registerClient(clientId, clientName)
    if not clients[clientId] then
        print("New client: " .. clientName .. " (ID: " .. clientId .. ")")
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
            serverName = SERVER_DISPLAY_NAME,
            message = success and "OK" or "ERROR"
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
            clients = getOnlineClients(),
            serverName = SERVER_DISPLAY_NAME
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
    end
    
    return {
        type = "error",
        message = "Bad request"
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
        print("Marked " .. removed .. " clients as offline")
    end
end

function displayStats()
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
    
    print(string.format("Stats: %d/%d online | %d pending | %d messages",
        online, total, pending, #messageHistory))
end

-- Main server loop
function main()
    loadData()
    
    print("\n=== Server Started ===")
    print("Server Name: " .. SERVER_DISPLAY_NAME)
    print("Server ID: " .. os.getComputerID())
    print("Protocol: " .. PROTOCOL)
    print("Modem Side: " .. MODEM_SIDE)
    print("Waiting for connections...")
    print("Press Ctrl+T to stop server\n")
    
    while true do
        local senderId, request, protocol = rednet.receive(PROTOCOL, 2)
        
        if senderId then
            if protocol == PROTOCOL then
                local response = processRequest(senderId, request)
                rednet.send(senderId, response, PROTOCOL)
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
        elseif event == "terminate" then
            print("\nServer stopping...")
            saveData()
            break
        end
    end
end

-- Error handling
local ok, err = pcall(main)
if not ok then
    print("Server error: " .. err)
    saveData()
end

rednet.unhost(PROTOCOL)
rednet.close()
print("Server stopped")
