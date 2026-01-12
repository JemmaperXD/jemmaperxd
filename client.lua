local SERVER_ID = 114 -- !!! ЖЕСТКО ПРОПИСАННЫЙ ID СЕРВЕРА !!!
local PORT = 1384
local modem = peripheral.find("modem") or error("No modem found")
modem.open(os.getComputerID())

-- Определение имени пользователя
local username = "Guest"
if fs.exists(".User") then
    local files = fs.list(".User")
    for _, f in ipairs(files) do if not f:match("^%.") then username = f break end end
end

-- Проверка подключения к серверу при запуске
term.clear()
print("Connecting to Server " .. SERVER_ID .. "...")
modem.transmit(SERVER_ID, PORT, {type = "handshake", user = username})
local t = os.startTimer(3)
local ok = false
while not ok do
    local e, p1, p2, p3, p4 = os.pullEvent()
    if e == "modem_message" and p4.type == "status" then ok = true
    elseif e == "timer" and p1 == t then error("Server offline!") end
end

-- GUI и Логика Чата (Telegram Style)
local contacts, messages = {}, {}
local target_user, input_buffer = nil, ""
local w, h = term.getSize()
local side_w = 14
local chat_win = window.create(term.current(), side_w + 2, 2, w - side_w - 2, h - 3)

local function decrypt(text, key)
    local res = ""
    for i = 1, #text do res = res .. string.char((text:byte(i) - key) % 256) end
    return res
end

local function draw_gui()
    -- Шапка
    term.setBackgroundColor(colors.blue)
    term.clear()
    term.setCursorPos(2,1)
    term.setTextColor(colors.white)
    term.write("TG-CC | User: " .. username .. " | Server: " .. SERVER_ID)

    -- Сайдбар
    term.setBackgroundColor(colors.lightGray)
    for i=2, h do term.setCursorPos(1, i) term.write(string.rep(" ", side_w)) end
    for i, name in ipairs(contacts) do
        if i > h-2 then break end
        term.setCursorPos(1, i+1)
        term.setBackgroundColor(name == target_user and colors.gray or colors.lightGray)
        term.setTextColor(name == target_user and colors.white or colors.black)
        term.write(" " .. name:sub(1, side_w-1))
    end

    -- Окно чата (Telegram Style: Me Right, Other Left)
    chat_win.setBackgroundColor(colors.black)
    chat_win.clear()
    local win_w, win_h = chat_win.getSize()
    local y_pos = win_h
    
    for i = #messages, 1, -1 do
        if y_pos < 1 then break end
        local m = messages[i]
        local is_my = (m.from == "Me")
        
        -- Текст сообщения (выравнивание)
        chat_win.setCursorPos(is_my and (win_w - #m.text) or 1, y_pos)
        chat_win.setTextColor(colors.white)
        chat_win.write(m.text)
        y_pos = y_pos - 1
        
        -- Никнейм над сообщением
        chat_win.setCursorPos(is_my and (win_w - #m.from) or 1, y_pos)
        chat_win.setTextColor(is_my and colors.green or colors.cyan)
        chat_win.write(m.from)
        y_pos = y_pos - 2
    end

    -- Поле ввода
    term.setBackgroundColor(colors.gray)
    term.setCursorPos(side_w + 1, h)
    term.setTextColor(colors.yellow)
    local prompt = target_user and ("To ["..target_user.."]: ") or "Select user ->"
    term.write(prompt .. input_buffer)
end

-- Параллельные процессы (Пинг и События)
parallel.waitForAll(
    function() -- Пинг
        while true do
            modem.transmit(SERVER_ID, PORT, {type = "ping", user = username})
            sleep(3)
        end
    end,
    function() -- События
        while true do
            draw_gui()
            local e, p1, p2, p3, p4 = os.pullEvent()
            if e == "char" then
                input_buffer = input_buffer .. p1
            elseif e == "key" then
                if p1 == keys.backspace then input_buffer = input_buffer:sub(1, -2)
                elseif p1 == keys.enter and target_user and #input_buffer > 0 then
                    modem.transmit(SERVER_ID, PORT, {type="send", user=username, to=target_user, text=input_buffer})
                    table.insert(messages, {from="Me", text=input_buffer})
                    input_buffer = ""
                end
            elseif e == "mouse_click" then
                if p2 <= side_w and contacts[p3-1] then
                    target_user = contacts[p3-1]
                end
            elseif e == "modem_message" and p3 == SERVER_ID then
                if p4.type == "status" then contacts = p4.users
                elseif p4.type == "msg" then
                    table.insert(messages, {from=p4.from, text=decrypt(p4.text, 7)})
                end
            end
        end
    end
)
