-- Telegram Server for CC:Tweaked
-- Modem ID: 1384
-- Handles message routing, encryption, and delivery confirmation

local SERVER_ID = 1384
local CONFIG_FILE = "server_config.cfg"
local USERS_FILE = "users.dat"
local MESSAGES_FILE = "server_messages.dat"
local ENCRYPTION_KEY = "MadeByJemmaperXDForTest" -- Change this in production!

-- Server state
local server = {
    users = {}, -- {username = {address, online, lastSeen}}
    messages = {}, -- {messageId = {from, to, text, time, status}}
    nextMessageId = 1,
    modem = nil,
    isRunning = true,
    onlineUsers = {}
}

-- Simple XOR encryption
local function encrypt(text, key)
    local result = ""
    local keyLen = #key
    for i = 1, #text do
        local charCode = string.byte(text, i)
        local keyChar = string.byte(key, (i - 1) % keyLen + 1)
        local encryptedChar = bit32.bxor(charCode, keyChar)
        result = result .. string.char(encryptedChar)
    end
    return result
end

-- Simple XOR decryption
local function decrypt(encryptedText, key)
    return encrypt(encryptedText, key) -- XOR is symmetric
end

-- Convert string to hex for transmission
local function toHex(str)
    return (str:gsub('.', function(c)
        return string.format('%02X', string.byte(c))
    end))
end

-- Convert hex back to string
local function fromHex(hex)
    return (hex:gsub('..', function(cc)
        return string.char(tonumber(cc, 16))
    end))
end

-- Initialize modem
local function initModem()
    for _, side in pairs(peripheral.getNames()) do
        if peripheral.getType(side) == "modem" then
            server.modem = peripheral.wrap(side)
            if server.modem then
                server.modem.open(SERVER_ID)
                print("Server modem initialized on side: " .. side)
                print("Server ID: " .. SERVER_ID)
                return true
            end
        end
    end
    return false
end

