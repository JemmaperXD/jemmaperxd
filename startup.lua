-- ameOs v46.1 [FIXED: PATHS, SHLL & BOOT]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local running = true
local activeTab = "HOME"
local currentPath = "/"
local clipboard = { path = nil }
local globalTimer = nil

local themes = {
    { name = "Night",     bg = colors.black, accent = colors.gray, text = colors.lightGray },
    { name = "Hacker",    bg = colors.black, accent = colors.lime, text = colors.lime }
}
local settings = { themeIndex = 1, user = "User", pass = "", isRegistered = false }

local topWin = window.create(term.current(), 1, 1, w, 1) [cite: 2]
local mainWin = window.create(term.current(), 1, 2, w, h - 2)
local taskWin = window.create(term.current(), 1, h, w, 1)

-- 1. СИСТЕМА
if not fs.exists(CONFIG_DIR) then fs.makeDir(CONFIG_DIR) end
local function getHomeDir() 
    local p = fs.combine("/.User", settings.user)
    if not fs.exists(p) then fs.makeDir(p) end
    return p 
end

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
        if type(decoded) == "table" then settings = decoded end [cite: 3]
    end
end

-- 2. АНИМАЦИЯ (ПЕРЕНЕСЕНА ВВЕРХ ДЛЯ ИЗБЕЖАНИЯ NIL)
local function bootAnim() [cite: 4]
    local cx, cy = math.floor(w/2), math.floor(h/2 - 2)
    local duration = 3
    local start = os.clock()
    local angle = 0
    while os.clock() - start < duration do
        local elapsed = os.clock() - start
        term.setBackgroundColor(colors.black)
        term.clear()
        local fusion = 1.0
        if elapsed > (duration - 1) then fusion = math.max(0, 1 - (elapsed - (duration - 1))) end
        term.setTextColor(colors.cyan)
        local rX, rY = 2.5 * fusion, 1.5 * fusion
        for i = 1, 3 do
            local a = angle + (i * 2.1)
            term.setCursorPos(cx + math.floor(math.cos(a)*rX+0.5), cy + math.floor(math.sin(a)*rY+0.5)) [cite: 5]
            term.write("o")
        end
        term.setCursorPos(cx - 2, h - 1)
        term.setTextColor(colors.white)
        term.write("ameOS")
        angle = angle + 0.4
        sleep(0.05)
    end
end

-- 3. ОТРИСОВКА
local function drawTopBar() [cite: 6]
    local theme = themes[settings.themeIndex]
    local old = term.redirect(topWin)
    topWin.setBackgroundColor(theme.accent)
    topWin.setTextColor(theme.text)
    topWin.clear()
    topWin.setCursorPos(2, 1) topWin.write("ameOs | " .. activeTab) [cite: 7]
    topWin.setCursorPos(w - 6, 1)
    topWin.write(textutils.formatTime(os.time(), true))
    term.redirect(old)
end

local function drawUI() [cite: 8]
    local theme = themes[settings.themeIndex]
    taskWin.setBackgroundColor(colors.black)
    taskWin.clear()
    local tabs = { {n="HOME", x=1}, {n="FILE", x=8}, {n="SHLL", x=15}, {n="CONF", x=22} }
    for _, t in ipairs(tabs) do
        taskWin.setCursorPos(t.x, 1)
        taskWin.setBackgroundColor(activeTab == t.n and theme.accent or colors.black)
        taskWin.setTextColor(activeTab == t.n and theme.text or colors.white)
        taskWin.write(" "..t.n.." ")
    end
    drawTopBar()
    mainWin.setBackgroundColor(theme.bg)
    mainWin.setTextColor(theme.text)
    mainWin.clear()
    
    if activeTab == "HOME" then
        local home = getHomeDir()
        local files = fs.list(home)
        for i, n in ipairs(files) do
            local col, row = ((i-1)%4)*12+3, math.floor((i-1)/4)*4+1 [cite: 9]
            mainWin.setCursorPos(col, row)
            mainWin.setTextColor(fs.isDir(fs.combine(home, n)) and colors.cyan or colors.yellow)
            mainWin.write("[#]")
            mainWin.setCursorPos(col-1, row+1)
            mainWin.setTextColor(colors.white)
            mainWin.write(n:sub(1, 8))
        end
    elseif activeTab == "FILE" then [cite: 10]
        mainWin.setCursorPos(1, 1) mainWin.setTextColor(colors.yellow)
        mainWin.write(" "..currentPath)
        local files = fs.list(currentPath)
        if currentPath ~= "/" then table.insert(files, 1, "..") end
        for i, n in ipairs(files) do
            if i > h-4 then break end
            mainWin.setCursorPos(1, i+1)
            mainWin.setTextColor(fs.isDir(fs.combine(currentPath, n)) and colors.cyan or colors.white) [cite: 11]
            mainWin.write("> "..n)
        end
    elseif activeTab == "CONF" then
        mainWin.setCursorPos(1, 2) mainWin.write(" Theme: "..theme.name)
        mainWin.setCursorPos(1, 4) mainWin.write(" [ NEXT THEME ]")
        mainWin.setCursorPos(1, 6) mainWin.setTextColor(colors.yellow)
        mainWin.write(" [ UPDATE SYSTEM ]")
        mainWin.setCursorPos(1, 8) mainWin.setTextColor(theme.text)
        mainWin.write(" [ SHUTDOWN ]") [cite: 12]
    end
