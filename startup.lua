-- ameOs v33.2 [ULTIMATE REPAIR 2026]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local running = true
local activeTab = "HOME"
local currentPath = "/"
local clipboard = { path = nil, mode = nil }

-- 1. ТЕМЫ И НАСТРОЙКИ
local themes = {
    { name = "Night",     bg = colors.black, accent = colors.gray, text = colors.lightGray },
    { name = "Hacker",    bg = colors.black, accent = colors.lime, text = colors.lime }
}
local settings = { themeIndex = 1, user = "User", pass = "", isRegistered = false }

-- Создание окон
local topWin = window.create(term.current(), 1, 1, w, 1)
local mainWin = window.create(term.current(), 1, 2, w, h - 2)
local taskWin = window.create(term.current(), 1, h, w, 1)

-- 2. СИСТЕМНЫЕ ФУНКЦИИ
local function getHomeDir() return fs.combine("/.User", "." .. settings.user) end

local function saveSettings()
    local f = fs.open(SETTINGS_PATH, "w")
    f.write(textutils.serialize(settings))
    f.close()
end

-- 3. АНИМАЦИЯ FUSION
local function bootAnim()
    local cx, cy = math.floor(w/2), math.floor(h/2 - 2)
    local start = os.clock()
    while os.clock() - start < 3 do
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setTextColor(colors.cyan)
        local a = os.clock() * 5
        for i = 1, 3 do
            local ang = a + (i * 2.1)
            term.setCursorPos(cx + math.floor(math.cos(ang)*3), cy + math.floor(math.sin(ang)*2))
            term.write("o")
        end
        term.setCursorPos(cx-2, h-1) term.setTextColor(colors.white) term.write("ameOS")
        sleep(0.05)
    end
end

-- 4. ОТРИСОВКА ИНТЕРФЕЙСА
local function drawUI()
    local theme = themes[settings.themeIndex]
    
    -- Taskbar
    taskWin.setBackgroundColor(colors.black)
    taskWin.clear()
    local menu = { "HOME", "FILE", "SHLL", "CONF" }
    for i, m in ipairs(menu) do
        taskWin.setCursorPos((i-1)*7 + 1, 1)
        taskWin.setBackgroundColor(activeTab == m and theme.accent or colors.black)
        taskWin.setTextColor(activeTab == m and theme.text or colors.white)
        taskWin.write(" "..m.." ")
    end

    -- Top Bar
    topWin.setBackgroundColor(theme.accent)
    topWin.setTextColor(theme.text)
    topWin.clear()
    topWin.setCursorPos(2, 1) topWin.write("ameOs | " .. activeTab)
    topWin.setCursorPos(w - 6, 1)
    topWin.write(textutils.formatTime(os.time(), true))

    -- Main Window
    mainWin.setBackgroundColor(theme.bg)
    mainWin.setTextColor(theme.text)
    mainWin.clear()

    if activeTab == "HOME" then
        local files = fs.list(getHomeDir())
        for i, n in ipairs(files) do
            local col, row = ((i-1)%3)*8+2, math.floor((i-1)/3)*3+1
            mainWin.setCursorPos(col, row)
            mainWin.setTextColor(fs.isDir(fs.combine(getHomeDir(), n)) and colors.cyan or colors.yellow)
            mainWin.write("[#]")
            mainWin.setCursorPos(col - 1, row + 1)
            mainWin.setTextColor(colors.white)
            mainWin.write(n:sub(1, 7))
        end
    elseif activeTab == "FILE" then
        mainWin.setCursorPos(1, 1) mainWin.setTextColor(colors.yellow)
        mainWin.write(" "..currentPath)
        local fList = fs.list(currentPath)
        if currentPath ~= "/" then table.insert(fList, 1, "..") end
        for i, n in ipairs(fList) do
            if i > h-4 then break end
            mainWin.setCursorPos(1, i+1)
            local isD = fs.isDir(fs.combine(currentPath, n))
            mainWin.setTextColor(isD and colors.cyan or colors.white)
            mainWin.write((isD and "> " or "  ") .. n)
        end
    elseif activeTab == "CONF" then
        mainWin.setCursorPos(1, 2) mainWin.write(" Theme: "..theme.name)
        mainWin.setCursorPos(1, 4) mainWin.write(" [ NEXT THEME ]")
        mainWin.setCursorPos(1, 6) mainWin.setTextColor(colors.yellow)
        mainWin.write(" [ UPDATE SYSTEM ]")
        mainWin.setCursorPos(1, 8) mainWin.setTextColor(theme.text)
        mainWin.write(" [ SHUTDOWN ]")
    end
