-- Messenger client for ComputerCraft: Tweaked
-- Run: client [--name <name>] [--modem <side>]

-- Configuration
local PROTOCOL = "messenger_v2"
local CONFIG_FILE = "messenger_client.cfg"
local RECONNECT_INTERVAL = 5 -- seconds
local PING_INTERVAL = 15 -- seconds
local MAX_MESSAGE_HISTORY = 1000

-- Global variables
local clientName = "Anonymous"
local modemSide = nil
local serverId = nil
local serverName = nil
local connected = false
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
    timestamp = colors.lightGray,
    unread = colors.yellow
}

-- Parse command line arguments
local args = {...}
for i = 1, #args do
    if args[i] == "-n" or args[i] == "--name" then
        clientName = args[i+1] or clientName
    elseif args[i] == "-m" or args[i] == "--modem" then
        modemSide = args[i+1]
    elseif args[i] == "-h" or args[i] == "--help" then
        print("Usage: client [options]")
        print("Options:")
        print("  -n, --name <name>    Client name")
        print("  -m, --modem <side>   Modem side")
        print("  -h, --help           Show this help")
        return
    end
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

local function findServer()
    local servers = rednet.lookup(PROTOCOL)
    if servers and #servers > 0 then
        serverId = servers[1]
        return true
    end
    return false
end

local function connectToServer()
    if not serverId then
        return false, "Server not found"
    end
    
    local response = rednet.send(serverId, {
        type = "register",
        clientName = clientName,
        timestamp = os.time()
    }, PROTOCOL)
    
    if not response then
        return false, "Send error"
    end
    
    -- Wait for response
    local startTime = os.time()
    while os.time() - startTime < 5 do
        local senderId, message, protocol = rednet.receive(PROTOCOL, 1)
        if senderId == serverId and message.type == "register_ack" then
            serverName = message.serverName
            contacts = message.clients or {}
            connected = true
            lastPing = os.time()
            
            -- Load messages
            rednet.send(serverId, {
                type = "get_messages",
                unreadOnly = false
            }, PROTOCOL)
            
            return true, "Connected to: " .. serverName
        end
    end
    
    return false, "Connection timeout"
end

local function sendPing()
    if not connected then return end
    
    rednet.send(serverId, {
        type = "ping",
        timestamp = os.time()
    }, PROTOCOL)
    
    lastPing = os.time()
end

