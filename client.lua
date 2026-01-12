-- Клиент мессенджера с GUI
local VERSION = "1.0"
local SERVER_ID = nil -- Задается при запуске
local MODEM_SIDE = "back"
local PING_INTERVAL = 10 -- секунд

-- Проверка аргументов
if not arg[1] then
    print("Использование: client <ID_сервера>")
    print("Пример: client 42")
    return
end

SERVER_ID = tonumber(arg[1])
if not SERVER_ID then
    print("Ошибка: неверный ID сервера")
    return
end

-- Инициализация
print("=== Клиент мессенджера v" .. VERSION .. " ===")
print("Подключение к серверу " .. SERVER_ID .. "...")

local modem = peripheral.find("modem")
if not modem then
    error("Не найден модем!")
end

rednet.open(MODEM_SIDE)
term.clear()

-- Состояние приложения
local state = {
    username = os.getComputerLabel() or "User" .. os.getComputerID(),
    messages = {},
    contacts = {},
    currentContact = nil,
    connected = false,
    lastPing = 0
}

-- GUI константы
local WIDTH, HEIGHT = term.getSize()
local INPUT_HEIGHT = 3
local CONTACTS_WIDTH = 20
local MESSAGES_X = CONTACTS_WIDTH + 2

-- GUI элементы
local gui = {
    contactsList = {},
    messageList = {},
    inputText = "",
    selectedContact = 1,
    scrollOffset = 0,
    inputScroll = 0
}

-- Функции сети
function sendRequest(request)
    rednet.send(SERVER_ID, request, "messenger_server")
    
    local senderId, response, protocol = rednet.receive("messenger_server", 3)
    
    if senderId == SERVER_ID and protocol == "messenger_server" then
        return response
    end
    
    return nil
end

function connectToServer()
    local response = sendRequest({
        type = "register",
        name = state.username
    })
    
    if response and response.success then
        state.connected = true
        return true
    end
    
    return false
end

function sendMessage(targetId, message)
    local response = sendRequest({
        type = "send_message",
        target = targetId,
        message = message,
        senderName = state.username
    })
    
    return response and response.success or false
end

function updateContacts()
    local response = sendRequest({
        type = "get_online"
    })
    
    if response and response.clients then
        state.contacts = response.clients
        return true
    end
    
    return false
end

function getNewMessages()
    local response = sendRequest({
        type = "get_messages"
    })
    
    if response and response.messages then
        for _, msg in ipairs(response.messages) do
            table.insert(state.messages, msg)
        end
        return true
    end
    
    return false
end

function sendPing()
    sendRequest({
        type = "ping"
    })
    state.lastPing = os.clock()
end

-- GUI функции
function drawBorder()
    term.setBackgroundColor(colors.blue)
    term.setTextColor(colors.white)
    
    -- Верхняя панель
    term.setCursorPos(1, 1)
    term.write(string.rep(" ", WIDTH))
    term.setCursorPos(2, 1)
    term.write("Мессенджер - " .. state.username)
    
    if state.connected then
        term.setCursorPos(WIDTH - 10, 1)
        term.write("ONLINE ")
    else
        term.setCursorPos(WIDTH - 10, 1)
        term.write("OFFLINE")
    end
    
    -- Разделители
    for y = 2, HEIGHT - INPUT_HEIGHT do
        term.setCursorPos(CONTACTS_WIDTH + 1, y)
        term.write("│")
    end
    
    -- Нижняя панель ввода
    term.setCursorPos(1, HEIGHT - INPUT_HEIGHT + 1)
    term.write(string.rep("─", WIDTH))
    
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

