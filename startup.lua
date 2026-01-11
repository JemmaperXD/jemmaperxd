-- ameOs v35.7 [STABLE REWRITE]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local running = true
local activeTab = "HOME"
local currentPath = "/"
local clockTimer = nil
local clipboard = { path = nil, mode = nil }

-- 1. ТЕМЫ И КОНФИГ
local themes = {
    { name = "Night",     bg = colors.black, accent = colors.gray, text = colors.lightGray },
    { name = "Hacker",    bg = colors.black, accent = colors.lime, text = colors.lime }
}
local settings = { themeIndex = 1, user = "User", pass = "", isRegistered = false }

-- Окна (Используем текущий терминал)
local topWin = window.create(term.current(), 1, 1, w, 1)
local mainWin = window.create(term.current(), 1, 2, w, h - 2)
local taskWin = window.create(term.current(), 1, h, w, 1)

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
        if type(decoded) == "table" then settings = decoded end
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
    topWin.setCursorPos(w - 6, 1)
    topWin.write(textutils.formatTime(os.time(), true))
end

-- 4. ГЛАВНЫЙ ИНТЕРФЕЙС
local function drawUI()
    local theme = themes[settings.themeIndex]
    
    -- Панель задач (Taskbar)
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

    -- Главное окно (Main Window)
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
            
            -- Иконки
            mainWin.setTextColor(isDir and colors.cyan or colors.yellow)
            mainWin.write("/---\\")
            mainWin.setCursorPos(col, row+1)
            mainWin.write("| # |")
            
            -- Имя файла
            mainWin.setCursorPos(col-1, row+2)
            mainWin.setTextColor(colors.white)
            mainWin.write(n:sub(1, 9))
        end
    elseif activeTab == "FILE" then
        mainWin.setCursorPos(1, 1) mainWin.setTextColor(colors.yellow)
        mainWin.write(" Path: "..currentPath)
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
        mainWin.setCursorPos(2, 2) mainWin.write("Theme: "..theme.name)
        mainWin.setCursorPos(2, 4) mainWin.write("[ NEXT THEME ]")
        mainWin.setCursorPos(2, 6) mainWin.setTextColor(colors.yellow)
        mainWin.write("[ UPDATE SYSTEM ]")
        mainWin.setCursorPos(2, 8) mainWin.setTextColor(theme.text)
        mainWin.write("[ SHUTDOWN ]")
    end
end

