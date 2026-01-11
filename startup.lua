-- ameOS v46.0 [LineageOS Style]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local running = true
local activeTab = "HOME"
local currentPath = "/"
local clipboard = { path = nil }
local globalTimer = nil

local themes = {
    { name = "Dark Moss", bg = colors.black, accent = colors.green, text = colors.gray },
    { name = "Abyss", bg = colors.black, accent = colors.cyan, text = colors.gray },
    { name = "Lineage", bg = colors.black, accent = colors.blue, text = colors.white }
}

local settings = { 
    themeIndex = 1, 
    user = "User", 
    pass = "", 
    isRegistered = false,
    soundEnabled = true,
    showClock = true
}

-- Создаем окна
local topWin = window.create(term.current(), 1, 1, w, 1)
local mainWin = window.create(term.current(), 1, 2, w, h - 2)
local taskWin = window.create(term.current(), 1, h, w, 1)

-- Функции системы
if not fs.exists(CONFIG_DIR) then fs.makeDir(CONFIG_DIR) end

local function getHomeDir() 
    return "/home/" .. settings.user 
end

local function saveSettings()
    local f = fs.open(SETTINGS_PATH, "w")
    if f then
        f.write(textutils.serialize(settings))
        f.close()
    end
end

local function loadSettings()
    if fs.exists(SETTINGS_PATH) then
        local f = fs.open(SETTINGS_PATH, "r")
        if f then
            local data = f.readAll()
            f.close()
            local decoded = textutils.unserialize(data)
            if type(decoded) == "table" then
                for k, v in pairs(decoded) do
                    settings[k] = v
                end
            end
        end
    end
end

