-- Messenger Client with GUI
local VERSION = "1.0"
local PROTOCOL = "messenger_v2"
local PING_INTERVAL = 10
local SERVER_ID = 114 -- ID сервера (ваш сервер имеет ID 114)

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
    print("Server ID: " .. SERVER_ID)
    print("Protocol: " .. PROTOCOL)
    return
end

print("=== Messenger Client v" .. VERSION .. " ===")
print("Connecting to server ID: " .. SERVER_ID)

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

rednet.open(MODEM_SIDE)
print("Modem opened on side: " .. MODEM_SIDE)

-- Application state
local state = {
    username = clientName or os.getComputerLabel() or "User" .. os.getComputerID(),
    messages = {},
    contacts = {},
    currentContact = nil,
    connected = false,
    lastPing = 0,
    serverId = SERVER_ID,
    serverName = "Unknown"
}

print("Client name: " .. state.username)

-- Network functions
function sendRequest(request, timeout)
    rednet.send(SERVER_ID, request, PROTOCOL)
    
    local senderId, response, protocol = rednet.receive(PROTOCOL, timeout or 3)
    
    if senderId == SERVER_ID and protocol == PROTOCOL then
        return response
    end
    
    return nil
end

function connectToServer()
    print("Connecting to server...")
    
    -- Test if server is reachable
    rednet.send(SERVER_ID, {type = "ping"}, PROTOCOL)
    local id, response = rednet.receive(PROTOCOL, 2)
    
    if id == SERVER_ID and response and response.type == "pong" then
        print("Server is reachable")
        
        -- Register with server
        local response = sendRequest({
            type = "register",
            name = state.username
        }, 5)
        
        if response and response.success then
            state.connected = true
            state.serverName = response.serverName or "Unknown"
            print("Connected to server: " .. state.serverName)
            return true
        else
            print("Failed to register with server")
            return false
        end
    else
        print("Server not responding")
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
        for _, msg in ipairs(response.messages) do
            table.insert(state.messages, msg)
        end
        
        -- Sound notification
        local speaker = peripheral.find("speaker")
        if speaker then
            speaker.playSound("block.note_block.pling", 0.5)
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

-- GUI constants
local WIDTH, HEIGHT = term.getSize()
local INPUT_HEIGHT = 3
local CONTACTS_WIDTH = 20
local MESSAGES_X = CONTACTS_WIDTH + 2

-- GUI elements
local gui = {
    inputText = "",
    selectedContact = 1,
    scrollOffset = 0,
    inputScroll = 0
}

-- GUI functions
function drawBorder()
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    
    term.setCursorPos(1, 1)
    term.write(string.rep(" ", WIDTH))
    
    term.setCursorPos(2, 1)
    term.write("M: " .. state.username)
    
    if state.connected then
        term.setCursorPos(WIDTH - 30, 1)
        term.write("S: " .. state.serverName .. " (ID:" .. SERVER_ID .. ")")
    end
    
    term.setCursorPos(WIDTH - 8, 1)
    if state.connected then
        term.setBackgroundColor(colors.green)
        term.write(" ONLINE ")
    else
        term.setBackgroundColor(colors.red)
        term.write("OFFLINE ")
    end
    
    term.setBackgroundColor(colors.blue)
    
    for y = 2, HEIGHT - INPUT_HEIGHT do
        term.setCursorPos(CONTACTS_WIDTH + 1, y)
        term.write("│")
    end
    
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
            
            if contact.id == state.currentContact then
                term.setBackgroundColor(colors.lightBlue)
                term.setTextColor(colors.black)
            else
                term.setBackgroundColor(colors.gray)
                term.setTextColor(colors.white)
            end
            
            term.setCursorPos(2, y)
            
            local displayName = contact.name
            if #displayName > CONTACTS_WIDTH - 5 then
                displayName = string.sub(displayName, 1, CONTACTS_WIDTH - 5) .. "..."
            end
            
            term.write(displayName)
        end
    end
    
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