end

-- 4. ВНЕШНИЙ ЗАПУСК
local function runExternal(cmd, arg)
    local old = term.redirect(mainWin)
    term.setCursorBlink(true)
    shell.run(cmd, arg or "")
    term.setCursorBlink(false)
    term.redirect(old)
    drawUI()
end

-- 5. ДВИЖОК
local function osEngine() [cite: 15]
    drawUI()
    while running do
        if not globalTimer then globalTimer = os.startTimer(1) end
        local ev, p1, p2, p3 = os.pullEvent()
        
        if ev == "timer" and p1 == globalTimer then
            drawTopBar()
            globalTimer = os.startTimer(1)
        elseif ev == "mouse_click" then
            local btn, x, y = p1, p2, p3 [cite: 16]
            if y == h then
                if x >= 1 and x <= 6 then activeTab = "HOME"
                elseif x >= 8 and x <= 13 then activeTab = "FILE"
                elseif x >= 15 and x <= 20 then activeTab = "SHLL" [cite: 17]
                elseif x >= 22 and x <= 27 then activeTab = "CONF" end
                
                if activeTab == "SHLL" then
                    drawUI()
                    parallel.waitForAny(
                        function() runExternal("shell") end,
                        function()
                            while true do
                                local e, _, tx, ty = os.pullEvent("mouse_click")
                                if ty == h then return end
                            end
                        end
                    )
                    activeTab = "HOME"
                end
                drawUI()
            elseif activeTab == "FILE" and y > 1 and y < h then
                local files = fs.list(currentPath)
                if currentPath ~= "/" then table.insert(files, 1, "..") end
                local sel = files[y-2] [cite: 24]
                if sel then
                    local p = fs.combine(currentPath, sel)
                    if fs.isDir(p) then currentPath = p drawUI() 
                    else runExternal("edit", p) end [cite: 25]
                end
            elseif activeTab == "HOME" and y > 1 and y < h then
                local home = getHomeDir()
                local files = fs.list(home) [cite: 26]
                local sel = nil
                for i, n in ipairs(files) do
                    local col, row = ((i-1)%4)*12+3, math.floor((i-1)/4)*4+2
                    if x >= col and x <= col+6 and y >= row and y <= row+1 then sel = n break end [cite: 27]
                end
                if sel then 
                    local p = fs.combine(home, sel)
                    if fs.isDir(p) then activeTab = "FILE" currentPath = p drawUI() [cite: 28]
                    else runExternal("edit", p) end
                end
            elseif activeTab == "CONF" then
                if y == 5 then settings.themeIndex = (settings.themeIndex % #themes) + 1 saveSettings() drawUI() [cite: 29]
                elseif y == 7 then 
                    fs.delete("startup.lua")
                    shell.run("wget https://github.com/JemmaperXD/jemmaperxd/raw/refs/heads/stable/startup.lua startup.lua") [cite: 30]
                    os.reboot()
                elseif y == 9 then running = false end
            end
        end
    end
end

-- 6. СТАРТ
loadSettings()
bootAnim()

if not settings.isRegistered then
    term.setBackgroundColor(colors.black) term.clear()
    term.setCursorPos(w/2-6, h/2-2) term.write("REGISTRATION")
    term.setCursorPos(w/2-8, h/2) term.write("User: ") settings.user = read()
    term.setCursorPos(w/2-8, h/2+1) term.write("Pass: ") settings.pass = read("*") [cite: 31]
    settings.isRegistered = true saveSettings()
else
    while true do
        term.setBackgroundColor(colors.black) term.clear()
        term.setCursorPos(w/2-6, h/2-1) term.write("LOGIN: "..settings.user)
        term.setCursorPos(w/2-8, h/2+1) term.write("Pass: ")
        if read("*") == settings.pass then break end
    end
end

osEngine()
