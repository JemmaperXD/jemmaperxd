-- ============================================
-- Мессенджер для ComputerCraft: Tweaked
-- Клиентская часть с GUI
-- ============================================

-- Настройки
local PROTOCOL = "messenger_v2"
local RECONNECT_INTERVAL = 5 -- секунд между попытками переподключения
local UPDATE_INTERVAL = 2 -- секунд между обновлениями данных
local MAX_MESSAGE_LENGTH = 256

-- Глобальные переменные
local clientName = "Гость"
local modemSide = nil
local serverId = nil
local serverName = "Неизвестно"
local running = true
local connected = false

-- Данные GUI
local contacts = {} -- Список контактов {id, name}
local selectedContact = 1 -- Индекс выбранного контакта
local messages = {} -- История сообщений по контактам {[contactId] = {messages}}
local inputBuffer = "" -- Текст в поле ввода
local scrollOffset = 0 -- Смещение для прокрутки истории
local contactScrollOffset = 0 -- Смещение для прокрутки контактов

-- Вспомогательные функции
local function log(message)
    local time = os.time()
    local formattedTime = textutils.formatTime(time, false)
    print("[" .. formattedTime .. "] " .. message)
end

local function findModem()
    -- Поиск модема на всех сторонах
    local sides = {"top", "bottom", "left", "right", "front", "back"}
    
    for _, side in ipairs(sides) do
        if peripheral.getType(side) == "modem" then
            if peripheral.wrap(side).isWireless() then
                return side
            end
        end
    end
    
    return nil
end

local function findServer()
    log("Поиск сервера...")
    local servers = rednet.lookup(PROTOCOL)
    
    if servers and #servers > 0 then
        serverId = servers[1]
        
        -- Получаем имя сервера
        rednet.send(serverId, textutils.serialize({type = "ping"}), PROTOCOL)
        local sender, response = rednet.receive(PROTOCOL, 2)
        
        if response then
            local data = textutils.unserialize(response)
            if data and data.type == "pong" then
                -- Пробуем получить имя через запрос списка
                rednet.send(serverId, textutils.serialize({type = "get_online"}), PROTOCOL)
                sender, response = rednet.receive(PROTOCOL, 2)
                
                if response then
                    data = textutils.unserialize(response)
                    if data and data.serverName then
                        serverName = data.serverName
                    end
                end
                
                return true
            end
        end
    end
    
    return false
end

local function connectToServer()
    if not modemSide then
        return false, "Не найден модем"
    end
    
    -- Открываем модем
    if not rednet.isOpen(modemSide) then
        rednet.open(modemSide)
    end
    
    -- Поиск сервера
    for i = 1, 3 do -- 3 попытки
        log("Попытка подключения " .. i .. "...")
        if findServer() then
            -- Регистрация на сервере
            local request = {
                type = "register",
                name = clientName
            }
            
            rednet.send(serverId, textutils.serialize(request), PROTOCOL)
            local sender, response = rednet.receive(PROTOCOL, 5)
            
            if response then
                local data = textutils.unserialize(response)
                if data and data.type == "register_response" and data.success then
                    serverName = data.serverName or serverName
                    connected = true
                    log("Подключено к серверу: " .. serverName)
                    return true
                end
            end
        end
        
        sleep(1)
    end
    
    return false, "Не удалось подключиться к серверу"
end

local function disconnect()
    connected = false
    serverId = nil
    if modemSide and rednet.isOpen(modemSide) then
        rednet.close(modemSide)
    end
end

local function sendRequest(request)
    if not connected or not serverId then
        return nil
    end
    
    rednet.send(serverId, textutils.serialize(request), PROTOCOL)
    local sender, response = rednet.receive(PROTOCOL, 5)
    
    if response and sender == serverId then
        return textutils.unserialize(response)
    end
    
    return nil
end

local function updateContacts()
    if not connected then return end
    
    local response = sendRequest({type = "get_online"})
    if response and response.type == "online_list" then
        contacts = {}
        for _, client in ipairs(response.clients) do
            table.insert(contacts, {
                id = client.id,
                name = client.name
            })
        end
        
        -- Сортируем по имени
        table.sort(contacts, function(a, b)
            return a.name:lower() < b.name:lower()
        end)
        
        return true
    end
    
    return false
end

