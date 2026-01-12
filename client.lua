-- client.lua
-- Клиент для "телеграмма" на CC:Tweaked
-- Автонаход имени пользователя из /.user/* (первый найденный)
-- Регистрируется у сервера на канале 1384
-- Слушает на собственном вычисленном канале
-- От сервера приходят зашифрованные сообщения (XOR с server_key)

local server_channel = 1384
local server_address_channel = 1384
local server_key = "s3rv3r_secret_key" -- должен совпадать с сервером
local modem = peripheral.find("modem")
if not modem then error("No modem peripheral found") end

local json = textutils.serialize and {
    encode = function(t) return textutils.serialize(t) end,
    decode = function(s) return textutils.unserialize(s) end
} or error("No textutils.serialize present")

-- Нахождение имени пользователя по /.user/*
local function detect_username()
    local root = "/.user"
    if not fs.exists(root) or not fs.isDir(root) then
        -- Если нет каталога, создать и предложить имя
        pcall(fs.makeDir, root)
        -- оставить имя пустым, пользователь должен создать файл
        return nil
    end
    local list = fs.list(root)
    for _, v in ipairs(list) do
        return v -- первый найденный — имя
    end
    return nil
end

local function compute_channel_from_name(name)
    -- стабильное вычисление канала из имени (1..65535)
    local h = 0
    for i = 1, #name do
        h = (h * 31 + name:byte(i)) % 60000
    end
    return (h % 60000) + 1024 -- убедиться, что >1024
end

local function xor_crypt(data, key)
    local out = {}
    for i = 1, #data do
        local a = data:byte(i)
        local b = key:byte(((i-1) % #key) + 1)
        out[i] = string.char(bit32.bxor(a, b))
    end
    return table.concat(out)
end

-- GUI: небольшое окно с полями: to, text, send button, inbox list
local termw, termh = term.getSize()
local username = detect_username()
if not username then
    print("No user detected in /.user/. Please create a folder or file inside /.user with your username as name.")
    return
end
local my_channel = compute_channel_from_name(username)
modem.open(my_channel)

-- Регистрация у сервера
local function register_at_server()
    local payload = {type="register", username=username, channel=my_channel}
    modem.transmit(server_channel, my_channel, json.encode(payload))
end

register_at_server()

-- Локальные структуры
local inbox = {} -- список сообщений {id, from, text, received_time}
local sent = {} -- список отправленных {id, to, text, status}

-- Отправка сообщения серверу
local function send_message(to, text)
    local payload = {type="send", to=to, from=username, text=text}
    modem.transmit(server_channel, my_channel, json.encode(payload))
    -- локальная запись (ID сервер назначит, но мы сохраняем попытку)
    table.insert(sent, {id="pending", to=to, text=text, status="sent"})
end

-- Приём сообщений
local function handle_incoming_deliver(payload)
    -- payload: {type="deliver", id=..., from=..., data=...}
    if not payload.id or not payload.from or not payload.data then return end
    local decrypted = xor_crypt(payload.data, server_key)
    table.insert(inbox, 1, {id=payload.id, from=payload.from, text=decrypted, received_time=os.time()})
    -- отправить ACK серверу
    local ack = {type="ack", id=payload.id}
    modem.transmit(server_channel, my_channel, json.encode(ack))
end

local function handle_reg_ack(payload)
    -- просто печать
    -- payload: {type="reg_ack", msg="ok"}
    -- nop
end

local function handle_stats(payload)
    -- nop or display later
end

-- Простейший GUI: режимы: inbox view, compose
local mode = "inbox" -- или "compose"
local compose_to = ""
local compose_text = ""
local cursor_pos = 1

local function draw_ui()
    term.clear()
    term.setCursorPos(1,1)
    print("MiniChat Client - user: " .. username .. " (channel " .. tostring(my_channel) .. ")")
    print("Server channel: " .. tostring(server_channel))
    print("Mode: " .. mode)
    if mode == "inbox" then
        print("Inbox (" .. tostring(#inbox) .. "):")
        local limit = math.min(10, #inbox)
        for i = 1, limit do
            local m = inbox[i]
            print(string.format("[%s] %s: %s", m.id, m.from, m.text))
        end
        print("")
        print("Commands: (c) compose, (r) register, (s) stats request, (q) quit")
    else
        print("Compose message")
        print("To: " .. compose_to)
        print("Text: " .. compose_text)
        print("")
        print("Commands: (enter) send, (esc) cancel, (q) quit")
    end
end

draw_ui()

-- Обработчик событий модема и клавиатуры/мыши
local running = true
local function event_loop()
    while running do
        draw_ui()
        local ev = {os.pullEvent()}
        if ev[1] == "modem_message" then
            local side, senderChannel, replyChannel, message, distance = ev[2], ev[3], ev[4], ev[5], ev[6]
            local ok, payload = pcall(json.decode, message)
            if ok and type(payload) == "table" then
                if payload.type == "deliver" then
                    handle_incoming_deliver(payload)
                elseif payload.type == "reg_ack" then
                    handle_reg_ack(payload)
                elseif payload.type == "stats" then
                    handle_stats(payload)
                end
            end
        elseif ev[1] == "key" then
            local key = ev[2]
            if key == keys.q then
                running = false
            elseif key == keys.c and mode == "inbox" then
                mode = "compose"
                compose_to = ""
                compose_text = ""
            elseif key == keys.r and mode == "inbox" then
                register_at_server()
            elseif key == keys.s and mode == "inbox" then
                -- попросить статистику у сервера
                local req = {type="req_stats", reply_channel=my_channel}
                modem.transmit(server_channel, my_channel, json.encode(req))
            elseif mode == "compose" then
                if key == keys.backspace then
                    if #compose_text > 0 then
                        compose_text = compose_text:sub(1, -2)
                    end
                elseif key == keys.enter then
                    if compose_to ~= "" and compose_text ~= "" then
                        send_message(compose_to, compose_text)
                        mode = "inbox"
                    end
                elseif key == keys.escape then
                    mode = "inbox"
                end
            end
        elseif ev[1] == "char" then
            local ch = ev[2]
            if mode == "compose" then
                -- простая логика: если to пуст, вводим to до символ ':' и потом текст после newline
                if compose_to == "" then
                    -- допустим разделитель - пробел+">" нельзя, сделаем: нажмите tab чтобы перейти к тексту
                    -- Для простоты: если нажата табуляция, переходим к тексту
                    if ch == "\t" then
                        -- noop
                    else
                        -- если пока нет ':' в compose_to, то заполняем to until newline
                        compose_to = compose_to .. ch
                    end
                else
                    compose_text = compose_text .. ch
                end
            end
        elseif ev[1] == "mouse_click" then
            -- простая мышевая поддержка: клик в верхней части переключает режим
            local x,y,button = ev[3], ev[4], ev[2]
            -- но CC:event формат: "mouse_click", button, x, y
            local bx, by = ev[2], ev[3] -- консервативный вариант (в зависимости от версии)
            -- не усложняем; GUI реагирует на клавиши
        end
    end
end

-- Асинхронный цикл обработки модем сообщений в параллели был бы лучше,
-- но в этой реализации мы используем единый event loop, который реагирует также на modem_message.

event_loop()
print("Client exiting.")