-- 5. КОНТЕКСТНОЕ МЕНЮ
local function showContext(x, y, fileName)
    local opts = fileName and {"Copy", "Cut", "Rename", "Delete"} or {"New File", "New Folder", "Paste"}
    local menuWin = window.create(term.current(), x, y, 12, #opts)
    menuWin.setBackgroundColor(colors.lightGray)
    menuWin.setTextColor(colors.black)
    menuWin.clear()
    for i, o in ipairs(opts) do menuWin.setCursorPos(1, i) menuWin.write(" "..o) end
    
    local _, b, mx, my = os.pullEvent("mouse_click")
    local choice = (mx >= x and mx <= x+11 and my >= y and my < y+#opts) and opts[my-y+1] or nil
    
    if choice then
        local targetDir = (activeTab == "HOME") and getHomeDir() or currentPath
        mainWin.setCursorPos(1, h-3) mainWin.setBackgroundColor(colors.gray)
        if choice == "New File" then 
            mainWin.write("Name: ") local n = read()
            if n and n ~= "" then local f = fs.open(fs.combine(targetDir, n), "w") f.close() end
        elseif choice == "New Folder" then 
            mainWin.write("Name: ") local n = read()
            if n and n ~= "" then fs.makeDir(fs.combine(targetDir, n)) end
        elseif choice == "Delete" and fileName then 
            fs.delete(fs.combine(targetDir, fileName))
        elseif choice == "Rename" and fileName then
            mainWin.write("New: ") local n = read()
            if n and n ~= "" then fs.move(fs.combine(targetDir, fileName), fs.combine(targetDir, n)) end
        elseif choice == "Copy" then 
            clipboard = { path = fs.combine(targetDir, fileName), mode = "copy" }
        elseif choice == "Paste" and clipboard.path then
            local d = fs.combine(targetDir, fs.getName(clipboard.path))
            if clipboard.mode == "copy" then fs.copy(clipboard.path, d) else fs.move(clipboard.path, d) end
        end
    end
    drawUI()
end

-- 6. ПАРАЛЛЕЛЬНЫЙ ЗАПУСК
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
            local internalTimer = os.startTimer(1)
            while true do
                local event, p1, p2, p3 = os.pullEvent()
                if event == "mouse_click" and p3 == h then 
                    os.queueEvent("mouse_click", 1, p2, p3)
                    return 
                elseif event == "timer" and p1 == internalTimer then
                    drawTopBar()
                    internalTimer = os.startTimer(1)
                end
            end
        end
    )

    term.setCursorBlink(false)
    term.redirect(oldTerm)
    drawUI()
    clockTimer = os.startTimer(1)
end

-- 7. ДВИЖОК СОБЫТИЙ
local function osEngine()
    drawUI()
    clockTimer = os.startTimer(1)
    while running do
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "timer" and p1 == clockTimer then
            drawTopBar()
            clockTimer = os.startTimer(1)
            
        elseif event == "mouse_click" then
            local btn, x, y = p1, p2, p3
            
            -- Клик по нижней панели
            if y == h then
                if x >= 1 and x <= 6 then activeTab = "HOME"
                elseif x >= 8 and x <= 13 then activeTab = "FILE"
                elseif x >= 15 and x <= 20 then activeTab = "SHLL"
                elseif x >= 22 and x <= 27 then activeTab = "CONF" end
                if activeTab == "SHLL" then drawUI() runInWindow() activeTab = "HOME" end
                drawUI()
                
            -- Логика рабочего стола
            elseif activeTab == "HOME" and y > 1 and y < h then
                local home = getHomeDir()
                local files = fs.list(home)
                local sel = nil
                for i, n in ipairs(files) do
                    local col = ((i-1)%4)*12+3
                    local row = math.floor((i-1)/4)*4+2
                    -- ИСПРАВЛЕННЫЙ КЛИК: попадание в иконку или имя (строки row по row+2)
                    if x >= col and x <= col+6 and y >= row+1 and y <= row+3 then 
                        sel = n break 
                    end
                end
                
                if btn == 2 then showContext(x, y, sel)
                elseif btn == 1 and sel then
                    local p = fs.combine(home, sel)
                    if fs.isDir(p) then activeTab = "FILE" currentPath = p drawUI()
                    else runInWindow("edit", p) end
                end
                
            -- Логика проводника
            elseif activeTab == "FILE" and y > 1 and y < h then
                local f = fs.list(currentPath)
                if currentPath ~= "/" then table.insert(f, 1, "..") end
                local s = f[y-1] -- Список начинается со 2-й строки экрана
                if s then
                    local p = fs.combine(currentPath, s)
                    if btn == 2 then showContext(x, y, s)
                    elseif btn == 1 then
                        if fs.isDir(p) then currentPath = p drawUI()
                        else runInWindow("edit", p) end
                    end
                end
                
            -- Логика настроек
            elseif activeTab == "CONF" then
                if y == 5 then settings.themeIndex = (settings.themeIndex % #themes) + 1 saveSettings() drawUI()
                elseif y == 7 then 
                    shell.run("wget", "https://raw.githubusercontent.com/JemmaperXD/jemmaperxd/main/startup.lua", "startup.lua")
                    os.reboot()
                elseif y == 9 then running = false end
            end
        end
    end
end

-- 8. ЛЕГЕНДАРНАЯ АНИМАЦИЯ FUSION
local function bootAnim()
    local cx, cy = math.floor(w/2), math.floor(h/2 - 2)
    local angle = 0
    for frame = 1, 40 do
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setTextColor(colors.cyan)
        local orbitSize = math.max(0.5, 3 - (frame/20))
        for i = 1, 3 do
            local a = angle + (i * 2.1)
            term.setCursorPos(cx + math.floor(math.cos(a)*orbitSize*1.8+0.5), cy + math.floor(math.sin(a)*orbitSize+0.5))
            term.write("o")
        end
        term.setCursorPos(cx - 2, h - 1)
        term.setTextColor(colors.white)
        term.write("ameOS")
        angle = angle + 0.4
        sleep(0.05)
    end
end

-- 9. ЗАПУСК ПРОГРАММЫ
loadSettings()
bootAnim()

-- ЭКРАН ВХОДА
term.setBackgroundColor(colors.gray)
term.clear()
if not settings.isRegistered then
    term.setCursorPos(w/2-8, h/2-2) term.write("Reg User: ") settings.user = read()
    term.setCursorPos(w/2-8, h/2+1) term.write("Reg Pass: ") settings.pass = read("*")
    settings.isRegistered = true saveSettings()
else
    while true do
        term.setBackgroundColor(colors.gray) term.clear()
        term.setCursorPos(w/2-8, h/2-1) term.write("User: "..settings.user)
        term.setCursorPos(w/2-8, h/2+2) term.write("Pass: ")
        if read("*") == settings.pass then break end
    end
end

currentPath = getHomeDir()
if not fs.exists(currentPath) then fs.makeDir(currentPath) end
osEngine()