local function updateMessages()
    if not connected then return {} end
    
    local response = sendRequest({type = "get_messages"})
    if response and response.type == "messages" then
        local newMessages = response.messages or {}
        
        -- Распределяем сообщения по контактам
        for _, msg in ipairs(newMessages) do
            local contactId = msg.sender
            if contactId == os.getComputerID() then
                contactId = msg.target
            end
            
            if not messages[contactId] then
                messages[contactId] = {}
            end
            
            table.insert(messages[contactId], msg)
            
            -- Звуковое уведомление (если есть динамик)
            if peripheral.find("speaker") and msg.sender ~= os.getComputerID() then
                peripheral.call("speaker", "playNote", "bell", 1)
            end
        end
        
        return newMessages
    end
    
    return {}
end

local function sendMessage(targetId, messageText)
    if not connected or not targetId or messageText == "" then
        return false
    end
    
    if #messageText > MAX_MESSAGE_LENGTH then
        messageText = messageText:sub(1, MAX_MESSAGE_LENGTH)
    end
    
    local request = {
        type = "send_message",
        target = targetId,
        message = messageText,
        senderName = clientName
    }
    
    local response = sendRequest(request)
    if response and response.type == "message_response" and response.success then
        -- Добавляем сообщение в локальную историю
        local msg = {
            sender = os.getComputerID(),
            senderName = clientName,
            target = targetId,
            message = messageText,
            time = os.epoch("utc")
        }
        
        if not messages[targetId] then
            messages[targetId] = {}
        end
        table.insert(messages[targetId], msg)
        
        return true
    end
    
    return false
end

