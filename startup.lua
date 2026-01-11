-- ameOs v34.7 [FINAL GOLD REWRITE]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local running = true
local activeTab = "HOME"
local currentPath = "/"
local clipboard = { path = nil, mode = nil }
local globalClockTimer = nil

-- 1. ТЕМЫ
local themes = {
    { name = "Night",     bg = colors.black, accent = colors.gray, text = colors.lightGray },
    { name = "Hacker",    bg = colors.black, accent = colors.lime, text = colors.lime }
}
local settings = { themeIndex = 1, user = "User", pass = "", isRegistered = false }

-- Создание окон на базе нативного терминала
local topWin = window.create(term.native(), 1, 1, w, 1)
local mainWin = window.create(term.native(), 1, 2, w, h - 2)
local taskWin = window.create(term.native(), 1, h, w, 1)

-- 2. ЯДРО СИСТЕМЫ
if not fs.exists(CONFIG_DIR) then fs.makeDir(CONFIG_DIR) end
local function getHomeDir() return fs.combine("/.User", "." .. settings.user) end

local function saveSettings()
    local f = fs.open(SETTINGS_PATH, "w")
    f.write(textutils.serialize(settings))
    f.close()
end

local function loadSettings()
    if fs.exists(SETTINGS_PATH) then
        local f = fs.open(SETTINGS_PATH, "r")
        local data = f.readAll() f.close()
        local decoded = textutils.unserialize(data or "")
        if decoded then settings = decoded end
    end
end

-- 3. ОТРИСОВКА ВЕРХНЕЙ ПАНЕЛИ
local function drawTopBar()
    local theme = themes[settings.themeIndex]
    topWin.setBackgroundColor(theme.accent)
    topWin.setTextColor(theme.text)
    topWin.clear()
    topWin.setCursorPos(2, 1)
    topWin.write("ameOs | " .. activeTab)
    topWin.setCursorPos(w - 5, 1)
    topWin.write(textutils.formatTime(os.time(), true))
end

-- 4. ОТРИСОВКА ГЛАВНОГО ЭКРАНА
local function drawUI()
    local theme = themes[settings.themeIndex]
    
    -- Taskbar
    taskWin.setBackgroundColor(colors.black)
    taskWin.clear()
    local menu = { {n="HOME", x=1}, {n="FILE", x=8}, {n="SHLL", x=15}, {n="CONF", x=22} }
    for _, m in ipairs(menu) do
        taskWin.setCursorPos(m.x, 1)
        taskWin.setBackgroundColor(activeTab == m.n and theme.accent or colors.black)
        taskWin.setTextColor(activeTab == m.n and theme.text or colors.white)
        taskWin.write(" "..m.n.." ")
    end

    drawTopBar()

    -- Main Window
    mainWin.setBackgroundColor(theme.bg)
    mainWin.setTextColor(theme.text)
    mainWin.clear()

    if activeTab == "HOME" then
        local files = fs.list(getHomeDir())
        for i, n in ipairs(files) do
            local col = ((i-1)%4)*12+3
            local row = math.floor((i-1)/4)*4+2
            mainWin.setCursorPos(col, row)
            local isDir = fs.isDir(fs.combine(getHomeDir(), n))
            
            if isDir then
                mainWin.setTextColor(colors.cyan)
                mainWin.write("/---\\") 
                mainWin.setCursorPos(col, row+1)
                mainWin.write("|== |") -- Иконка папки
            else
                mainWin.setTextColor(colors.yellow)
                mainWin.write(".---.")
                mainWin.setCursorPos(col, row+1)
                mainWin.write("|#  |") -- Иконка файла
            end
            mainWin.setCursorPos(col-1, row+2)
            mainWin.setTextColor(colors.white)
            mainWin.write(n:sub(1, 10))
        end
    elseif activeTab == "FILE" then
        mainWin.setCursorPos(1, 1)
        mainWin.setTextColor(colors.yellow)
        mainWin.write(" Path: " .. currentPath)
        local files = fs.list(currentPath)
        if currentPath ~= "/" then table.insert(files, 1, "..") end
        for i, n in ipairs(files) do
            if i > h-4 then break end
            mainWin.setCursorPos(1, i+1)
            local isDir = fs.isDir(fs.combine(currentPath, n))
            mainWin.setTextColor(isDir and colors.cyan or colors.white)
            mainWin.write(isDir and "[D] " or "[F] ")
            mainWin.write(n)
        end
    elseif activeTab == "CONF" then
        mainWin.setCursorPos(2, 2)
        mainWin.write("Theme: " .. theme.name)
        mainWin.setCursorPos(2, 4)
        mainWin.write("[ NEXT THEME ]")
        mainWin.setCursorPos(2, 6)
        mainWin.setTextColor(colors.yellow)
        mainWin.write("[ UPDATE SYSTEM ]")
        mainWin.setCursorPos(2, 8)
        mainWin.setTextColor(theme.text)
        mainWin.write("[ SHUTDOWN ]")
    end
end

