-- Telegram Client for CC:Tweaked
-- Connects to server ID: 1384

local SERVER_ID = 1384
local CONFIG_FILE = "client_config.cfg"
local CONTACTS_FILE = "client_contacts.dat"
local MESSAGES_FILE = "client_messages.dat"
local ENCRYPTION_KEY = "CC_TELEGRAM_2024_KEY" -- Must match server key!

-- Client state
local client = {
    username = "",
    serverId = SERVER_ID,
    modem = nil,
    isRunning = true,
    isConnected = false,
    isLoggedIn = false,
    contacts = {},
    messages = {}, -- Organized by contact: {contact = {messages}}
    pendingMessages = {}, -- Messages waiting for delivery confirmation
    unreadCounts = {},
    currentScreen = "login", -- login, contacts, chat, settings
    selectedContact = 1,
    inputBuffer = "",
    messageOffset = 0,
    currentChat = nil
}

-- Simple XOR encryption/decryption (same as server)
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

local function decrypt(encryptedText, key)
    return encrypt(encryptedText, key) -- XOR is symmetric
end

-- Hex conversion (same as server)
local function toHex(str)
    return (str:gsub('.', function(c)
        return string.format('%02X', string.byte(c))
    end))
end

local function fromHex(hex)
    return (hex:gsub('..', function(cc)
        return string.char(tonumber(cc, 16))
    end))
end

-- Initialize modem
local function initModem()
    for _, side in pairs(peripheral.getNames()) do
        if peripheral.getType(side) == "modem" then
            client.modem = peripheral.wrap(side)
            if client.modem then
                client.modem.open(SERVER_ID)
                print("Modem initialized on side: " .. side)
                return true
            end
        end
    end
    return false
end

-- Load client data
local function loadData()
    -- Load config
    if fs.exists(CONFIG_FILE) then
        local file = fs.open(CONFIG_FILE, "r")
        client.username = file.readLine() or ""
        file.close()
    end
    
    -- Load contacts
    if fs.exists(CONTACTS_FILE) then
        local file = fs.open(CONTACTS_FILE, "r")
        local data = file.readAll()
        file.close()
        if data ~= "" then
            client.contacts = textutils.unserialize(data) or {}
        end
    end
    
    -- Load messages
    if fs.exists(MESSAGES_FILE) then
        local file = fs.open(MESSAGES_FILE, "r")
        local data = file.readAll()
        file.close()
        if data ~= "" then
            client.messages = textutils.unserialize(data) or {}
        end
    end
end

-- Save client data
local function saveData()
    -- Save config
    local file = fs.open(CONFIG_FILE, "w")
    file.writeLine(client.username)
    file.close()
    
    -- Save contacts
    local file = fs.open(CONTACTS_FILE, "w")
    file.write(textutils.unserialize(client.contacts))
    file.close()
    
    -- Save messages
    local file = fs.open(MESSAGES_FILE, "w")
    file.write(textutils.unserialize(client.messages))
    file.close()
end

-- Send packet to server
local function sendToServer(packet)
    if client.modem and client.isConnected then
        client.modem.transmit(SERVER_ID, SERVER_ID, packet)
        return true
    end
    return false
end

-- Register with server
local function registerWithServer(username)
    local packet = {
        type = "register",
        username = username
    }
    
    sendToServer(packet)
    
    -- Wait for response
    local startTime = os.time()
    while os.time() - startTime < 5 do
        local event, modemSide, channel, replyChannel, message = os.pullEvent("modem_message")
        if message and message.type == "register_response" then
            if message.success then
                client.username = username
                client.isConnected = true
                saveData()
                return true, message.message
            else
                return false, message.message
            end
        end
    end
    return false, "Server timeout"
end

-- Login to server
local function loginToServer(username)
    local packet = {
        type = "login",
        username = username
    }
    
    sendToServer(packet)
    
    -- Wait for response
    local startTime = os.time()
    while os.time() - startTime < 5 do
        local event, modemSide, channel, replyChannel, message = os.pullEvent("modem_message")
        if message and message.type == "login_response" then
            if message.success then
                client.isLoggedIn = true
                client.isConnected = true
                
                -- Process offline messages
                if message.offlineMessages then
                    for _, msg in ipairs(message.offlineMessages) do
                        processIncomingMessage(msg)
                    end
                end
                
                return true, "Login successful"
            else
                return false, "Login failed"
            end
        end
    end
    return false, "Server timeout"
end

-- Send message to contact
local function sendMessageToContact(contact, text)
    local packet = {
        type = "send_message",
        sender = client.username,
        recipient = contact,
        text = text
    }
    
    sendToServer(packet)
    
    -- Store in pending messages
    local tempId = os.time() .. "_" .. math.random(1000)
    client.pendingMessages[tempId] = {
        contact = contact,
        text = text,
        time = os.time(),
        status = "sending"
    }
    
    return tempId
