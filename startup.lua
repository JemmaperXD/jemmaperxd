-- ameOs v11.0: Ultimate Pocket Edition
-- Дата выпуска: 10.01.2026
-- Особенности: Вертикальный таскбар, Контекстное меню ПКМ, Защита /.config

local w, h = term.getSize()
local CONFIG_DIR = "/.config"
local SETTINGS_PATH = CONFIG_DIR .. "/ame_settings.cfg"
local taskbarW = 9
local running = true
local activeTab = "Desktop"
local currentPath = "/"

-- 1. ТЕМЫ
local themes = {
    { name = "Ame Cyan",  bg = colors.blue,      accent = colors.cyan,    text = colors.white },
    { name = "Dark Mode", bg = colors.black,     accent = colors.gray,    text = colors.lightGray },
    { name = "Hacker",    bg = colors.black,     accent = colors.lime,    text = colors.lime },
    { name = "Lineage",   bg = colors.gray,      accent = colors.lime,    text = colors.white }
}

local settings = { themeIndex = 1, user = "", pass = "", isRegistered = false }

-- 2. СИСТЕМА ФАЙЛОВ И НАСТРОЕК
if not fs.exists(CONFIG_DIR) then fs.makeDir(CONFIG_DIR) end

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

-- 3. ГРАФИЧЕСКИЕ ОКНА
local mainWin = window.create(term.current(), 1, 2, w - taskbarW, h - 1)
local topWin = window.create(term.current(), 1, 1, w - taskbarW, 1)
local taskWin = window.create(term.current(), w - taskbarW + 1, 1, taskbarW, h)

-- 4. АНИМАЦИЯ ЗАГРУЗКИ (5 СЕКУНД)
local function drawLineageLogo(x, y, color)
    term.setTextColor(color)
    term.setCursorPos(x+2, y);   print("#####")
    term.setCursorPos(x+1, y+1); print("#     #")
    term.setCursorPos(x,   y+2); print("#  o o o #")
    term.setCursorPos(x+1, y+3); print("#     #")
    term.setCursorPos(x+2, y+4); print("#####")
end

local function bootAnim()
    local centerX, centerY = math.floor(w/2 - 4), math.floor(h/2 - 3)
    local timer = os.startTimer(5)
    local frame = 0
    while true do
        term.setBackgroundColor(colors.black)
        term.clear()
        local pulse = (frame % 2 == 0) and colors.cyan or colors.blue
        drawLineageLogo(centerX, centerY, pulse)
        
        term.setCursorPos(centerX-1, centerY+6)
        term.setTextColor(colors.gray)
        local bar = math.min(math.floor((frame/25)*10), 10)
        write("["..string.rep("=", bar)..string.rep(" ", 10-bar).."]")
        
        frame = frame + 1
        local ev, id = os.pullEvent()
        if ev == "timer" and id == timer then break end
        if ev ~= "timer" then sleep(0.1) end
    end
end

-- 5. АВТОРИЗАЦИЯ
local function systemAuth()
    loadSettings()
    term.setBackgroundColor(colors.gray)
    term.clear()
    if not settings.isRegistered then
        term.setCursorPos(w/2-6, h/2-2) print("REGISTRATION")
        term.setCursorPos(w/2-8, h/2) write("User: ") settings.user = read()
        term.setCursorPos(w/2-8, h/2+1) write("Pass: ") settings.pass = read("*")
        settings.isRegistered = true
        saveSettings()
    else
        while true do
            term.setBackgroundColor(colors.gray) term.clear()
            term.setCursorPos(w/2-6, h/2-1) print("LOGIN: "..settings.user)
            term.setCursorPos(w/2-8, h/2+1) write("Pass: ")
            if read("*") == settings.pass then break end
        end
    end
end

-- 6. ПРОВОДНИК
local fileList = {}
local function drawExplorer()
    mainWin.setBackgroundColor(colors.black)
    mainWin.clear()
    mainWin.setCursorPos(1, 1)
    mainWin.setTextColor(colors.yellow)
    mainWin.write(" " .. currentPath)
    fileList = fs.list(currentPath)
    if currentPath ~= "/" then table.insert(fileList, 1, "..") end
    for i, name in ipairs(fileList) do
        if i > h-3 then break end
        mainWin.setCursorPos(1, i+1)
        local isDir = fs.isDir(fs.combine(currentPath, name))
        mainWin.setTextColor(isDir and colors.cyan or colors.white)
        mainWin.write((isDir and "> " or "  ") .. name:sub(1, w-taskbarW-2))
    end
end

-- 7. ГЛАВНОЕ ПРИЛОЖЕНИЕ
local function mainApp()
    while running do
        local theme = themes[settings.themeIndex]
        
        -- Taskbar
        taskWin.setBackgroundColor(colors.black)
        taskWin.clear()
        local btns = {"Desktop", "Files", "Shell", "Settings"}
        for i, n in ipairs(btns) do
            taskWin.setCursorPos(1, i*2)
            taskWin.setBackgroundColor(activeTab == n and theme.accent or colors.black)
            taskWin.setTextColor(activeTab == n and theme.text or colors.white)
            taskWin.write(string.format(" %-7s", n))
        end
        taskWin.setBackgroundColor(colors.black)
        taskWin.setTextColor(colors.yellow)
        taskWin.setCursorPos(2, h) taskWin.write(textutils.formatTime(os.time(), true))

        -- Top bar & Main
        topWin.setBackgroundColor(theme.accent)
        topWin.setTextColor(theme.text)
        topWin.clear() topWin.setCursorPos(2,1) topWin.write("ameOs")

        mainWin.setBackgroundColor(theme.bg)
        mainWin.setTextColor(theme.text)
        mainWin.clear()

        if activeTab == "Desktop" then
            mainWin.setCursorPos(2,2) mainWin.write("Welcome, "..settings.user)
        elseif activeTab == "Files" then drawExplorer()
        elseif activeTab == "Shell" then
            mainWin.setVisible(true) term.redirect(mainWin)
            shell.run("shell") term.redirect(term.native())
            activeTab = "Desktop"
        elseif activeTab == "Settings" then
            mainWin.setCursorPos(1,2) mainWin.write(" Theme: "..theme.name)
            mainWin.setCursorPos(1,4) mainWin.write(" [ Switch Theme ]")
            mainWin.setCursorPos(1,6) mainWin.setTextColor(colors.red)
            mainWin.write(" [ Exit OS ]")
        end

        local ev, btn, x, y = os.pullEvent()
        if ev == "mouse_click" then
            if x > w - taskbarW then
                local row = math.floor(y/2)
                if row >= 1 and row <= 4 then activeTab = btns[row] end
            elseif activeTab == "Files" and y > 2 then
                local sel = fileList[y-2]
                if sel then
                    local p = fs.combine(currentPath, sel)
                    if fs.isDir(p) then currentPath = p 
                    else term.redirect(mainWin) shell.run("edit", p) term.redirect(term.native()) end
                end
            elseif activeTab == "Settings" and y == 5 then
                settings.themeIndex = (settings.themeIndex % #themes) + 1
                saveSettings()
            elseif activeTab == "Settings" and y == 7 then running = false end
        end
    end
end

-- 8. ЗАПУСК
bootAnim()
local ok, err = pcall(function()
    systemAuth()
    mainApp()
end)

if not ok then
    term.redirect(term.native())
    term.setBackgroundColor(colors.red)
    term.clear()
    term.setCursorPos(1,1)
    print("CRITICAL ERROR:")
    print(err)
    sleep(5)
end

term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
print("ameOs closed.")