function drawContacts()
    term.setBackgroundColor(colors.gray)
    term.setTextColor(colors.white)
    
    for i = 1, HEIGHT - INPUT_HEIGHT - 1 do
        term.setCursorPos(1, i + 1)
        term.write(string.rep(" ", CONTACTS_WIDTH))
    end
    
    term.setCursorPos(2, 2)
    term.write("Контакты:")
    
    local startIdx = gui.scrollOffset
    local maxVisible = HEIGHT - INPUT_HEIGHT - 2
    
    for i = 1, math.min(#state.contacts, maxVisible) do
        local idx = i + startIdx
        if idx <= #state.contacts then
            local contact = state.contacts[idx]
            local y = i + 2
            
            if i == gui.selectedContact - startIdx then
                term.setBackgroundColor(colors.lightBlue)
                term.setTextColor(colors.black)
            else
                term.setBackgroundColor(colors.gray)
                term.setTextColor(colors.white)
            end
            
            term.setCursorPos(2, y)
            local displayName = string.sub(contact.name, 1, CONTACTS_WIDTH - 3)
            if #contact.name > CONTACTS_WIDTH - 3 then
                displayName = displayName .. "..."
            end
            term.write(displayName)
            
            -- Индикатор новых сообщений
            local hasNew = false
            for _, msg in ipairs(state.messages) do
                if msg.sender == contact.id and not msg.read then
                    hasNew = true
                    break
                end
            end
            
            if hasNew then
                term.setCursorPos(CONTACTS_WIDTH - 1, y)
                term.write("●")
            end
        end
    end
    
    -- Скроллбар
    if #state.contacts > maxVisible then
        local barHeight = math.floor(maxVisible * maxVisible / #state.contacts)
        local barPos = math.floor(gui.scrollOffset * maxVisible / #state.contacts)
        
        for i = 1, barHeight do
            term.setCursorPos(CONTACTS_WIDTH, 2 + barPos + i)
            term.write("▐")
        end
    end
    
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
end

function drawMessages()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    
    for y = 2, HEIGHT - INPUT_HEIGHT do
        term.setCursorPos(MESSAGES_X, y)
        term.write(string.rep(" ", WIDTH - MESSAGES_X))
    end
    
    if not state.currentContact then
        term.setCursorPos(MESSAGES_X + 5, HEIGHT / 2)
        term.write("Выберите контакт для общения")
        return
    end
    
    -- Фильтруем сообщения для текущего контакта
    local contactMessages = {}
    for _, msg in ipairs(state.messages) do
        if msg.sender == state.currentContact or 
           (msg.target == state.currentContact and msg.sender == os.getComputerID()) then
            table.insert(contactMessages, msg)
        end
    end
    
    -- Отображаем сообщения
    local startY = HEIGHT - INPUT_HEIGHT - 1
    local msgIndex = #contactMessages
    
    for y = startY, 2, -1 do
        if msgIndex < 1 then break end
        
        local msg = contactMessages[msgIndex]
        local isOwn = msg.sender == os.getComputerID()
        
        -- Время
        local timeStr = os.date("%H:%M", msg.time / 1000)
        term.setCursorPos(WIDTH - 6, y)
        term.write(timeStr)
        
        -- Имя отправителя
        local name = isOwn and "Вы" or msg.senderName
        term.setCursorPos(MESSAGES_X, y)
        
        if isOwn then
            term.setTextColor(colors.green)
        else
            term.setTextColor(colors.yellow)
        end
        
        term.write(name .. ":")
        
        -- Сообщение
        term.setTextColor(colors.white)
        term.setCursorPos(MESSAGES_X, y + 1)
        
        local maxWidth = WIDTH - MESSAGES_X - 2
        local message = msg.message
        
        -- Перенос строк
        for line = 1, math.ceil(#message / maxWidth) do
            local start = (line - 1) * maxWidth + 1
            local text = string.sub(message, start, start + maxWidth - 1)
            term.write(text)
            
            if line < math.ceil(#message / maxWidth) then
                y = y + 1
                term.setCursorPos(MESSAGES_X, y + 1)
            end
        end
        
        msgIndex = msgIndex - 1
        y = y - math.ceil(#message / maxWidth)
    end
    
    term.setTextColor(colors.white)
end

function drawInput()
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    
    for y = HEIGHT - INPUT_HEIGHT + 2, HEIGHT do
        term.setCursorPos(1, y)
        term.write(string.rep(" ", WIDTH))
    end
    
    if state.currentContact then
        local contactName = "неизвестно"
        for _, c in ipairs(state.contacts) do
            if c.id == state.currentContact then
                contactName = c.name
                break
            end
        end
        
        term.setCursorPos(1, HEIGHT - INPUT_HEIGHT + 2)
        term.write("Сообщение для " .. contactName .. ":")
        
        -- Поле ввода
        term.setCursorPos(1, HEIGHT - 1)
        term.write("> ")
        
        -- Отображаем текст с учетом прокрутки
        local displayText = gui.inputText
        if #displayText > WIDTH - 3 then
            if gui.inputScroll > 0 then
                displayText = string.sub(displayText, gui.inputScroll + 1)
            end
            displayText = string.sub(displayText, 1, WIDTH - 3)
        end
        
        term.write(displayText)
        
        -- Курсор
        local cursorPos = #gui.inputText - gui.inputScroll + 2
        if cursorPos <= WIDTH then
            term.setCursorPos(cursorPos, HEIGHT - 1)
        end
    else
        term.setCursorPos(1, HEIGHT - 1)
        term.write("Выберите контакт для отправки сообщения")
    end
end

function drawUI()
    term.setBackgroundColor(colors.black)
    term.clear()
    
    drawBorder()
    drawContacts()
    drawMessages()
    drawInput()
    
    term.setCursorPos(1, HEIGHT)
end

function handleInput()
    while true do
        local event, key, x, y = os.pullEvent()
        
        if event == "key" then
            if y >= HEIGHT - 1 then -- Ввод текста
                if key == keys.enter then
                    if gui.inputText ~= "" and state.currentContact then
                        if sendMessage(state.currentContact, gui.inputText) then
                            table.insert(state.messages, {
                                sender = os.getComputerID(),
                                senderName = state.username,
                                target = state.currentContact,
                                message = gui.inputText,
                                time = os.epoch("utc")
                            })
                            gui.inputText = ""
                            gui.inputScroll = 0
                            drawUI()
                        end
                    end
                elseif key == keys.backspace then
                    if #gui.inputText > 0 then
                        gui.inputText = string.sub(gui.inputText, 1, -2)
                        if gui.inputScroll > 0 then
                            gui.inputScroll = math.max(0, gui.inputScroll - 1)
                        end
                        drawUI()
                    end
                end
            else -- Навигация в списке контактов
                if key == keys.up then
                    if gui.selectedContact > 1 then
                        gui.selectedContact = gui.selectedContact - 1
                        if gui.selectedContact <= gui.scrollOffset then
                            gui.scrollOffset = gui.scrollOffset - 1
                        end
                        state.currentContact = state.contacts[gui.selectedContact].id
                        drawUI()
                    end
                elseif key == keys.down then
                    if gui.selectedContact < #state.contacts then
                        gui.selectedContact = gui.selectedContact + 1
                        local maxVisible = HEIGHT - INPUT_HEIGHT - 2
                        if gui.selectedContact > gui.scrollOffset + maxVisible then
                            gui.scrollOffset = gui.scrollOffset + 1
                        end
                        state.currentContact = state.contacts[gui.selectedContact].id
                        drawUI()
                    end
                elseif key == keys.enter then
                    if state.contacts[gui.selectedContact] then
                        state.currentContact = state.contacts[gui.selectedContact].id
                        drawUI()
                    end
                end
            end
            
        elseif event == "char" then
            if y >= HEIGHT - 1 then
                gui.inputText = gui.inputText .. key
                if #gui.inputText > WIDTH - 3 then
                    gui.inputScroll = #gui.inputText - (WIDTH - 3)
                end
                drawUI()
            end
            
        elseif event == "mouse_click" then
            if x <= CONTACTS_WIDTH and y >= 2 and y <= HEIGHT - INPUT_HEIGHT then
                local contactIndex = y - 2 + gui.scrollOffset
                if contactIndex <= #state.contacts then
                    gui.selectedContact = contactIndex
                    state.currentContact = state.contacts[contactIndex].id
                    drawUI()
                end
            end
            
        elseif event == "mouse_scroll" then
            if x <= CONTACTS_WIDTH then
                gui.scrollOffset = math.max(0, 
                    math.min(#state.contacts - (HEIGHT - INPUT_HEIGHT - 2), 
                    gui.scrollOffset - key))
                drawUI()
            end
        end
    end
end

-- Основной цикл клиента
function main()
    -- Подключаемся к серверу
    if not connectToServer() then
        print("Ошибка подключения к серверу")
        return
    end
    
    print("Подключено. Загрузка GUI...")
    sleep(1)
    
    -- Начальная загрузка контактов
    updateContacts()
    
    if #state.contacts > 0 then
        state.currentContact = state.contacts[1].id
        gui.selectedContact = 1
    end
    
    -- Загружаем сообщения
    getNewMessages()
    
    -- Запускаем потоки
    parallel.waitForAny(
        function()
            -- Обновление данных
            while true do
                sleep(5) -- Обновляем каждые 5 секунд
                updateContacts()
                getNewMessages()
                
                -- Пинг каждые 10 секунд
                if os.clock() - state.lastPing > PING_INTERVAL then
                    sendPing()
                end
                
                drawUI()
            end
        end,
        
        function()
            -- Обработка ввода
            drawUI()
            handleInput()
        end
    )
end

-- Запуск
local ok, err = pcall(main)
if not ok then
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    print("Ошибка: " .. err)
end

rednet.close()
