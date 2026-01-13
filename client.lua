-- Messenger Client for CC:Tweaked
local VERSION = "1.0"
local PROTOCOL = "messenger_v2"
local SERVER_ID = 114
local PING_INTERVAL = 10

-- Parse arguments
local args = {...}
local clientName = nil
local modemSide = nil

for i = 1, #args do
    local arg = args[i]
    if arg == "-n" or arg == "--name" then
        clientName = args[i + 1]
    elseif arg == "-m" or arg == "--modem" then
        modemSide = args[i + 1]
    elseif arg == "-h" or arg == "--help" then
        print("Messenger Client v" .. VERSION)
        print("Usage: client [options]")
        print("Options:")
        print("  -n, --name <name>    Client display name")
        print("  -m, --modem <side>   Modem side")
        print("  -h, --help           Show help")
        return
    end
end

print("=== Messenger Client v" .. VERSION .. " ===")
print("Server ID: " .. SERVER_ID)

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

-- Client state
local state = {
    username = clientName or os.getComputerLabel() or "User" .. os.getComputerID(),
    messages = {},
    contacts = {},
    currentContact = nil,
    connected = false,
    serverName = "Unknown",
    myId = os.getComputerID()
}

print("Client: " .. state.username .. " (ID: " .. state.myId .. ")")

-- Network functions
function sendRequest(request, timeout)
    rednet.send(SERVER_ID, request, PROTOCOL)
    local id, response, protocol = rednet.receive(PROTOCOL, timeout or 3)
    if id == SERVER_ID and protocol == PROTOCOL then
        return response
    end
    return nil
end

function connectToServer()
    print("Connecting...")
    local response = sendRequest({
        type = "register",
        name = state.username
    }, 5)
    
    if response and response.success then
        state.connected = true
        state.serverName = response.serverName or "Server"
        print("Connected to " .. state.serverName)
        return true
    end
    return false
end

function updateContacts()
    local response = sendRequest({type = "get_online"})
    if response and response.clients then
        -- Filter out myself from contacts
        state.contacts = {}
        for _, client in ipairs(response.clients) do
            if client.id ~= state.myId then  -- Don't add myself
                table.insert(state.contacts, client)
            end
        end
        state.serverName = response.serverName or state.serverName
        return true
    end
    return false
end

function getMessages()
    local response = sendRequest({type = "get_messages"})
    if response and response.messages then
        for _, msg in ipairs(response.messages) do
            table.insert(state.messages, msg)
        end
        return true
    end
    return false
end

function sendMessage(target, text)
    local response = sendRequest({
        type = "send_message",
        target = target,
        message = text,
        senderName = state.username
    })
    return response and response.success or false
end

-- GUI setup
local W, H = term.getSize()
local CONTACTS_W = 20
local INPUT_H = 3
local MSG_X = CONTACTS_W + 2

local gui = {
    inputText = "",
    selected = 1,
    scroll = 0,
    lastDraw = 0
}

function drawBorder()
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    
    term.setCursorPos(1, 1)
    term.write(string.rep(" ", W))
    term.setCursorPos(2, 1)
    term.write("Messenger - " .. state.username)
    
    term.setCursorPos(W - 25, 1)
    term.write("Srv: " .. state.serverName)
    
    term.setCursorPos(W - 8, 1)
    if state.connected then
        term.setBackgroundColor(colors.green)
        term.write(" ONLINE ")
    else
        term.setBackgroundColor(colors.red)
        term.write("OFFLINE ")
    end
    
    term.setBackgroundColor(colors.blue)
    for y = 2, H - INPUT_H do
        term.setCursorPos(CONTACTS_W + 1, y)
        term.write("│")
    end
    
    term.setCursorPos(1, H - INPUT_HEIGHT + 1)
    term.write(string.rep("─", W))
    
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

