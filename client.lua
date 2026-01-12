local modem = peripheral.find("modem") or error("No modem found")
local SERVER_ID = 1384
local PORT = 1384
modem.open(os.getComputerID())

-- Получение имени пользователя из папки
local username = "Unknown"
if fs.exists(".User") then
    local files = fs.list(".User")
    if #files > 0 then username = files[1] end
end

local messages = {}
local input_to = ""
local input_text = ""
local active_field = "to" -- "to" or "msg"

local function decrypt(text, key)
    local result = ""
    for i = 1, #text do
        result = result .. string.char((text:byte(i) - key) % 256)
    end
    return result
end

local function draw_gui()
    term.setBackgroundColor(colors.black)
    term.clear()
    
    -- Шапка
    term.setBackgroundColor(colors.blue)
    term.setCursorPos(1,1)
    term.clearLine()
    print(" TG-CC | User: " .. username)
    
    -- Окно сообщений
    term.setBackgroundColor(colors.black)
    for i = 1, 10 do
        term.setCursorPos(1, 2 + i)
        if messages[i] then
            print(messages[i])
        end
    end
    
    -- Поля ввода
    term.setCursorPos(1, 15)
    term.write("To: " .. (active_field == "to" and "> " or "") .. input_to)
    term.setCursorPos(1, 16)
    term.write("Msg: " .. (active_field == "msg" and "> " or "") .. input_text)
    
    term.setCursorPos(1, 18)
    term.setTextColor(colors.yellow)
    print("[ SEND ]  [ SWITCH FIELD ]")
    term.setTextColor(colors.white)
end

-- Авто-подключение к серверу
modem.transmit(SERVER_ID, PORT, {type = "handshake", user = username})

while true do
    draw_gui()
    local event, p1, p2, p3, p4, p5 = os.pullEvent()
    
    if event == "mouse_click" then
        local x, y = p2, p3
        if y == 18 then
            if x <= 8 then -- Нажата кнопка SEND
                modem.transmit(SERVER_ID, PORT, {
                    type = "send",
                    user = username,
                    to = input_to,
                    text = input_text
                })
                input_text = ""
            elseif x >= 11 then -- SWITCH
                active_field = (active_field == "to") and "msg" or "to"
            end
        end
        
    elseif event == "char" then
        if active_field == "to" then input_to = input_to .. p1
        else input_text = input_text .. p1 end
        
    elseif event == "key" then
        if p1 == keys.backspace then
            if active_field == "to" then input_to = input_to:sub(1, -2)
            else input_text = input_text:sub(1, -2) end
        end
        
    elseif event == "modem_message" then
        local msg = p4
        if msg.type == "msg" then
            local decoded = decrypt(msg.text, 5)
            table.insert(messages, "["..msg.from.."]: "..decoded)
        elseif msg.type == "ack" then
            table.insert(messages, "Server: Msg "..msg.id.." Delivered")
        end
    end
end