-- GUI функции
local function drawStatusBar()
    local w, h = term.getSize()
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    term.clearLine()
    
    local statusText = "Мессенджер | " .. clientName
    local serverStatus = connected and "ONLINE" or "OFFLINE"
    local serverColor = connected and colors.green or colors.red
    
    term.setCursorPos(1, 1)
    term.write(statusText)
    
    term.setCursorPos(w - #serverStatus - 2, 1)
    term.write("[" .. serverStatus .. "]")
    
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

local function drawContacts()
    local w, h = term.getSize()
    local contactWidth = math.floor(w * 0.2) -- 20% ширины
    local contactHeight = h - 3 -- Высота минус статусная строка и поле ввода
    
    -- Рисуем фон списка контактов
    term.setBackgroundColor(colors.gray)
    for y = 2, contactHeight + 1 do
        term.setCursorPos(1, y)
        term.write(string.rep(" ", contactWidth))
    end
    
    -- Заголовок контактов
    term.setCursorPos(1, 2)
    term.setTextColor(colors.white)
    term.setBackgroundColor(colors.blue)
    local title = " Контакты (" .. #contacts .. ") "
    term.write(title .. string.rep(" ", contactWidth - #title))
    
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    
    -- Рисуем контакты
    local startIndex = contactScrollOffset + 1
    local endIndex = math.min(startIndex + contactHeight - 3, #contacts)
    
    for i = startIndex, endIndex do
        local contact = contacts[i]
        local y = i - startIndex + 4
        
        if i == selectedContact then
            term.setBackgroundColor(colors.lightBlue)
            term.setTextColor(colors.black)
        else
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
        end
        
        term.setCursorPos(1, y)
        local displayName = contact.name
        if #displayName > contactWidth - 7 then
            displayName = displayName:sub(1, contactWidth - 10) .. "..."
        end
        
        local line = " " .. displayName .. " "
        term.write(line .. string.rep(" ", contactWidth - #line))
    end
    
    -- Очищаем оставшиеся строки
    term.setBackgroundColor(colors.gray)
    for y = endIndex - startIndex + 5, contactHeight + 1 do
        term.setCursorPos(1, y)
        term.write(string.rep(" ", contactWidth))
    end
    
    -- Полоса прокрутки контактов
    if #contacts > contactHeight - 3 then
        local scrollbarHeight = contactHeight - 3
        local scrollbarPos = math.floor(contactScrollOffset / #contacts * scrollbarHeight)
        
        for y = 3, contactHeight + 1 do
            term.setCursorPos(contactWidth, y)
            if y == scrollbarPos + 3 then
                term.setBackgroundColor(colors.lightGray)
                term.write("█")
            else
                term.setBackgroundColor(colors.gray)
                term.write("│")
            end
        end
    end
end

local function drawChat()
    local w, h = term.getSize()
    local contactWidth = math.floor(w * 0.2)
    local chatWidth = w - contactWidth
    local chatHeight = h - 4 -- Высота минус статусная строка, заголовок и поле ввода
    
    -- Очищаем область чата
    term.setBackgroundColor(colors.black)
    for y = 2, chatHeight + 2 do
        term.setCursorPos(contactWidth + 1, y)
        term.write(string.rep(" ", chatWidth))
    end
    
    -- Заголовок чата
    if #contacts > 0 then
        local contact = contacts[selectedContact]
        term.setBackgroundColor(colors.purple)
        term.setTextColor(colors.white)
        term.setCursorPos(contactWidth + 1, 2)
        local title = " Чат с " .. contact.name .. " "
        term.write(title .. string.rep(" ", chatWidth - #title))
    else
        term.setBackgroundColor(colors.purple)
        term.setTextColor(colors.white)
        term.setCursorPos(contactWidth + 1, 2)
        local title = " Нет контактов "
        term.write(title .. string.rep(" ", chatWidth - #title))
    end
    
    -- Рисуем сообщения
    if #contacts > 0 then
        local contact = contacts[selectedContact]
        local chatMessages = messages[contact.id] or {}
        
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.white)
        
        local startIndex = math.max(1, #chatMessages - chatHeight + scrollOffset + 1)
        local endIndex = #chatMessages - scrollOffset
        
        for i = startIndex, endIndex do
            local msg = chatMessages[i]
            if not msg then break end
            
            local y = chatHeight - (endIndex - i) + 2
            if y > 2 then
                term.setCursorPos(contactWidth + 1, y)
                
                -- Форматируем время
                local timeStr = os.date("%H:%M", msg.time / 1000)
                
                -- Определяем цвет и выравнивание
                local isOwn = msg.sender == os.getComputerID()
                
                if isOwn then
                    term.setTextColor(colors.green)
                    term.write("[" .. timeStr .. "] Вы: ")
                else
                    term.setTextColor(colors.cyan)
                    term.write("[" .. timeStr .. "] " .. msg.senderName .. ": ")
                end
                
                term.setTextColor(colors.white)
                
                -- Выводим текст сообщения
                local prefixLength = #timeStr + #msg.senderName + 5
                local maxLineLength = chatWidth - 2
                
                -- Перенос длинных сообщений
                local messageText = msg.message
                local lineStart = 1
                local lineNum = 0
                
                while lineStart <= #messageText do
                    if lineNum > 0 then
                        y = y + 1
                        if y > chatHeight + 2 then break end
                        term.setCursorPos(contactWidth + 1, y)
                        term.write(string.rep(" ", prefixLength))
                    end
                    
                    local lineEnd = math.min(lineStart + maxLineLength - (lineNum == 0 and prefixLength or 0) - 1, #messageText)
                    local line = messageText:sub(lineStart, lineEnd)
                    
                    if lineNum == 0 then
                        term.setCursorPos(contactWidth + 1 + prefixLength, y)
                    else
                        term.setCursorPos(contactWidth + 1, y)
                    end
                    
                    term.write(line)
                    lineStart = lineEnd + 1
                    lineNum = lineNum + 1
                end
            end
        end
    end
    
    -- Полоса прокрутки чата
    if #contacts > 0 then
        local contact = contacts[selectedContact]
        local chatMessages = messages[contact.id] or {}
        
        if #chatMessages > chatHeight then
            local scrollbarHeight = chatHeight
            local scrollbarPos = math.floor(scrollOffset / #chatMessages * scrollbarHeight)
            
            for y = 3, chatHeight + 2 do
                term.setCursorPos(w, y)
                if y == scrollbarPos + 3 then
                    term.setBackgroundColor(colors.lightGray)
                    term.write("█")
                else
                    term.setBackgroundColor(colors.black)
                    term.write("│")
                end
            end
        end
    end
end

local function drawInput()
    local w, h = term.getSize()
    local inputHeight = 3
    
    -- Рисуем поле ввода
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    
    -- Разделитель
    for x = 1, w do
        term.setCursorPos(x, h - inputHeight)
        term.write("─")
    end
    
    -- Поле ввода
    term.setCursorPos(1, h - inputHeight + 1)
    term.write("> ")
    
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    
    -- Отображаем буфер ввода
    local displayText = inputBuffer
    local maxLength = w - 3
    
    if #displayText > maxLength then
        displayText = "..." .. displayText:sub(-maxLength + 3)
    end
    
    term.write(displayText)
    
    -- Курсор
    local cursorPos = math.min(#inputBuffer + 1, maxLength + 1)
    term.setCursorPos(2 + cursorPos, h - inputHeight + 1)
    
    -- Подсказка в последней строке
    term.setCursorPos(1, h)
    term.clearLine()
    term.write("Enter: отправить | Стрелки: выбор | Ctrl+T: выход")
end

local function drawGUI()
    term.clear()
    drawStatusBar()
    drawContacts()
    drawChat()
    drawInput()
end

local function handleInput()
    while running do
        local event, param1, param2, param3 = os.pullEvent()
        
        if event == "key" then
            local key = param1
            
            if key == keys.enter then
                -- Отправка сообщения
                if #contacts > 0 and inputBuffer ~= "" then
                    local contact = contacts[selectedContact]
                    if sendMessage(contact.id, inputBuffer) then
                        inputBuffer = ""
                        scrollOffset = 0
                        drawChat()
                        drawInput()
                    end
                end
                
            elseif key == keys.backspace then
                -- Удаление символа
                inputBuffer = inputBuffer:sub(1, -2)
                drawInput()
                
            elseif key == keys.up then
                -- Выбор предыдущего контакта
                if #contacts > 0 then
                    selectedContact = math.max(1, selectedContact - 1)
                    
                    -- Прокрутка списка контактов
                    local w, h = term.getSize()
                    local contactHeight = h - 3
                    local visibleContacts = contactHeight - 3
                    
                    if selectedContact < contactScrollOffset + 1 then
                        contactScrollOffset = math.max(0, selectedContact - 1)
                    end
                    
                    scrollOffset = 0
                    drawContacts()
                    drawChat()
                end
                
            elseif key == keys.down then
                -- Выбор следующего контакта
                if #contacts > 0 then
                    selectedContact = math.min(#contacts, selectedContact + 1)
                    
                    -- Прокрутка списка контактов
                    local w, h = term.getSize()
                    local contactHeight = h - 3
                    local visibleContacts = contactHeight - 3
                    
                    if selectedContact > contactScrollOffset + visibleContacts then
                        contactScrollOffset = selectedContact - visibleContacts
                    end
                    
                    scrollOffset = 0
                    drawContacts()
                    drawChat()
                end
                
            elseif key == keys.pageUp then
                -- Прокрутка чата вверх
                scrollOffset = math.min(scrollOffset + 5, 1000)
                drawChat()
                
            elseif key == keys.pageDown then
                -- Прокрутка чата вниз
                scrollOffset = math.max(0, scrollOffset - 5)
                drawChat()
            end
            
        elseif event == "char" then
            -- Ввод текста
            if #inputBuffer < MAX_MESSAGE_LENGTH then
                inputBuffer = inputBuffer .. param1
                drawInput()
            end
            
        elseif event == "mouse_click" then
            local button = param1
            local x, y = param2, param3
            
            local w, h = term.getSize()
            local contactWidth = math.floor(w * 0.2)
            
            -- Клик по списку контактов
            if x >= 1 and x <= contactWidth and y >= 4 and y <= h - 3 then
                local contactIndex = y - 4 + contactScrollOffset + 1
                if contactIndex <= #contacts then
                    selectedContact = contactIndex
                    scrollOffset = 0
                    drawContacts()
                    drawChat()
                end
                
            -- Клик по полю ввода
            elseif y == h - 2 then
                -- Фокус на поле ввода
                drawInput()
            end
            
        elseif event == "mouse_scroll" then
            local direction = param1
            local x, y = param2, param3
            
            local w, h = term.getSize()
            local contactWidth = math.floor(w * 0.2)
            
            -- Скролл в списке контактов
            if x >= 1 and x <= contactWidth then
                local maxScroll = math.max(0, #contacts - (h - 6))
                if direction > 0 then
                    contactScrollOffset = math.max(0, contactScrollOffset - 1)
                else
                    contactScrollOffset = math.min(maxScroll, contactScrollOffset + 1)
                end
                drawContacts()
                
            -- Скролл в чате
            elseif x > contactWidth then
                if direction > 0 then
                    scrollOffset = math.min(scrollOffset + 1, 1000)
                else
                    scrollOffset = math.max(0, scrollOffset - 1)
                end
                drawChat()
            end
            
        elseif event == "terminate" then
            running = false
            break
        end
    end
end

local function updateData()
    while running do
        sleep(UPDATE_INTERVAL)
        
        -- Проверка соединения
        if connected then
            local success = pcall(function()
                -- Обновляем контакты
                if updateContacts() then
                    -- Обновляем выбранный контакт, если текущий удален
                    if #contacts > 0 and selectedContact > #contacts then
                        selectedContact = #contacts
                    elseif #contacts == 0 then
                        selectedContact = 1
                    end
                end
                
                -- Получаем новые сообщения
                local newMessages = updateMessages()
                if #newMessages > 0 then
                    -- Перерисовываем чат, если новые сообщения для текущего контакта
                    local needRedraw = false
                    for _, msg in ipairs(newMessages) do
                        local contactId = msg.sender
                        if contactId == os.getComputerID() then
                            contactId = msg.target
                        end
                        
                        if #contacts > 0 then
                            local contact = contacts[selectedContact]
                            if contact and contact.id == contactId then
                                needRedraw = true
                                break
                            end
                        end
                    end
                    
                    if needRedraw then
                        drawChat()
                    end
                    
                    -- Обновляем список контактов
                    drawContacts()
                end
                
                -- Пинг сервера для поддержания соединения
                sendRequest({type = "ping"})
            end)
            
            if not success then
                connected = false
                log("Потеряно соединение с сервером")
                drawStatusBar()
            end
        else
            -- Попытка переподключения
            local success, err = connectToServer()
            if success then
                drawStatusBar()
                updateContacts()
                drawContacts()
                drawChat()
            end
        end
    end
end

local function printHelp()
    print("Использование: client [опции]")
    print("Опции:")
    print("  -n, --name <имя>   Имя клиента")
    print("  -m, --modem <сторона> Сторона модема")
    print("  -h, --help        Показать эту справку")
    print()
    print("Примеры:")
    print("  client --name \"Игрок1\"")
    print("  client -n \"Игрок2\" -m left")
end

local function parseArguments()
    local args = {...}
    local i = 1
    while i <= #args do
        local arg = args[i]
        
        if arg == "-n" or arg == "--name" then
            i = i + 1
            if args[i] then
                clientName = args[i]
            end
        elseif arg == "-m" or arg == "--modem" then
            i = i + 1
            if args[i] then
                modemSide = args[i]
            end
        elseif arg == "-h" or arg == "--help" then
            printHelp()
            return false
        end
        
        i = i + 1
    end
    
    return true
end

-- Основная функция
local function main()
    -- Обработка аргументов командной строки
    if not parseArguments() then
        return
    end
    
    -- Поиск модема
    if not modemSide then
        modemSide = findModem()
    end
    
    if not modemSide then
        print("Не найден беспроводной модем!")
        print("Доступные стороны: top, bottom, left, right, front, back")
        print("Укажите сторону через --modem <сторона>")
        return
    end
    
    -- Подключение к сервере
    log("Запуск клиента...")
    log("Имя: " .. clientName)
    log("Модем: " .. modemSide)
    
    local success, err = connectToServer()
    if not success then
        print("Ошибка: " .. (err or "неизвестная ошибка"))
        print("Проверьте, запущен ли сервер и доступен ли модем")
        return
    end
    
    -- Загрузка начальных данных
    updateContacts()
    
    -- Настройка терминала
    term.clear()
    term.setCursorPos(1, 1)
    
    -- Запуск потоков
    parallel.waitForAny(
        function() handleInput() end,
        function() updateData() end
    )
    
    -- Корректное завершение
    disconnect()
    term.clear()
    term.setCursorPos(1, 1)
    print("Клиент завершен.")
end

-- Обработка ошибок
local ok, err = pcall(main)
if not ok then
    term.clear()
    term.setCursorPos(1, 1)
    print("Ошибка в клиенте: " .. err)
    print("Подробности: " .. debug.traceback())
    sleep(5)
end
