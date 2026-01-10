-- ameOs v33.1 [STABLE REBUILD]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local running = true
local activeTab = "HOME"
local currentPath = "/"
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
        local decoded = textutils.unserialize(data)
        if decoded then settings = decoded end
    end
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

-- 4. ВВОД ДАННЫХ (Для создания/переименования)
local function getPopupInput(prompt)
    local theme = themes[settings.themeIndex]
    mainWin.setBackgroundColor(colors.gray)
    mainWin.setTextColor(colors.white)
    mainWin.setCursorPos(2, h-4)
    mainWin.write(" " .. prompt .. ": ")
    term.setCursorBlink(true)
    local val = read()
    term.setCursorBlink(false)
    return val
end

-- 5. ОТРИСОВКА
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
    -- Top
    topWin.setBackgroundColor(theme.accent)
    topWin.setTextColor(theme.text)
    topWin.clear()
    topWin.setCursorPos(2, 1) topWin.write("ameOs | " .. activeTab)
    topWin.setCursorPos(w - 6, 1)
    topWin.write(textutils.formatTime(os.time(), true))
    -- Main
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
        local files = fs.list(currentPath)
        if currentPath ~= "/" then table.insert(files, 1, "..") end
        for i, n in ipairs(files) do
            if i > h-4 then break end
            mainWin.setCursorPos(1, i+1)
            mainWin.setTextColor(fs.isDir(fs.combine(currentPath, n)) and colors.cyan or colors.white)
            mainWin.write((fs.isDir(fs.combine(currentPath, n)) and "> " or "  ") .. n)
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

-- 6. АВТОРИЗАЦИЯ
local function systemAuth()
    loadSettings()
    term.setBackgroundColor(colors.gray)
    term.clear()
    if not settings.isRegistered then
        term.setCursorPos(w/2-6, h/2-2) term.write("REGISTRATION")
        term.setCursorBlink(true)
        term.setCursorPos(w/2-8, h/2) term.write("User: ") settings.user = read()
        term.setCursorPos(w/2-8, h/2+1) term.write("Pass: ") settings.pass = read("*")
        settings.isRegistered = true
        saveSettings()
    else
        while true do
            term.setBackgroundColor(colors.gray) term.clear()
            term.setCursorPos(w/2-6, h/2-1) term.write("LOGIN: "..settings.user)
            term.setCursorPos(w/2-8, h/2+1) term.write("Pass: ")
            term.setCursorBlink(true)
            if read("*") == settings.pass then break end
        end
    end
    term.setCursorBlink(false)
end

-- 7. КОНТЕКСТНОЕ МЕНЮ
local function showMenu(mx, my, file)
    local opts = file and {"Copy", "Cut", "Rename", "Delete"} or {"New File", "New Folder", "Paste"}
    local menuWin = window.create(term.current(), mx, my, 12, #opts)
    menuWin.setBackgroundColor(colors.lightGray)
    menuWin.setTextColor(colors.black)
    menuWin.clear()
    for i, o in ipairs(opts) do menuWin.setCursorPos(1, i) menuWin.write(" "..o) end
    
    local _, b, ex, ey = os.pullEvent("mouse_click")
    if ex >= mx and ex <= mx+11 and ey >= my and ey < my+#opts then
        local c = opts[ey-my+1]
        if c == "New File" then 
            local n = getPopupInput("File Name")
            if n then local f = fs.open(fs.combine(getHomeDir(), n), "w") f.close() end
        elseif c == "New Folder" then
            local n = getPopupInput("Folder Name")
            if n then fs.makeDir(fs.combine(getHomeDir(), n)) end
        elseif c == "Delete" then fs.delete(fs.combine(getHomeDir(), file))
        elseif c == "Copy" then clipboard = { path = fs.combine(getHomeDir(), file), mode = "copy" }
        elseif c == "Cut" then clipboard = { path = fs.combine(getHomeDir(), file), mode = "cut" }
        elseif c == "Paste" and clipboard.path then
            local t = fs.combine(getHomeDir(), fs.getName(clipboard.path))
            if clipboard.mode == "copy" then fs.copy(clipboard.path, t) else fs.move(clipboard.path, t) clipboard.path = nil end
        elseif c == "Rename" then
            local n = getPopupInput("New Name")
            if n then fs.move(fs.combine(getHomeDir(), file), fs.combine(getHomeDir(), n)) end
        end
    end
    drawUI()
end

-- 8. ГЛАВНЫЙ ЦИКЛ
local function osEngine()
    drawUI()
    local clockT = os.startTimer(1)
    while running do
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "timer" and p1 == clockT then
            drawUI() clockT = os.startTimer(1)
        elseif ev == "mouse_click" then
            local btn, x, y = p1, p2, p3
            if y == h then
                if x >= 1 and x <= 6 then activeTab = "HOME"
                elseif x >= 8 and x <= 13 then activeTab = "FILE"
                elseif x >= 15 and x <= 20 then activeTab = "SHLL"
                elseif x >= 22 and x <= 27 then activeTab = "CONF" end
                if activeTab == "SHLL" then
                    drawUI()
                    local old = term.redirect(mainWin)
                    term.setBackgroundColor(colors.black) term.clear() term.setCursorPos(1,1) term.setCursorBlink(true)
                    parallel.waitForAny(function() shell.run("shell") end, function()
                        while true do local _, _, mx, my = os.pullEvent("mouse_click") if my == h then os.queueEvent("mouse_click", 1, mx, my) return end end
                    end)
                    term.setCursorBlink(false) term.redirect(old) activeTab = "HOME"
                end
                drawUI()
            elseif activeTab == "HOME" and btn == 2 then
                local files = fs.list(getHomeDir())
                local sel = nil
                for i, n in ipairs(files) do
                    local col, row = ((i-1)%3)*8+2, math.floor((i-1)/3)*3+2
                    if x >= col and x <= col+3 and y == row then sel = n break end
                end
                showMenu(x, y, sel)
            elseif activeTab == "FILE" and y > 1 and y < h then
                local f = fs.list(currentPath)
                if currentPath ~= "/" then table.insert(f, 1, "..") end
                local s = f[y-1]
                if s then
                    local p = fs.combine(currentPath, s)
                    if fs.isDir(p) then currentPath = p drawUI()
                    else
                        local old = term.redirect(mainWin) term.setCursorBlink(true)
                        shell.run("edit", p) term.setCursorBlink(false) term.redirect(old) drawUI()
                    end
                end
            elseif activeTab == "CONF" then
                if y == 5 then settings.themeIndex = (settings.themeIndex % #themes) + 1 drawUI()
                elseif y == 7 then 
                    fs.delete("startup.lua")
                    shell.run("wget https://github.com/JemmaperXD/jemmaperxd/raw/refs/heads/main/startup.lua startup.lua")
                    os.reboot()
                elseif y == 9 then running = false end
            end
        end
    end
end

-- СТАРТ
bootAnim()
systemAuth()
currentPath = getHomeDir()
if not fs.exists(currentPath) then fs.makeDir(currentPath) end
osEngine()
