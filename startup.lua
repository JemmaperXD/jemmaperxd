-- ameOs v37.5 [CONTEXT MENU & TIMER FIX]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local running = true
local activeTab = "HOME"
local currentPath = "/"
local clockTimer = nil
local clipboard = { path = nil, mode = nil }

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
        local decoded = textutils.unserialize(data or "")
        if type(decoded) == "table" then settings = decoded end
    end
end

-- 3. АНИМАЦИЯ FUSION (v32.5)
local function bootAnim()
    local cx, cy = math.floor(w/2), math.floor(h/2 - 2)
    local duration = 5
    local start = os.clock()
    local angle = 0
    while os.clock() - start < duration do
        local elapsed = os.clock() - start
        term.setBackgroundColor(colors.black)
        term.clear()
        local fusion = 1.0
        if elapsed > (duration - 2) then fusion = math.max(0, 1 - (elapsed - (duration - 2)) / 2) end
        term.setTextColor(colors.cyan)
        local rX, rY = 2.5 * fusion, 1.5 * fusion
        for i = 1, 3 do
            local a = angle + (i * 2.1)
            term.setCursorPos(cx + math.floor(math.cos(a)*rX+0.5), cy + math.floor(math.sin(a)*rY+0.5))
            term.write("o")
        end
        term.setCursorPos(cx - 2, h - 1)
        term.setTextColor(colors.white)
        term.write("ameOS")
        angle = angle + 0.4
        sleep(0.05)
    end
end

-- 4. ОБНОВЛЕНИЕ СИСТЕМЫ
local function updateSystem()
    mainWin.setBackgroundColor(colors.black)
    mainWin.clear()
    mainWin.setCursorPos(1, 1)
    mainWin.setTextColor(colors.yellow)
    mainWin.write(" Cleaning old files...")
    if fs.exists("startup.lua") then fs.delete("startup.lua") end
    mainWin.setCursorPos(1, 2)
    mainWin.write(" Connecting to server...")
    local url = "https://github.com/JemmaperXD/jemmaperxd/raw/refs/heads/main/startup.lua"
    if shell.run("wget", url, "startup.lua") then
        mainWin.setCursorPos(1, 4)
        mainWin.setTextColor(colors.lime)
        mainWin.write(" Update complete! Rebooting...")
        sleep(2)
        os.reboot()
    end
end

-- 5. ОТРИСОВКА ЧАСОВ (ФИКС ТАЙМЕРА)
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

-- 6. ОТРИСОВКА UI
local function drawUI()
    local theme = themes[settings.themeIndex]
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
        local files = fs.list(getHomeDir())
        for i, n in ipairs(files) do
            local col, row = ((i-1)%4)*12+3, math.floor((i-1)/4)*4+1
            mainWin.setCursorPos(col, row)
            mainWin.setTextColor(fs.isDir(fs.combine(getHomeDir(), n)) and colors.cyan or colors.yellow)
            mainWin.write("[#]")
            mainWin.setCursorPos(col-1, row+1)
            mainWin.setTextColor(colors.white)
            mainWin.write(n:sub(1, 8))
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

