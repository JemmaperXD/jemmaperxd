-- Messenger Server for CC:Tweaked
local VERSION = "1.0"
local SERVER_ID = 1384 -- Фиксированный ID сервера
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
        print()
        print("Server ID is fixed to: " .. SERVER_ID)
        return
    end
end

-- Initialization
print("=== Messenger Server v" .. VERSION .. " ===")
print("Loading...")

-- Function to find wireless modem
function findWirelessModem(specifiedSide)
    print("Searching for wireless modem...")
    
    if specifiedSide then
        -- Check specified side first
        local modem = peripheral.wrap(specifiedSide)
        if modem and modem.isWireless and modem.isWireless() then
            print("Using specified modem on side: " .. specifiedSide)
            return specifiedSide
        else
            print("Warning: No wireless modem found on specified side: " .. specifiedSide)
        end
    end
    
    -- Get all peripherals
    local sides = peripheral.getNames()
    
    for _, side in ipairs(sides) do
        local type = peripheral.getType(side)
        if type == "modem" then
            -- Check if it's a wireless modem
            local modem = peripheral.wrap(side)
            if modem and modem.isWireless and modem.isWireless() then
                print("Found wireless modem on side: " .. side)
                return side
            end
        end
    end
    
    -- If not found, list available peripherals
    print("No wireless modem found!")
    print("Available peripherals:")
    for _, side in ipairs(sides) do
        print("  " .. side .. " - " .. peripheral.getType(side))
    end
    
    -- Ask user to specify side
    print("\nPlease enter modem side (left, right, top, bottom, back, front):")
    local input = read()
    
    if input then
        -- Check if this side has a modem
        local modem = peripheral.wrap(input)
        if modem and modem.isWireless and modem.isWireless() then
            print("Using modem on side: " .. input)
            return input
        else
            print("Error: No wireless modem found on side: " .. input)
        end
    end
    
    return nil
end

-- Find and open modem
local MODEM_SIDE = findWirelessModem(modemSide)
if not MODEM_SIDE then
    print("ERROR: Could not find wireless modem!")
    print("Please attach a wireless modem and try again")
    return
end

local modem = peripheral.wrap(MODEM_SIDE)
if not modem then
    print("ERROR: Cannot access modem on side: " .. MODEM_SIDE)
    return
end

rednet.open(MODEM_SIDE)
print("Modem opened successfully on side: " .. MODEM_SIDE)

-- Set server name
local SERVER_DISPLAY_NAME = serverName or os.getComputerLabel() or "Server" .. os.getComputerID()
print("Server display name: " .. SERVER_DISPLAY_NAME)
print("Server computer ID: " .. os.getComputerID())
print("Fixed server ID: " .. SERVER_ID)
print("Protocol: " .. PROTOCOL)

-- Data structures
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
                print("Data loaded: " .. #messageHistory .. " messages, " .. countTable(clients) .. " clients")
                print("Server name: " .. SERVER_DISPLAY_NAME)
            end
        end
    end
end

function countTable(tbl)
    local count = 0
    for _ in pairs(tbl) do
        count = count + 1
    end
    return count
end

function registerClient(clientId, clientName)
    if not clients[clientId] then
        print("New client registered: " .. clientName .. " (ID: " .. clientId .. ")")
    else
        print("Client reconnected: " .. clientName .. " (ID: " .. clientId .. ")")
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
    
    print("[" .. os.date("%H:%M:%S") .. "] Message from " .. senderName .. 
          " (" .. senderId .. ") to " .. clients[targetId].name .. 
          " (" .. targetId .. "): " .. string.sub(message, 1, 20) .. (#message > 20 and "..." or ""))
    
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
        
    elseif request.type == "get_server_info" then
        return {
            type = "server_info",
            serverName = SERVER_DISPLAY_NAME,
            serverId = SERVER_ID,
            onlineCount = #getOnlineClients()
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
    print(string.format("[%s] Stats: %d/%d online | %d pending | %d messages",
        os.date("%H:%M:%S"), stats.online, stats.total, stats.pending, stats.totalMessages))
end

-- Main server loop
function main()
    loadData()
    
    print("\n=== Server Started ===")
    print("Server Name: " .. SERVER_DISPLAY_NAME)
    print("Server ID: " .. os.getComputerID())
    print("Fixed Server ID: " .. SERVER_ID)
    print("Protocol: " .. PROTOCOL)
    print("Modem Side: " .. MODEM_SIDE)
    print("Waiting for connections...")
    print("Press Ctrl+T to stop server\n")
    
    while true do
        local senderId, request, protocol = rednet.receive(nil, 2)
        
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

rednet.close()
print("Server stopped")
