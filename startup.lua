-- ameOs v25.0 [BOTTOM BAR STABLE 2026]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local running = true
local activeTab = "HOME"
local currentPath = "/"

-- 1. ТЕМЫ
local themes = {
    { name = "Cyan", bg = colors.blue,  accent = colors.cyan, text = colors.white },
    { name = "Dark", bg = colors.black, accent = colors.gray, text = colors.lightGray },
    { name = "Hacker", bg = colors.black, accent = colors.lime, text = colors.lime }
}
local settings = { themeIndex = 1, user = "User", pass = "", isRegistered = false }

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

-- 3. АНИМАЦИЯ (15 сек, круг в конце)
local function bootAnim()
    local cx, cy = math.floor(w/2), math.floor(h/2 - 2)
    local duration = 15
    local start = os.clock()
    local angle = 0
    while true do
        local elapsed = os.clock() - start
        if elapsed >= duration then break end
        term.setBackgroundColor(colors.black)
        term.clear()
        if elapsed > 11 then
            term.setTextColor(colors.gray)
            term.setCursorPos(cx-2, cy-1) term.write("#####")
            term.setCursorPos(cx-3, cy)   term.write("#     #")
            term.setCursorPos(cx-2, cy+1) term.write("#####")
            term.setTextColor(colors.cyan)
            for i = 1, 3 do
                local a = angle + (i * 2.1)
                local dx = math.floor(math.cos(a)*2.5+0.5)
                local dy = math.floor(math.sin(a)*1.5+0.5)
                term.setCursorPos(cx+dx, cy+dy) term.write("o")
            end
        end
        local barLen = 14
        local progress = math.floor((elapsed / duration) * barLen)
        term.setCursorPos(w/2 - barLen/2, cy + 5)
        term.setTextColor(colors.gray)
        term.write("["..string.rep("=", progress)..string.rep(" ", barLen-progress).."]")
        term.setCursorPos(w/2 - 2, h - 1)
        term.setTextColor(colors.white)
        term.write("ameOS")
        angle = angle + 0.4
        sleep(0.1)
    end
end

-- 4. АВТОРИЗАЦИЯ
local function systemAuth()
    loadSettings()
    term.setBackgroundColor(colors.gray)
    term.clear()
    if not settings.isRegistered then
        term.setCursorPos(w/2-6, h/2-2) term.write("REGISTRATION")
        term.setCursorPos(w/2-8, h/2)   term.write("Name: ") settings.user = read()
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
    local home = getHomeDir()
    if not fs.exists(home) then fs.makeDir(home) end
    currentPath = home
end

-- 5. ГЛАВНОЕ ПРИЛОЖЕНИЕ
local function mainApp()
    local topWin = window.create(term.current(), 1, 1, w, 1)
    local mainWin = window.create(term.current(), 1, 2, w, h - 2)
    local taskWin = window.create(term.current(), 1, h, w, 1)
    
    local fileList = {}
    local menu = { {n="HOME", x=1}, {n="FILE", x=8}, {n="SHLL", x=15}, {n="CONF", x=22} }

    while running do
        local theme = themes[settings.themeIndex]
        
        -- Taskbar (ВНИЗУ)
        taskWin.setBackgroundColor(colors.black)
        taskWin.clear()
        for i, m in ipairs(menu) do
            taskWin.setCursorPos(m.x, 1)
            taskWin.setBackgroundColor(activeTab == m.n and theme.accent or colors.black)
            taskWin.setTextColor(activeTab == m.n and theme.text or colors.white)
            taskWin.write(" "..m.n.." ")
        end

        -- Top / Main
        topWin.setBackgroundColor(theme.accent)
        topWin.setTextColor(theme.text)
        topWin.clear()
        topWin.setCursorPos(2, 1) topWin.write("ameOs | " .. activeTab)
        topWin.setCursorPos(w-6, 1) topWin.write(textutils.formatTime(os.time(), true))

        mainWin.setBackgroundColor(theme.bg)
        mainWin.setTextColor(theme.text)
        mainWin.clear()

        if activeTab == "HOME" then
            mainWin.setCursorPos(2, 2) mainWin.write("Welcome, " .. settings.user)
        elseif activeTab == "FILE" then
            mainWin.setBackgroundColor(colors.black)
            mainWin.setTextColor(colors.yellow)
            mainWin.setCursorPos(1, 1) mainWin.write(" "..currentPath)
            fileList = fs.list(currentPath)
            if currentPath ~= "/" then table.insert(fileList, 1, "..") end
            for i, n in ipairs(fileList) do
                if i > h-4 then break end
                mainWin.setCursorPos(1, i+1)
                local isD = fs.isDir(fs.combine(currentPath, n))
                mainWin.setTextColor(isD and colors.cyan or colors.white)
                mainWin.write((isD and "> " or "  ") .. n)
            end
        elseif activeTab == "SHLL" then
            mainWin.setVisible(true)
            local old = term.redirect(mainWin)
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
            term.clear() term.setCursorPos(1,1)
            print("Shell Mode. Click Bottom Bar to Exit.")
            parallel.waitForAny(
                function() shell.run("shell") end,
                function()
                    while true do
                        local e, b, x, y = os.pullEvent("mouse_click")
                        if y == h then return end
                    end
                end
            )
            term.redirect(old)
            activeTab = "HOME"
        elseif activeTab == "CONF" then
            mainWin.setCursorPos(1, 2) mainWin.write(" Theme: "..theme.name)
            mainWin.setCursorPos(1, 4) mainWin.write(" [ NEXT THEME ]")
            mainWin.setCursorPos(1, 6) mainWin.setTextColor(colors.red)
            mainWin.write(" [ SHUTDOWN ]")
        end

        -- Events
        local ev, btn, x, y = os.pullEvent("mouse_click")
        if y == h then
            if x >= 1 and x <= 6 then activeTab = "HOME"
            elseif x >= 8 and x <= 13 then activeTab = "FILE"
            elseif x >= 15 and x <= 20 then activeTab = "SHLL"
            elseif x >= 22 and x <= 27 then activeTab = "CONF" end
        elseif activeTab == "FILE" and y > 2 and y < h then
            local sel = fileList[y-2]
            if sel then
                local p = fs.combine(currentPath, sel)
                if fs.isDir(p) then currentPath = p 
                else 
                    local old = term.redirect(mainWin)
                    shell.run("edit", p)
                    term.redirect(old)
                end
            end
        elseif activeTab == "CONF" then
            if y == 5 then 
                settings.themeIndex = (settings.themeIndex % #themes) + 1
                saveSettings() 
            elseif y == 7 then running = false end
        end
    end
end

-- 6. START
bootAnim()
systemAuth()
pcall(mainApp)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
print("ameOs closed.")