-- 7. КОНТЕКСТНОЕ МЕНЮ
local function showContext(x, y, fileName)
    local opts = fileName and {"Copy", "Rename", "Delete"} or {"New File", "Paste"}
    local menuWin = window.create(term.current(), x, y, 12, #opts)
    menuWin.setBackgroundColor(colors.lightGray)
    menuWin.setTextColor(colors.black)
    menuWin.clear()
    for i, o in ipairs(opts) do menuWin.setCursorPos(1, i) menuWin.write(" "..o) end
    local _, b, mx, my = os.pullEvent("mouse_click")
    local choice = (mx >= x and mx <= x+11 and my >= y and my < y+#opts) and opts[my-y+1] or nil
    if choice then
        local target = (activeTab == "HOME") and getHomeDir() or currentPath
        if choice == "New File" then mainWin.setCursorPos(1,1) mainWin.write("Name: ") local n = read() if n~="" then fs.open(fs.combine(target, n), "w").close() end
        elseif choice == "Delete" then fs.delete(fs.combine(target, fileName))
        elseif choice == "Copy" then clipboard = { path = fs.combine(target, fileName) }
        elseif choice == "Paste" and clipboard.path then fs.copy(clipboard.path, fs.combine(target, fs.getName(clipboard.path))) end
    end
    drawUI()
end

-- 8. ДВИЖОК
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
            if y == h then -- Таскбар теперь работает всегда
                local oldTab = activeTab
                if x >= 1 and x <= 6 then activeTab = "HOME"
                elseif x >= 8 and x <= 13 then activeTab = "FILE"
                elseif x >= 15 and x <= 20 then activeTab = "SHLL"
                elseif x >= 22 and x <= 27 then activeTab = "CONF" end
                
                if activeTab == "SHLL" then
                    drawUI()
                    local old = term.redirect(mainWin)
                    term.setBackgroundColor(colors.black) term.clear() term.setCursorPos(1,1)
                    term.setCursorBlink(true)
                    parallel.waitForAny(function() shell.run("shell") end, function()
                        while true do
                            local _, _, mx, my = os.pullEvent("mouse_click")
                            if my == h then os.queueEvent("mouse_click", 1, mx, my) return end
                        end
                    end)
                    term.setCursorBlink(false) term.redirect(old)
                    activeTab = "HOME"
                end
                if activeTab ~= oldTab then clockTimer = os.startTimer(0.1) end -- Сброс таймера для фикса часов
                drawUI()
            elseif activeTab == "FILE" and y > 1 and y < h then
                local files = fs.list(currentPath)
                if currentPath ~= "/" then table.insert(files, 1, "..") end
                local sel = files[y-2]
                if btn == 2 then showContext(x, y, sel)
                elseif sel then
                    local p = fs.combine(currentPath, sel)
                    if fs.isDir(p) then currentPath = p drawUI()
                    else local old = term.redirect(mainWin) term.setCursorBlink(true) shell.run("edit", p) term.setCursorBlink(false) term.redirect(old) drawUI() end
                end
            elseif activeTab == "HOME" and y > 1 and y < h then
                local files = fs.list(getHomeDir())
                local sel = nil
                for i, n in ipairs(files) do
                    local col, row = ((i-1)%4)*12+3, math.floor((i-1)/4)*4+2
                    if x >= col and x <= col+6 and y >= row and y <= row+1 then sel = n break end
                end
                if btn == 2 then showContext(x, y, sel)
                elseif sel then 
                    local p = fs.combine(getHomeDir(), sel)
                    if fs.isDir(p) then activeTab = "FILE" currentPath = p else local old = term.redirect(mainWin) term.setCursorBlink(true) shell.run("edit", p) term.setCursorBlink(false) term.redirect(old) end
                    drawUI()
                end
            elseif activeTab == "CONF" then
                if y == 5 then settings.themeIndex = (settings.themeIndex % #themes) + 1 saveSettings() drawUI()
                elseif y == 7 then updateSystem()
                elseif y == 9 then running = false end
            end
        end
    end
end

-- 9. ВХОД (ЧЕРНЫЙ ФОН)
bootAnim()
loadSettings()
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorBlink(true)
if not settings.isRegistered then
    term.setCursorPos(w/2-6, h/2-2) term.setTextColor(colors.cyan) term.write("REGISTRATION")
    term.setCursorPos(w/2-8, h/2) term.setTextColor(colors.white) term.write("User: ") settings.user = read()
    term.setCursorPos(w/2-8, h/2+1) term.write("Pass: ") settings.pass = read("*")
    settings.isRegistered = true saveSettings()
else
    while true do
        term.clear()
        term.setCursorPos(w/2-6, h/2-1) term.setTextColor(colors.cyan) term.write("LOGIN: "..settings.user)
        term.setCursorPos(w/2-8, h/2+1) term.setTextColor(colors.white) term.write("Pass: ")
        if read("*") == settings.pass then break end
    end
end
term.setCursorBlink(false)
osEngine()
