-- client.lua - ameMessenger (Hidden History Edition)
local protocol = "messenger_v2"
-- Теперь файл начинается с точки, что делает его скрытым для команды ls
local history_file = ".chat_history" 
local server_id = nil
local client_name = ""

-- 1. История сообщений (Загрузка/Сохранение)
local messages = {}

local function save_history()
    local f = fs.open(history_file, "w")
    f.write(textutils.serialize(messages))
    f.close()
end

local function load_history()
    -- Проверка на миграцию: если остался старый видимый файл, делаем его скрытым
    if fs.exists("chat_history.dat") then
        fs.move("chat_history.dat", history_file)
    end

    if fs.exists(history_file) then
        local f = fs.open(history_file, "r")
        local data = textutils.unserialize(f.readAll())
        f.close()
        if type(data) == "table" then
            messages = data
        end
    end
end

-- 2. Логин и поиск имени (проверка /.User/.Name)
local function get_name()
    if fs.exists("/.User") then
        local files = fs.list("/.User")
        for _, f in ipairs(files) do
            if f:sub(1,1) == "." then return f:sub(2) end
        end
    end
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.blue)
    print("=== Welcome to ameMessenger ===")
    term.setTextColor(colors.white)
    write("Enter your name: ")
    local name = read()
    return (name and name ~= "") and name or "User" .. os.getComputerID()
end

client_name = get_name()
load_history()

-- UI State
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
    term.setTextColor(colors.white)
    term.write(" ameMessenger | " .. client_name .. " (ID:" .. os.getComputerID() .. ")")
    
    local st_text = server_id and "ONLINE" or "SEARCH..."
    term.setCursorPos(w - #st_text, 1)
    term.setTextColor(server_id and colors.green or colors.red)
    term.write(st_text)

    -- Sidebar (Contacts)
    local cp_w = 12
    for i=2, h-2 do
        term.setCursorPos(1, i)
        term.setBackgroundColor(colors.gray)
        term.write(string.rep(" ", cp_w))
    end

    for i, c in ipairs(contacts) do
        if i + 1 < h - 1 then
            term.setCursorPos(1, i+1)
            term.setBackgroundColor(selected_contact == c.id and colors.lightGray or colors.gray)
            term.setTextColor(colors.white)
            term.write(" " .. c.name:sub(1, cp_w-2))
        end
    end

    -- Messages Area
    term.setBackgroundColor(colors.black)
    if selected_contact then
        local chat = messages[selected_contact] or {}
        local visible_h = h - 4
        for i=0, visible_h do
            local m = chat[#chat - i]
            if m then
                term.setCursorPos(cp_w + 2, h - 3 - i)
                term.setTextColor(m.sender == os.getComputerID() and colors.lightBlue or colors.white)
                term.write((m.senderName or ("ID "..m.sender)) .. ": " .. m.message)
            end
        end
    else
        term.setCursorPos(cp_w + 4, math.floor(h/2))
        term.setTextColor(colors.gray)
        term.write("Select a contact")
    end

    -- Input Line
    term.setCursorPos(1, h)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    term.write("> " .. input_buffer)
end

local function main_logic()
    while true do
        server_id = rednet.lookup(protocol)
        if server_id then
            rednet.send(server_id, {type = "register", name = client_name}, protocol)
            rednet.send(server_id, {type = "get_online"}, protocol)
            rednet.send(server_id, {type = "get_messages"}, protocol)
        end
        os.sleep(2)
        draw_gui()
    end
end

local function network_handler()
    while true do
        local id, msg = rednet.receive(protocol)
        if type(msg) == "table" then
            if msg.type == "online_list" then
                contacts = msg.clients
            elseif msg.type == "messages" then
                local got_new = false
                for _, m in ipairs(msg.messages) do
                    local partner = (m.sender == os.getComputerID()) and m.target or m.sender
                    messages[partner] = messages[partner] or {}
                    table.insert(messages[partner], m)
                    got_new = true
                end
                if got_new then save_history() end
            elseif msg.type == "error" then
                input_buffer = "SYSTEM ERROR: " .. tostring(msg.message)
            end
            draw_gui()
        end
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
            elseif p1 == keys.enter and selected_contact and #input_buffer > 0 then
                if server_id then
                    rednet.send(server_id, {
                        type = "send_message",
                        target = selected_contact,
                        message = input_buffer,
                        senderName = client_name
                    }, protocol)
                    
                    messages[selected_contact] = messages[selected_contact] or {}
                    table.insert(messages[selected_contact], {
                        sender = os.getComputerID(),
                        message = input_buffer,
                        senderName = client_name
                    })
                    save_history()
                    input_buffer = ""
                end
            end
        elseif event == "mouse_click" then
            if p2 <= 12 and contacts[p3-1] then
                selected_contact = contacts[p3-1].id
            end
        end
        draw_gui()
    end
end

-- Open Modem
for _, s in ipairs(peripheral.getNames()) do
    if peripheral.getType(s) == "modem" then rednet.open(s) end
end

parallel.waitForAny(main_logic, network_handler, input_handler)