end

-- 5. АВТОРИЗАЦИЯ
local function systemAuth()
    if fs.exists(SETTINGS_PATH) then
        local f = fs.open(SETTINGS_PATH, "r")
        settings = textutils.unserialize(f.readAll()) or settings
        f.close()
    end
    
    term.setBackgroundColor(colors.gray)
    term.clear()
    term.setCursorBlink(true)
    
    if not settings.isRegistered then
        term.setCursorPos(w/2-6, h/2-2) term.write("REGISTRATION")
        term.setCursorPos(w/2-8, h/2) term.write("User: ") settings.user = read()
        term.setCursorPos(w/2-8, h/2+1) term.write("Pass: ") settings.pass = read("*")
        settings.isRegistered = true
        saveSettings()
    else
        while true do
            term.setBackgroundColor(colors.gray) term.clear()
            term.setCursorPos(w/2-6, h/2-1) term.write("LOGIN: "..settings.user)
            term.setCursorPos(w/2-8, h/2+1) term.write("Pass: ")
            if read("*") == settings.pass then break end
        end
    end
    term.setCursorBlink(false)
end

-- 6. ЯДРО СИСТЕМЫ
local function osEngine()
    drawUI()
    local clockT = os.startTimer(1)
    
    while running do
        local ev, p1, p2, p3 = os.pullEvent()
        
        if ev == "timer" and p1 == clockT then
            drawUI()
            clockT = os.startTimer(1)
            
        elseif ev == "mouse_click" then
            local btn, x, y = p1, p2, p3
            
            -- Taskbar
            if y == h then
                if x <= 7 then activeTab = "HOME"
                elseif x <= 14 then activeTab = "FILE"
                elseif x <= 21 then activeTab = "SHLL"
                elseif x <= 28 then activeTab = "CONF" end
                
                if activeTab == "SHLL" then
                    drawUI()
                    local old = term.redirect(mainWin)
                    term.setBackgroundColor(colors.black) term.clear() term.setCursorPos(1,1)
                    term.setCursorBlink(true)
                    parallel.waitForAny(
                        function() shell.run("shell") end,
                        function()
                            while true do
                                local _, _, mx, my = os.pullEvent("mouse_click")
                                if my == h then os.queueEvent("mouse_click", 1, mx, my) return end
                            end
                        end
                    )
                    term.setCursorBlink(false) term.redirect(old)
                    activeTab = "HOME"
                end
                drawUI()

            -- FILE Tab Logic
            elseif activeTab == "FILE" and y > 1 and y < h then
                local fList = fs.list(currentPath)
                if currentPath ~= "/" then table.insert(fList, 1, "..") end
                local clicked = fList[y-1]
                if clicked then
                    local fullP = fs.combine(currentPath, clicked)
                    if fs.isDir(fullP) then
                        currentPath = fullP
                    else
                        local old = term.redirect(mainWin)
                        term.setCursorBlink(true)
                        shell.run("edit", fullP)
                        term.setCursorBlink(false)
                        term.redirect(old)
                    end
                    drawUI()
                end

            -- CONF Tab Logic
            elseif activeTab == "CONF" then
                if y == 5 then 
                    settings.themeIndex = (settings.themeIndex % #themes) + 1 
                    saveSettings()
                    drawUI()
                elseif y == 7 then
                    running = false
                    os.queueEvent("system_update")
                elseif y == 9 then
                    running = false
                end
            end
        end
    end
end

-- 7. ЗАПУСК И ОБНОВЛЕНИЕ
bootAnim()
systemAuth()
currentPath = getHomeDir()
if not fs.exists(currentPath) then fs.makeDir(currentPath) end

-- Запуск ядра
osEngine()

-- Если вышли из цикла из-за обновления
local _, ev = os.pullEvent()
if ev == "system_update" then
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1,1)
    print("Updating...")
    if fs.exists("startup.lua") then fs.delete("startup.lua") end
    shell.run("wget https://github.com/JemmaperXD/jemmaperxd/raw/refs/heads/main/startup.lua startup.lua")
    os.reboot()
end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
print("ameOs closed.")