-- НОВАЯ АНИМАЦИЯ ЗАГРУЗКИ LINEAGEOS
local function lineageBootAnim()
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorBlink(false)
    
    local centerX, centerY = math.floor(w/2), math.floor(h/2)
    local radius = 4
    local duration = 3.5
    local startTime = os.clock()
    
    -- Анимация круга
    while os.clock() - startTime < duration do
        local elapsed = os.clock() - startTime
        local progress = elapsed / duration
        
        term.setBackgroundColor(colors.black)
        term.clear()
        
        -- Рисуем внешний круг
        term.setTextColor(colors.blue)
        for angle = 0, 360, 30 do
            local rad = math.rad(angle)
            local x = centerX + math.floor(math.cos(rad) * radius + 0.5)
            local y = centerY + math.floor(math.sin(rad) * radius + 0.5)
            term.setCursorPos(x, y)
            term.write("o")
        end
        
        -- Рисуем заполняющийся прогресс
        term.setTextColor(colors.cyan)
        local fillAngle = progress * 360
        for angle = 0, fillAngle, 30 do
            local rad = math.rad(angle)
            local x = centerX + math.floor(math.cos(rad) * (radius - 1) + 0.5)
            local y = centerY + math.floor(math.sin(rad) * (radius - 1) + 0.5)
            term.setCursorPos(x, y)
            term.write("•")
        end
        
        -- Текст загрузки
        term.setTextColor(colors.white)
        term.setCursorPos(centerX - 4, centerY + radius + 2)
        term.write("ameOS")
        
        -- Процент
        term.setCursorPos(centerX - 2, centerY + radius + 3)
        term.setTextColor(colors.green)
        term.write(math.floor(progress * 100) .. "%")
        
        sleep(0.1)
    end
    
    -- Финальный экран
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setTextColor(colors.cyan)
    
    -- Логотип
    local logo = {
        "╔══════════════╗",
        "║    ameOS     ║",
        "║  LineageOS   ║",
        "║    Style     ║",
        "╚══════════════╝"
    }
    
    for i, line in ipairs(logo) do
        term.setCursorPos(centerX - math.floor(#line/2), centerY - 3 + i)
        term.write(line)
        sleep(0.1)
    end
    
    sleep(1)
end

-- Функции интерфейса
local function drawTopBar()
    local theme = themes[settings.themeIndex]
    local old = term.redirect(topWin)
    topWin.setBackgroundColor(theme.accent)
    topWin.setTextColor(theme.text)
    topWin.clear()
    
    topWin.setCursorPos(2, 1)
    topWin.write("ameOS | " .. activeTab)
    
    if settings.showClock then
        topWin.setCursorPos(w - 8, 1)
        topWin.write(os.date("%H:%M"))
    end
    
    term.redirect(old)
end

local function drawUI()
    local theme = themes[settings.themeIndex]
    
    -- Очищаем и настраиваем основное окно
    mainWin.setBackgroundColor(theme.bg)
    mainWin.setTextColor(theme.text)
    mainWin.clear()
    mainWin.setCursorBlink(false)
    
    -- Очищаем и настраиваем панель задач
    taskWin.setBackgroundColor(colors.black)
    taskWin.clear()
    
    -- Рисуем вкладки
    local tabs = {"HOME", "FILE", "CONF"}
    local x = 2
    for _, tab in ipairs(tabs) do
        taskWin.setCursorPos(x, 1)
        if activeTab == tab then
            taskWin.setBackgroundColor(theme.accent)
            taskWin.setTextColor(theme.text)
        else
            taskWin.setBackgroundColor(colors.black)
            taskWin.setTextColor(colors.white)
        end
        taskWin.write(" " .. tab .. " ")
        x = x + #tab + 3
    end
    
    -- Рисуем верхнюю панель
    drawTopBar()
    
    -- Содержимое в зависимости от активной вкладки
    if activeTab == "HOME" then
        local home = getHomeDir()
        if not fs.exists(home) then fs.makeDir(home) end
        
        mainWin.setCursorPos(2, 2)
        mainWin.setTextColor(theme.accent)
        mainWin.write("Welcome, " .. settings.user .. "!")
        
        mainWin.setCursorPos(2, 4)
        mainWin.setTextColor(theme.text)
        mainWin.write("Home Directory:")
        
        local files = fs.list(home)
        for i, file in ipairs(files) do
            if i <= h - 6 then
                mainWin.setCursorPos(4, 5 + i)
                local isDir = fs.isDir(fs.combine(home, file))
                mainWin.setTextColor(isDir and colors.yellow or colors.white)
                mainWin.write((isDir and "📁 " or "📄 ") .. file)
            end
        end
        
    elseif activeTab == "FILE" then
        mainWin.setCursorPos(2, 2)
        mainWin.setTextColor(theme.accent)
        mainWin.write("Path: " .. currentPath)
        
        local files = fs.list(currentPath)
        if currentPath ~= "/" then
            table.insert(files, 1, "..")
        end
        
        for i, file in ipairs(files) do
            if i <= h - 4 then
                mainWin.setCursorPos(2, 3 + i)
                local path = fs.combine(currentPath, file)
                local isDir = fs.isDir(path)
                mainWin.setTextColor(isDir and colors.cyan or colors.white)
                mainWin.write("> " .. file)
            end
        end
        
    elseif activeTab == "CONF" then
        mainWin.setCursorPos(2, 2)
        mainWin.setTextColor(theme.accent)
        mainWin.write("Settings")
        
        mainWin.setCursorPos(2, 4)
        mainWin.setTextColor(theme.text)
        mainWin.write("Theme: " .. themes[settings.themeIndex].name)
        
        mainWin.setCursorPos(2, 5)
        mainWin.setTextColor(theme.text)
        mainWin.write("Sound: " .. (settings.soundEnabled and "ON" or "OFF"))
        
        mainWin.setCursorPos(2, 6)
        mainWin.setTextColor(theme.text)
        mainWin.write("Show Clock: " .. (settings.showClock and "ON" or "OFF"))
        
        mainWin.setCursorPos(2, 8)
        mainWin.setTextColor(colors.yellow)
        mainWin.write("[Change Theme]")
        
        mainWin.setCursorPos(2, 9)
        mainWin.setTextColor(colors.yellow)
        mainWin.write("[Toggle Sound]")
        
        mainWin.setCursorPos(2, 10)
        mainWin.setTextColor(colors.yellow)
        mainWin.write("[Toggle Clock]")
        
        mainWin.setCursorPos(2, 12)
        mainWin.setTextColor(colors.red)
        mainWin.write("[Shutdown]")
    end
end

-- Основной цикл
local function mainLoop()
    loadSettings()
    
    -- Запускаем анимацию загрузки
    lineageBootAnim()
    
    -- Показываем интерфейс
    drawUI()
    
    globalTimer = os.startTimer(0.5)
    
    while running do
        local event, p1, p2, p3 = os.pullEvent()
        
        if event == "timer" and p1 == globalTimer then
            drawTopBar()
            globalTimer = os.startTimer(0.5)
            
        elseif event == "mouse_click" then
            local button, x, y = p1, p2, p3
            
            -- Клик по панели задач
            if y == h then
                if x >= 2 and x <= 6 then
                    activeTab = "HOME"
                elseif x >= 9 and x <= 13 then
                    activeTab = "FILE"
                elseif x >= 16 and x <= 19 then
                    activeTab = "CONF"
                end
                drawUI()
                
            -- Клик в основном окне
            elseif y > 1 and y < h then
                if activeTab == "CONF" then
                    if y == 8 then -- Change Theme
                        settings.themeIndex = settings.themeIndex + 1
                        if settings.themeIndex > #themes then
                            settings.themeIndex = 1
                        end
                        saveSettings()
                        drawUI()
                    elseif y == 9 then -- Toggle Sound
                        settings.soundEnabled = not settings.soundEnabled
                        saveSettings()
                        drawUI()
                    elseif y == 10 then -- Toggle Clock
                        settings.showClock = not settings.showClock
                        saveSettings()
                        drawUI()
                    elseif y == 12 then -- Shutdown
                        running = false
                    end
                    
                elseif activeTab == "FILE" then
                    local files = fs.list(currentPath)
                    if currentPath ~= "/" then
                        table.insert(files, 1, "..")
                    end
                    
                    local line = y - 2
                    if line >= 1 and line <= #files then
                        local selected = files[line]
                        local path = fs.combine(currentPath, selected)
                        
                        if fs.isDir(path) then
                            currentPath = path
                            drawUI()
                        else
                            shell.run("edit", path)
                            drawUI()
                        end
                    end
                end
            end
        end
    end
    
    -- Завершение работы
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.white)
    term.write("Shutting down...")
    sleep(1)
    term.clear()
end

-- Запускаем систему
local success, err = pcall(mainLoop)
if not success then
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1, 1)
    term.setTextColor(colors.red)
    term.write("Error: " .. tostring(err))
    sleep(3)
end
