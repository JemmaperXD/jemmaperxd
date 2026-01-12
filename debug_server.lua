local PORT = 1384
local modem = peripheral.find("modem") or error("No modem found")
modem.open(PORT)

print("Simple Server active. My ID: " .. os.getComputerID())

while true do
    local _, _, channel, replyID, msg = os.pullEvent("modem_message")
    if msg == "PING" then
        print("Received PING from " .. replyID .. ", sending PONG...")
        modem.transmit(replyID, PORT, "PONG")
    end
end
