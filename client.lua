-- Простой рабочий клиент мессенджера
local VERSION = "1.0"
local PROTOCOL = "messenger_v2"
local SERVER_ID = 114

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
    end
end

print("=== Messenger Client ===")

-- Find modem
local MODEM_SIDE = modemSide or "back"
local modem = peripheral.wrap(MODEM_SIDE)
if not modem or not modem.isWireless or not modem.isWireless() then
    print("Checking for modem...")
    local sides = peripheral.getNames()
    for _, side in ipairs(sides) do
        if peripheral.getType(side) == "modem" then
            MODEM_SIDE = side
            modem = peripheral.wrap(side)
            if modem and modem.isWireless and modem.isWireless() then
                break
            end
        end
    end
end

if not modem then
    print("ERROR: No wireless modem!")
    return
end

rednet.open(MODEM_SIDE)
print("Modem: " .. MODEM_SIDE)

-- Client state
local state = {
    username = clientName or os.getComputerLabel() or "User" .. os.getComputerID(),
    messages = {},
    contacts = {},
    currentContact = nil,
    connected = false,
    myId = os.getComputerID()
}

print("Client: " .. state.username .. " (ID: " .. state.myId .. ")")
print("Server: " .. SERVER_ID)

-- Network functions
function sendRequest(request)
    rednet.send(SERVER_ID, request, PROTOCOL)
    local id, response = rednet.receive(PROTOCOL, 3)
    if id == SERVER_ID then
        return response
    end
    return nil
end

function connectToServer()
    print("Connecting...")
    local response = sendRequest({
        type = "register",
        name = state.username
    })
    
    if response and response.success then
        state.connected = true
        print("Connected!")
        return true
    end
    return false
end

function updateContacts()
    local response = sendRequest({type = "get_online"})
    if response and response.clients then
        -- Remove myself from contacts
        state.contacts = {}
        for _, client in ipairs(response.clients) do
            if client.id ~= state.myId then
                table.insert(state.contacts, client)
            end
        end
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

-- Simple GUI
local W, H = term.getSize()
local CONTACTS_W = 20
local INPUT_H = 3

local gui = {
    inputText = "",
    selected = 1
}

function drawUI()
    term.clear()
    term.setCursorPos(1, 1)
    print("=== Messenger ===")
    print("You: " .. state.username)
    print("--- Contacts ---")
    
    for i, contact in ipairs(state.contacts) do
        if i == gui.selected then
            term.write("> ")
        else
            term.write("  ")
        end
        print(contact.name .. " (ID:" .. contact.id .. ")")
    end
    
    print("--- Messages ---")
    if state.currentContact then
        local contactName = "Unknown"
        for _, c in ipairs(state.contacts) do
            if c.id == state.currentContact then
                contactName = c.name
                break
            end
        end
        
        for _, msg in ipairs(state.messages) do
            if msg.sender == state.currentContact or msg.target == state.currentContact then
                local prefix = msg.sender == state.myId and "You: " or contactName .. ": "
                print(prefix .. msg.message)
            end
        end
    end
    
    print("--- Input ---")
    print("> " .. gui.inputText)
    term.setCursorBlink(true)
    term.setCursorPos(3 + #gui.inputText, H)
end

-- Simple input handler
function main()
    if not connectToServer() then
        print("Failed to connect!")
        return
    end
    
    updateContacts()
    getMessages()
    
    if #state.contacts > 0 then
        state.currentContact = state.contacts[1].id
    end
    
    drawUI()
    
    while true do
        local event, param1, param2, param3 = os.pullEvent()
        
        if event == "key" then
            if param1 == keys.up then
                if gui.selected > 1 then
                    gui.selected = gui.selected - 1
                    state.currentContact = state.contacts[gui.selected].id
                    drawUI()
                end
            elseif param1 == keys.down then
                if gui.selected < #state.contacts then
                    gui.selected = gui.selected + 1
                    state.currentContact = state.contacts[gui.selected].id
                    drawUI()
                end
            elseif param1 == keys.enter then
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
            elseif param1 == keys.backspace then
                if #gui.inputText > 0 then
                    gui.inputText = string.sub(gui.inputText, 1, -2)
                    drawUI()
                end
            end
        elseif event == "char" then
            gui.inputText = gui.inputText .. param1
            drawUI()
        elseif event == "terminate" then
            break
        end
    end
end

local ok, err = pcall(main)
if not ok then
    print("Error: " .. err)
end

term.setCursorBlink(false)
rednet.close()
print("Client stopped")
