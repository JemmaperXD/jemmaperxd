-- ameOs v23.0 [COMPLETE REPAIR & STABLE]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local sideW = 6 -- Панель слева (4 символа + отступы)
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

-- 2. СИСТЕМА СОХРАНЕНИЯ
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

-- 3. АНИМАЦИЯ (Без лагов)
local function bootAnim()
    local cx, cy = math.floor(w/2), math.floor(h/2 - 2)
    local angle = 0
    for f = 1, 35 do
        term.setBackgroundColor(colors.black)
        term.clear()
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
        angle = angle + 0.3
        sleep(0.1)
    end
end

-- 4. ВХОД И ПРОВЕРКА ПАПОК
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

-- 5. ГЛАВНЫЙ ИНТЕРФЕЙС
local function mainApp()
    local taskWin = window.create(term.current(), 1, 1, sideW, h)
    local topWin = window.create(term.current(), sideW + 1, 1, w - sideW, 1)
    local mainWin = window.create(term.current(), sideW + 1, 2, w - sideW, h - 1)
    
    local fileList = {}
    local menu = { {n="HOME", s="HOME"}, {n="FILE", s="FILE"}, {n="SHLL", s="SHLL"}, {n="CONF", s="CONF"} }

    while running do
        local theme = themes[settings.themeIndex]
        
        -- Taskbar (СЛЕВА)
        taskWin.setBackgroundColor(colors.black)
        taskWin.clear()
        for i, m in ipairs(menu) do
            taskWin.setCursorPos(1, i*3)
            if activeTab == m.n then
                taskWin.setBackgroundColor(theme.accent)
                taskWin.setTextColor(theme.text)
            else
                taskWin.setBackgroundColor(colors.black)
                taskWin.setTextColor(colors.white)
            end
            taskWin.write(" "..m.s.." ")
        end
        taskWin.setBackgroundColor(colors.black)
        taskWin.setTextColor(colors.yellow)
        taskWin.setCursorPos(1, h) taskWin.write(textutils.formatTime(os.time(), true):sub(1, sideW))

        -- Top Bar
        topWin.setBackgroundColor(theme.accent)
        topWin.setTextColor(theme.text)
        topWin.clear()
        topWin.setCursorPos(2, 1) topWin.write("ameOs | " .. activeTab)

        -- Content Window
        mainWin.setBackgroundColor(theme.bg)
        mainWin.setTextColor(theme.text)
        mainWin.clear()

        if activeTab == "HOME" then
            mainWin.setCursorPos(2, 2) mainWin.write("User: " .. settings.user)
            mainWin.setCursorPos(2, 4) mainWin.write("Path: " .. currentPath)
        elseif activeTab == "FILE" then
            mainWin.setBackgroundColor(colors.black)
            mainWin.setTextColor(colors.yellow)
            mainWin.setCursorPos(1, 1) mainWin.write(" "..currentPath)
            fileList = fs.list(currentPath)
            if currentPath ~= "/" then table.insert(fileList, 1, "..") end
            for i, n in ipairs(fileList) do
                if i > h-3 then break end
                mainWin.setCursorPos(1, i+1)
                local isD = fs.isDir(fs.combine(currentPath, n))
                mainWin.setTextColor(isD and colors.cyan or colors.white)
                mainWin.write((isD and "> " or "  ") .. n:sub(1, w-sideW-2))
            end
        elseif activeTab == "SHLL" then
            mainWin.setVisible(true)
            local old = term.redirect(mainWin)
            term.setBackgroundColor(colors.black)
            term.setTextColor(colors.white)
            term.clear() term.setCursorPos(1,1)
            print("Terminal Mode. Type 'exit'")
            shell.run("shell")
            term.redirect(old)
            activeTab = "HOME"
        elseif activeTab == "CONF" then
            mainWin.setCursorPos(1, 2) mainWin.write(" Theme: "..theme.name)
            mainWin.setCursorPos(1, 4) mainWin.write(" [ NEXT THEME ]")
            mainWin.setCursorPos(1, 6) mainWin.setTextColor(colors.red)
            mainWin.write(" [ SHUTDOWN ]")
        end

        -- Event Handler
        local ev, btn, x, y = os.pullEvent()
        if ev == "mouse_click" then
            if x <= sideW then -- Клик по таскбару
                local row = math.floor(y/3)
                if row >= 1 and row <= 4 then activeTab = menu[row].n end
            elseif activeTab == "FILE" and y > 2 then -- Проводник
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
                elseif y == 7 then 
                    running = false 
                end
            end
        end
    end
end

-- 6. START
bootAnim()
systemAuth()
local ok, err = pcall(mainApp)
if not ok then
    term.redirect(term.native())
    term.setBackgroundColor(colors.red)
    term.clear()
    term.setCursorPos(1,1)
    print("System Error: "..err)
    sleep(5)
end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
print("ameOs closed.")
