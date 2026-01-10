-- ameOs v15.0 [STABLE BUILD 2026]
-- Фикс серого экрана, вращающееся лого, правый таскбар, защита .config

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
    { name = "Hacker",    bg = colors.black,     accent = colors.lime,    text = colors.lime }
}
local settings = { themeIndex = 1, user = "User", pass = "", isRegistered = false }

-- 2. СИСТЕМА ФАЙЛОВ
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

-- 3. АНИМАЦИЯ ЗАГРУЗКИ (5 секунд, вращение)
local function bootAnim()
    local cx, cy = math.floor(w/2), math.floor(h/2 - 2)
    local endTime = os.clock() + 5
    local angle = 0
    
    while os.clock() < endTime do
        term.setBackgroundColor(colors.black)
        term.clear()
        
        -- Кольцо
        term.setTextColor(colors.gray)
        term.setCursorPos(cx-2, cy-1) term.write("#####")
        term.setCursorPos(cx-3, cy)   term.write("#     #")
        term.setCursorPos(cx-3, cy+1) term.write("#     #")
        term.setCursorPos(cx-2, cy+2) term.write("#####")
        
        -- Вращающиеся точки
        term.setTextColor(colors.cyan)
        for i = 1, 3 do
            local a = angle + (i * (math.pi * 2 / 3))
            local dx = math.floor(math.cos(a) * 2.5 + 0.5)
            local dy = math.floor(math.sin(a) * 1.5 + 0.5)
            term.setCursorPos(cx + dx, cy + 1 + dy)
            term.write("o")
        end
        
        -- Бар прогресса
        local progress = math.floor(((5 - (endTime - os.clock())) / 5) * 10)
        term.setCursorPos(cx-5, cy+5)
        term.setTextColor(colors.gray)
        term.write("[" .. string.rep("=", progress) .. string.rep(" ", 10-progress) .. "]")
        
        angle = angle + 0.3
        sleep(0.05)
    end
end

-- 4. АВТОРИЗАЦИЯ
local function systemAuth()
    loadSettings()
    term.setBackgroundColor(colors.gray)
    term.clear()
    term.setTextColor(colors.white)
    
    if not settings.isRegistered then
        term.setCursorPos(w/2-6, h/2-2) term.write("REGISTRATION")
        term.setCursorPos(w/2-8, h/2)   term.write("User: ") 
        settings.user = read()
        term.setCursorPos(w/2-8, h/2+1) term.write("Pass: ") 
        settings.pass = read("*")
        settings.isRegistered = true
        saveSettings()
    else
        while true do
            term.setBackgroundColor(colors.gray)
            term.clear()
            term.setCursorPos(w/2-6, h/2-1) term.write("LOGIN: "..settings.user)
            term.setCursorPos(w/2-8, h/2+1) term.write("Pass: ")
            local input = read("*")
            if input == settings.pass then break end
        end
    end
end

-- 5. ГЛАВНЫЙ ИНТЕРФЕЙС
local function mainApp()
    -- Создаем окна только ПОСЛЕ авторизации
    local topWin = window.create(term.current(), 1, 1, w - taskbarW, 1)
    local mainWin = window.create(term.current(), 1, 2, w - taskbarW, h - 1)
    local taskWin = window.create(term.current(), w - taskbarW + 1, 1, taskbarW, h)
    
    local fileList = {}

    while running do
        local theme = themes[settings.themeIndex]
        
        -- Отрисовка таскбара
        taskWin.setBackgroundColor(colors.black)
        taskWin.clear()
        local btns = {"Desktop", "Files", "Shell", "Settings"}
        for i, n in ipairs(btns) do
            taskWin.setCursorPos(1, i*2)
            if activeTab == n then
                taskWin.setBackgroundColor(theme.accent)
                taskWin.setTextColor(theme.text)
            else
                taskWin.setBackgroundColor(colors.black)
                taskWin.setTextColor(colors.white)
            end
            taskWin.write(string.format(" %-7s", n))
        end
        -- Время
        taskWin.setBackgroundColor(colors.black)
        taskWin.setTextColor(colors.yellow)
        taskWin.setCursorPos(2, h)
        taskWin.write(textutils.formatTime(os.time(), true))

        -- Отрисовка верхней панели
        topWin.setBackgroundColor(theme.accent)
        topWin.setTextColor(theme.text)
        topWin.clear()
        topWin.setCursorPos(2, 1)
        topWin.write("ameOs")

        -- Отрисовка контента
        mainWin.setBackgroundColor(theme.bg)
        mainWin.setTextColor(theme.text)
        mainWin.clear()

        if activeTab == "Desktop" then
            mainWin.setCursorPos(2, 2)
            mainWin.write("Welcome, " .. settings.user)
            mainWin.setCursorPos(2, 4)
            mainWin.write("Current time: " .. textutils.formatTime(os.time()))
        elseif activeTab == "Files" then
            mainWin.setBackgroundColor(colors.black)
            mainWin.clear()
            mainWin.setTextColor(colors.yellow)
            mainWin.setCursorPos(1,1) mainWin.write(" " .. currentPath)
            fileList = fs.list(currentPath)
            if currentPath ~= "/" then table.insert(fileList, 1, "..") end
            for i, n in ipairs(fileList) do
                if i > h-3 then break end
                mainWin.setCursorPos(1, i+1)
                local isDir = fs.isDir(fs.combine(currentPath, n))
                mainWin.setTextColor(isDir and colors.cyan or colors.white)
                mainWin.write((isDir and "> " or "  ") .. n:sub(1, w-taskbarW-2))
            end
        elseif activeTab == "Shell" then
            mainWin.setVisible(true)
            term.redirect(mainWin)
            print("Type 'exit' to return")
            shell.run("shell")
            term.redirect(term.native())
            activeTab = "Desktop"
        elseif activeTab == "Settings" then
            mainWin.setCursorPos(1, 2) mainWin.write(" Theme: "..theme.name)
            mainWin.setCursorPos(1, 4) mainWin.write(" [ Switch Theme ]")
            mainWin.setCursorPos(1, 6) mainWin.setTextColor(colors.red)
            mainWin.write(" [ Shutdown ]")
        end

        -- Обработка событий
        local ev, button, x, y = os.pullEvent()
        if ev == "mouse_click" then
            if x > w - taskbarW then
                local row = math.floor(y/2)
                if row >= 1 and row <= 4 then activeTab = btns[row] end
            elseif activeTab == "Files" and y > 2 then
                local sel = fileList[y-2]
                if sel then
                    local p = fs.combine(currentPath, sel)
                    if fs.isDir(p) then currentPath = p 
                    else 
                        term.redirect(mainWin) 
                        shell.run("edit", p) 
                        term.redirect(term.native()) 
                    end
                end
            elseif activeTab == "Settings" then
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

-- 6. ТОЧКА ВХОДА
local function start()
    bootAnim()
    systemAuth()
    
    local ok, err = pcall(mainApp)
    if not ok then
        term.redirect(term.native())
        term.setBackgroundColor(colors.red)
        term.setTextColor(colors.white)
        term.clear()
        term.setCursorPos(1,1)
        print("System Error: " .. err)
        print("\nPress any key to reboot...")
        os.pullEvent("key")
        os.reboot()
    end
end

start()

term.setBackgroundColor(colors.black)
term.setTextColor(colors.white)
term.clear()
term.setCursorPos(1,1)
print("ameOs closed.")
