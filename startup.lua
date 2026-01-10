-- ameOs v20.0 [RIGHT SLIM SIDEBAR 2026]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local taskW = 6 -- Ультра-узкая панель справа
local running = true
local activeTab = "Home"
local currentPath = "/"

-- 1. ТЕМЫ И НАСТРОЙКИ
local themes = {
    { name = "Cyan", bg = colors.blue,  accent = colors.cyan, text = colors.white },
    { name = "Dark", bg = colors.black, accent = colors.gray, text = colors.lightGray },
    { name = "Hacker", bg = colors.black, accent = colors.lime, text = colors.lime }
}
local settings = { themeIndex = 1, user = "User", pass = "", isRegistered = false }

if not fs.exists(CONFIG_DIR) then fs.makeDir(CONFIG_DIR) end
local function getHomeDir() return "/.User/." .. settings.user end

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

-- 2. ПЛАВНАЯ АНИМАЦИЯ (Двойная буферизация)
local function bootAnim()
    local buf = window.create(term.current(), 1, 1, w, h)
    local cx, cy = math.floor(w/2), math.floor(h/2 - 2)
    local angle = 0
    for f = 1, 40 do
        buf.setBackgroundColor(colors.black)
        buf.clear()
        buf.setTextColor(colors.gray)
        buf.setCursorPos(cx-2, cy-1) buf.write("#####")
        buf.setTextColor(colors.cyan)
        for i = 1, 3 do
            local a = angle + (i * 2.1)
            local dx, dy = math.floor(math.cos(a)*2.5+0.5), math.floor(math.sin(a)*1.5+0.5)
            buf.setCursorPos(cx+dx, cy+dy) buf.write("o")
        end
        buf.setVisible(true) buf.setVisible(false)
        angle = angle + 0.3
        sleep(0.05)
    end
end

-- 3. АВТОРИЗАЦИЯ
local function systemAuth()
    loadSettings()
    term.setBackgroundColor(colors.gray)
    term.clear()
    if not settings.isRegistered then
        term.setCursorPos(w/2-4, h/2-2) print("HELLO")
        term.setCursorPos(w/2-8, h/2) write("Name: ") settings.user = read()
        term.setCursorPos(w/2-8, h/2+1) write("Pass: ") settings.pass = read("*")
        settings.isRegistered = true
        saveSettings()
    else
        while true do
            term.setBackgroundColor(colors.gray) term.clear()
            term.setCursorPos(w/2-6, h/2-1) print("USER: "..settings.user)
            term.setCursorPos(w/2-8, h/2+1) write("Pass: ")
            if read("*") == settings.pass then break end
        end
    end
    local home = getHomeDir()
    if not fs.exists(home) then fs.makeDir(home) end
    currentPath = home
end

-- 4. ГЛАВНОЕ ПРИЛОЖЕНИЕ
local function mainApp()
    -- Окна: контент слева, панель справа
    local topWin = window.create(term.current(), 1, 1, w - taskW, 1)
    local mainWin = window.create(term.current(), 1, 2, w - taskW, h - 1)
    local taskWin = window.create(term.current(), w - taskW + 1, 1, taskW, h)
    
    local fileList = {}
    local menu = { {n="Home", s="Home"}, {n="Files", s="File"}, {n="Shell", s="Shll"}, {n="Set", s="Conf"} }

    while running do
        local theme = themes[settings.themeIndex]
        
        -- Панель задач (Справа)
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
        taskWin.setCursorPos(1, h) taskWin.write(textutils.formatTime(os.time(),true):sub(1,taskW))

        -- Верх
        topWin.setBackgroundColor(theme.accent)
        topWin.setTextColor(theme.text)
        topWin.clear()
        topWin.setCursorPos(2, 1) topWin.write("ameOs")

        -- Контент
        mainWin.setBackgroundColor(theme.bg)
        mainWin.setTextColor(theme.text)
        mainWin.clear()

        if activeTab == "Home" then
            mainWin.setCursorPos(2, 2) mainWin.write("User: " .. settings.user)
            mainWin.setCursorPos(2, 4) mainWin.setTextColor(colors.gray)
            mainWin.write("Dir: " .. getHomeDir())
        elseif activeTab == "Files" then
            mainWin.setBackgroundColor(colors.black)
            mainWin.clear()
            mainWin.setTextColor(colors.yellow)
            mainWin.setCursorPos(1,1) mainWin.write(" "..currentPath)
            fileList = fs.list(currentPath)
            if currentPath ~= "/" then table.insert(fileList, 1, "..") end
            for i, n in ipairs(fileList) do
                if i > h-3 then break end
                mainWin.setCursorPos(1, i+1)
                local isD = fs.isDir(fs.combine(currentPath, n))
                mainWin.setTextColor(isD and colors.cyan or colors.white)
                mainWin.write((isD and "> " or "  ") .. n:sub(1, w-taskW-2))
            end
        elseif activeTab == "Shell" then
            mainWin.setVisible(true)
            local old = term.redirect(mainWin)
            print("Type 'exit' to return")
            shell.run("shell")
            term.redirect(old)
            activeTab = "Home"
        elseif activeTab == "Set" then
            mainWin.setCursorPos(1, 2) mainWin.write(" Theme: "..theme.name)
            mainWin.setCursorPos(1, 4) mainWin.write(" [ NEXT ]")
            mainWin.setCursorPos(1, 6) mainWin.setTextColor(colors.red)
            mainWin.write(" [ EXIT ]")
        end

        local ev, btn, x, y = os.pullEvent()
        if ev == "mouse_click" then
            if x > w - taskW then
                local row = math.floor(y/3)
                if row >= 1 and row <= 4 then activeTab = menu[row].n end
            elseif activeTab == "Files" and y > 2 then
                local sel = fileList[y-2]
                if sel then
                    local p = fs.combine(currentPath, sel)
                    if fs.isDir(p) then currentPath = p 
                    else 
                        mainWin.setVisible(true)
                        local old = term.redirect(mainWin)
                        shell.run("edit", p)
                        term.redirect(old)
                    end
                end
            elseif activeTab == "Set" then
                if y == 5 then settings.themeIndex = (settings.themeIndex % #themes) + 1 saveSettings()
                elseif y == 7 then running = false end
            end
        end
    end
end

-- 5. СТАРТ
bootAnim()
systemAuth()
pcall(mainApp)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
print("ameOs closed.")
