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
        print("  -s, --side <side>    Specify modem side")
        print("  -h, --help           Show help")
        return
    end
end

print("=== Messenger Server v" .. VERSION .. " ===")
print("Loading...")

-- Find modem
function findModem(side)
    if side then
        local modem = peripheral.wrap(side)
        if modem and modem.isWireless and modem.isWireless() then
            return side
        end
    end
    
    local sides = peripheral.getNames()
    for _, s in ipairs(sides) do
        if peripheral.getType(s) == "modem" then
            local modem = peripheral.wrap(s)
            if modem and modem.isWireless and modem.isWireless() then
                return s
            end
        end
    end
    
    return nil
end

local MODEM_SIDE = findModem(modemSide)
if not MODEM_SIDE then
    print("No modem found!")
    return
end

rednet.open(MODEM_SIDE)
print("Modem opened: " .. MODEM_SIDE)

-- Server setup
local SERVER_NAME = serverName or os.getComputerLabel() or "Server" .. os.getComputerID()
rednet.host(PROTOCOL, SERVER_NAME)

print("Server: " .. SERVER_NAME)
print("ID: " .. os.getComputerID())
print("Protocol: " .. PROTOCOL)

-- Data storage
local clients = {}
local messages = {}

-- Functions
function saveData()
    local data = {clients = clients, messages = messages}
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
            end
        end
    end
end

function processRequest(senderId, request)
    if request.type == "register" then
        clients[senderId] = {
            name = request.name,
            lastSeen = os.epoch("utc")
        }
        if not messages[senderId] then
            messages[senderId] = {}
        end
        return {type = "register_response", success = true, serverName = SERVER_NAME}
        
    elseif request.type == "send_message" then
        local targetId = request.target
        if clients[targetId] then
            local msg = {
                sender = senderId,
                senderName = request.senderName,
                message = request.message,
                time = os.epoch("utc")
            }
            table.insert(messages[targetId], msg)
            return {type = "message_response", success = true}
        else
            return {type = "message_response", success = false, error = "Client not found"}
        end
        
    elseif request.type == "get_online" then
        local online = {}
        for id, client in pairs(clients) do
            if os.epoch("utc") - client.lastSeen < 30000 then
                table.insert(online, {id = id, name = client.name})
            end
        end
        return {type = "online_list", clients = online, serverName = SERVER_NAME}
        
    elseif request.type == "get_messages" then
        local userMsgs = messages[senderId] or {}
        return {type = "messages", messages = userMsgs}
        
    elseif request.type == "ping" then
        if clients[senderId] then
            clients[senderId].lastSeen = os.epoch("utc")
        end
        return {type = "pong"}
    end
    
    return {type = "error", message = "Unknown request"}
end

-- Main loop
function main()
    loadData()
    
    print("\n=== Server Started ===")
    print("Waiting for connections...")
    print("Ctrl+T to stop\n")
    
    while true do
        local id, msg, protocol = rednet.receive(PROTOCOL, 1)
        
        if id then
            if protocol == PROTOCOL then
                local response = processRequest(id, msg)
                rednet.send(id, response, PROTOCOL)
            end
        end
        
        local event = os.pullEventRaw()
        if event == "terminate" then
            break
        end
    end
end

local ok, err = pcall(main)
if not ok then
    print("Error: " .. err)
end

saveData()
rednet.unhost(PROTOCOL)
rednet.close()
print("Server stopped")
