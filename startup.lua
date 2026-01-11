-- ameOs v36.2 [FINAL REPAIR]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local running = true
local activeTab = "HOME"
local currentPath = "/"
local clockTimer = nil
local clipboard = { path = nil, mode = nil }

local themes = {
    { name = "Night",     bg = colors.black, accent = colors.gray, text = colors.lightGray },
    { name = "Hacker",    bg = colors.black, accent = colors.lime, text = colors.lime }
}
local settings = { themeIndex = 1, user = "User", pass = "", isRegistered = false }

local topWin = window.create(term.current(), 1, 1, w, 1)
local mainWin = window.create(term.current(), 1, 2, w, h - 2)
local taskWin = window.create(term.current(), 1, h, w, 1)

-- 1. СИСТЕМА
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
        if type(decoded) == "table" then settings = decoded end
    end
end

-- 2. ГРАФИКА И UI
local function drawTopBar()
    local theme = themes[settings.themeIndex]
    topWin.setBackgroundColor(theme.accent)
    topWin.setTextColor(theme.text)
    topWin.clear()
    topWin.setCursorPos(2, 1) topWin.write("ameOs | " .. activeTab)
    topWin.setCursorPos(w - 6, 1)
    topWin.write(textutils.formatTime(os.time(), true))
    topWin.setCursorBlink(false)
end

local function drawUI()
    local theme = themes[settings.themeIndex]
    term.setCursorBlink(false)
    
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

    mainWin.setBackgroundColor(theme.bg)
    mainWin.setTextColor(theme.text)
    mainWin.clear()

    if activeTab == "HOME" then
        local home = getHomeDir()
        if not fs.exists(home) then fs.makeDir(home) end
        local files = fs.list(home)
        for i, n in ipairs(files) do
            local col = ((i-1)%4)*12+3
            local row = math.floor((i-1)/4)*4+2
            mainWin.setCursorPos(col, row)
            local isDir = fs.isDir(fs.combine(home, n))
            mainWin.setTextColor(isDir and colors.cyan or colors.yellow)
            mainWin.write("/---\\")
            mainWin.setCursorPos(col, row+1)
            mainWin.write("| # |")
            mainWin.setCursorPos(col-1, row+2)
            mainWin.setTextColor(colors.white)
            mainWin.write(n:sub(1, 9))
        end
    elseif activeTab == "FILE" then
        mainWin.setCursorPos(1, 1) mainWin.setTextColor(colors.yellow)
        mainWin.write(" "..currentPath)
        local files = fs.list(currentPath)
        if currentPath ~= "/" then table.insert(files, 1, "..") end
        for i, n in ipairs(files) do
            if i > h-4 then break end
            mainWin.setCursorPos(1, i+1)
            mainWin.setTextColor(fs.isDir(fs.combine(currentPath, n)) and colors.cyan or colors.white)
            mainWin.write("> "..n)
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

-- 3. ПАРАЛЛЕЛЬНЫЙ ЗАПУСК (БЕЗ МОРГАНИЯ У ЧАСОВ)
local function runInWindow(prog, arg)
    local oldTerm = term.redirect(mainWin)
    mainWin.setBackgroundColor(colors.black)
    mainWin.clear()
    mainWin.setCursorPos(1,1)
    if prog == "edit" or not prog then term.setCursorBlink(true) end
    
    parallel.waitForAny(
        function() if prog then shell.run(prog, arg) else shell.run("shell") end end,
        function()
            local t = os.startTimer(1)
            while true do
                local ev, p1, p2, p3 = os.pullEvent()
                if ev == "mouse_click" and p3 == h then os.queueEvent("mouse_click", 1, p2, p3) return
                elseif ev == "timer" and p1 == t then 
                    drawTopBar() 
                    term.redirect(mainWin)
                    t = os.startTimer(1) 
                end
            end
        end
    )
    term.setCursorBlink(false)
    term.redirect(oldTerm)
    drawUI()
end

-- 4. ДВИЖОК СОБЫТИЙ (ТОЧНЫЕ КЛИКИ)
local function osEngine()
    drawUI()
    clockTimer = os.startTimer(1)
    while running do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "timer" and p1 == clockTimer then
            drawTopBar() clockTimer = os.startTimer(1)
        elseif event == "mouse_click" then
            local btn, x, y = p1, p2, p3
            if y == h then
                if x >= 1 and x <= 6 then activeTab = "HOME"
                elseif x >= 8 and x <= 13 then activeTab = "FILE"
                elseif x >= 15 and x <= 20 then activeTab = "SHLL"
                elseif x >= 22 and x <= 27 then activeTab = "CONF" end
                if activeTab == "SHLL" then drawUI() runInWindow() activeTab = "HOME" end
                drawUI()
            elseif activeTab == "HOME" and y >= 2 and y < h then
                local home = getHomeDir()
                local files = fs.list(home)
                local sel = nil
                for i, n in ipairs(files) do
                    local col = ((i-1)%4)*12+3
                    local row = math.floor((i-1)/4)*4+3 -- Реальная строка на мониторе
                    if x >= col and x <= col+6 and y >= row-1 and y <= row+1 then 
                        sel = n break 
                    end
                end
                if btn == 1 and sel then
                    local p = fs.combine(home, sel)
                    if fs.isDir(p) then activeTab = "FILE" currentPath = p drawUI()
                    else runInWindow("edit", p) end
                end
            elseif activeTab == "FILE" and y >= 3 and y < h then
                local f = fs.list(currentPath)
                if currentPath ~= "/" then table.insert(f, 1, "..") end
                local s = f[y-2] -- Список файлов начинается со строки 3 на мониторе
                if s then
                    local p = fs.combine(currentPath, s)
                    if btn == 1 then
                        if fs.isDir(p) then currentPath = p drawUI()
                        else runInWindow("edit", p) end
                    end
                end
            elseif activeTab == "CONF" then
                if y == 5 then settings.themeIndex = (settings.themeIndex % #themes) + 1 saveSettings() drawUI()
                elseif y == 9 then running = false end
            end
        end
    end
end

-- 5. АНИМАЦИЯ FUSION (Legacy v32.5)
local function bootAnim()
    local cx, cy = math.floor(w/2), math.floor(h/2 - 1)
    local angle = 0
    for frame = 1, 40 do
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setTextColor(colors.cyan)
        -- Код из v32.5: фиксированный радиус и вращение
        for i = 1, 3 do
            local a = angle + (i * 2.09)
            term.setCursorPos(cx + math.floor(math.cos(a)*3+0.5), cy + math.floor(math.sin(a)*2+0.5))
            term.write("o")
        end
        term.setCursorPos(cx - 2, h - 1)
        term.setTextColor(colors.white)
        term.write("ameOS")
        angle = angle + 0.3
        sleep(0.05)
    end
end

-- 6. СТАРТ
loadSettings()
bootAnim()
term.setBackgroundColor(colors.gray)
term.clear()
term.setCursorBlink(false)
currentPath = getHomeDir()
if not fs.exists(currentPath) then fs.makeDir(currentPath) end
osEngine()