-- Load server data
local function loadData()
    -- Load users
    if fs.exists(USERS_FILE) then
        local file = fs.open(USERS_FILE, "r")
        local data = file.readAll()
        file.close()
        if data ~= "" then
            server.users = textutils.unserialize(data) or {}
        end
    end
    
    -- Load messages
    if fs.exists(MESSAGES_FILE) then
        local file = fs.open(MESSAGES_FILE, "r")
        local data = file.readAll()
        file.close()
        if data ~= "" then
            local saved = textutils.unserialize(data) or {}
            server.messages = saved.messages or {}
            server.nextMessageId = saved.nextMessageId or 1
        end
    end
    
    print("Loaded " .. #server.users .. " users and " .. #server.messages .. " messages")
end

-- Save server data
local function saveData()
    -- Save users
    local file = fs.open(USERS_FILE, "w")
    file.write(textutils.unserialize(server.users))
    file.close()
    
    -- Save messages
    local file = fs.open(MESSAGES_FILE, "w")
    local data = {
        messages = server.messages,
        nextMessageId = server.nextMessageId
    }
    file.write(textutils.unserialize(data))
    file.close()
end

-- Register new user
local function registerUser(username, modemSide)
    if server.users[username] then
        return false, "User already exists"
    end
    
    server.users[username] = {
        address = modemSide,
        online = true,
        lastSeen = os.time(),
        status = "Online"
    }
    
    server.onlineUsers[username] = modemSide
    
    print("User registered: " .. username)
    saveData()
    return true, "Registration successful"
end

-- Update user status
local function updateUserStatus(username, modemSide)
    if server.users[username] then
        server.users[username].online = true
        server.users[username].lastSeen = os.time()
        server.users[username].address = modemSide
        server.onlineUsers[username] = modemSide
        return true
    end
    return false
end

-- Process and route message
local function processMessage(sender, recipient, messageText)
    -- Check if recipient exists
    if not server.users[recipient] then
        return false, "Recipient not found"
    end
    
    -- Check if recipient is online
    if not server.onlineUsers[recipient] then
        return false, "Recipient is offline"
    end
    
    -- Create message record
    local messageId = server.nextMessageId
    server.nextMessageId = server.nextMessageId + 1
    
    local messageData = {
        id = messageId,
        from = sender,
        to = recipient,
        text = messageText,
        time = os.time(),
        status = "sent", -- sent, delivered, read
        encrypted = toHex(encrypt(messageText, ENCRYPTION_KEY))
    }
    
    -- Store message
    server.messages[messageId] = messageData
    
    -- Send to recipient
    local recipientAddress = server.onlineUsers[recipient]
    
    local deliveryPacket = {
        type = "message",
        messageId = messageId,
        from = sender,
        encryptedText = messageData.encrypted,
        timestamp = messageData.time
    }
    
    -- Send message
    server.modem.transmit(SERVER_ID, SERVER_ID, deliveryPacket)
    
    -- Send confirmation to sender
    local confirmationPacket = {
        type = "confirmation",
        messageId = messageId,
        status = "sent_to_server"
    }
    
    server.modem.transmit(SERVER_ID, SERVER_ID, confirmationPacket)
    
    print("Message " .. messageId .. " sent from " .. sender .. " to " .. recipient)
    saveData()
    
    return true, messageId
end

-- Mark message as delivered
local function markMessageDelivered(messageId, clientAddress)
    if server.messages[messageId] then
        server.messages[messageId].status = "delivered"
        server.messages[messageId].deliveredTime = os.time()
        
        -- Notify sender
        local sender = server.messages[messageId].from
        if server.onlineUsers[sender] then
            local notification = {
                type = "delivery_report",
                messageId = messageId,
                status = "delivered",
                timestamp = os.time()
            }
            server.modem.transmit(SERVER_ID, SERVER_ID, notification)
        end
        
        saveData()
        return true
    end
    return false
end

-- Mark message as read
local function markMessageRead(messageId)
    if server.messages[messageId] then
        server.messages[messageId].status = "read"
        server.messages[messageId].readTime = os.time()
        
        -- Notify sender
        local sender = server.messages[messageId].from
        if server.onlineUsers[sender] then
            local notification = {
                type = "read_report",
                messageId = messageId,
                status = "read",
                timestamp = os.time()
            }
            server.modem.transmit(SERVER_ID, SERVER_ID, notification)
        end
        
        saveData()
        return true
    end
    return false
end

-- Get user list (for client requests)
local function getUserList()
    local users = {}
    for username, data in pairs(server.users) do
        table.insert(users, {
            username = username,
            online = data.online,
            status = data.status,
            lastSeen = data.lastSeen
        })
    end
    return users
end

-- Get offline messages for user
local function getOfflineMessages(username)
    local offlineMessages = {}
    for id, message in pairs(server.messages) do
        if message.to == username and message.status == "sent" then
            table.insert(offlineMessages, {
                id = message.id,
                from = message.from,
                encryptedText = message.encrypted,
                timestamp = message.time
            })
        end
    end
    return offlineMessages
end

-- Process incoming packets
local function processPackets()
    print("Server started. Listening for connections...")
    
    while server.isRunning do
        local event, modemSide, senderChannel, replyChannel, message, senderDistance = os.pullEvent("modem_message")
        
        if message and message.type then
            -- Handle registration
            if message.type == "register" then
                local username = message.username
                local success, result = registerUser(username, modemSide)
                
                local response = {
                    type = "register_response",
                    success = success,
                    message = result,
                    serverId = SERVER_ID
                }
                
                server.modem.transmit(SERVER_ID, SERVER_ID, response)
                print("Registration attempt: " .. username .. " - " .. tostring(success))
            
            -- Handle login/status update
            elseif message.type == "login" then
                local username = message.username
                local updated = updateUserStatus(username, modemSide)
                
                -- Send offline messages if any
                local offlineMessages = getOfflineMessages(username)
                
                local response = {
                    type = "login_response",
                    success = updated,
                    offlineMessages = offlineMessages,
                    serverTime = os.time()
                }
                
                server.modem.transmit(SERVER_ID, SERVER_ID, response)
                
                if updated then
                    print("User logged in: " .. username)
                end
            
            -- Handle message sending
            elseif message.type == "send_message" then
                local sender = message.sender
                local recipient = message.recipient
                local text = message.text
                
                -- Verify sender is registered
                if not server.users[sender] then
                    local errorResponse = {
                        type = "error",
                        error = "Sender not registered"
                    }
                    server.modem.transmit(SERVER_ID, SERVER_ID, errorResponse)
                else
                    local success, result = processMessage(sender, recipient, text)
                    
                    local response = {
                        type = "send_response",
                        success = success,
                        messageId = result,
                        error = not success and result or nil
                    }
                    
                    server.modem.transmit(SERVER_ID, SERVER_ID, response)
                end
            
            -- Handle message delivery confirmation
            elseif message.type == "delivery_confirm" then
                local messageId = message.messageId
                markMessageDelivered(messageId, modemSide)
                print("Message " .. messageId .. " delivered")
            
            -- Handle message read confirmation
            elseif message.type == "read_confirm" then
                local messageId = message.messageId
                markMessageRead(messageId)
                print("Message " .. messageId .. " read")
            
            -- Handle user list request
            elseif message.type == "get_users" then
                local users = getUserList()
                local response = {
                    type = "users_list",
                    users = users
                }
                server.modem.transmit(SERVER_ID, SERVER_ID, response)
            
            -- Handle ping
            elseif message.type == "ping" then
                local response = {
                    type = "pong",
                    serverTime = os.time(),
                    onlineUsers = #server.onlineUsers
                }
                server.modem.transmit(SERVER_ID, SERVER_ID, response)
            
            -- Handle logout
            elseif message.type == "logout" then
                local username = message.username
                if server.users[username] then
                    server.users[username].online = false
                    server.onlineUsers[username] = nil
                    print("User logged out: " .. username)
                    saveData()
                end
            end
        end
        
        -- Auto-save every 30 seconds
        if os.time() % 30 == 0 then
            saveData()
        end
    end
end

-- Server console interface
local function serverConsole()
    while server.isRunning do
        print("\n=== Server Commands ===")
        print("1. Show online users")
        print("2. Show all users")
        print("3. Show message statistics")
        print("4. Save data")
        print("5. Shutdown server")
        print("======================")
        write("Command: ")
        
        local command = read()
        
        if command == "1" then
            print("\nOnline Users (" .. #server.onlineUsers .. "):")
            for username, _ in pairs(server.onlineUsers) do
                print("  - " .. username)
            end
        
        elseif command == "2" then
            print("\nAll Registered Users:")
            for username, data in pairs(server.users) do
                local status = data.online and "Online" or "Offline"
                print("  - " .. username .. " (" .. status .. ")")
            end
        
        elseif command == "3" then
            local sent = 0
            local delivered = 0
            local read = 0
            
            for _, msg in pairs(server.messages) do
                if msg.status == "sent" then sent = sent + 1
                elseif msg.status == "delivered" then delivered = delivered + 1
                elseif msg.status == "read" then read = read + 1 end
            end
            
            print("\nMessage Statistics:")
            print("  Total messages: " .. (server.nextMessageId - 1))
            print("  Sent: " .. sent)
            print("  Delivered: " .. delivered)
            print("  Read: " .. read)
        
        elseif command == "4" then
            saveData()
            print("Data saved successfully")
        
        elseif command == "5" then
            print("Shutting down server...")
            saveData()
            server.isRunning = false
            break
        end
        
        sleep(1)
    end
end

-- Main server function
local function main()
    print("=== Telegram Server ===")
    print("Initializing...")
    
    -- Initialize modem
    if not initModem() then
        print("ERROR: No modem found!")
        print("Please attach a modem to the server")
        return
    end
    
    -- Load data
    loadData()
    
    -- Start server processes
    parallel.waitForAny(
        function() processPackets() end,
        function() serverConsole() end
    )
    
    print("Server stopped")
end

-- Run server
main()
