-- ameOs v35.0 [STABLE GOLD]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local running = true
local activeTab = "HOME"
local currentPath = "/"
local clockTimer = nil

-- 1. НАСТРОЙКИ
local themes = {
    { name = "Night",     bg = colors.black, accent = colors.gray, text = colors.lightGray },
    { name = "Hacker",    bg = colors.black, accent = colors.lime, text = colors.lime }
}
local settings = { themeIndex = 1, user = "User", pass = "", isRegistered = false }

-- Окна
local topWin = window.create(term.native(), 1, 1, w, 1)
local mainWin = window.create(term.native(), 1, 2, w, h - 2)
local taskWin = window.create(term.native(), 1, h, w, 1)

-- 2. СИСТЕМА ФАЙЛОВ
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
        local data = f.readAll()
        f.close()
        local decoded = textutils.unserialize(data or "")
        if type(decoded) == "table" then settings = decoded end
    end
end

-- 3. ИНТЕРФЕЙС
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

local function drawUI()
    local theme = themes[settings.themeIndex]
    
    -- Панель задач
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

    -- Главное окно
    mainWin.setBackgroundColor(theme.bg)
    mainWin.setTextColor(theme.text)
    mainWin.clear()

    if activeTab == "HOME" then
        local homeP = getHomeDir()
        if not fs.exists(homeP) then fs.makeDir(homeP) end
        local files = fs.list(homeP)
        for i, n in ipairs(files) do
            local col = ((i-1)%4)*12+3
            local row = math.floor((i-1)/4)*4+2
            mainWin.setCursorPos(col, row)
            if fs.isDir(fs.combine(homeP, n)) then
                mainWin.setTextColor(colors.cyan)
                mainWin.write("[ == ]")
            else
                mainWin.setTextColor(colors.yellow)
                mainWin.write("[# - ]")
            end
            mainWin.setCursorPos(col, row+1)
            mainWin.setTextColor(colors.white)
            mainWin.write(n:sub(1, 8))
        end
    elseif activeTab == "FILE" then
        mainWin.setCursorPos(1, 1)
        mainWin.setTextColor(colors.yellow)
        mainWin.write(" Path: " .. currentPath)
        local f = fs.list(currentPath)
        if currentPath ~= "/" then table.insert(f, 1, "..") end
        for i, n in ipairs(f) do
            if i > h-4 then break end
            mainWin.setCursorPos(1, i+1)
            local isD = fs.isDir(fs.combine(currentPath, n))
            mainWin.setTextColor(isD and colors.cyan or colors.white)
            mainWin.write(isD and "[D] " or "[F] ")
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

-- 4. ВЫПОЛНЕНИЕ ПРОГРАММ
local function runInWindow(prog, arg)
    local oldT = term.redirect(mainWin)
    mainWin.setBackgroundColor(colors.black)
    mainWin.clear()
    mainWin.setCursorPos(1,1)
    term.setCursorBlink(true)

    parallel.waitForAny(
        function() 
            if prog then shell.run(prog, arg) else shell.run("shell") end
        end,
        function()
            local t = os.startTimer(1)
            while true do
                local ev, p1, p2, p3 = os.pullEvent()
                if ev == "mouse_click" and p3 == h then 
                    os.queueEvent("mouse_click", 1, p2, p3)
                    return 
                elseif ev == "timer" and p1 == t then
                    drawTopBar()
                    t = os.startTimer(1)
                end
            end
        end
    )

    term.setCursorBlink(false)
    term.redirect(oldT)
    drawUI()
    clockTimer = os.startTimer(1)
end

-- 5. ОБНОВЛЕНИЕ (DEBUG)
local function updateSystem()
    mainWin.setBackgroundColor(colors.black)
    mainWin.clear()
    mainWin.setTextColor(colors.yellow)
    mainWin.setCursorPos(1,1)
    print(" Connecting...")
    sleep(0.5)
    print(" Downloading: startup.lua")
    
    -- Используем raw ссылку, чтобы не скачать HTML страницу вместо кода
    local rawUrl = "https://raw.githubusercontent.com/JemmaperXD/jemmaperxd/main/startup.lua"
    
    if fs.exists("startup.lua") then fs.delete("startup.lua") end
    shell.run("wget", rawUrl, "startup.lua")
    
    print(" Verifying...")
    sleep(0.5)
    print(" Rebooting...")
    sleep(1)
    os.reboot()
end

-- 6. ДВИЖОК
local function osEngine()
    drawUI()
    clockTimer = os.startTimer(1)
    while running do
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "timer" and p1 == clockTimer then
            drawTopBar()
            clockTimer = os.startTimer(1)
        elseif ev == "mouse_click" then
            local x, y = p2, p3
            if y == h then
                if x < 7 then activeTab = "HOME"
                elseif x < 14 then activeTab = "FILE"
                elseif x < 21 then activeTab = "SHLL"
                elseif x < 28 then activeTab = "CONF" end
                if activeTab == "SHLL" then drawUI() runInWindow() activeTab = "HOME" end
                drawUI()
            elseif activeTab == "HOME" and y > 1 and y < h then
                local f = fs.list(getHomeDir())
                local sel = nil
                for i, n in ipairs(f) do
                    local col = ((i-1)%4)*12+3
                    local row = math.floor((i-1)/4)*4+2
                    if x >= col and x <= col+5 and y >= row and y <= row+1 then sel = n break end
                end
                if sel then
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
                if y == 4 then settings.themeIndex = (settings.themeIndex % #themes) + 1 saveSettings() drawUI()
                elseif y == 6 then updateSystem()
                elseif y == 8 then running = false end
            end
        end
    end
end

-- 7. СТАРТ
loadSettings()

-- Анимация Fusion
local function bootAnim()
    local cx, cy = math.floor(w/2), math.floor(h/2-1)
    for frame = 1, 20 do
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setTextColor(colors.cyan)
        local r = 2 * (1 - frame/30)
        for i = 1, 3 do
            local a = (frame/4) + (i * 2.1)
            term.setCursorPos(cx + math.floor(math.cos(a)*r*2+0.5), cy + math.floor(math.sin(a)*r+0.5))
            term.write("o")
        end
        term.setCursorPos(cx-2, h)
        term.setTextColor(colors.white)
        term.write("ameOS")
        sleep(0.05)
    end
end

bootAnim()

-- Вход
term.setBackgroundColor(colors.black)
term.clear()
if not settings.isRegistered then
    term.setCursorPos(w/2-8, h/2-2) term.write("Reg User: ") settings.user = read()
    term.setCursorPos(w/2-8, h/2+1) term.write("Reg Pass: ") settings.pass = read("*")
    settings.isRegistered = true
    saveSettings()
else
    while true do
        term.clear()
        term.setCursorPos(w/2-8, h/2-1) term.write("User: "..settings.user)
        term.setCursorPos(w/2-8, h/2+2) term.write("Pass: ")
        if read("*") == settings.pass then break end
    end
end

currentPath = getHomeDir()
osEngine()
