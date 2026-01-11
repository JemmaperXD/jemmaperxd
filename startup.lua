-- ameOs v34.0 [OFFICIAL STABLE]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local running = true
local activeTab = "HOME"
local currentPath = "/"
local clipboard = { path = nil, mode = nil }
local clockTimer = nil

-- 1. ТЕМЫ
local themes = {
    { name = "Night",     bg = colors.black, accent = colors.gray, text = colors.lightGray },
    { name = "Hacker",    bg = colors.black, accent = colors.lime, text = colors.lime }
}
local settings = { themeIndex = 1, user = "User", pass = "", isRegistered = false }

-- Окна
local topWin = window.create(term.current(), 1, 1, w, 1)
local mainWin = window.create(term.current(), 1, 2, w, h - 2)
local taskWin = window.create(term.current(), 1, h, w, 1)

-- 2. СИСТЕМА
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
        local decoded = textutils.unserialize(data)
        if decoded then settings = decoded end
    end
end

-- 3. ОТРИСОВКА ВЕРХНЕЙ ПАНЕЛИ
local function drawTopBar()
    local theme = themes[settings.themeIndex]
    topWin.setBackgroundColor(theme.accent)
    topWin.setTextColor(theme.text)
    topWin.clear()
    topWin.setCursorPos(2, 1) topWin.write("ameOs | " .. activeTab)
    topWin.setCursorPos(w - 6, 1)
    topWin.write(textutils.formatTime(os.time(), true))
end

-- 4. ГЛАВНАЯ ОТРИСОВКА
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

-- 5. ПАРАЛЛЕЛЬНЫЙ ЗАПУСК (SHELL/EDIT)
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
            while true do
                local timer = os.startTimer(1)
                local event, p1, p2, p3 = os.pullEvent()
                if event == "mouse_click" and p3 == h then 
                    os.queueEvent("mouse_click", 1, p2, p3)
                    return 
                elseif event == "timer" and p1 == timer then
                    drawTopBar()
                end
            end
        end
    )

    term.setCursorBlink(false)
    term.redirect(oldTerm)
    drawUI()
    clockTimer = os.startTimer(1)
end

-- 6. КОНТЕКСТНОЕ МЕНЮ
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
        mainWin.setCursorPos(1, h-3) mainWin.setBackgroundColor(colors.gray)
        if choice == "New File" then mainWin.write(" Name: ") local n = read() if n and n ~= "" then local f = fs.open(fs.combine(getHomeDir(), n), "w") f.close() end
        elseif choice == "New Folder" then mainWin.write(" Name: ") local n = read() if n and n ~= "" then fs.makeDir(fs.combine(getHomeDir(), n)) end
        elseif choice == "Delete" then fs.delete(fs.combine(getHomeDir(), fileName))
        elseif choice == "Rename" then mainWin.write(" New: ") local n = read() if n and n ~= "" then fs.move(fs.combine(getHomeDir(), fileName), fs.combine(getHomeDir(), n)) end
        elseif choice == "Copy" then clipboard = { path = fs.combine(getHomeDir(), fileName), mode = "copy" }
        elseif choice == "Cut" then clipboard = { path = fs.combine(getHomeDir(), fileName), mode = "cut" }
        elseif choice == "Paste" and clipboard.path then
            local d = fs.combine(getHomeDir(), fs.getName(clipboard.path))
            if clipboard.mode == "copy" then fs.copy(clipboard.path, d) else fs.move(clipboard.path, d) clipboard.path = nil end
        end
    end
    drawUI()
end

-- 7. ДВИЖОК ОС
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
            if y == h then -- Клик по таскбару
                if x >= 1 and x <= 6 then activeTab = "HOME"
                elseif x >= 8 and x <= 13 then activeTab = "FILE"
                elseif x >= 15 and x <= 20 then activeTab = "SHLL"
                elseif x >= 22 and x <= 27 then activeTab = "CONF" end
                
                if activeTab == "SHLL" then
                    drawUI()
                    runInWindow()
                    activeTab = "HOME"
                end
                drawUI()
                
            elseif activeTab == "HOME" and y > 1 and y < h then
                local files = fs.list(getHomeDir())
                local sel = nil
                for i, n in ipairs(files) do
                    local col = ((i-1)%4)*12+3
                    local row = math.floor((i-1)/4)*4+2
                    if x >= col and x <= col+5 and y >= row+1 and y <= row+2 then sel = n break end
                end
                if btn == 2 then showContext(x, y, sel)
                elseif btn == 1 and sel then
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
                elseif y == 7 then 
                    shell.run("wget", "https://github.com/JemmaperXD/jemmaperxd/raw/refs/heads/main/startup.lua", "startup.lua")
                    os.reboot()
                elseif y == 9 then running = false end
            end
        end
    end
end

-- 8. СТАРТ
loadSettings()

-- Анимация Fusion (v32.5 Style)
local function bootAnim()
    local cx, cy = math.floor(w/2), math.floor(h/2 - 2)
    local start = os.clock()
    local angle = 0
    while os.clock() - start < 3 do
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setTextColor(colors.cyan)
        for i = 1, 3 do
            local a = angle + (i * 2.1)
            term.setCursorPos(cx + math.floor(math.cos(a)*3+0.5), cy + math.floor(math.sin(a)*1.5+0.5))
            term.write("o")
        end
        term.setCursorPos(cx - 2, h - 1)
        term.setTextColor(colors.white)
        term.write("ameOS")
        angle = angle + 0.5
        sleep(0.05)
    end
end

bootAnim()

-- Авторизация
term.setBackgroundColor(colors.gray)
term.clear()
if not settings.isRegistered then
    term.setCursorPos(w/2-8, h/2-1) term.write("Reg User: ") settings.user = read()
    term.setCursorPos(w/2-8, h/2)   term.write("Reg Pass: ") settings.pass = read("*")
    settings.isRegistered = true
    saveSettings()
else
    while true do
        term.setBackgroundColor(colors.gray) term.clear()
        term.setCursorPos(w/2-8, h/2) term.write("Pass for "..settings.user..": ")
        if read("*") == settings.pass then break end
    end
end

currentPath = getHomeDir()
if not fs.exists(currentPath) then fs.makeDir(currentPath) end
osEngine()

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
print("ameOs closed.")
