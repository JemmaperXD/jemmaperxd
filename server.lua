-- Messenger Server for CC:Tweaked
local VERSION = "1.2"
local PORT = 1384
local MAX_CLIENTS = 20

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
        print("Usage: server [options]")
        print("Options:")
        print("  -n, --name <name>    Set server display name")
        print("  -s, --side <side>    Specify modem side (left/right/top/bottom/back/front)")
        print("  -h, --help           Show this help message")
        return
    end
end

-- Function to get username from /.User folder
function getUsernameFromFolder()
    local userFolderPath = "/.User"
    
    if fs.exists(userFolderPath) and fs.isDir(userFolderPath) then
        -- List all items in /.User folder
        local items = fs.list(userFolderPath)
        
        for _, item in ipairs(items) do
            local itemPath = fs.combine(userFolderPath, item)
            
            -- Check if it's a directory and starts with "."
            if fs.isDir(itemPath) and string.sub(item, 1, 1) == "." then
                local username = string.sub(item, 2) -- Remove the leading dot
                if username and username ~= "" then
                    return username
                end
            end
        end
    end
    
    return nil
end

-- Ask for username if not found
function askForUsername()
    print("No username found in /.User folder")
    print("Please enter your username:")
    
    local username = read()
    
    -- Validate username
    while not username or username == "" or #username > 20 do
        if not username or username == "" then
            print("Username cannot be empty. Please enter username:")
        elseif #username > 20 then
            print("Username too long (max 20 characters). Please enter shorter name:")
        end
        username = read()
    end
    
    -- Create /.User/.username folder
    local userFolderPath = "/.User"
    if not fs.exists(userFolderPath) then
        fs.makeDir(userFolderPath)
    end
    
    local userSpecificFolder = fs.combine(userFolderPath, "." .. username)
    if not fs.exists(userSpecificFolder) then
        fs.makeDir(userSpecificFolder)
    end
    
    return username
end

-- Get or ask for username
local DEFAULT_USERNAME = os.getComputerLabel() or "Server" .. os.getComputerID()
local username = getUsernameFromFolder()

if not username then
    username = askForUsername()
end

-- Initialization
print("=== Messenger Server v" .. VERSION .. " ===")
print("Server username: " .. username)

-- Function to find wireless modem
function findWirelessModem(specifiedSide)
    if specifiedSide then
        -- Check specified side first
        local modem = peripheral.wrap(specifiedSide)
        if modem and modem.isWireless and modem.isWireless() then
            return specifiedSide
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
                return side
            end
        end
    end
    
    -- If not found, list available peripherals
    print("Available peripherals:")
    for _, side in ipairs(sides) do
        print("  " .. side .. " - " .. peripheral.getType(side))
    end
    
    -- Ask user to specify side
    print("\nPlease enter modem side (left, right, top, bottom, back, front):")
    local input = read()
    
    if input then
        local modem = peripheral.wrap(input)
        if modem and modem.isWireless and modem.isWireless() then
            return input
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

-- Set server name
local SERVER_DISPLAY_NAME = serverName or username

-- Data structures
local clients = {} -- id -> {name, lastSeen, online, registered}
local messages = {}
local messageHistory = {}
local messageIds = {}

-- Generate unique message ID
function generateMessageId()
    return os.getComputerID() .. "_" .. os.epoch("utc") .. "_" .. math.random(1000, 9999)
end

-- Functions
function saveData()
    local data = {
        clients = clients,
        messages = messages,
        serverName = SERVER_DISPLAY_NAME,
        messageHistory = messageHistory
    }
    
    local file = fs.open("server_data.dat", "w")
    if file then
        file.write(textutils.serialize(data))
        file.close()
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
                messageHistory = data.messageHistory or messageHistory
            end
        end
    end
end

function registerClient(clientId, clientName)
    local isNew = not clients[clientId]
    
    clients[clientId] = {
        name = clientName,
        lastSeen = os.epoch("utc"),
        online = true,
        registered = true
    }
    
    if not messages[clientId] then
        messages[clientId] = {}
    end
    
    return true, isNew
end

function isDuplicateMessage(senderId, targetId, message, timestamp)
    for _, msg in ipairs(messageHistory) do
        if msg.sender == senderId and 
           msg.target == targetId and 
           msg.message == message and
           os.epoch("utc") - msg.time < 5000 then
            return true
        end
    end
    return false
end