-- 5. ОБНОВЛЕНИЕ (С ОТЛАДКОЙ)
local function updateSystem()
    mainWin.setBackgroundColor(colors.black)
    mainWin.clear()
    mainWin.setCursorPos(1, 1)
    mainWin.setTextColor(colors.yellow)
    mainWin.write(" Connecting to server...")
    sleep(0.8)
    mainWin.setCursorPos(1, 2)
    mainWin.write(" Downloading: startup.lua")
    
    if fs.exists("startup.lua") then fs.delete("startup.lua") end
    local success, err = pcall(function() 
        shell.run("wget", "https://github.com/JemmaperXD/jemmaperxd/raw/refs/heads/main/startup.lua", "startup.lua")
    end)
    
    if success then
        mainWin.setCursorPos(1, 4)
        mainWin.write(" Update successful! Rebooting...")
        sleep(1)
        os.reboot()
    else
        mainWin.setTextColor(colors.red)
        mainWin.write(" Error: " .. tostring(err))
        sleep(2)
    end
end

-- 6. ПАРАЛЛЕЛЬНАЯ СИСТЕМА СОБЫТИЙ (FIXED)
local function runInWindow(prog, arg)
    local oldTerm = term.redirect(mainWin)
    mainWin.setBackgroundColor(colors.black)
    mainWin.clear()
    mainWin.setCursorPos(1,1)
    term.setCursorBlink(true)

    parallel.waitForAny(
        function() 
            if prog then shell.run(prog, arg) else shell.run("shell") end
        end,
        function()
            local internalClock = os.startTimer(1)
            while true do
                local event, p1, p2, p3 = os.pullEvent()
                if event == "mouse_click" and p3 == h then 
                    os.queueEvent("mouse_click", 1, p2, p3)
                    return 
                elseif event == "timer" and p1 == internalClock then
                    drawTopBar()
                    internalClock = os.startTimer(1)
                end
            end
        end
    )

    term.setCursorBlink(false)
    term.redirect(oldTerm)
    drawUI()
    globalClockTimer = os.startTimer(1)
end

-- 7. ОБРАБОТЧИК КЛИКОВ И ЛОГИКА
local function osEngine()
    drawUI()
    globalClockTimer = os.startTimer(1)
    while running do
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "timer" and p1 == globalClockTimer then
            drawTopBar()
            globalClockTimer = os.startTimer(1)
            
        elseif event == "mouse_click" then
            local btn, x, y = p1, p2, p3
            
            if y == h then -- Клик по таскбару
                if x >= 1 and x <= 6 then activeTab = "HOME"
                elseif x >= 8 and x <= 13 then activeTab = "FILE"
                elseif x >= 15 and x <= 20 then activeTab = "SHLL"
                elseif x >= 22 and x <= 27 then activeTab = "CONF" end
                
                if activeTab == "SHLL" then drawUI() runInWindow() activeTab = "HOME" end
                drawUI()
                
            elseif activeTab == "HOME" and y > 1 and y < h then
                local files = fs.list(getHomeDir())
                local sel = nil
                for i, n in ipairs(files) do
                    local col = ((i-1)%4)*12+3
                    local row = math.floor((i-1)/4)*4+2
                    if x >= col and x <= col+5 and y >= row and y <= row+1 then sel = n break end
                end
                if btn == 1 and sel then
                    local p = fs.combine(getHomeDir(), sel)
                    if fs.isDir(p) then activeTab = "FILE" currentPath = p drawUI()
                    else runInWindow("edit", p) end
                end
                
            elseif activeTab == "FILE" and y > 1 and y < h then
                local f = fs.list(currentPath)
                if currentPath ~= "/" then table.insert(f, 1, "..") end
                local s = f[y-1]
                if s then
                    local p = fs.combine(currentPath, s)
                    if fs.isDir(p) then currentPath = p drawUI()
                    else runInWindow("edit", p) end
                end
                
            elseif activeTab == "CONF" then
                if y == 5 then settings.themeIndex = (settings.themeIndex % #themes) + 1 saveSettings() drawUI()
                elseif y == 7 then updateSystem()
                elseif y == 9 then running = false end
            end
        end
    end
end

-- 8. АНИМАЦИЯ ЗАГРУЗКИ FUSION
local function bootAnim()
    local cx, cy = math.floor(w/2), math.floor(h/2 - 1)
    for frame = 1, 25 do
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setTextColor(colors.cyan)
        local rad = 2.2 * (1 - frame/35)
        for i = 1, 3 do
            local a = (frame/4) + (i * 2.09)
            term.setCursorPos(cx + math.floor(math.cos(a)*rad*2.2+0.5), cy + math.floor(math.sin(a)*rad+0.5))
            term.write("o")
        end
        term.setCursorPos(cx - 2, h - 1)
        term.setTextColor(colors.white)
        term.write("ameOS")
        sleep(0.05)
    end
end

-- 9. ТОЧКА ВХОДА
loadSettings()
bootAnim()

term.setBackgroundColor(colors.black)
term.clear()

if not settings.isRegistered then
    term.setCursorPos(w/2-8, h/2-2) term.write("Reg User: ") settings.user = read()
    term.setCursorPos(w/2-8, h/2+1) term.write("Reg Pass: ") settings.pass = read("*")
    settings.isRegistered = (settings.user ~= "")
    saveSettings()
else
    while true do
        term.setBackgroundColor(colors.black) term.clear()
        term.setCursorPos(w/2-8, h/2-1) term.write("User: "..settings.user)
        term.setCursorPos(w/2-8, h/2+2) term.write("Pass: ") -- +3 от логина
        if read("*") == settings.pass then break end
    end
end

currentPath = getHomeDir()
if not fs.exists(currentPath) then fs.makeDir(currentPath) end
osEngine()

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
print("ameOs v34.7 Session Ended.")