local function sendMessage(text)
    if not connected or not selectedContact then
        return false, "Not connected or no contact selected"
    end
    
    if text == "" then
        return false, "Message cannot be empty"
    end
    
    rednet.send(serverId, {
        type = "send_message",
        recipientId = selectedContact,
        text = text,
        timestamp = os.time()
    }, PROTOCOL)
    
    -- Add locally for instant display
    local message = {
        senderId = serverId, -- Temporary ID
        senderName = clientName,
        text = text,
        timestamp = os.time(),
        local = true
    }
    
    messages[selectedContact] = messages[selectedContact] or {}
    table.insert(messages[selectedContact], message)
    
    if #messages[selectedContact] > MAX_MESSAGE_HISTORY then
        table.remove(messages[selectedContact], 1)
    end
    
    uiState.messageScroll = math.max(0, #messages[selectedContact] - 10)
    
    return true
end

local function formatTime(timestamp)
    if not timestamp then return "" end
    local time = os.date("*t", timestamp)
    return string.format("%02d:%02d", time.hour, time.min)
end

local function wrapText(text, width)
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
    
    return lines
end

-- UI functions
local function drawSidebar()
    local width = math.floor(term.getSize() * 0.2)
    local height = term.getSize()
    
    term.setBackgroundColor(colors.sidebar)
    term.clear()
    
    term.setCursorPos(1, 1)
    term.setTextColor(colors.text)
    term.write("Contacts")
    
    if connected then
        term.setCursorPos(1, 2)
        term.setTextColor(colors.success)
        term.write("✓ ")
        term.setTextColor(colors.text)
        term.write(serverName)
    else
        term.setCursorPos(1, 2)
        term.setTextColor(colors.error)
        term.write("✗ Disconnected")
    end
    
    term.setCursorPos(1, 4)
    term.write("---")
    
    -- Contacts list
    local startY = 5
    local i = 1
    
    for contactId, contact in pairs(contacts) do
        if i > uiState.contactScroll and startY + i - uiState.contactScroll <= height then
            local y = startY + i - uiState.contactScroll
            
            term.setCursorPos(1, y)
            
            if contactId == selectedContact then
                term.setBackgroundColor(colors.highlight)
                term.clearLine()
                term.setCursorPos(1, y)
            else
                term.setBackgroundColor(colors.sidebar)
            end
            
            term.setTextColor(colors.text)
            
            -- New message indicator
            if unreadCount[contactId] and unreadCount[contactId] > 0 then
                term.setTextColor(colors.unread)
                term.write("[" .. unreadCount[contactId] .. "] ")
                term.setTextColor(colors.text)
            end
            
            -- Status
            if contact.status == "online" then
                term.setTextColor(colors.success)
                term.write("● ")
            else
                term.setTextColor(colors.error)
                term.write("○ ")
            end
            
            term.setTextColor(colors.text)
            
            -- Name
            local displayName = contact.name
            if #displayName > width - 3 then
                displayName = displayName:sub(1, width - 6) .. "..."
            end
            
            term.write(displayName)
        end
        i = i + 1
    end
    
    term.setBackgroundColor(colors.background)
end

local function drawChatArea()
    local sidebarWidth = math.floor(term.getSize() * 0.2)
    local width = term.getSize() - sidebarWidth
    local height = term.getSize() - 4 -- minus input area
    
    term.setBackgroundColor(colors.background)
    
    for y = 1, height do
        term.setCursorPos(sidebarWidth + 1, y)
        term.clearLine()
    end
    
    if not selectedContact then
        term.setCursorPos(sidebarWidth + width/2 - 10, height/2)
        term.setTextColor(colors.text)
        term.write("Select contact to chat")
        return
    end
    
    local contactName = contacts[selectedContact] and contacts[selectedContact].name or "Unknown"
    term.setCursorPos(sidebarWidth + 1, 1)
    term.setTextColor(colors.text)
    term.write("Chat with: ")
    term.setTextColor(colors.highlight)
    term.write(contactName)
    
    -- Message history
    local chatMessages = messages[selectedContact] or {}
    local startMessage = math.max(1, #chatMessages - height + 3 - uiState.messageScroll)
    local y = 3
    
    for i = startMessage, #chatMessages do
        if y > height then break end
        
        local msg = chatMessages[i]
        term.setCursorPos(sidebarWidth + 1, y)
        
        if msg.senderId == serverId or msg.senderName == clientName then
            term.setTextColor(colors.highlight)
            term.write("You: ")
        else
            term.setTextColor(colors.success)
            term.write(msg.senderName .. ": ")
        end
        
        term.setTextColor(colors.text)
        
        -- Time
        term.setCursorPos(sidebarWidth + width - 6, y)
        term.setTextColor(colors.timestamp)
        term.write(formatTime(msg.timestamp))
        
        -- Message text
        term.setCursorPos(sidebarWidth + 1, y + 1)
        term.setTextColor(colors.text)
        
        local lines = wrapText(msg.text, width - 2)
        for j, line in ipairs(lines) do
            if y + j > height then break end
            term.setCursorPos(sidebarWidth + 1, y + j)
            term.write(line)
        end
        
        y = y + #lines + 2
    end
end

local function drawInputArea()
    local sidebarWidth = math.floor(term.getSize() * 0.2)
    local height = term.getSize()
    local inputHeight = 3
    
    term.setBackgroundColor(colors.background)
    
    for y = height - inputHeight + 1, height do
        term.setCursorPos(sidebarWidth + 1, y)
        term.clearLine()
    end
    
    -- Separator
    term.setCursorPos(sidebarWidth + 1, height - inputHeight)
    term.setTextColor(colors.timestamp)
    term.write(string.rep("-", term.getSize() - sidebarWidth))
    
    -- Input field
    local inputY = height - inputHeight + 2
    term.setCursorPos(sidebarWidth + 1, inputY)
    term.setTextColor(colors.text)
    term.write("> ")
    
    local maxWidth = term.getSize() - sidebarWidth - 3
    local displayText = uiState.inputText
    
    if #displayText > maxWidth then
        local cursorPos = uiState.inputCursor
        if cursorPos > maxWidth then
            displayText = "..." .. displayText:sub(cursorPos - maxWidth + 4, cursorPos + 10)
        else
            displayText = displayText:sub(1, maxWidth)
        end
    end
    
    term.write(displayText)
    
    -- Cursor
    local cursorX = sidebarWidth + 3 + math.min(#uiState.inputText, maxWidth)
    term.setCursorPos(cursorX, inputY)
    
    -- Help
    term.setCursorPos(sidebarWidth + 1, height)
    term.setTextColor(colors.timestamp)
    term.write("Enter: send | F1: help | Ctrl+T: exit")
end

local function drawHelp()
    term.setBackgroundColor(colors.background)
    term.clear()
    
    term.setCursorPos(1, 1)
    term.setTextColor(colors.highlight)
    term.write("Messenger Help")
    
    term.setCursorPos(1, 3)
    term.setTextColor(colors.text)
    term.write("Controls:")
    term.setCursorPos(1, 5)
    term.write("Up/Down    Scroll contacts")
    term.setCursorPos(1, 6)
    term.write("Enter      Select contact")
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
    if message.type == "new_message" then
        local msg = message.message
        messages[msg.senderId] = messages[msg.senderId] or {}
        table.insert(messages[msg.senderId], msg)
        
        if msg.senderId ~= selectedContact then
            unreadCount[msg.senderId] = (unreadCount[msg.senderId] or 0) + 1
            
            -- Sound notification
            if peripheral.getType("speaker") then
                local speaker = peripheral.wrap("speaker")
                speaker.playSound("block.note_block.pling", 0.5)
            end
        end
        
        if #messages[msg.senderId] > MAX_MESSAGE_HISTORY then
            table.remove(messages[msg.senderId], 1)
        end
        
    elseif message.type == "client_online" then
        contacts[message.clientId] = {
            name = message.clientName,
            status = "online"
        }
        
    elseif message.type == "client_offline" then
        if contacts[message.clientId] then
            contacts[message.clientId].status = "offline"
        end
        
    elseif message.type == "messages" then
        -- Process incoming messages
        for _, msg in ipairs(message.messages) do
            local senderId = msg.senderId
            messages[senderId] = messages[senderId] or {}
            table.insert(messages[senderId], msg)
            
            if senderId ~= selectedContact then
                unreadCount[senderId] = (unreadCount[senderId] or 0) + 1
            end
        end
        
    elseif message.type == "online_list" then
        contacts = message.clients or {}
        
    elseif message.type == "pong" then
        -- Keep alive
        
    elseif message.type == "error" then
        print("Server error: " .. message.message)
    end
end

-- Main function
local function main()
    -- Check modem
    if not findModem() then
        print("Error: Wireless modem not found!")
        print("Place modem on any side of computer")
        return
    end
    
    -- Open modem
    rednet.open(modemSide)
    
    print("Messenger client starting...")
    print("Client name: " .. clientName)
    
    -- Find and connect to server
    local connectedMessage = ""
    while not connected do
        if findServer() then
            local success, msg = connectToServer()
            connectedMessage = msg
            if success then
                print(msg)
                break
            else
                print("Connection failed: " .. msg)
            end
        else
            print("Searching for server...")
        end
        sleep(RECONNECT_INTERVAL)
    end
    
    -- Main event loop
    local lastPingTime = os.time()
    
    while true do
        -- Handle rednet messages
        local senderId, message, protocol = rednet.receive(PROTOCOL, 0.1)
        if senderId and protocol == PROTOCOL then
            handleServerMessage(message)
        end
        
        -- Send ping
        if connected and os.time() - lastPingTime > PING_INTERVAL then
            sendPing()
            lastPingTime = os.time()
        end
        
        -- Handle events
        local event, p1, p2, p3 = os.pullEventRaw()
        
        if event == "rednet_message" then
            local sId, msg, proto = p1, p2, p3
            if proto == PROTOCOL then
                handleServerMessage(msg)
            end
            
        elseif event == "key" then
            local key = p1
            local held = p2
            
            if key == 20 then -- Ctrl+T
                break
                
            elseif key == 63 then -- F1
                uiState.showHelp = not uiState.showHelp
                
            elseif key == 28 then -- Enter
                if uiState.showHelp then
                    uiState.showHelp = false
                elseif uiState.inputText ~= "" then
                    sendMessage(uiState.inputText)
                    uiState.inputText = ""
                    uiState.inputCursor = 1
                end
                
            elseif key == 14 then -- Backspace
                if #uiState.inputText > 0 then
                    uiState.inputText = uiState.inputText:sub(1, -2)
                    uiState.inputCursor = math.max(1, uiState.inputCursor - 1)
                end
                
            elseif key == 200 then -- Up arrow
                uiState.contactScroll = math.max(0, uiState.contactScroll - 1)
                
            elseif key == 208 then -- Down arrow
                uiState.contactScroll = uiState.contactScroll + 1
                
            elseif key == 201 then -- Page Up
                uiState.messageScroll = math.min(#(messages[selectedContact] or {}), 
                    uiState.messageScroll + 5)
                
            elseif key == 209 then -- Page Down
                uiState.messageScroll = math.max(0, uiState.messageScroll - 5)
            end
            
        elseif event == "char" then
            if not uiState.showHelp then
                uiState.inputText = uiState.inputText .. p1
                uiState.inputCursor = uiState.inputCursor + 1
            end
            
        elseif event == "mouse_click" then
            local button, x, y = p1, p2, p3
            local sidebarWidth = math.floor(term.getSize() * 0.2)
            
            if x <= sidebarWidth then
                -- Click in sidebar
                local contactIndex = y - 4 + uiState.contactScroll
                local i = 1
                for contactId, _ in pairs(contacts) do
                    if i == contactIndex then
                        selectedContact = contactId
                        unreadCount[contactId] = 0
                        uiState.messageScroll = 0
                        break
                    end
                    i = i + 1
                end
            end
            
        elseif event == "term_resize" then
            -- Redraw on resize
            
        elseif event == "mouse_scroll" then
            local direction, x, y = p1, p2, p3
            local sidebarWidth = math.floor(term.getSize() * 0.2)
            
            if x <= sidebarWidth then
                uiState.contactScroll = uiState.contactScroll + direction
                if uiState.contactScroll < 0 then uiState.contactScroll = 0 end
            else
                uiState.messageScroll = uiState.messageScroll + direction
                if uiState.messageScroll < 0 then uiState.messageScroll = 0 end
            end
        end
        
        -- Redraw UI
        drawUI()
    end
    
    -- Clean shutdown
    print("Disconnecting...")
    rednet.close(modemSide)
    print("Client stopped")
end

-- Start
main()