function sendMessage(senderId, targetId, message, senderName, messageId)
    if not clients[targetId] or not clients[targetId].registered then
        return false, "Client not found or not registered"
    end
    
    if isDuplicateMessage(senderId, targetId, message, os.epoch("utc")) then
        return true, "Message already sent"
    end
    
    local msg = {
        id = messageId or generateMessageId(),
        sender = senderId,
        senderName = senderName,
        target = targetId,
        message = message,
        time = os.epoch("utc"),
        delivered = false
    }
    
    table.insert(messageHistory, msg)
    table.insert(messages[targetId], msg)
    
    if #messageHistory % 10 == 0 then
        saveData()
    end
    
    return true, "Message sent"
end

function getOnlineClients()
    local online = {}
    local now = os.epoch("utc")
    
    for id, client in pairs(clients) do
        if client.registered and client.online and now - client.lastSeen < 30000 then
            table.insert(online, {
                id = id,
                name = client.name
            })
        end
    end
    return online
end

function getAllRegisteredClients()
    local allClients = {}
    local now = os.epoch("utc")
    
    for id, client in pairs(clients) do
        if client.registered then
            table.insert(allClients, {
                id = id,
                name = client.name,
                online = client.online and now - client.lastSeen < 30000,
                lastSeen = client.lastSeen
            })
        end
    end
    return allClients
end

function getClientMessages(clientId)
    local clientMsgs = messages[clientId] or {}
    local result = {}
    
    -- Return all undelivered messages
    for i = #clientMsgs, 1, -1 do
        local msg = clientMsgs[i]
        if not msg.delivered then
            table.insert(result, msg)
            msg.delivered = true
        end
    end
    
    -- Clean old delivered messages (keep last 50)
    local newQueue = {}
    local count = 0
    for i = #clientMsgs, 1, -1 do
        local msg = clientMsgs[i]
        if not msg.delivered or count < 50 then
            table.insert(newQueue, 1, msg)
            if msg.delivered then
                count = count + 1
            end
        end
    end
    
    messages[clientId] = newQueue
    
    return result
end

function processRequest(senderId, request)
    if request.type == "register" then
        local success, isNew = registerClient(senderId, request.name)
        return {
            type = "register_response",
            success = success,
            serverName = SERVER_DISPLAY_NAME,
            isNew = isNew
        }
        
    elseif request.type == "send_message" then
        local success, err = sendMessage(senderId, request.target, 
                                        request.message, request.senderName, request.messageId)
        return {
            type = "message_response",
            success = success,
            messageId = request.messageId or generateMessageId(),
            error = not success and err or nil
        }
        
    elseif request.type == "get_online" then
        return {
            type = "online_list",
            clients = getOnlineClients(),
            serverName = SERVER_DISPLAY_NAME
        }
        
    elseif request.type == "get_all_clients" then
        return {
            type = "all_clients",
            clients = getAllRegisteredClients(),
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
            serverId = os.getComputerID(),
            onlineCount = #getOnlineClients(),
            totalCount = #getAllRegisteredClients()
        }
    end
    
    return {
        type = "error",
        message = "Bad request"
    }
end

function cleanupOldClients()
    local now = os.epoch("utc")
    
    for id, client in pairs(clients) do
        if now - client.lastSeen > 300000 then
            client.online = false
        end
    end
end

function cleanupOldMessages()
    local now = os.epoch("utc")
    local cutoff = now - 86400000
    
    local newHistory = {}
    for _, msg in ipairs(messageHistory) do
        if msg.time > cutoff then
            table.insert(newHistory, msg)
        end
    end
    
    if #messageHistory ~= #newHistory then
        messageHistory = newHistory
    end
end

function displayStatus()
    local online = getOnlineClients()
    local allClients = getAllRegisteredClients()
    
    print(string.format("[%s] Online: %d | Registered: %d",
        os.date("%H:%M:%S"), #online, #allClients))
end

-- Main server loop
function main()
    loadData()
    
    print("\n=== Server Started ===")
    print("Server Name: " .. SERVER_DISPLAY_NAME)
    print("Server ID: " .. os.getComputerID())
    print("Server Port: " .. PORT)
    print("Modem Side: " .. MODEM_SIDE)
    print("Waiting for connections...")
    print("Press Ctrl+T to stop server\n")
    
    while true do
        local senderId, request, protocol = rednet.receive(PORT, 2)
        
        if senderId then
            if protocol == PORT then
                local response = processRequest(senderId, request)
                rednet.send(senderId, response, PORT)
            end
        end
        
        local timer = os.startTimer(10)
        local event = os.pullEvent()
        
        if event == "timer" then
            cleanupOldClients()
            cleanupOldMessages()
            displayStatus()
            
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
