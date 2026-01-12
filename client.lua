-- Messenger client for ComputerCraft: Tweaked
-- Run: client [--name <name>] [--modem <side>]

-- Configuration
local PROTOCOL = "messenger_v2"
local CONFIG_FILE = "messenger_client.cfg"
local RECONNECT_INTERVAL = 5 -- seconds
local PING_INTERVAL = 15 -- seconds
local MAX_MESSAGE_HISTORY = 1000

-- Global variables
local clientName = nil
local modemSide = nil
local serverId = nil
local serverName = nil
local connected = false
local connectionError = nil
local lastPing = 0
local messageQueue = {}
local contacts = {}
local selectedContact = nil
local messages = {}
local unreadCount = {}
local uiState = {
    contactScroll = 0,
    messageScroll = 0,
    inputText = "",
    inputCursor = 1,
    showHelp = false
}

-- Colors
local colors = {
    background = colors.black,
    sidebar = colors.gray,
    text = colors.white,
    highlight = colors.blue,
    error = colors.red,
    success = colors.green,
    warning = colors.yellow,
    timestamp = colors.lightGray,
    unread = colors.yellow
}

-- Function to get default username from /.User directory
local function getDefaultUsername()
    local userDir = "/.User"
    if fs.exists(userDir) and fs.isDir(userDir) then
        local files = fs.list(userDir)
        for _, file in ipairs(files) do
            -- Check if folder starts with dot
            if file:sub(1,1) == "." and fs.isDir(userDir .. "/" .. file) then
                -- Return folder name without dot
                return file:sub(2)
            end
        end
    end
    return nil
end

-- Parse command line arguments
local args = {...}
local explicitName = nil
local explicitModem = nil

for i = 1, #args do
    if args[i] == "-n" or args[i] == "--name" then
        explicitName = args[i+1]
    elseif args[i] == "-m" or args[i] == "--modem" then
        explicitModem = args[i+1]
    elseif args[i] == "-h" or args[i] == "--help" then
        print("Usage: client [options]")
        print("Options:")
        print("  -n, --name <name>    Client name")
        print("  -m, --modem <side>   Modem side")
        print("  -h, --help           Show this help")
        return
    end
end

-- Determine client name
if explicitName then
    clientName = explicitName
else
    -- Try to get name from /.User folder
    local defaultName = getDefaultUsername()
    if defaultName then
        clientName = defaultName
    else
        -- Interactive registration
        term.clear()
        term.setCursorPos(1, 1)
        print("=== Messenger Client ===")
        print()
        print("No user profile found.")
        print()
        
        -- Ask for username
        while not clientName or clientName:len() < 1 or clientName:len() > 20 do
            term.write("Enter your username (1-20 chars): ")
            clientName = read()
            
            if clientName and clientName:len() > 0 and clientName:len() <= 20 then
                -- Create user directory
                local userDir = "/.User"
                if not fs.exists(userDir) then
                    fs.makeDir(userDir)
                end
                
                -- Create hidden folder for this user
                local userFolder = userDir .. "/." .. clientName
                if not fs.exists(userFolder) then
                    fs.makeDir(userFolder)
                    print("User profile created!")
                end
                break
            else
                print("Invalid name. Must be 1-20 characters.")
                clientName = nil
            end
        end
    end
end

-- Fallback if no name set
if not clientName or clientName == "" then
    clientName = "Anonymous"
end

-- Set modem side from command line
if explicitModem then
    modemSide = explicitModem
end

-- Utility functions
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

local function findModem()
    if modemSide then
        if peripheral.getType(modemSide) == "modem" then
            return true
        else
            print("Error: Modem not found on side: " .. modemSide)
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

local function findServer()
    local servers = rednet.lookup(PROTOCOL)
    if servers then
        if type(servers) == "table" then
            if #servers > 0 then
                serverId = servers[1]
                print("Found server with ID: " .. serverId)
                return true
            end
        else
            -- In some versions, rednet.lookup returns a single number
            serverId = servers
            print("Found server with ID: " .. serverId)
            return true
        end
    end
    print("No server found with protocol: " .. PROTOCOL)
    return false
end

