local modem = peripheral.find("modem") or error("Modem not found", 0)
modem.open(1384)

-- Хранилище сообщений
local messages = {}
local messageCounter = 0

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

print("Telegram Server started on channel 1384")

while true do
    local event, side, channel, replyChannel, message, distance = os.pullEvent("modem_message")
    
    if channel == 1384 then
        local data = textutils.unserialize(message)
        
        if data.type == "send" then
            -- Создаем новое сообщение
            messageCounter = messageCounter + 1
            local msgId = messageCounter
            
            -- Шифруем сообщение
            local encryptedText = encrypt(data.text, 5)
            
            local newMessage = {
                id = msgId,
                from = replyChannel,
                to = data.to,
                text = encryptedText,
                timestamp = os.time(),
                delivered = false
            }
            
            table.insert(messages, newMessage)
            
            -- Отправляем подтверждение отправителю
            modem.transmit(replyChannel, 1384, textutils.serialize({
                type = "sent",
                messageId = msgId
            }))
            
            -- Отправляем сообщение получателю
            modem.transmit(data.to, 1384, textutils.serialize({
                type = "message",
                messageId = msgId,
                from = replyChannel,
                text = encryptedText
            }))
            
        elseif data.type == "delivery_report" then
            -- Обновляем статус доставки
            for i, msg in ipairs(messages) do
                if msg.id == data.messageId and msg.from == replyChannel then
                    msg.delivered = true
                    break
                end
            end
            
        elseif data.type == "get_status" then
            -- Возвращаем статус сообщения
            local status = "not_found"
            for i, msg in ipairs(messages) do
                if msg.id == data.messageId and msg.from == replyChannel then
                    status = msg.delivered and "delivered" or "sent"
                    break
                end
            end
            
            modem.transmit(replyChannel, 1384, textutils.serialize({
                type = "status_report",
                messageId = data.messageId,
                status = status
            }))
        end
    end
end
