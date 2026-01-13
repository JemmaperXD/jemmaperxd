-- client.lua - ameMessenger (Final Version)
local protocol = "messenger_v2"
local history_file = ".chat_history"
local server_id = nil
local client_name = ""
local messages = {}

-- Сохранение/Загрузка истории
local function save_history()
    local f = fs.open(history_file, "w")
    f.write(textutils.serialize(messages))
    f.close()
end

local function load_history()
    if fs.exists(history_file) then
        local f = fs.open(history_file, "r")
        local data = textutils.unserialize(f.readAll())
        f.close()
        if type(data) == "table" then messages = data end
    end
end

-- Получение ника и создание скрытых папок
local function get_name()
    if not fs.exists("/.User") then fs.makeDir("/.User") end
    local files = fs.list("/.User")
    for _, f in ipairs(files) do
        if f:sub(1,1) == "." then return f:sub(2) end
    end
    term.clear()
    term.setCursorPos(1,1)
    write("Enter your name: ")
    local name = read() or "User"..os.getComputerID()
    fs.makeDir("/.User/."..name)
    return name
end

client_name = get_name()
load_history()

local selected_contact = nil
local contacts = {}
local input_buffer = ""

local function draw_gui()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()

    -- Header
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.clearLine()
    term.write(" ameMessenger | " .. client_name .. " (ID:" .. os.getComputerID() .. ")")
    
    -- Sidebar (Contacts)
    local cp_w = 12
    for i=2, h-1 do
        term.setCursorPos(1, i)
        term.setBackgroundColor(colors.gray)
        term.write(string.rep(" ", cp_w))
    end

    for i, c in ipairs(contacts) do
        if i + 1 < h then
            term.setCursorPos(1, i+1)
            term.setBackgroundColor(selected_contact == c.id and colors.lightGray or colors.gray)
            term.write(" " .. c.name:sub(1, cp_w-2))
        end
    end

    -- Messages
    term.setBackgroundColor(colors.black)
    if selected_contact then
        local chat = messages[selected_contact] or {}
        local v_h = h - 3
        for i=0, v_h-1 do
            local m = chat[#chat - i]
            if m then
                term.setCursorPos(cp_w + 2, h - 2 - i)
                term.setTextColor(m.sender == os.getComputerID() and colors.lightBlue or colors.white)
                term.write((m.senderName or "ID "..m.sender) .. ": " .. m.message)
            end
        end
    end

    -- Input
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write("> " .. input_buffer)
end

local function network_handler()
    while true do
        server_id = rednet.lookup(protocol)
        if server_id then
            rednet.send(server_id, {type = "register", name = client_name}, protocol)
            rednet.send(server_id, {type = "get_online"}, protocol)
            rednet.send(server_id, {type = "get_messages"}, protocol)
        end
        local id, msg = rednet.receive(protocol, 2)
        if type(msg) == "table" then
            if msg.type == "online_list" then
                contacts = msg.clients
            elseif msg.type == "messages" then
                for _, m in ipairs(msg.messages) do
                    local partner = (m.sender == os.getComputerID()) and m.target or m.sender
                    messages[partner] = messages[partner] or {}
                    table.insert(messages[partner], m)
                end
                save_history()
            elseif msg.type == "error" then
                input_buffer = "SYS: " .. tostring(msg.message)
            end
        end
        draw_gui()
    end
end

local function input_handler()
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "char" then
            input_buffer = input_buffer .. p1
        elseif event == "key" then
            if p1 == keys.backspace then
                input_buffer = input_buffer:sub(1, -2)
            elseif p1 == keys.enter and #input_buffer > 0 then
                if input_buffer:sub(1, 8) == ".report " then
                    if server_id then rednet.send(server_id, {type = "report", reason = input_buffer:sub(9)}, protocol) end
                    input_buffer = ""
                elseif selected_contact and server_id then
                    rednet.send(server_id, {type = "send_message", target = selected_contact, message = input_buffer, senderName = client_name}, protocol)
                    messages[selected_contact] = messages[selected_contact] or {}
                    table.insert(messages[selected_contact], {sender = os.getComputerID(), message = input_buffer, senderName = client_name})
                    save_history()
                    input_buffer = ""
                end
            end
        elseif event == "mouse_click" then
            if p2 <= 12 and contacts[p3-1] then selected_contact = contacts[p3-1].id end
        end
        draw_gui()
    end
end

for _, s in ipairs(peripheral.getNames()) do if peripheral.getType(s) == "modem" then rednet.open(s) end end
parallel.waitForAny(network_handler, input_handler)
