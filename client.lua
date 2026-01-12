local modem = peripheral.find("modem") or error("No modem found")
local SERVER_ID = 1384
local PORT = 1384
modem.open(os.getComputerID())

-- Нахождение имени пользователя
local username = "Guest"
if fs.exists(".User") then
    local files = fs.list(".User")
    if #files > 0 then username = files[1] end
end

local contacts = {}
local messages = {}
local target_user = "Nobody"
local input_buffer = ""

-- Окна (GUI)
local w, h = term.getSize()
local sidebar = window.create(term.current(), 1, 2, 15, h - 1)
local chat_win = window.create(term.current(), 17, 2, w - 16, h - 4)
local input_win = window.create(term.current(), 17, h - 1, w - 16, 1)

local function decrypt(text, key)
    local res = ""
    for i = 1, #text do res = res .. string.char((text:byte(i) - key) % 256) end
    return res
end

local function draw_gui()
    -- Шапка
    term.setBackgroundColor(colors.blue)
    term.clear()
    term.setCursorPos(2, 1)
    term.setTextColor(colors.white)
    term.write("TG CC:T | User: " .. username .. " | Chat with: " .. target_user)

    -- Sidebar (Контакты)
    sidebar.setBackgroundColor(colors.lightGray)
    sidebar.clear()
    sidebar.setCursorPos(1, 1)
    sidebar.setTextColor(colors.black)
    sidebar.write(" ONLINE: ")
    for i, name in ipairs(contacts) do
        sidebar.setCursorPos(1, i + 1)
        if name == target_user then sidebar.setTextColor(colors.blue) else sidebar.setTextColor(colors.black) end
        sidebar.write(" " .. name:sub(1, 13))
    end

    -- Chat Area
    chat_win.setBackgroundColor(colors.black)
    chat_win.clear()
    local start_y = 1
    for i = math.max(1, #messages - 10), #messages do
        chat_win.setCursorPos(1, start_y)
        chat_win.setTextColor(colors.gray)
        chat_win.write(messages[i].from .. ": ")
        chat_win.setTextColor(colors.white)
        chat_win.write(messages[i].text)
        start_y = start_y + 1
    end

    -- Input Area
    input_win.setBackgroundColor(colors.gray)
    input_win.clear()
    input_win.setCursorPos(1, 1)
    input_win.setTextColor(colors.white)
    input_win.write("> " .. input_buffer)
end

-- Поток пинга сервера
local function ping_loop()
    while true do
        modem.transmit(SERVER_ID, PORT, {type = "ping", user = username})
        sleep(5)
    end
end

-- Поток обработки событий
local function event_loop()
    while true do
        draw_gui()
        local event, p1, p2, p3 = os.pullEvent()

        if event == "char" then
            input_buffer = input_buffer .. p1
        elseif event == "key" then
            if p1 == keys.backspace then
                input_buffer = input_buffer:sub(1, -2)
            elseif p1 == keys.enter and #input_buffer > 0 and target_user ~= "Nobody" then
                modem.transmit(SERVER_ID, PORT, {
                    type = "send", user = username, to = target_user, text = input_buffer
                })
                table.insert(messages, {from = "Me", text = input_buffer})
                input_buffer = ""
            end
        elseif event == "mouse_click" then
            -- Выбор контакта в сайдбаре
            if p2 <= 15 and p3 > 1 and contacts[p3 - 1] then
                target_user = contacts[p3 - 1]
            end
        elseif event == "modem_message" then
            local data = p3
            if data.type == "user_list" then
                contacts = data.users
            elseif data.type == "msg" then
                table.insert(messages, {from = data.from, text = decrypt(data.text, 7)})
            elseif data.type == "ack" then
                -- Можно добавить визуальный "галочку" (чекбокс)
            end
        end
    end
end

parallel.waitForAll(ping_loop, event_loop)
