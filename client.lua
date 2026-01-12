local modem = peripheral.find("modem") or error("Modem not found", 0)
local serverChannel = 1384
local clientId = os.getComputerID()

modem.open(clientId)

-- Простой шифр Цезаря (для демонстрации)
local function encrypt(text, key)
    local result = ""
    for i = 1, #text do
        local char = string.byte(text, i)
        result = result .. string.char((char + key) % 256)
    end
    return result
end

local function decrypt(text, key)
    local result = ""
    for i = 1, #text do
        local char = string.byte(text, i)
        result = result .. string.char((char - key) % 256)
    end
    return result
end

local function sendMessage(to, text)
    modem.transmit(serverChannel, clientId, textutils.serialize({
        type = "send",
        to = to,
        text = text
    }))
    
    -- Ждем подтверждение отправки
    local timer = os.startTimer(5)
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "modem_message" and p2 == serverChannel then
            local data = textutils.unserialize(p1)
            if data.type == "sent" then
                print("Message sent! ID: " .. data.messageId)
                return data.messageId
            end
        elseif event == "timer" and p1 == timer then
            print("Timeout waiting for send confirmation")
            return nil
        end
    end
end

local function checkDeliveryStatus(messageId)
    modem.transmit(serverChannel, clientId, textutils.serialize({
        type = "get_status",
        messageId = messageId
    }))
    
    -- Ждем статус
    local timer = os.startTimer(5)
    while true do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "modem_message" and p2 == serverChannel then
            local data = textutils.unserialize(p1)
            if data.type == "status_report" and data.messageId == messageId then
                return data.status
            end
        elseif event == "timer" and p1 == timer then
            return "timeout"
        end
    end
end

local function sendDeliveryReport(messageId, from)
    modem.transmit(serverChannel, clientId, textutils.serialize({
        type = "delivery_report",
        messageId = messageId
    }))
    
    -- Подтверждаем получение отправителю
    modem.transmit(from, clientId, "Message received")
end

print("Telegram Client started")
print("Your ID: " .. clientId)
print("Commands:")
print("  send <id> <message> - Send message")
print("  status <id> - Check message status")
print("  exit - Exit program")

while true do
    local event, p1, p2, p3, p4, p5 = os.pullEvent()
    
    if event == "modem_message" then
        if p2 == serverChannel then
            local data = textutils.unserialize(p1)
            if data.type == "message" then
                -- Расшифровываем сообщение
                local decryptedText = decrypt(data.text, 5)
                print("New message from " .. data.from .. ": " .. decryptedText)
                
                -- Отправляем отчет о доставке
                sendDeliveryReport(data.messageId, data.from)
                
            elseif data.type == "sent" then
                print("Server confirmed message ID: " .. data.messageId)
                
            elseif data.type == "status_report" then
                print("Message " .. data.messageId .. " status: " .. data.status)
            end
        else
            -- Прямое сообщение о получении
            print("Delivery confirmed: " .. p1)
        end
        
    elseif event == "term_enter" then
        local input = p1
        local command = string.sub(input, 1, 4)
        
        if command == "send" then
            local _, _, to, text = string.find(input, "send (%d+) (.+)")
            if to and text then
                local messageId = sendMessage(tonumber(to), text)
                if messageId then
                    print("Message ID: " .. messageId)
                end
            else
                print("Usage: send <id> <message>")
            end
            
        elseif command == "stat" then
            local _, _, messageId = string.find(input, "status (%d+)")
            if messageId then
                local status = checkDeliveryStatus(tonumber(messageId))
                print("Status: " .. status)
            else
                print("Usage: status <id>")
            end
            
        elseif input == "exit" then
            break
        else
            print("Unknown command")
        end
    end
end
