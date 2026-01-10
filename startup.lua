-- ameOs v6.0 for Pocket Computer
-- Дата: 10.01.2026

local w, h = term.getSize()
local CONFIG_DIR = "/.config"
local SETTINGS_PATH = CONFIG_DIR .. "/ame_settings.cfg"
local running = true
local activeTab = "Desktop"

-- 1. СИСТЕМА ТЕМ
local themes = {
    { name = "Ame Cyan",  bg = colors.blue,      accent = colors.cyan,    text = colors.white },
    { name = "Dark Mode", bg = colors.black,     accent = colors.gray,    text = colors.lightGray },
    { name = "Lineage",   bg = colors.gray,      accent = colors.lime,    text = colors.white },
    { name = "Hacker",    bg = colors.black,     accent = colors.lime,    text = colors.lime },
    { name = "Sunrise",   bg = colors.orange,    accent = colors.yellow,  text = colors.black }
}

local settings = { themeIndex = 1, userName = "User" }

-- 2. СОХРАНЕНИЕ / ЗАГРУЗКА
if not fs.exists(CONFIG_DIR) then fs.makeDir(CONFIG_DIR) end

local function saveSettings()
    local f = fs.open(SETTINGS_PATH, "w")
    f.write(textutils.serialize(settings))
    f.close()
end

local function loadSettings()
    if fs.exists(SETTINGS_PATH) then
        local f = fs.open(SETTINGS_PATH, "r")
        local data = f.readAll()
        f.close()
        local decoded = textutils.unserialize(data)
        if decoded then settings = decoded end
    end
end

loadSettings()
local currentTheme = themes[settings.themeIndex] or themes[1]

-- 3. ОКНА
local topWin = window.create(term.current(), 1, 1, w, 1)
local mainWin = window.create(term.current(), 1, 2, w, h - 2)
local taskWin = window.create(term.current(), 1, h, w, 1)

-- 4. АНИМАЦИЯ ЗАГРУЗКИ (Lineage style)
local function drawLineageLogo(x, y)
    term.setTextColor(currentTheme.accent)
    term.setCursorPos(x+2, y);   print("#####")
    term.setCursorPos(x+1, y+1); print("#     #")
    term.setCursorPos(x,   y+2); print("#  o o o #")
    term.setCursorPos(x+1, y+3); print("#     #")
    term.setCursorPos(x+2, y+4); print("#####")
end

local function bootAnim()
    term.setBackgroundColor(colors.black)
    term.clear()
    local centerX, centerY = math.floor(w/2 - 4), math.floor(h/2 - 3)
    for i = 1, 10 do
        term.setCursorPos(centerX + 1, centerY + 6)
        term.setTextColor(currentTheme.accent)
        if i % 2 == 0 then drawLineageLogo(centerX, centerY) end
        sleep(0.1)
    end
end

-- 5. ПОТОКИ (МНОГОЗАДАЧНОСТЬ)
local function taskClock()
    while running do
        topWin.setBackgroundColor(currentTheme.accent)
        topWin.setTextColor(currentTheme.text)
        topWin.setCursorPos(w - 8, 1)
        topWin.write(" " .. textutils.formatTime(os.time(), true) .. " ")
        sleep(0.8)
    end
end

local function drawInterface()
    -- Top Bar
    topWin.setBackgroundColor(currentTheme.accent)
    topWin.setTextColor(currentTheme.text)
    topWin.clear()
    topWin.setCursorPos(2, 1)
    topWin.write("ameOs | " .. activeTab)

    -- Taskbar
    taskWin.setBackgroundColor(colors.black)
    taskWin.clear()
    local btn = {"Desktop", "Files", "Settings"}
    for i, name in ipairs(btn) do
        taskWin.setTextColor(activeTab == name and currentTheme.accent or colors.white)
        taskWin.write(" [" .. name .. "] ")
    end
end

local function taskMain()
    while running do
        drawInterface()
        mainWin.setBackgroundColor(currentTheme.bg)
        mainWin.setTextColor(currentTheme.text)
        mainWin.clear()

        if activeTab == "Desktop" then
            mainWin.setCursorPos(2, 2)
            mainWin.write("Welcome, " .. settings.userName)
        elseif activeTab == "Files" then
            local files = fs.list("/")
            for i=1, math.min(#files, h-4) do
                mainWin.setCursorPos(2, i+1)
                mainWin.write("- " .. files[i])
            end
        elseif activeTab == "Settings" then
            mainWin.setCursorPos(2, 2)
            mainWin.write("Theme: " .. currentTheme.name)
            mainWin.setCursorPos(2, 4)
            mainWin.setTextColor(currentTheme.accent)
            mainWin.write("[ Switch Theme ]")
            mainWin.setCursorPos(2, 6)
            mainWin.setTextColor(colors.red)
            mainWin.write("[ Exit OS ]")
        end

        local ev, side, x, y = os.pullEvent("mouse_click")

        if y == h then -- Taskbar
            if x < 10 then activeTab = "Desktop"
            elseif x < 18 then activeTab = "Files"
            else activeTab = "Settings" end
        elseif activeTab == "Settings" then
            if y == 5 then
                settings.themeIndex = settings.themeIndex + 1
                if settings.themeIndex > #themes then settings.themeIndex = 1 end
                currentTheme = themes[settings.themeIndex]
                saveSettings()
            elseif y == 7 then
                running = false
            end
        end
    end
end

-- ЗАПУСК
bootAnim()
parallel.waitForAny(taskClock, taskMain)

-- ВЫХОД
term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1,1)
print("ameOs closed. Configs saved in /.config/")