local function connectToServer()
    if not serverId then
        return false, "Server not found"
    end
    
    -- Send registration request
    print("Attempting to connect to server ID: " .. serverId)
    local success = rednet.send(serverId, {
        type = "register",
        clientName = clientName,
        timestamp = os.time()
    }, PROTOCOL)
    
    if not success then
        return false, "Failed to send registration"
    end
    
    -- Wait for response
    local startTime = os.time()
    while os.time() - startTime < 10 do
        local senderId, message, protocol = rednet.receive(PROTOCOL, 0.5)
        if senderId and senderId == serverId and protocol == PROTOCOL then
            if message.type == "register_ack" then
                serverName = message.serverName or "Unknown Server"
                contacts = message.clients or {}
                connected = true
                connectionError = nil
                lastPing = os.time()
                
                print("Successfully registered as: " .. clientName)
                
                -- Load messages
                rednet.send(serverId, {
                    type = "get_messages",
                    unreadOnly = false
                }, PROTOCOL)
                
                return true, "Connected to: " .. serverName
            elseif message.type == "register_error" then
                return false, "Registration error: " .. (message.message or "Unknown error")
            elseif message.type == "error" then
                return false, "Error: " .. (message.message or "Unknown error")
            end
        end
        
        -- Check timeout
        if os.time() - startTime >= 10 then
            break
        end
    end
    
    return false, "Connection timeout"
end

local function sendPing()
    if not connected or not serverId then 
        return false 
    end
    
    local success = rednet.send(serverId, {
        type = "ping",
        timestamp = os.time()
    }, PROTOCOL)
    
    if success then
        lastPing = os.time()
        return true
    else
        connected = false
        connectionError = "Failed to send ping"
        return false
    end
end

