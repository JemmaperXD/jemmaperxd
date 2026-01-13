-- client.lua - Messenger V2 Client (STABLE)
local protocol = "messenger_v2"
local args = {...}
local client_name = "User" .. os.getComputerID()
local server_id = nil
local modem_side = nil

-- UI State
local selected_contact = nil
local contacts = {}
local messages = {} -- [contactID] = { {sender, msg, time}, ... }
local input_buffer = ""
local status = "SEARCHING..."

-- Инициализация модема
for i=1, #args do
    if (args[i] == "--modem" or args[i] == "-m") then modem_side = args[i+1] end
    if (args[i] == "--name" or args[i] == "-n") then client_name = args[i+1] end
end

local function init_rednet()
    for _, s in ipairs(peripheral.getNames()) do
        if peripheral.getType(s) == "modem" and (not modem_side or s == modem_side) then
            rednet.open(s)
            return true
        end
    end
    return false
end

-- Отрисовка GUI
local function draw_gui()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.black)
    term.clear()

    -- Верхняя панель
    term.setCursorPos(1, 1)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    local status_color = (server_id) and colors.green or colors.red
    local status_text = (server_id) and "ONLINE" or "OFFLINE"
    
    term.write(" Messenger V2 | User: " .. client_name)
    term.setCursorPos(w - #status_text - 1, 1)
    term.setTextColor(status_color)
    term.write(status_text)

    -- Левая панель (Контакты)
    local cp_w = math.floor(w * 0.3)
    for i = 2, h - 3 do
        term.setCursorPos(1, i)
        term.setBackgroundColor(colors.gray)
        term.write(string.rep(" ", cp_w))
    end
    
    for i, contact in ipairs(contacts) do
        if i + 1 < h - 3 then
            term.setCursorPos(1, i + 1)
            if selected_contact == contact.id then
                term.setBackgroundColor(colors.lightGray)
            else
                term.setBackgroundColor(colors.gray)
            end
            term.setTextColor(colors.white)
            -- Обрезаем имя, если длинное
            local name_display = contact.name
            if #name_display > cp_w - 2 then name_display = name_display:sub(1, cp_w - 5) .. "..." end
            term.write(" " .. name_display)
        end
    end

    -- Область сообщений
    term.setBackgroundColor(colors.black)
    if selected_contact then
        local chat = messages[selected_contact] or {}
        local msg_area_h = h - 4
        
        -- Показываем последние N сообщений
        for i = 0, math.min(#chat, msg_area_h) - 1 do
            local msg_idx = #chat - i
            if msg_idx > 0 then
                local m = chat[msg_idx]
                local is_me = (m.sender == os.getComputerID())
                local sender_lbl = is_me and "Me: " or (m.senderName or "?") .. ": "
                local line = sender_lbl .. m.message
                
                -- Простая обрезка для одной строки (можно усложнить для переноса)
                if #line > (w - cp_w - 2) then line = line:sub(1, w - cp_w - 5) .. "..." end
                
                term.setCursorPos(cp_w + 2, h - 3 - i)
                term.setTextColor(is_me and colors.lightBlue or colors.white)
                term.write(line)
            end
        end
    else
        term.setCursorPos(cp_w + 2, math.floor(h/2))
        term.setTextColor(colors.gray)
        term.write("Select a contact to start chatting")
    end

    -- Нижняя панель (Ввод)
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.setCursorPos(1, h - 2)
    term.clearLine()
    term.setCursorPos(1, h - 1)
    term.clearLine()
    term.write("> " .. input_buffer .. "_")
end

-- Логика запросов
local function update_loop()
    while true do
        local new_server = rednet.lookup(protocol)
        server_id = new_server -- Обновляем глобальный ID
        
        if server_id then
            -- Регистрация
            rednet.send(server_id, {type = "register", name = client_name}, protocol)
            -- Список онлайн
            rednet.send(server_id, {type = "get_online"}, protocol)
            -- Новые сообщения
            rednet.send(server_id, {type = "get_messages"}, protocol)
        end
        
        os.sleep(2)
        draw_gui()
    end
end

-- Обработка сети
local function network_handler()
    while true do
        local id, msg = rednet.receive(protocol)
        if type(msg) == "table" then
            if msg.type == "online_list" then
                contacts = {}
                for _, c in ipairs(msg.clients) do
                    if c.id ~= os.getComputerID() then table.insert(contacts, c) end
                end
            elseif msg.type == "messages" then
                for _, m in ipairs(msg.messages) do
                    -- Используем ID отправителя как ключ чата
                    local chat_id = (m.sender == os.getComputerID()) and m.target or m.sender
                    -- Если это мое сообщение, которое вернулось (синхронизация), или входящее
                    if m.sender == os.getComputerID() then chat_id = m.target end
                    
                    messages[m.sender] = messages[m.sender] or {}
                    table.insert(messages[m.sender], m)
                    
                    if peripheral.find("speaker") then peripheral.find("speaker").playNote("bit", 1, 12) end
                end
            end
            draw_gui()
        end
    end
end

-- Ввод пользователя
local function input_handler()
    local w, h = term.getSize()
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "char" then
            if #input_buffer < (w - 5) then -- Ограничение длины
                input_buffer = input_buffer .. p1
            end
        elseif event == "key" then
            if p1 == keys.backspace then
                input_buffer = input_buffer:sub(1, -2)
            elseif p1 == keys.enter then
                -- ОТПРАВКА: Проверяем наличие сервера!
                if server_id and selected_contact and #input_buffer > 0 then
                    local pkt = {
                        type = "send_message",
                        target = selected_contact,
                        message = input_buffer,
                        senderName = client_name
                    }
                    rednet.send(server_id, pkt, protocol)
                    
                    -- Добавляем себе в историю сразу
                    messages[selected_contact] = messages[selected_contact] or {}
                    table.insert(messages[selected_contact], {
                        sender = os.getComputerID(), 
                        message = input_buffer, 
                        senderName = client_name
                    })
                    input_buffer = ""
                end
            elseif p1 == keys.terminate then
                 -- Штатный выход
                 return
            end
        elseif event == "mouse_click" then
            local cp_w = math.floor(w * 0.3)
            if p2 <= cp_w and p3 > 1 and p3 < h - 3 then
                local idx = p3 - 1
                if contacts[idx] then selected_contact = contacts[idx].id end
            end
        end
        draw_gui()
    end
end

if not init_rednet() then error("Modem required!") end
parallel.waitForAny(update_loop, network_handler, input_handler)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