end

-- Confirm message delivery to server
local function confirmDelivery(messageId)
    local packet = {
        type = "delivery_confirm",
        messageId = messageId
    }
    sendToServer(packet)
end

-- Confirm message read to server
local function confirmRead(messageId)
    local packet = {
        type = "read_confirm",
        messageId = messageId
    }
    sendToServer(packet)
end

-- Process incoming message from server
local function processIncomingMessage(messageData)
    local messageId = messageData.messageId
    local sender = messageData.from
    local encryptedText = messageData.encryptedText
    
    -- Decrypt message
    local decryptedText = decrypt(fromHex(encryptedText), ENCRYPTION_KEY)
    
    -- Add to messages
    if not client.messages[sender] then
        client.messages[sender] = {}
    end
    
    local messageRecord = {
        id = messageId,
        from = sender,
        text = decryptedText,
        time = messageData.timestamp or os.time(),
        status = "received",
        encrypted = encryptedText
    }
    
    table.insert(client.messages[sender], messageRecord)
    
    -- Update unread count
    if client.currentChat ~= sender then
        client.unreadCounts[sender] = (client.unreadCounts[sender] or 0) + 1
    end
    
    -- Send delivery confirmation
    confirmDelivery(messageId)
    
    -- Save messages
    saveData()
    
    -- Show notification if not in chat with sender
    if client.currentScreen ~= "chat" or client.currentChat ~= sender then
        print("New message from " .. sender)
    end
    
    return messageId
end

-- Process server responses
local function processServerResponses()
    while client.isRunning do
        local event, modemSide, channel, replyChannel, message = os.pullEvent("modem_message")
        
        if message and message.type then
            -- Handle incoming message
            if message.type == "message" then
                processIncomingMessage(message)
            
            -- Handle send confirmation
            elseif message.type == "send_response" then
                -- Find pending message and update status
                for tempId, pending in pairs(client.pendingMessages) do
                    if pending.status == "sending" and pending.text == message.text then
                        pending.status = message.success and "sent" or "failed"
                        pending.messageId = message.messageId
                        pending.error = message.error
                        break
                    end
                end
            
            -- Handle delivery report
            elseif message.type == "delivery_report" then
                local messageId = message.messageId
                -- Update message status in all contacts
                for contact, messages in pairs(client.messages) do
                    for _, msg in ipairs(messages) do
                        if msg.id == messageId then
                            msg.status = "delivered"
                            msg.deliveredTime = message.timestamp
                            break
                        end
                    end
                end
            
            -- Handle read report
            elseif message.type == "read_report" then
                local messageId = message.messageId
                -- Update message status
                for contact, messages in pairs(client.messages) do
                    for _, msg in ipairs(messages) do
                        if msg.id == messageId then
                            msg.status = "read"
                            msg.readTime = message.timestamp
                            break
                        end
                    end
                end
            
            -- Handle users list
            elseif message.type == "users_list" then
                -- Update contacts with online status
                for _, userData in ipairs(message.users) do
                    for i, contact in ipairs(client.contacts) do
                        if contact.username == userData.username then
                            client.contacts[i].online = userData.online
                            client.contacts[i].lastSeen = userData.lastSeen
                            break
                        end
                    end
                end
            
            -- Handle ping response
            elseif message.type == "pong" then
                client.isConnected = true
            end
        end
    end
end

-- Request user list from server
local function requestUserList()
    local packet = {
        type = "get_users"
    }
    sendToServer(packet)
end

-- Add contact
local function addContact(username)
    for _, contact in ipairs(client.contacts) do
        if contact.username == username then
            return false, "Contact already exists"
        end
    end
    
    table.insert(client.contacts, {
        username = username,
        online = false,
        lastSeen = 0
    })
    
    saveData()
    return true, "Contact added"
end

-- Remove contact
local function removeContact(index)
    if index >= 1 and index <= #client.contacts then
        local username = client.contacts[index].username
        table.remove(client.contacts, index)
        
        -- Clear unread count
        client.unreadCounts[username] = nil
        
        saveData()
        return true
    end
    return false
end

-- UI Drawing functions
local function drawHeader()
    term.clear()
    term.setCursorPos(1, 1)
    term.write("=== Telegram Client ===")
    term.setCursorPos(25, 1)
    term.write("User: " .. client.username)
    
    if client.isConnected then
        term.setCursorPos(45, 1)
        term.write("[ONLINE]")
    else
        term.setCursorPos(45, 1)
        term.write("[OFFLINE]")
    end
end

