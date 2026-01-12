-- Messenger Client with GUI
local VERSION = "1.0"
local SERVER_ID = nil
local PING_INTERVAL = 10

-- Check arguments
if not arg[1] then
    print("Usage: client <server_id>")
    print("Example: client 42")
    print("\nTo find server ID, run 'server' on server computer")
    return
end

SERVER_ID = tonumber(arg[1])
if not SERVER_ID then
    print("Error: Invalid server ID")
    print("Server ID must be a number")
    return
end

print("=== Messenger Client v" .. VERSION .. " ===")
print("Connecting to server " .. SERVER_ID .. "...")

-- Function to find wireless modem
function findWirelessModem()
    print("Searching for wireless modem...")
    
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
local MODEM_SIDE = findWirelessModem()
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

-- Application state
local state = {
    username = os.getComputerLabel() or "User" .. os.getComputerID(),
    messages = {},
    contacts = {},
    currentContact = nil,
    connected = false,
    lastPing = 0,
    serverId = SERVER_ID
}

-- GUI constants
local WIDTH, HEIGHT = term.getSize()
local INPUT_HEIGHT = 3
local CONTACTS_WIDTH = 20
local MESSAGES_X = CONTACTS_WIDTH + 2

-- GUI elements
local gui = {
    contactsList = {},
    messageList = {},
    inputText = "",
    selectedContact = 1,
    scrollOffset = 0,
    inputScroll = 0,
    showHelp = false
}

-- Network functions
function sendRequest(request)
    rednet.send(SERVER_ID, request, "messenger_server")
    
    local senderId, response, protocol = rednet.receive("messenger_server", 5)
    
    if senderId == SERVER_ID and protocol == "messenger_server" then
        return response
    end
    
    return nil
end

function connectToServer()
    print("Connecting to server...")
    local response = sendRequest({
        type = "register",
        name = state.username
    })
    
    if response and response.success then
        state.connected = true
        print("Connected to server!")
        return true
    else
        print("Failed to connect to server")
        return false
    end
end

function sendMessage(targetId, message)
    local response = sendRequest({
        type = "send_message",
        target = targetId,
        message = message,
        senderName = state.username
    })
    
    if response and response.success then
        return true
    else
        print("Failed to send message: " .. (response and response.error or "timeout"))
        return false
    end
end

function updateContacts()
    local response = sendRequest({
        type = "get_online"
    })
    
    if response and response.clients then
        state.contacts = response.clients
        
        -- Keep current contact selected if possible
        if state.currentContact then
            local found = false
            for _, contact in ipairs(state.contacts) do
                if contact.id == state.currentContact then
                    found = true
                    break
                end
            end
            if not found then
                state.currentContact = nil
            end
        end
        
        return true
    end
    
    return false
end

function getNewMessages()
    local response = sendRequest({
        type = "get_messages"
    })
    
    if response and response.messages then
        local newCount = 0
        for _, msg in ipairs(response.messages) do
            table.insert(state.messages, msg)
            newCount = newCount + 1
        end
        
        if newCount > 0 then
            -- Play sound if speaker available
            local speaker = peripheral.find("speaker")
            if speaker then
                speaker.playSound("block.note_block.pling", 0.5)
            end
        end
        
        return true
    end
    
    return false
end

function sendPing()
    sendRequest({
        type = "ping"
    })
    state.lastPing = os.clock()
end

-- GUI functions
function drawBorder()
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    
    -- Top bar
    term.setCursorPos(1, 1)
    term.write(string.rep(" ", WIDTH))
    term.setCursorPos(2, 1)
    
    local status = state.connected and "ONLINE" or "OFFLINE"
    local statusColor = state.connected and colors.green or colors.red
    
    term.write("Messenger - " .. state.username .. " (S:" .. SERVER_ID .. ")")
    
    term.setCursorPos(WIDTH - 15, 1)
    term.write("[" .. status .. "]")
    
    -- Separator
    for y = 2, HEIGHT - INPUT_HEIGHT do
        term.setCursorPos(CONTACTS_WIDTH + 1, y)
        term.write("│")
    end
    
    -- Input panel separator
    term.setCursorPos(1, HEIGHT - INPUT_HEIGHT + 1)
    term.write(string.rep("─", WIDTH))
    
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

