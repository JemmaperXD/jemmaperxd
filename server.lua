-- Настройки
local PORT = 1384
local modem = peripheral.find("modem") or error("No modem found!")
modem.open(PORT)

local users = {} -- Список пользователей { [id] = name }
local logs = {}
local msg_count = 0

-- Функция шифрования (должна совпадать с клиентской)
local function encrypt(text, key)
    local res = ""
    for i = 1, #text do
        res = res .. string.char((text:byte(i) + key) % 256)
    end
    return res
end

-- Отрисовка статистики сервера
local function redraw()
    term.setBackgroundColor(colors.gray)
    term.clear()
    term.setCursorPos(1,1)
    term.setTextColor(colors.white)
    print(" === TG-SERVER 2026 ACTIVE ===")
    print(" ID: " .. os.getComputerID() .. " | Port: " .. PORT)
    print(string.rep("-", 30))
    
    -- Вывод последних 10 логов
    for i = math.max(1, #logs - 10), #logs do
        print(logs[i])
    end
end

redraw()

while true do
    local event, side, channel, replyChannel, message = os.pullEvent("modem_message")
    
    if channel == PORT and type(message) == "table" then
        -- 1. ОБРАБОТКА ПОДКЛЮЧЕНИЯ (HANDSHAKE / PING)
        if message.type == "handshake" or message.type == "ping" then
            users[replyChannel] = message.user
            
            -- Собираем список всех имен для клиента
            local online_names = {}
            for id, name in pairs(users) do
                table.insert(online_names, name)
            end
            
            -- ОТВЕТ КЛИЕНТУ (Чтобы он не выдал ошибку "Could not connect")
            modem.transmit(replyChannel, PORT, {
                type = "status",
                online = true,
                users = online_names
            })
            
        -- 2. ОБРАБОТКА ПЕРЕСЫЛКИ СООБЩЕНИЙ
        elseif message.type == "send" then
            msg_count = msg_count + 1
            local target_id = nil
            
            -- Ищем ID получателя по имени
            for id, name in pairs(users) do
                if name == message.to then
                    target_id = id
                    break
                end
            end
            
            if target_id then
                -- Шифруем сообщение перед отправкой (ключ 7 как в клиенте)
                local encrypted_text = encrypt(message.text, 7)
                
                modem.transmit(target_id, PORT, {
                    type = "msg",
                    from = message.user,
                    text = encrypted_text
                })
                
                table.insert(logs, string.format("[%03d] %s -> %s", msg_count, message.user, message.to))
            else
                table.insert(logs, string.format("FAIL: %s to %s (Offline)", message.user, message.to))
            end
            
            redraw()
        end
    end
end
