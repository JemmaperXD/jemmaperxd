local modem = peripheral.find("modem") or error("No modem found")
local SERVER_ID = 1384
local PORT = 1384
modem.open(os.getComputerID())

-- 1. ОПРЕДЕЛЕНИЕ ИМЕНИ (Auto-login)
local username = "Guest"
if fs.exists(".User") then
    local files = fs.list(".User")
    for _, f in ipairs(files) do
        if not f:match("^%.") then username = f break end
    end
end

-- 2. ПРОВЕРКА ПОДКЛЮЧЕНИЯ ПРИ ЗАПУСКЕ
print("Connecting to TG-Server...")
modem.transmit(SERVER_ID, PORT, {type = "handshake", user = username})
local timer = os.startTimer(3)
local connected = false

while not connected do
    local event, p1, p2, p3, p4 = os.pullEvent()
    if event == "modem_message" and p4.type == "status" then
        connected = true
    elseif event == "timer" and p1 == timer then
        error("Could not connect to server at ID " .. SERVER_ID)
    end
end

-- 3. GUI И ЛОГИКА ЧАТА
local contacts = {}
local messages = {}
local target_user = nil
local input_buffer = ""

local w, h = term.getSize()
local side_w = 14
local sidebar = window.create(term.current(), 1, 2, side_w, h - 1)
local chat_win = window.create(term.current(), side_w + 2, 2, w - side_w - 1, h - 3)

local function decrypt(text, key)
    local res = ""
    for i = 1, #text do res = res .. string.char((text:byte(i) - key) % 256) end
    return res
end

local function draw_interface()
    -- Header
    term.setBackgroundColor(colors.blue)
    term.clear()
    term.setCursorPos(1,1)
    term.setTextColor(colors.white)
    local title = " TG-CC 2026 | User: " .. username
    term.write(title .. string.rep(" ", w - #title))

    -- Sidebar
    sidebar.setBackgroundColor(colors.lightGray)
    sidebar.clear()
    for i, name in ipairs(contacts) do
        sidebar.setCursorPos(1, i)
        if name == target_user then
            sidebar.setBackgroundColor(colors.gray)
            sidebar.setTextColor(colors.white)
        else
            sidebar.setBackgroundColor(colors.lightGray)
            sidebar.setTextColor(colors.black)
        end
        sidebar.write(" " .. name:sub(1, side_w - 1))
    end

    -- Chat Area
    chat_win.setBackgroundColor(colors.black)
    chat_win.clear()
    local y_off = 1
    for i = math.max(1, #messages - (h-5)), #messages do
        local m = messages[i]
        chat_win.setCursorPos(1, y_off)
        chat_win.setTextColor(m.from == "Me" and colors.green or colors.cyan)
        chat_win.write(m.from .. ": ")
        chat_win.setTextColor(colors.white)
        chat_win.write(m.text)
        y_off = y_off + 1
    end

    -- Bottom Input
    term.setBackgroundColor(colors.gray)
    term.setCursorPos(side_w + 1, h)
    term.clearLine()
    term.setTextColor(colors.yellow)
    term.write(target_user and (" To [" .. target_user .. "]: ") or " Select user ->")
    term.setTextColor(colors.white)
    term.write(input_buffer)
end

local function ping_loop()
    while true do
        modem.transmit(SERVER_ID, PORT, {type = "ping", user = username})
        sleep(3)
    end
end

local function main_loop()
    while true do
        draw_interface()
        local event, p1, p2, p3, p4 = os.pullEvent()

        if event == "char" then
            input_buffer = input_buffer .. p1
        elseif event == "key" then
            if p1 == keys.backspace then
                input_buffer = input_buffer:sub(1, -2)
            elseif p1 == keys.enter and target_user and #input_buffer > 0 then
                modem.transmit(SERVER_ID, PORT, {
                    type = "send", user = username, to = target_user, text = input_buffer
                })
                table.insert(messages, {from = "Me", text = input_buffer})
                input_buffer = ""
            end
        elseif event == "mouse_click" then
            if p2 <= side_w and contacts[p3 - 1] then
                target_user = contacts[p3 - 1]
                if target_user == username then target_user = nil end -- Нельзя писать самому себе
            end
        elseif event == "modem_message" then
            local data = p4
            if data.type == "status" then
                contacts = data.users
            elseif data.type == "msg" then
                table.insert(messages, {from = data.from, text = decrypt(data.text, 7)})
                if not target_user then target_user = data.from end
            end
        end
    end
end

parallel.waitForAll(ping_loop, main_loop)