function drawContacts()
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    
    for i = 1, HEIGHT - INPUT_HEIGHT - 1 do
        term.setCursorPos(1, i + 1)
        term.write(string.rep(" ", CONTACTS_WIDTH))
    end
    
    term.setCursorPos(2, 2)
    term.write("Contacts [" .. #state.contacts .. "]:")
    
    local startIdx = gui.scrollOffset
    local maxVisible = HEIGHT - INPUT_HEIGHT - 2
    
    for i = 1, math.min(#state.contacts, maxVisible) do
        local idx = i + startIdx
        if idx <= #state.contacts then
            local contact = state.contacts[idx]
            local y = i + 2
            
            -- Highlight selected contact
            if contact.id == state.currentContact then
                term.setBackgroundColor(colors.lightBlue)
                term.setTextColor(colors.black)
            else
                term.setBackgroundColor(colors.gray)
                term.setTextColor(colors.white)
            end
            
            term.setCursorPos(2, y)
            
            -- Truncate long names
            local displayName = contact.name
            if #displayName > CONTACTS_WIDTH - 3 then
                displayName = string.sub(displayName, 1, CONTACTS_WIDTH - 3) .. "..."
            end
            
            -- Add ID for short names
            if #displayName < CONTACTS_WIDTH - 10 then
                displayName = displayName .. " (" .. contact.id .. ")"
            end
            
            term.write(displayName)
        end
    end
    
    -- Scrollbar
    if #state.contacts > maxVisible then
        local barHeight = math.floor(maxVisible * maxVisible / #state.contacts)
        local barPos = math.floor(gui.scrollOffset * maxVisible / #state.contacts)
        
        for i = 1, barHeight do
            term.setCursorPos(CONTACTS_WIDTH, 2 + barPos + i)
            term.write("▐")
        end
    end
    
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

function drawMessages()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    
    -- Clear messages area
    for y = 2, HEIGHT - INPUT_HEIGHT do
        term.setCursorPos(MESSAGES_X, y)
        term.write(string.rep(" ", WIDTH - MESSAGES_X))
    end
    
    if not state.currentContact then
        term.setCursorPos(MESSAGES_X + 5, math.floor(HEIGHT / 2))
        term.write("Select a contact from the left panel")
        return
    end
    
    -- Get contact name
    local contactName = "Unknown"
    for _, c in ipairs(state.contacts) do
        if c.id == state.currentContact then
            contactName = c.name
            break
        end
    end
    
    -- Filter messages for current contact
    local contactMessages = {}
    for _, msg in ipairs(state.messages) do
        if msg.sender == state.currentContact or 
           (msg.target == state.currentContact and msg.sender == os.getComputerID()) then
            table.insert(contactMessages, msg)
        end
    end
    
    if #contactMessages == 0 then
        term.setCursorPos(MESSAGES_X + 5, math.floor(HEIGHT / 2))
        term.write("No messages with " .. contactName)
        return
    end
    
    -- Display messages (newest at bottom)
    local displayY = HEIGHT - INPUT_HEIGHT - 1
    local msgIndex = #contactMessages
    
    while msgIndex > 0 and displayY >= 2 do
        local msg = contactMessages[msgIndex]
        local isOwn = msg.sender == os.getComputerID()
        
        -- Time
        local timeStr = os.date("%H:%M", msg.time / 1000)
        term.setCursorPos(WIDTH - 7, displayY)
        term.write(timeStr)
        
        -- Sender
        term.setCursorPos(MESSAGES_X, displayY)
        if isOwn then
            term.setTextColor(colors.green)
            term.write("You:")
        else
            term.setTextColor(colors.yellow)
            term.write(contactName .. ":")
        end
        
        -- Message text (with wrapping)
        term.setTextColor(colors.white)
        local message = msg.message
        local maxWidth = WIDTH - MESSAGES_X - 2
        
        displayY = displayY - 1
        
        -- Split message into lines
        local lines = {}
        while #message > 0 do
            if #message <= maxWidth then
                table.insert(lines, message)
                break
            else
                -- Try to break at space
                local breakPos = maxWidth
                while breakPos > 0 and message:sub(breakPos, breakPos) ~= " " do
                    breakPos = breakPos - 1
                end
                if breakPos == 0 then breakPos = maxWidth end
                
                table.insert(lines, message:sub(1, breakPos))
                message = message:sub(breakPos + 1)
            end
        end
        
        -- Display lines from bottom up
        for i = #lines, 1, -1 do
            if displayY < 2 then break end
            term.setCursorPos(MESSAGES_X, displayY)
            term.write(lines[i])
            displayY = displayY - 1
        end
        
        displayY = displayY - 1  -- Space between messages
        msgIndex = msgIndex - 1
    end
    
    term.setTextColor(colors.white)
end

function drawInput()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    
    -- Clear input area
    for y = HEIGHT - INPUT_HEIGHT + 2, HEIGHT do
        term.setCursorPos(1, y)
        term.write(string.rep(" ", WIDTH))
    end
    
    if not state.currentContact then
        term.setCursorPos(1, HEIGHT - 1)
        term.write("F1:Help | Arrow Keys:Navigate | Enter:Select/Send")
        return
    end
    
    -- Get contact name
    local contactName = "Unknown"
    for _, c in ipairs(state.contacts) do
        if c.id == state.currentContact then
            contactName = c.name
            break
        end
    end
    
    term.setCursorPos(1, HEIGHT - INPUT_HEIGHT + 2)
    term.write("To: " .. contactName .. " (ID:" .. state.currentContact .. ")")
    
    -- Input field
    term.setCursorPos(1, HEIGHT - 1)
    term.write("> ")
    
    -- Display text with scrolling
    local displayText = gui.inputText
    if #displayText > WIDTH - 3 then
        if gui.inputScroll > 0 then
            displayText = string.sub(displayText, gui.inputScroll + 1)
        end
        displayText = string.sub(displayText, 1, WIDTH - 3)
    end
    
    term.write(displayText)
    
    -- Show cursor
    local cursorPos = #gui.inputText - gui.inputScroll + 3
    if cursorPos <= WIDTH then
        term.setCursorPos(cursorPos, HEIGHT - 1)
        term.setCursorBlink(true)
    end
end

function drawHelp()
    term.setBackgroundColor(colors.black)
    term.clear()
    
    term.setCursorPos(1, 1)
    term.setTextColor(colors.cyan)
    term.write("=== Messenger Help ===\n\n")
    
    term.setTextColor(colors.yellow)
    term.write("Navigation:\n")
    term.setTextColor(colors.white)
    term.write("  Up/Down - Select contact\n")
    term.write("  Enter   - Select contact/Send message\n")
    term.write("  F1      - Show this help\n")
    term.write("  Ctrl+T  - Exit program\n\n")
    
    term.setTextColor(colors.yellow)
    term.write("Messaging:\n")
    term.setTextColor(colors.white)
    term.write("  Type text in bottom line\n")
    term.write("  Enter to send message\n")
    term.write("  Backspace to delete text\n\n")
    
    term.setTextColor(colors.yellow)
    term.write("Status:\n")
    term.setTextColor(colors.white)
    term.write("  ONLINE  - Connected to server\n")
    term.write("  OFFLINE - Not connected\n")
    term.write("  Green   - Your messages\n")
    term.write("  Yellow  - Received messages\n\n")
    
    term.setTextColor(colors.cyan)
    term.write("Press any key to continue...")
    
    os.pullEvent("key")
end

function drawUI()
    term.setBackgroundColor(colors.black)
    term.clear()
    
    drawBorder()
    drawContacts()
    drawMessages()
    drawInput()
end

function handleInput()
    while true do
        local event, key, x, y = os.pullEvent()
        
        if event == "key" then
            if key == keys.f1 then
                drawHelp()
                drawUI()
            elseif key == keys.up then
                if #state.contacts > 0 then
                    gui.selectedContact = math.max(1, gui.selectedContact - 1)
                    if gui.selectedContact <= gui.scrollOffset then
                        gui.scrollOffset = math.max(0, gui.scrollOffset - 1)
                    end
                    state.currentContact = state.contacts[gui.selectedContact].id
                    drawUI()
                end
            elseif key == keys.down then
                if #state.contacts > 0 then
                    gui.selectedContact = math.min(#state.contacts, gui.selectedContact + 1)
                    local maxVisible = HEIGHT - INPUT_HEIGHT - 2
                    if gui.selectedContact > gui.scrollOffset + maxVisible then
                        gui.scrollOffset = math.min(#state.contacts - maxVisible, gui.scrollOffset + 1)
                    end
                    state.currentContact = state.contacts[gui.selectedContact].id
                    drawUI()
                end
            elseif key == keys.enter then
                if state.currentContact then
                    -- Send message
                    if gui.inputText ~= "" then
                        if sendMessage(state.currentContact, gui.inputText) then
                            table.insert(state.messages, {
                                sender = os.getComputerID(),
                                senderName = state.username,
                                target = state.currentContact,
                                message = gui.inputText,
                                time = os.epoch("utc")
                            })
                            gui.inputText = ""
                            gui.inputScroll = 0
                            drawUI()
                        end
                    end
                else
                    -- Select first contact
                    if #state.contacts > 0 then
                        state.currentContact = state.contacts[1].id
                        gui.selectedContact = 1
                        drawUI()
                    end
                end
            elseif key == keys.backspace then
                if #gui.inputText > 0 then
                    gui.inputText = string.sub(gui.inputText, 1, -2)
                    if gui.inputScroll > 0 then
                        gui.inputScroll = math.max(0, gui.inputScroll - 1)
                    end
                    drawUI()
                end
            end
        elseif event == "char" then
            gui.inputText = gui.inputText .. key
            if #gui.inputText > WIDTH - 3 then
                gui.inputScroll = #gui.inputText - (WIDTH - 3)
            end
            drawUI()
        elseif event == "mouse_click" then
            if x <= CONTACTS_WIDTH and y >= 2 and y <= HEIGHT - INPUT_HEIGHT then
                local contactIndex = y - 2 + gui.scrollOffset
                if contactIndex <= #state.contacts then
                    gui.selectedContact = contactIndex
                    state.currentContact = state.contacts[contactIndex].id
                    drawUI()
                end
            end
        elseif event == "mouse_scroll" then
            if x <= CONTACTS_WIDTH then
                gui.scrollOffset = math.max(0, 
                    math.min(#state.contacts - (HEIGHT - INPUT_HEIGHT - 2), 
                    gui.scrollOffset - key))
                drawUI()
            end
        elseif event == "terminate" then
            break
        end
    end
end

-- Main client loop
function main()
    -- Connect to server
    if not connectToServer() then
        print("Failed to connect to server. Press any key to exit...")
        os.pullEvent("key")
        return
    end
    
    -- Initial data load
    updateContacts()
    getNewMessages()
    
    if #state.contacts > 0 then
        state.currentContact = state.contacts[1].id
        gui.selectedContact = 1
    end
    
    -- Start parallel threads
    parallel.waitForAny(
        function()
            -- Data refresh thread
            while true do
                sleep(3) -- Refresh every 3 seconds
                if state.connected then
                    updateContacts()
                    getNewMessages()
                    
                    if os.clock() - state.lastPing > PING_INTERVAL then
                        sendPing()
                    end
                    
                    drawUI()
                end
            end
        end,
        
        function()
            -- Input handling thread
            drawUI()
            handleInput()
        end
    )
end

-- Start
local ok, err = pcall(main)
if not ok then
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    print("Error: " .. err)
end

term.setCursorBlink(false)
rednet.close()
print("\nClient stopped")