function drawMessages()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    
    for y = 2, HEIGHT - INPUT_HEIGHT do
        term.setCursorPos(MESSAGES_X, y)
        term.write(string.rep(" ", WIDTH - MESSAGES_X))
    end
    
    if not state.connected then
        term.setCursorPos(MESSAGES_X + 5, math.floor(HEIGHT / 2))
        term.write("Not connected to server")
        return
    end
    
    if not state.currentContact then
        term.setCursorPos(MESSAGES_X + 5, math.floor(HEIGHT / 2))
        term.write("Select a contact")
        return
    end
    
    local contactName = "Unknown"
    for _, c in ipairs(state.contacts) do
        if c.id == state.currentContact then
            contactName = c.name
            break
        end
    end
    
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
    
    local displayY = HEIGHT - INPUT_HEIGHT - 1
    local msgIndex = #contactMessages
    
    while msgIndex > 0 and displayY >= 2 do
        local msg = contactMessages[msgIndex]
        local isOwn = msg.sender == os.getComputerID()
        
        local timeStr = os.date("%H:%M", msg.time / 1000)
        term.setCursorPos(WIDTH - 7, displayY)
        term.write(timeStr)
        
        term.setCursorPos(MESSAGES_X, displayY)
        if isOwn then
            term.setTextColor(colors.green)
            term.write("You: ")
        else
            term.setTextColor(colors.yellow)
            term.write(contactName .. ": ")
        end
        
        term.setTextColor(colors.white)
        local message = msg.message
        local maxWidth = WIDTH - MESSAGES_X - 2
        
        displayY = displayY - 1
        
        while #message > 0 do
            if #message <= maxWidth then
                term.setCursorPos(MESSAGES_X, displayY)
                term.write(message)
                break
            else
                local breakPos = maxWidth
                while breakPos > 0 and message:sub(breakPos, breakPos) ~= " " do
                    breakPos = breakPos - 1
                end
                if breakPos == 0 then breakPos = maxWidth end
                
                term.setCursorPos(MESSAGES_X, displayY)
                term.write(message:sub(1, breakPos))
                message = message:sub(breakPos + 1)
                displayY = displayY - 1
            end
        end
        
        displayY = displayY - 1
        msgIndex = msgIndex - 1
    end
    
    term.setTextColor(colors.white)
end

function drawInput()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    
    for y = HEIGHT - INPUT_HEIGHT + 2, HEIGHT do
        term.setCursorPos(1, y)
        term.write(string.rep(" ", WIDTH))
    end
    
    if not state.connected then
        term.setCursorPos(1, HEIGHT - 1)
        term.write("Connecting to server...")
        return
    end
    
    if not state.currentContact then
        term.setCursorPos(1, HEIGHT - 1)
        term.write("Select a contact to message")
        return
    end
    
    local contactName = "Unknown"
    for _, c in ipairs(state.contacts) do
        if c.id == state.currentContact then
            contactName = c.name
            break
        end
    end
    
    term.setCursorPos(1, HEIGHT - INPUT_HEIGHT + 2)
    term.write("To " .. contactName .. ":")
    
    term.setCursorPos(1, HEIGHT - 1)
    term.write("> ")
    
    local displayText = gui.inputText
    if #displayText > WIDTH - 3 then
        if gui.inputScroll > 0 then
            displayText = string.sub(displayText, gui.inputScroll + 1)
        end
        displayText = string.sub(displayText, 1, WIDTH - 3)
    end
    
    term.write(displayText)
    
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
            if key == keys.up then
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
    local attempts = 0
    local maxAttempts = 5
    
    while not state.connected and attempts < maxAttempts do
        attempts = attempts + 1
        print("Attempt " .. attempts .. "/" .. maxAttempts)
        
        if connectToServer() then
            break
        end
        
        if attempts < maxAttempts then
            sleep(2)
        end
    end
    
    if not state.connected then
        print("Failed to connect to server ID: " .. SERVER_ID)
        print("Make sure server is running with ID 114")
        print("Press any key to exit...")
        os.pullEvent("key")
        return
    end
    
    updateContacts()
    getNewMessages()
    
    if #state.contacts > 0 then
        state.currentContact = state.contacts[1].id
        gui.selectedContact = 1
    end
    
    parallel.waitForAny(
        function()
            while true do
                sleep(3)
                
                if not state.connected then
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
