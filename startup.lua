-- ameOs v32.8 [PRE-CONTEXT MENU STABLE]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local running = true
local updateMode = false
local activeTab = "HOME"
local currentPath = "/"

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
local function saveSettings()
    local f = fs.open(SETTINGS_PATH, "w")
    f.write(textutils.serialize(settings))
    f.close()
end

-- 3. АНИМАЦИЯ ЗАГРУЗКИ FUSION
local function bootAnim()
    local cx, cy = math.floor(w/2), math.floor(h/2 - 1)
    for i = 1, 40 do
        local t = os.startTimer(0.05)
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setTextColor(colors.cyan)
        local a = i * 0.4
        for orbit = 1, 3 do
            local ang = a + (orbit * 2.1)
            term.setCursorPos(cx + math.floor(math.cos(ang)*4), cy + math.floor(math.sin(ang)*2))
            term.write("o")
        end
        term.setCursorPos(cx-2, cy+4)
        term.setTextColor(colors.white)
        term.write("ameOS")
        repeat local _, id = os.pullEvent("timer") until id == t
    end
end

-- 4. АВТОРИЗАЦИЯ
local function auth()
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

-- 5. ОТРИСОВКА
local function drawUI()
    local theme = themes[settings.themeIndex]
    
    -- Taskbar
    taskWin.setBackgroundColor(colors.black)
    taskWin.clear()
    local menu = {"HOME", "FILE", "SHLL", "CONF"}
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
    topWin.setCursorPos(2, 1) topWin.write("ameOs | "..activeTab)
    topWin.setCursorPos(w-6, 1) topWin.write(textutils.formatTime(os.time(), true))

    -- Main Window
    mainWin.setBackgroundColor(theme.bg)
    mainWin.setTextColor(theme.text)
    mainWin.clear()

    if activeTab == "HOME" then
        local p = fs.combine("/.User", "."..settings.user)
        if not fs.exists(p) then fs.makeDir(p) end
        local files = fs.list(p)
        for i, n in ipairs(files) do
            local col, row = ((i-1)%3)*8+2, math.floor((i-1)/3)*3+1
            mainWin.setCursorPos(col, row)
            mainWin.setTextColor(fs.isDir(fs.combine(p, n)) and colors.cyan or colors.yellow)
            mainWin.write("[#]")
            mainWin.setCursorPos(col-1, row+1)
            mainWin.setTextColor(colors.white)
            mainWin.write(n:sub(1, 7))
        end
    elseif activeTab == "FILE" then
        mainWin.setCursorPos(1, 1) mainWin.setTextColor(colors.yellow)
        mainWin.write(" "..currentPath)
        local items = fs.list(currentPath)
        if currentPath ~= "/" then table.insert(items, 1, "..") end
        for i, n in ipairs(items) do
            if i > h-4 then break end
            mainWin.setCursorPos(1, i+1)
            local isD = fs.isDir(fs.combine(currentPath, n))
            mainWin.setTextColor(isD and colors.cyan or colors.white)
            mainWin.write((isD and "> " or "  ")..n)
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

-- 6. ГЛАВНЫЙ ЦИКЛ
local function osLoop()
    drawUI()
    local clockTimer = os.startTimer(1)
    while running do
        local ev, p1, p2, p3 = os.pullEvent()
        if ev == "timer" and p1 == clockTimer then
            drawUI()
            clockTimer = os.startTimer(1)
        elseif ev == "mouse_click" then
            local x, y = p2, p3
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
                    parallel.waitForAny(function() shell.run("shell") end, function()
                        while true do local _,_,mx,my = os.pullEvent("mouse_click") if my == h then os.queueEvent("mouse_click", 1, mx, my) return end end
                    end)
                    term.setCursorBlink(false) term.redirect(old)
                    activeTab = "HOME"
                end
                drawUI()
            elseif activeTab == "FILE" and y > 1 and y < h then
                local items = fs.list(currentPath)
                if currentPath ~= "/" then table.insert(items, 1, "..") end
                local sel = items[y-1]
                if sel then
                    local p = fs.combine(currentPath, sel)
                    if fs.isDir(p) then currentPath = p else 
                        local old = term.redirect(mainWin) term.setCursorBlink(true)
                        shell.run("edit", p) term.setCursorBlink(false) term.redirect(old)
                    end
                end
                drawUI()
            elseif activeTab == "CONF" then
                if y == 5 then settings.themeIndex = (settings.themeIndex % #themes) + 1 saveSettings() drawUI()
                elseif y == 7 then running = false updateMode = true
                elseif y == 9 then running = false end
            end
        end
    end
end

-- 7. ЗАПУСК
bootAnim()
auth()
currentPath = fs.combine("/.User", "."..settings.user)
if not fs.exists(currentPath) then fs.makeDir(currentPath) end

osLoop()

-- ПОСТ-ПРОЦЕССЫ
if updateMode then
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1,1)
    print("Updating...")
    if fs.exists("startup.lua") then fs.delete("startup.lua") end
    shell.run("wget", "https://github.com/JemmaperXD/jemmaperxd/raw/refs/heads/main/startup.lua", "startup.lua")
    os.reboot()
end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
print("ameOs closed.")