local function drawLoginScreen()
    drawHeader()
    
    local width, height = term.getSize()
    
    term.setCursorPos(width/2 - 10, height/2 - 2)
    term.write("Enter username: ")
    
    term.setCursorPos(width/2 - 10, height/2)
    term.write(client.inputBuffer)
    
    term.setCursorPos(width/2 - 15, height/2 + 2)
    term.write("[Enter] Login  [R] Register  [Q] Quit")
end

local function drawContactsScreen()
    drawHeader()
    
    local width, height = term.getSize()
    
    term.setCursorPos(1, 3)
    term.write("Contacts (" .. #client.contacts .. "):")
    term.setCursorPos(1, 4)
    term.write(string.rep("=", width))
    
    for i, contact in ipairs(client.contacts) do
        term.setCursorPos(2, 4 + i)
        
        if i == client.selectedContact and client.currentScreen == "contacts" then
            term.write("> ")
        else
            term.write("  ")
        end
        
        local displayName = contact.username
        if client.unreadCounts[contact.username] and client.unreadCounts[contact.username] > 0 then
            displayName = displayName .. " [" .. client.unreadCounts[contact.username] .. "]"
        end
        
        if contact.online then
            displayName = displayName .. " (Online)"
        else
            local timeAgo = os.time() - contact.lastSeen
            if timeAgo < 60 then
                displayName = displayName .. " (Just now)"
            elseif timeAgo < 3600 then
                displayName = displayName .. " (" .. math.floor(timeAgo/60) .. "m ago)"
            else
                displayName = displayName .. " (Offline)"
            end
        end
        
        term.write(displayName)
    end
    
    term.setCursorPos(1, height - 2)
    term.write(string.rep("=", width))
    term.setCursorPos(1, height - 1)
    term.write("[A]dd  [R]emove  [Enter]Chat  [S]ync  [L]ogout  [Q]uit")
end

local function drawChatScreen()
    if not client.currentChat then return end
    
    drawHeader()
    
    local width, height = term.getSize()
    local messages = client.messages[client.currentChat] or {}
    
    term.setCursorPos(1, 3)
    term.write("Chat with: " .. client.currentChat)
    term.setCursorPos(1, 4)
    term.write(string.rep("=", width))
    
    -- Draw messages
    local startMsg = math.max(1, #messages - (height - 8) + 1 - client.messageOffset)
    local yPos = 5
    
    for i = startMsg, #messages do
        if yPos > height - 4 then break end
        
        local msg = messages[i]
        term.setCursorPos(1, yPos)
        
        -- Format: [HH:MM] Sender: Message [Status]
        local timeStr = os.date("%H:%M", msg.time)
        local prefix = "[" .. timeStr .. "] " .. (msg.from == client.username and "You" : msg.from) .. ": "
        
        term.write(prefix)
        
        -- Message text with word wrap
        local remainingWidth = width - #prefix - 10
        local text = msg.text
        local lines = {}
        local currentLine = ""
        
        for word in text:gmatch("%S+") do
            if #currentLine + #word + 1 <= remainingWidth then
                if currentLine ~= "" then
                    currentLine = currentLine .. " " .. word
                else
                    currentLine = word
                end
            else
                table.insert(lines, currentLine)
                currentLine = word
            end
        end
        
        if currentLine ~= "" then
            table.insert(lines, currentLine)
        end
        
        -- Print first line
        term.write(lines[1] or "")
        
        -- Status indicator
        local statusPos = width - 8
        term.setCursorPos(statusPos, yPos)
        if msg.status == "sent" then term.write("[SENT]")
        elseif msg.status == "delivered" then term.write("[DELV]")
        elseif msg.status == "read" then term.write("[READ]")
        else term.write("[RCVD]") end
        
        -- Print remaining lines
        for j = 2, #lines do
            yPos = yPos + 1
            if yPos > height - 4 then break end
            term.setCursorPos(#prefix + 1, yPos)
            term.write(lines[j])
        end
        
        yPos = yPos + 1
    end
    
    -- Draw input area
    term.setCursorPos(1, height - 2)
    term.write(string.rep("=", width))
    term.setCursorPos(1, height - 1)
    term.write("Message: " .. client.inputBuffer)
    
    term.setCursorPos(1, height)
    term.write("[Esc]Back  [Up/Down]Scroll  [Enter]Send")
end

-- Main input handler
local function handleInput()
    while client.isRunning do
        if client.currentScreen == "login" then
            drawLoginScreen()
        elseif client.currentScreen == "contacts" then
            drawContactsScreen()
        elseif client.currentScreen == "chat" then
            drawChatScreen()
        end
        
        local event, key, x, y = os.pullEvent()
        
        if event == "key" then
            if client.currentScreen == "login" then
                if key == keys.enter then
                    if #client.inputBuffer > 0 then
                        local success, message = loginToServer(client.inputBuffer)
                        if success then
                            client.currentScreen = "contacts"
                            requestUserList()
                        else
                            print("Login failed: " .. message)
                            sleep(2)
                        end
                        client.inputBuffer = ""
                    end
                elseif key == keys.r then
                    if #client.inputBuffer > 0 then
                        local success, message = registerWithServer(client.inputBuffer)
                        if success then
                            print("Registration successful!")
                            sleep(1)
                            client.currentScreen = "contacts"
                        else
                            print("Registration failed: " .. message)
                            sleep(2)
                        end
                        client.inputBuffer = ""
                    end
                elseif key == keys.backspace then
                    client.inputBuffer = client.inputBuffer:sub(1, -2)
                elseif key == keys.q then
                    client.isRunning = false
                end
            
            elseif client.currentScreen == "contacts" then
                if key == keys.up then
                    client.selectedContact = math.max(1, client.selectedContact - 1)
                elseif key == keys.down then
                    client.selectedContact = math.min(#client.contacts, client.selectedContact + 1)
                elseif key == keys.enter then
                    if #client.contacts > 0 then
                        client.currentChat = client.contacts[client.selectedContact].username
                        client.currentScreen = "chat"
                        client.messageOffset = 0
                        -- Clear unread count
                        client.unreadCounts[client.currentChat] = nil
                        -- Mark messages as read
                        if client.messages[client.currentChat] then
                            for _, msg in ipairs(client.messages[client.currentChat]) do
                                if msg.status == "received" or msg.status == "delivered" then
                                    confirmRead(msg.id)
                                    msg.status = "read"
                                end
                            end
                        end
                    end
                elseif key == keys.a then
                    term.setCursorPos(1, 20)
                    term.write("Enter contact username: ")
                    local username = read()
                    if username and username ~= "" then
                        local success, message = addContact(username)
                        if not success then
                            print("Error: " .. message)
                            sleep(2)
                        end
                    end
                elseif key == keys.r then
                    if #client.contacts > 0 then
                        removeContact(client.selectedContact)
                        if client.selectedContact > #client.contacts then
                            client.selectedContact = math.max(1, #client.contacts)
                        end
                    end
                elseif key == keys.s then
                    requestUserList()
                    print("Syncing with server...")
                    sleep(1)
                elseif key == keys.l then
                    -- Logout
                    local packet = {
                        type = "logout",
                        username = client.username
                    }
                    sendToServer(packet)
                    client.isLoggedIn = false
                    client.currentScreen = "login"
                elseif key == keys.q then
                    client.isRunning = false
                end
            
            elseif client.currentScreen == "chat" then
                if key == keys.enter then
                    if #client.inputBuffer > 0 and client.currentChat then
                        sendMessageToContact(client.currentChat, client.inputBuffer)
                        -- Add to local messages immediately
                        if not client.messages[client.currentChat] then
                            client.messages[client.currentChat] = {}
                        end
                        table.insert(client.messages[client.currentChat], {
                            from = client.username,
                            text = client.inputBuffer,
                            time = os.time(),
                            status = "sending"
                        })
                        client.inputBuffer = ""
                        saveData()
                    end
                elseif key == keys.backspace then
                    client.inputBuffer = client.inputBuffer:sub(1, -2)
                elseif key == keys.up then
                    client.messageOffset = math.min(client.messageOffset + 1, 10)
                elseif key == keys.down then
                    client.messageOffset = math.max(client.messageOffset - 1, 0)
                elseif key == keys.escape then
                    client.currentScreen = "contacts"
                    client.currentChat = nil
                    client.messageOffset = 0
                end
            end
        
        elseif event == "char" then
            local char = key
            -- Only allow English characters and basic punctuation
            if char:match("^[%w%s%p]*$") then
                if client.currentScreen == "login" or client.currentScreen == "chat" then
                    client.inputBuffer = client.inputBuffer .. char
                end
            end
        end
    end
end

-- Keep connection alive
local function keepAlive()
    while client.isRunning do
        sleep(30)
        if client.isLoggedIn then
            local packet = {
                type = "ping"
            }
            sendToServer(packet)
        end
    end
end

-- Main client function
local function main()
    print("=== Telegram Client ===")
    print("Initializing...")
    
    -- Initialize modem
    if not initModem() then
        print("ERROR: No modem found!")
        print("Please attach a modem to the computer")
        return
    end
    
    -- Load data
    loadData()
    
    -- Start client processes
    parallel.waitForAny(
        function() processServerResponses() end,
        function() handleInput() end,
        function() keepAlive() end
    )
    
    -- Save data on exit
    saveData()
    print("Client stopped")
end

-- Run client
main()
