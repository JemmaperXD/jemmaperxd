-- Messenger Client with GUI
local VERSION = "1.0"
local PROTOCOL = "messenger_v2"
local PING_INTERVAL = 10

-- Parse command line arguments
local args = {...}
local clientName = nil
local modemSide = nil
local showHelp = false

for i = 1, #args do
    local arg = args[i]
    if arg == "-n" or arg == "--name" then
        clientName = args[i + 1]
    elseif arg == "-m" or arg == "--modem" then
        modemSide = args[i + 1]
    elseif arg == "-h" or arg == "--help" then
        showHelp = true
    end
end

if showHelp then
    print("Messenger Client v" .. VERSION)
    print("Usage: client [options]")
    print()
    print("Options:")
    print("  -n, --name <name>     Client display name")
    print("  -m, --modem <side>    Modem side (left/right/top/bottom/back/front)")
    print("  -h, --help            Show this help message")
    print()
    print("The client will automatically find the server")
    print("using protocol: " .. PROTOCOL)
    print()
    print("Examples:")
    print("  client")
    print("  client --name Alice")
    print("  client --name Bob --modem right")
    return
end

print("=== Messenger Client v" .. VERSION .. " ===")
print("Looking for server with protocol: " .. PROTOCOL)

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

rednet.open(MODEM_SIDE)
print("Modem opened successfully on side: " .. MODEM_SIDE)

-- Application state
local state = {
    username = clientName or os.getComputerLabel() or "User" .. os.getComputerID(),
    messages = {},
    contacts = {},
    currentContact = nil,
    connected = false,
    lastPing = 0,
    serverId = nil,
    serverName = "Unknown"
}

print("Client name: " .. state.username)

-- Function to find server
function findServer()
    print("Looking for server...")
    local serverIds = rednet.lookup(PROTOCOL)
    
    if not serverIds or #serverIds == 0 then
        print("No server found. Make sure server is running.")
        return nil
    end
    
    -- Try each server
    for _, serverId in ipairs(serverIds) do
        print("Trying server ID: " .. serverId)
        
        -- Send test ping
        rednet.send(serverId, {type = "ping"}, PROTOCOL)
        local id, response = rednet.receive(PROTOCOL, 2)
        
        if id == serverId and response and response.type == "pong" then
            print("Found server: " .. serverId)
            return serverId
        end
    end
    
    print("Could not connect to any server")
    return nil
end

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
    inputScroll = 0
}

-- Network functions
function sendRequest(request, timeout)
    if not state.serverId then
        return nil
    end
    
    rednet.send(state.serverId, request, PROTOCOL)
    
    local senderId, response, protocol = rednet.receive(PROTOCOL, timeout or 3)
    
    if senderId == state.serverId and protocol == PROTOCOL then
        return response
    end
    
    return nil
end

function connectToServer()
    print("Connecting to server...")
    
    -- Find server
    state.serverId = findServer()
    if not state.serverId then
        return false
    end
    
    -- Register with server
    local response = sendRequest({
        type = "register",
        name = state.username
    }, 5)
    
    if response and response.success then
        state.connected = true
        state.serverName = response.serverName or "Unknown"
        print("Connected to server: " .. state.serverName .. " (ID: " .. state.serverId .. ")")
        return true
    else
        print("Failed to register with server")
        state.serverId = nil
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
        print("Failed to send message")
        return false
    end
end

function updateContacts()
    local response = sendRequest({
        type = "get_online"
    })
    
    if response and response.clients then
        state.contacts = response.clients
        state.serverName = response.serverName or state.serverName
        
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
    if state.serverId then
        sendRequest({
            type = "ping"
        })
        state.lastPing = os.clock()
    end
end

-- GUI functions
function drawBorder()
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    
    -- Top bar
    term.setCursorPos(1, 1)
    term.write(string.rep(" ", WIDTH))
    
    term.setCursorPos(2, 1)
    term.write("M: " .. state.username)
    
    -- Server info
    if state.serverId then
        term.setCursorPos(WIDTH - 35, 1)
        term.write("S: " .. state.serverName .. " (ID:" .. state.serverId .. ")")
    end
    
    -- Status
    term.setCursorPos(WIDTH - 8, 1)
    if state.connected then
        term.setBackgroundColor(colors.green)
        term.write(" ONLINE ")
    else
        term.setBackgroundColor(colors.red)
        term.write("OFFLINE ")
    end
    
    term.setBackgroundColor(colors.blue)
    
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
    if state.connected then
        term.write("Contacts [" .. #state.contacts .. "]:")
    else
        term.write("Not connected")
    end
    
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
            if #displayName > CONTACTS_WIDTH - 8 then
                displayName = string.sub(displayName, 1, CONTACTS_WIDTH - 8) .. "..."
            end
            
            term.write(displayName)
            
            -- Show ID
            term.setCursorPos(CONTACTS_WIDTH - 5, y)
            term.write("(" .. contact.id .. ")")
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
    
    if not state.connected then
        term.setCursorPos(MESSAGES_X + 5, math.floor(HEIGHT / 2) - 1)
        term.write("Not connected to server")
        term.setCursorPos(MESSAGES_X + 5, math.floor(HEIGHT / 2))
        term.write("Searching for server...")
        return
    end
    
    if not state.currentContact then
        term.setCursorPos(MESSAGES_X + 5, math.floor(HEIGHT / 2) - 1)
        term.write("No contact selected")
        term.setCursorPos(MESSAGES_X + 5, math.floor(HEIGHT / 2))
        term.write("← Select a contact from the list")
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
            term.write("You: ")
        else
            term.setTextColor(colors.yellow)
            term.write(contactName .. ": ")
        end
        
        -- Message text
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
        
        displayY = displayY - 1
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
    
    if not state.connected then
        term.setCursorPos(1, HEIGHT - 1)
        term.write("Trying to connect to server...")
        return
    end
    
    if not state.currentContact then
        term.setCursorPos(1, HEIGHT - 1)
        term.write("Select a contact to message")
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
    term.write("To " .. contactName .. ":")
    
    -- Input field
    term.setCursorPos(1, HEIGHT - 1)
    term.write("> ")
    
    -- Display text
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
                -- Show help
                term.setBackgroundColor(colors.black)
                term.clear()
                term.setCursorPos(1, 1)
                print("Help - Messenger Client")
                print("Arrow keys: Select contact")
                print("Enter: Send message/Select contact")
                print("Backspace: Delete text")
                print("F1: This help")
                print("Ctrl+T: Exit")
                print("\nPress any key to continue...")
                os.pullEvent("key")
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
        elseif event == "terminate" then
            break
        end
    end
end

-- Main client loop
function main()
    -- Try to connect to server
    local attempts = 0
    local maxAttempts = 10
    
    while not state.connected and attempts < maxAttempts do
        attempts = attempts + 1
        print("Connection attempt " .. attempts .. "/" .. maxAttempts)
        
        if connectToServer() then
            break
        end
        
        if attempts < maxAttempts then
            sleep(2)
        end
    end
    
    if not state.connected then
        print("Failed to connect after " .. maxAttempts .. " attempts")
        print("Press any key to exit...")
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
                sleep(3)
                
                if not state.connected then
                    -- Try to reconnect
                    if connectToServer() then
                        updateContacts()
                        getNewMessages()
                    end
                else
                    updateContacts()
                    getNewMessages()
                    
                    if os.clock() - state.lastPing > PING_INTERVAL then
                        sendPing()
                    end
                end
                
                drawUI()
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