function drawContacts()
    term.setBackgroundColor(colors.gray)
    for y = 2, H - INPUT_H do
        term.setCursorPos(1, y)
        term.write(string.rep(" ", CONTACTS_W))
    end
    
    term.setCursorPos(2, 2)
    term.write("Contacts [" .. #state.contacts .. "]:")
    
    local maxVisible = H - INPUT_H - 2
    local start = gui.scroll
    
    for i = 1, math.min(#state.contacts, maxVisible) do
        local idx = i + start
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
            local name = contact.name
            if #name > CONTACTS_W - 8 then
                name = string.sub(name, 1, CONTACTS_W - 8) .. "..."
            end
            term.write(name)
            
            -- Show ID in parentheses
            term.setCursorPos(CONTACTS_W - 5, y)
            term.write("(" .. contact.id .. ")")
        end
    end
    
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

function drawMessages()
    for y = 2, H - INPUT_H do
        term.setCursorPos(MSG_X, y)
        term.write(string.rep(" ", W - MSG_X))
    end
    
    if not state.currentContact then
        term.setCursorPos(MSG_X + 5, math.floor(H / 2) - 1)
        term.write("No contact selected")
        term.setCursorPos(MSG_X + 5, math.floor(H / 2))
        term.write("← Select a contact from the list")
        return
    end
    
    local contactName = "Unknown"
    for _, c in ipairs(state.contacts) do
        if c.id == state.currentContact then
            contactName = c.name
            break
        end
    end
    
    -- Get messages for this contact
    local chatMsgs = {}
    for _, msg in ipairs(state.messages) do
        if msg.sender == state.currentContact or 
           msg.target == state.currentContact then
            table.insert(chatMsgs, msg)
        end
    end
    
    if #chatMsgs == 0 then
        term.setCursorPos(MSG_X + 5, math.floor(H / 2))
        term.write("No messages with " .. contactName)
        term.setCursorPos(MSG_X + 5, math.floor(H / 2) + 1)
        term.write("Start typing below to send a message")
        return
    end
    
    -- Display messages (newest at bottom)
    local displayY = H - INPUT_H - 1
    local msgIndex = #chatMsgs
    
    while msgIndex > 0 and displayY >= 2 do
        local msg = chatMsgs[msgIndex]
        local isOwn = msg.sender == state.myId
        
        -- Time
        local timeStr = os.date("%H:%M", msg.time / 1000)
        term.setCursorPos(W - 6, displayY)
        term.write(timeStr)
        
        -- Sender
        term.setCursorPos(MSG_X, displayY)
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
        local maxWidth = W - MSG_X - 2
        
        displayY = displayY - 1
        
        -- Word wrap for long messages
        while #message > 0 do
            if #message <= maxWidth then
                term.setCursorPos(MSG_X, displayY)
                term.write(message)
                break
            else
                -- Try to break at space
                local breakPos = maxWidth
                while breakPos > 0 and message:sub(breakPos, breakPos) ~= " " do
                    breakPos = breakPos - 1
                end
                if breakPos == 0 then breakPos = maxWidth end
                
                term.setCursorPos(MSG_X, displayY)
                term.write(message:sub(1, breakPos))
                message = message:sub(breakPos + 1)
                displayY = displayY - 1
                if displayY < 2 then break end
            end
        end
        
        displayY = displayY - 1
        msgIndex = msgIndex - 1
    end
    
    term.setTextColor(colors.white)
end

function drawInput()
    for y = H - INPUT_H + 2, H do
        term.setCursorPos(1, y)
        term.write(string.rep(" ", W))
    end
    
    if not state.currentContact then
        term.setCursorPos(1, HEIGHT - 1)
        term.write("Select a contact to send message")
        return
    end
    
    local contactName = "Unknown"
    for _, c in ipairs(state.contacts) do
        if c.id == state.currentContact then
            contactName = c.name
            break
        end
    end
    
    term.setCursorPos(1, H - INPUT_H + 2)
    term.write("To " .. contactName .. " (" .. state.currentContact .. "):")
    
    term.setCursorPos(1, H - 1)
    term.write("> " .. gui.inputText)
    
    -- Show cursor
    local cursorPos = #gui.inputText + 3
    if cursorPos <= W then
        term.setCursorPos(cursorPos, H - 1)
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
    
    gui.lastDraw = os.clock()
end

function handleInput()
    while true do
        local event, key, x, y = os.pullEvent()
        
        if event == "key" then
            if key == keys.up then
                if gui.selected > 1 then
                    gui.selected = gui.selected - 1
                    if gui.selected <= gui.scroll then
                        gui.scroll = gui.scroll - 1
                    end
                    state.currentContact = state.contacts[gui.selected].id
                    drawUI()
                end
            elseif key == keys.down then
                if gui.selected < #state.contacts then
                    gui.selected = gui.selected + 1
                    local maxVisible = H - INPUT_H - 2
                    if gui.selected > gui.scroll + maxVisible then
                        gui.scroll = gui.scroll + 1
                    end
                    state.currentContact = state.contacts[gui.selected].id
                    drawUI()
                end
            elseif key == keys.enter then
                if gui.inputText ~= "" and state.currentContact then
                    if sendMessage(state.currentContact, gui.inputText) then
                        table.insert(state.messages, {
                            sender = state.myId,
                            senderName = state.username,
                            target = state.currentContact,
                            message = gui.inputText,
                            time = os.epoch("utc")
                        })
                        gui.inputText = ""
                        drawUI()
                    end
                end
            elseif key == keys.backspace then
                if #gui.inputText > 0 then
                    gui.inputText = string.sub(gui.inputText, 1, -2)
                    drawUI()
                end
            end
            
        elseif event == "char" then
            gui.inputText = gui.inputText .. key
            drawUI()
            
        elseif event == "mouse_click" then
            if x <= CONTACTS_W and y >= 2 and y <= H - INPUT_H then
                local idx = y - 2 + gui.scroll
                if idx <= #state.contacts then
                    gui.selected = idx
                    state.currentContact = state.contacts[idx].id
                    drawUI()
                end
            end
            
        elseif event == "terminate" then
            break
        end
    end
end

-- Main
function main()
    -- Connect to server
    local attempts = 0
    while not state.connected and attempts < 5 do
        attempts = attempts + 1
        print("Connection attempt " .. attempts .. "/5")
        if connectToServer() then
            break
        end
        sleep(2)
    end
    
    if not state.connected then
        print("Cannot connect to server!")
        print("Make sure server with ID " .. SERVER_ID .. " is running")
        print("Press any key to exit...")
        os.pullEvent("key")
        return
    end
    
    -- Load initial data
    updateContacts()
    getMessages()
    
    -- Set default contact if available
    if #state.contacts > 0 then
        state.currentContact = state.contacts[1].id
        gui.selected = 1
    end
    
    -- Start threads
    parallel.waitForAny(
        function()
            -- Background update thread
            while true do
                sleep(3)
                if state.connected then
                    updateContacts()
                    getMessages()
                    drawUI()
                else
                    -- Try to reconnect
                    if connectToServer() then
                        updateContacts()
                        getMessages()
                        drawUI()
                    end
                end
            end
        end,
        
        function()
            -- Input thread
            drawUI()
            handleInput()
        end
    )
end

-- Run client
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
