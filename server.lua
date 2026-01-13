-- server.lua - Messenger V2 Server
local protocol = "messenger_v2"
local data_file = "server_data.dat"
local args = {...}

local server_data = {
    name = "Default Server",
    clients = {}, -- [id] = {name = string, lastSeen = timestamp}
    history = {}, -- { {sender, senderName, target, message, time}, ... }
    messages_queue = {} -- [targetID] = { {msg}, {msg} }
}

-- Утилиты
local function log(msg)
    print(("[%s] %s"):format(os.date("%H:%M:%S"), msg))
end

local function save_data()
    local f = fs.open(data_file, "w")
    f.write(textutils.serialize(server_data))
    f.close()
end

local function load_data()
    if fs.exists(data_file) then
        local f = fs.open(data_file, "r")
        server_data = textutils.unserialize(f.readAll())
        f.close()
        log("Data loaded from file.")
    end
end

-- Инициализация модема
local function init_modem(side)
    if side then
        if peripheral.getType(side) == "modem" then
            rednet.open(side)
            return side
        end
    else
        for _, s in ipairs(peripheral.getNames()) do
            if peripheral.getType(s) == "modem" and peripheral.call(s, "isWireless") then
                rednet.open(s)
                return s
            end
        end
    end
    return nil
end

-- Обработка аргументов
local modem_side = nil
for i=1, #args do
    if args[i] == "--side" or args[i] == "-s" then modem_side = args[i+1] end
    if args[i] == "--name" or args[i] == "-n" then server_data.name = args[i+1] end
end

local active_side = init_modem(modem_side)
if not active_side then
    error("No wireless modem found! Use --side <side>")
end

rednet.host(protocol, server_data.name)
load_data()
log("Server '" .. server_data.name .. "' started on ID " .. os.getComputerID())

-- Основной цикл обработки
local function handle_requests()
    while true do
        local id, msg = rednet.receive(protocol)
        if type(msg) == "table" then
            if msg.type == "register" then
                server_data.clients[id] = {name = msg.name, lastSeen = os.epoch("utc")}
                rednet.send(id, {type = "register_response", success = true, serverName = server_data.name}, protocol)
                log("Registered client: " .. msg.name .. " (" .. id .. ")")
                save_data()

            elseif msg.type == "get_online" then
                local list = {}
                for cid, cdata in pairs(server_data.clients) do
                    if os.epoch("utc") - cdata.lastSeen < 60000 then -- 1 min timeout
                        table.insert(list, {id = cid, name = cdata.name})
                    end
                end
                rednet.send(id, {type = "online_list", clients = list, serverName = server_data.name}, protocol)

            elseif msg.type == "send_message" then
                local packet = {
                    sender = id,
                    senderName = msg.senderName,
                    target = msg.target,
                    message = msg.message,
                    time = os.epoch("utc")
                }
                table.insert(server_data.history, packet)
                server_data.messages_queue[msg.target] = server_data.messages_queue[msg.target] or {}
                table.insert(server_data.messages_queue[msg.target], packet)
                rednet.send(id, {type = "message_response", success = true}, protocol)
                log("Msg: " .. msg.senderName .. " -> " .. (msg.target or "all"))

            elseif msg.type == "get_messages" then
                local queue = server_data.messages_queue[id] or {}
                rednet.send(id, {type = "messages", messages = queue}, protocol)
                server_data.messages_queue[id] = {}

            elseif msg.type == "ping" then
                if server_data.clients[id] then server_data.clients[id].lastSeen = os.epoch("utc") end
                rednet.send(id, {type = "pong", time = os.epoch("utc")}, protocol)
            end
        end
    end
end

-- Автосохранение
local function auto_save()
    while true do
        os.sleep(30)
        save_data()
    end
end

parallel.waitForAny(handle_requests, auto_save)