local function sendMessage(text)
    if not connected or not serverId then
        return false, "Not connected to server"
    end
    
    if not selectedContact then
        return false, "No contact selected"
    end
    
    if not text or text == "" then
        return false, "Message cannot be empty"
    end
    
    local success = rednet.send(serverId, {
        type = "send_message",
        recipientId = selectedContact,
        text = text,
        timestamp = os.time()
    }, PROTOCOL)
    
    if not success then
        return false, "Failed to send message"
    end
    
    -- Add locally for instant display
    local message = {
        senderId = serverId, -- Temporary ID
        senderName = clientName,
        text = text,
        timestamp = os.time(),
        isLocal = true
    }
    
    if not messages[selectedContact] then
        messages[selectedContact] = {}
    end
    
    table.insert(messages[selectedContact], message)
    
    if #messages[selectedContact] > MAX_MESSAGE_HISTORY then
        table.remove(messages[selectedContact], 1)
    end
    
    -- Автоматически прокручиваем к новому сообщению
    uiState.messageScroll = math.max(0, (#messages[selectedContact]) - 10)
    
    return true, "Message sent"
end

local function formatTime(timestamp)
    if not timestamp then return "" end
    local time = os.date("*t", timestamp)
    return string.format("%02d:%02d", time.hour, time.min)
end

local function wrapText(text, width)
    if not text then return {} end
    
    local lines = {}
    local line = ""
    
    for word in text:gmatch("%S+") do
        if #line + #word + 1 > width then
            table.insert(lines, line)
            line = word
        else
            if line ~= "" then
                line = line .. " " .. word
            else
                line = word
            end
        end
    end
    
    if line ~= "" then
        table.insert(lines, line)
    end
    
    if #lines == 0 then
        lines = {""}
    end
    
    return lines
end

-- UI functions
local function clearScreen()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
end

local function drawSidebar()
    local width, height = term.getSize()
    local sidebarWidth = math.floor(width * 0.2)
    
    -- Очистка боковой панели
    for y = 1, height do
        term.setCursorPos(1, y)
        term.setBackgroundColor(colors.sidebar)
        term.clearLine()
    end
    
    term.setCursorPos(1, 1)
    term.setTextColor(colors.text)
    term.write("Contacts")
    
    -- Статус подключения
    term.setCursorPos(1, 2)
    if connected then
        term.setTextColor(colors.success)
        term.write("✓ ")
        term.setTextColor(colors.text)
        term.write(serverName or "Server")
    else
        term.setTextColor(colors.error)
        term.write("✗ Disconnected")
    end
    
    -- Имя пользователя
    term.setCursorPos(1, 3)
    term.setTextColor(colors.timestamp)
    term.write("You: " .. clientName)
    
    -- Ошибка подключения (если есть)
    local errorLine = 4
    if connectionError then
        term.setCursorPos(1, errorLine)
        term.setTextColor(colors.error)
        local errText = "Error: " .. connectionError
        if #errText > sidebarWidth - 2 then
            errText = errText:sub(1, sidebarWidth - 5) .. "..."
        end
        term.write(errText)
        errorLine = errorLine + 1
    end
    
    -- Разделитель
    term.setCursorPos(1, errorLine)
    term.setTextColor(colors.timestamp)
    term.write(string.rep("-", sidebarWidth))
    
    -- Список контактов
    local startY = errorLine + 1
    local i = 0
    local contactList = {}
    
    -- Convert contacts to list for ordered display
    for contactId, contact in pairs(contacts) do
        table.insert(contactList, {id = contactId, data = contact})
    end
    
    -- Сортируем контакты по имени
    table.sort(contactList, function(a, b)
        return (a.data.name or "Unknown") < (b.data.name or "Unknown")
    end)
    
    for _, contactEntry in ipairs(contactList) do
        local contactScroll = uiState.contactScroll or 0
        if i >= contactScroll and startY + i - contactScroll <= height then
            local y = startY + i - contactScroll
            local contactId = contactEntry.id
            local contact = contactEntry.data
            
            term.setCursorPos(1, y)
            
            if contactId == selectedContact then
                term.setBackgroundColor(colors.highlight)
                term.clearLine()
                term.setCursorPos(1, y)
            else
                term.setBackgroundColor(colors.sidebar)
            end
            
            -- Индикатор непрочитанных сообщений
            if unreadCount[contactId] and unreadCount[contactId] > 0 then
                term.setTextColor(colors.unread)
                term.write("[" .. unreadCount[contactId] .. "] ")
                term.setTextColor(colors.text)
            else
                term.setTextColor(colors.text)
            end
            
            -- Статус онлайн/офлайн
            if contact.status == "online" then
                term.setTextColor(colors.success)
                term.write("● ")
            else
                term.setTextColor(colors.error)
                term.write("○ ")
            end
            
            term.setTextColor(colors.text)
            
            -- Имя контакта
            local displayName = contact.name or "Unknown"
            if #displayName > sidebarWidth - 4 then
                displayName = displayName:sub(1, sidebarWidth - 7) .. "..."
            end
            
            term.write(displayName)
        end
        i = i + 1
    end
end

local function drawChatArea()
    local width, height = term.getSize()
    local sidebarWidth = math.floor(width * 0.2)
    local chatWidth = width - sidebarWidth
    local chatHeight = height - 4
    
    -- Clear chat area
    for y = 1, chatHeight do
        term.setCursorPos(sidebarWidth + 1, y)
        term.setBackgroundColor(colors.background)
        term.clearLine()
    end
    
    if not connected then
        local message = "Not connected to server"
        term.setCursorPos(sidebarWidth + math.floor(chatWidth/2) - math.floor(#message/2), math.floor(chatHeight/2) - 1)
        term.setTextColor(colors.warning)
        term.write(message)
        
        if connectionError then
            term.setCursorPos(sidebarWidth + math.floor(chatWidth/2) - math.floor(#connectionError/2), math.floor(chatHeight/2) + 1)
            term.setTextColor(colors.error)
            term.write(connectionError)
        else
            local searching = "Searching for server..."
            term.setCursorPos(sidebarWidth + math.floor(chatWidth/2) - math.floor(#searching/2), math.floor(chatHeight/2) + 2)
            term.setTextColor(colors.text)
            term.write(searching)
        end
        return
    end
    
    if not selectedContact then
        local message = "Select contact to chat"
        term.setCursorPos(sidebarWidth + math.floor(chatWidth/2) - math.floor(#message/2), math.floor(chatHeight/2))
        term.setTextColor(colors.text)
        term.write(message)
        return
    end
    
    local contactName = contacts[selectedContact] and contacts[selectedContact].name or "Unknown"
    
    -- Заголовок чата
    term.setCursorPos(sidebarWidth + 1, 1)
    term.setTextColor(colors.text)
    term.write("Chat with: ")
    term.setTextColor(colors.highlight)
    term.write(contactName)
    
    -- Разделитель
    term.setCursorPos(sidebarWidth + 1, 2)
    term.setTextColor(colors.timestamp)
    term.write(string.rep("-", chatWidth))
    
    -- История сообщений
    local chatMessages = messages[selectedContact] or {}
    local messageScroll = uiState.messageScroll or 0
    local maxVisible = chatHeight - 3
    local totalMessages = #chatMessages
    
    if totalMessages == 0 then
        local noMessages = "No messages yet. Start the conversation!"
        term.setCursorPos(sidebarWidth + math.floor(chatWidth/2) - math.floor(#noMessages/2), math.floor(chatHeight/2))
        term.setTextColor(colors.timestamp)
        term.write(noMessages)
        return
    end
    
    local startMessage = math.max(1, totalMessages - maxVisible - messageScroll + 1)
    local y = 3
    
    for i = startMessage, totalMessages do
        if y > chatHeight then break end
        
        local msg = chatMessages[i]
        if not msg then break end
        
        term.setCursorPos(sidebarWidth + 1, y)
        
        -- Определяем отправителя
        if msg.senderId == serverId or msg.senderName == clientName or msg.isLocal then
            term.setTextColor(colors.highlight)
            term.write("You: ")
        else
            term.setTextColor(colors.success)
            term.write((msg.senderName or "Unknown") .. ": ")
        end
        
        term.setTextColor(colors.text)
        
        -- Время
        term.setCursorPos(sidebarWidth + chatWidth - 6, y)
        term.setTextColor(colors.timestamp)
        term.write(formatTime(msg.timestamp))
        
        -- Текст сообщения
        term.setCursorPos(sidebarWidth + 1, y + 1)
        term.setTextColor(colors.text)
        
        local lines = wrapText(msg.text or "", chatWidth - 2)
        for j, line in ipairs(lines) do
            if y + j > chatHeight then break end
            term.setCursorPos(sidebarWidth + 1, y + j)
            term.write(line)
        end
        
        y = y + #lines + 2
    end
    
    -- Показать индикатор прокрутки
    if messageScroll > 0 then
        term.setCursorPos(sidebarWidth + chatWidth - 3, 3)
        term.setTextColor(colors.timestamp)
        term.write("↑")
    end
    
    if totalMessages - messageScroll > maxVisible then
        term.setCursorPos(sidebarWidth + chatWidth - 3, chatHeight)
        term.setTextColor(colors.timestamp)
        term.write("↓")
    end
end

local function drawInputArea()
    local width, height = term.getSize()
    local sidebarWidth = math.floor(width * 0.2)
    local inputHeight = 3
    
    -- Clear input area
    for y = height - inputHeight + 1, height do
        term.setCursorPos(sidebarWidth + 1, y)
        term.setBackgroundColor(colors.background)
        term.clearLine()
    end
    
    -- Separator
    term.setCursorPos(sidebarWidth + 1, height - inputHeight)
    term.setTextColor(colors.timestamp)
    term.write(string.rep("-", width - sidebarWidth))
    
    -- Input field
    local inputY = height - inputHeight + 2
    term.setCursorPos(sidebarWidth + 1, inputY)
    
    if not connected then
        term.setTextColor(colors.warning)
        term.write("Not connected. Reconnecting...")
        return
    end
    
    if not selectedContact then
        term.setTextColor(colors.text)
        term.write("Select a contact first")
        return
    end
    
    term.setTextColor(colors.text)
    term.write("> ")
    
    local maxWidth = width - sidebarWidth - 3
    local displayText = uiState.inputText or ""
    
    if #displayText > maxWidth then
        local cursorPos = uiState.inputCursor or 1
        if cursorPos > maxWidth then
            displayText = "..." .. displayText:sub(cursorPos - maxWidth + 4, cursorPos + 10)
        else
            displayText = displayText:sub(1, maxWidth)
        end
    end
    
    term.write(displayText)
    
    -- Cursor
    local cursorX = sidebarWidth + 3 + math.min(#displayText, maxWidth)
    term.setCursorPos(cursorX, inputY)
    term.setCursorBlink(true)
    
    -- Help
    term.setCursorPos(sidebarWidth + 1, height)
    term.setTextColor(colors.timestamp)
    term.write("Enter: send | F1: help | Ctrl+T: exit")
end

local function drawHelp()
    clearScreen()
    
    term.setCursorPos(1, 1)
    term.setTextColor(colors.highlight)
    term.write("Messenger Help")
    
    term.setCursorPos(1, 3)
    term.setTextColor(colors.text)
    term.write("Controls:")
    term.setCursorPos(1, 5)
    term.write("Up/Down    Scroll contacts")
    term.setCursorPos(1, 6)
    term.write("Enter      Select contact/send")
    term.setCursorPos(1, 7)
    term.write("PgUp/PgDn  Scroll messages")
    term.setCursorPos(1, 8)
    term.write("F1         Show/hide help")
    term.setCursorPos(1, 9)
    term.write("Ctrl+T     Exit")
    
    term.setCursorPos(1, 11)
    term.write("Sending messages:")
    term.setCursorPos(1, 13)
    term.write("Type text and press Enter")
    
    term.setCursorPos(1, 15)
    term.write("User: " .. clientName)
    
    term.setCursorPos(1, 17)
    term.write("Press any key to continue...")
end

local function drawUI()
    if uiState.showHelp then
        drawHelp()
        return
    end
    
    drawSidebar()
    drawChatArea()
    drawInputArea()
end

-- Server message handlers
local function handleServerMessage(message)
    if not message or not message.type then return end
    
    if message.type == "new_message" then
        local msg = message.message
        if not msg or not msg.senderId then return end
        
        messages[msg.senderId] = messages[msg.senderId] or {}
        table.insert(messages[msg.senderId], msg)
        
        if msg.senderId ~= selectedContact then
            unreadCount[msg.senderId] = (unreadCount[msg.senderId] or 0) + 1
            
            -- Sound notification
            if peripheral.isPresent("speaker") then
                local speaker = peripheral.find("speaker")
                if speaker then
                    speaker.playSound("block.note_block.pling", 0.5)
                end
            end
        end
        
        if #messages[msg.senderId] > MAX_MESSAGE_HISTORY then
            table.remove(messages[msg.senderId], 1)
        end
        
    elseif message.type == "client_online" then
        if message.clientId then
            contacts[message.clientId] = {
                name = message.clientName or "Unknown",
                status = "online"
            }
        end
        
    elseif message.type == "client_offline" then
        if message.clientId and contacts[message.clientId] then
            contacts[message.clientId].status = "offline"
        end
        
    elseif message.type == "messages" then
        -- Process incoming messages
        if message.messages and type(message.messages) == "table" then
            for _, msg in ipairs(message.messages) do
                if msg and msg.senderId then
                    local senderId = msg.senderId
                    messages[senderId] = messages[senderId] or {}
                    table.insert(messages[senderId], msg)
                    
                    if senderId ~= selectedContact then
                        unreadCount[senderId] = (unreadCount[senderId] or 0) + 1
                    end
                end
            end
        end
        
    elseif message.type == "online_list" then
        contacts = message.clients or {}
        
    elseif message.type == "pong" then
        -- Keep alive
        
    elseif message.type == "error" then
        print("Server error: " .. (message.message or "Unknown error"))
        if message.message and (message.message:find("not registered") or message.message:find("Client not registered")) then
            connected = false
            connectionError = "Not registered. Reconnecting..."
            print("Reconnecting...")
        end
    end
end

-- Main function
local function main()
    -- Check modem
    if not findModem() then
        print("Error: Wireless modem not found!")
        print("Place modem on any side of computer")
        print("Press any key to exit...")
        os.pullEvent("key")
        return
    end
    
    -- Open modem
    rednet.open(modemSide)
    
    print("Messenger client starting...")
    print("Client name: " .. clientName)
    print("Modem side: " .. modemSide)
    print("Press F1 for help, Ctrl+T to exit")
    sleep(2) -- Give user time to read
    
    -- Main event loop
    local lastPingTime = os.time()
    local lastReconnectAttempt = os.time() - RECONNECT_INTERVAL
    local lastUIRefresh = os.time()
    
    clearScreen()
    drawUI()
    
    while true do
        local eventTime = os.time()
        
        -- Handle reconnection if not connected
        if not connected then
            if eventTime - lastReconnectAttempt >= RECONNECT_INTERVAL then
                if findServer() then
                    local success, msg = connectToServer()
                    if success then
                        print("Connected: " .. msg)
                        connectionError = nil
                    else
                        connectionError = msg
                        print("Connection failed: " .. msg)
                    end
                else
                    connectionError = "Server not found"
                    print("Server not found. Retrying...")
                end
                lastReconnectAttempt = eventTime
                drawUI()
            end
        end
        
        -- Send ping if connected
        if connected and eventTime - lastPingTime >= PING_INTERVAL then
            sendPing()
            lastPingTime = eventTime
        end
        
        -- Handle rednet messages with timeout
        local senderId, message, protocol
        local startTime = os.clock()
        while os.clock() - startTime < 0.1 do
            senderId, message, protocol = rednet.receive(PROTOCOL, 0.05)
            if senderId and protocol == PROTOCOL then
                if senderId == serverId then
                    handleServerMessage(message)
                end
                break
            end
        end
        
        -- Auto-refresh UI every 0.5 seconds
        if eventTime - lastUIRefresh >= 0.5 then
            drawUI()
            lastUIRefresh = eventTime
        end
        
        -- Handle events with very short timeout
        local event, p1, p2, p3 = os.pullEventRaw(0.05)
        
        if event == "rednet_message" then
            local sId, msg, proto = p1, p2, p3
            if proto == PROTOCOL and sId == serverId then
                handleServerMessage(msg)
                drawUI()
            end
            
        elseif event == "key" then
            local key = p1
            
            if key == 20 then -- Ctrl+T
                term.setCursorBlink(false)
                break
                
            elseif key == 63 then -- F1
                uiState.showHelp = not uiState.showHelp
                drawUI()
                
            elseif key == 28 then -- Enter
                if uiState.showHelp then
                    uiState.showHelp = false
                    drawUI()
                else
                    -- Если нет выбранного контакта, выбираем первый
                    if not selectedContact then
                        for contactId, _ in pairs(contacts) do
                            selectedContact = contactId
                            unreadCount[contactId] = 0
                            uiState.messageScroll = 0
                            break
                        end
                        drawUI()
                    elseif (uiState.inputText or "") ~= "" and selectedContact and connected then
                        local success, msg = sendMessage(uiState.inputText)
                        if not success then
                            print("Failed to send: " .. msg)
                        end
                        uiState.inputText = ""
                        uiState.inputCursor = 1
                        drawUI()
                    end
                end
                
            elseif key == 14 then -- Backspace
                if #(uiState.inputText or "") > 0 then
                    uiState.inputText = uiState.inputText:sub(1, -2)
                    uiState.inputCursor = math.max(1, (uiState.inputCursor or 1) - 1)
                    drawUI()
                end
                
            elseif key == 200 then -- Up arrow
                uiState.contactScroll = math.max(0, (uiState.contactScroll or 0) - 1)
                drawUI()
                
            elseif key == 208 then -- Down arrow
                uiState.contactScroll = (uiState.contactScroll or 0) + 1
                drawUI()
                
            elseif key == 201 then -- Page Up
                if selectedContact then
                    uiState.messageScroll = math.min(#(messages[selectedContact] or {}), 
                        (uiState.messageScroll or 0) + 5)
                    drawUI()
                end
                
            elseif key == 209 then -- Page Down
                uiState.messageScroll = math.max(0, (uiState.messageScroll or 0) - 5)
                drawUI()
                
            elseif key == 203 then -- Left arrow
                uiState.inputCursor = math.max(1, (uiState.inputCursor or 1) - 1)
                drawUI()
                
            elseif key == 205 then -- Right arrow
                uiState.inputCursor = math.min(#(uiState.inputText or "") + 1, (uiState.inputCursor or 1) + 1)
                drawUI()
            end
            
        elseif event == "char" then
            if not uiState.showHelp and connected then
                uiState.inputText = (uiState.inputText or "") .. p1
                uiState.inputCursor = (uiState.inputCursor or 1) + 1
                drawUI()
            end
            
        elseif event == "mouse_click" then
            local button, x, y = p1, p2, p3
            local sidebarWidth = math.floor(term.getSize() * 0.2)
            
            if x <= sidebarWidth then
                -- Click in sidebar
                local contactIndex = y - 7 + (uiState.contactScroll or 0)
                local i = 1
                for contactId, _ in pairs(contacts) do
                    if i == contactIndex then
                        selectedContact = contactId
                        unreadCount[contactId] = 0
                        uiState.messageScroll = 0
                        drawUI()
                        break
                    end
                    i = i + 1
                end
            end
            
        elseif event == "term_resize" then
            drawUI()
            
        elseif event == "mouse_scroll" then
            local direction, x, y = p1, p2, p3
            local sidebarWidth = math.floor(term.getSize() * 0.2)
            
            if x <= sidebarWidth then
                uiState.contactScroll = math.max(0, (uiState.contactScroll or 0) + direction)
            else
                uiState.messageScroll = math.max(0, (uiState.messageScroll or 0) + direction)
            end
            drawUI()
        end
    end
    
    -- Clean shutdown
    term.setCursorBlink(false)
    print("Disconnecting...")
    rednet.close(modemSide)
    print("Client stopped")
end

-- Start with error handling
local success, err = pcall(main)
if not success then
    term.setCursorBlink(false)
    print("Client crashed with error: " .. err)
    print("Press any key to exit...")
    os.pullEvent("key")
end
