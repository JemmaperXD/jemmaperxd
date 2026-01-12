local m = peripheral.find("modem") or error("No modem found")
m.open(1384)
print("Server ready. ID: " .. os.getComputerID())
while true do
    local _, _, _, id, msg = os.pullEvent("modem_message")
    if msg == "PING" then
        print("Got PING from " .. id .. ". Sending PONG.")
        m.transmit(id, 1384, "PONG")
    end
end
