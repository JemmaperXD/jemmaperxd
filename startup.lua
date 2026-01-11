[file name]: изображение.png
[file content begin]
\[0 \textcircled{1} 0\]
[file content end]

-- ameOs v46.0 [TOTAL CLOCK & NAVIGATION FIX]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local running = true
local activeTab = "HOME"
local currentPath = "/"
local clipboard = { path = nil }
local globalTimer = nil

local themes = {
    { name = "Dark Moss", bg = colors.black, accent = colors.green, text = colors.gray },
    { name = "Abyss",     bg = colors.black, accent = colors.cyan, text = colors.gray },
    { name = "Charcoal",  bg = colors.black, accent = colors.gray, text = colors.lightGray },
    { name = "Slate",     bg = colors.black, accent = colors.lightGray, text = colors.gray },
    { name = "Lineage",   bg = colors.black, accent = colors.blue, text = colors.white }
}
local settings = { 
    themeIndex = 1, 
    user = "User", 
    pass = "", 
    isRegistered = false,
    soundEnabled = true,
    autoStart = true,
    showHidden = false,
    language = "EN",
    animationSpeed = 1.0,
    showClock = true,
    showBattery = true,
    fontSize = 1
}

local topWin = window.create(term.current(), 1, 1, w, 1)
local mainWin = window.create(term.current(), 1, 2, w, h - 2)
local taskWin = window.create(term.current(), 1, h, w, 1)

-- 1. SYSTEM UTILS
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
        local decoded = textutils.unserialize(data or "")
        if type(decoded) == "table" then 
            for k, v in pairs(decoded) do
                settings[k] = v
            end
            if settings.themeIndex > #themes then
                settings.themeIndex = 1
            end
        end
    end
end

local function getUniquePath(dir, name)
    local path = fs.combine(dir, name)
    if not fs.exists(path) then return path end
    
    local ext = ""
    local base = name
    local dotPos = name:find("%.[^%.]*$")
    if dotPos then
        base = name:sub(1, dotPos-1)
        ext = name:sub(dotPos)
    end
    
    local counter = 1
    repeat
        path = fs.combine(dir, base .. "(" .. counter .. ")" .. ext)
        counter = counter + 1
    until not fs.exists(path)
    return path
end

local function normalizePath(path)
    if path == "" or path == nil then
        return "/"
    end
    path = path:gsub("//+", "/")
    if path:sub(1, 1) ~= "/" then
        path = "/" .. path
    end
    return path
end

-- 2. НОВАЯ АНИМАЦИЯ ЗАГРУЗКИ В СТИЛЕ LINEAGEOS
local function lineageBootAnim()
    while true do
        local success, error = pcall(function()
            local centerX, centerY = math.floor(w/2), math.floor(h/2 - 2)
            local radius = 5
            local duration = 4
            local startTime = os.clock()
            local dots = {"⠋", "⠙", "⠹", "⠸", "⠼", "⠴", "⠦", "⠧", "⠇", "⠏"}
            local dotIndex = 1
            
            -- Анимация кругового прогресса
            while os.clock() - startTime < duration do
                local elapsed = os.clock() - startTime
                term.setBackgroundColor(colors.black)
                term.clear()
                
                -- Рисуем внешний круг
                term.setTextColor(colors.blue)
                for angle = 0, 360, 15 do
                    local rad = math.rad(angle)
                    local x = centerX + math.floor(math.cos(rad) * radius + 0.5)
                    local y = centerY + math.floor(math.sin(rad) * radius + 0.5)
                    term.setCursorPos(x, y)
                    term.write("●")
                end
                
                -- Рисуем заполняющийся внутренний круг
                local progress = math.min(1, elapsed / duration)
                local fillAngle = progress * 360
                term.setTextColor(colors.cyan)
                
                for angle = 0, fillAngle, 15 do
                    local rad = math.rad(angle)
                    local x = centerX + math.floor(math.cos(rad) * (radius - 1) + 0.5)
                    local y = centerY + math.floor(math.sin(rad) * (radius - 1) + 0.5)
                    term.setCursorPos(x, y)
                    term.write("◉")
                end
                
                -- Текст и анимированные точки
                term.setTextColor(colors.white)
                term.setCursorPos(centerX - 4, centerY + radius + 2)
                term.write("ameOS " .. dots[dotIndex])
                
                term.setCursorPos(centerX - 6, centerY + radius + 3)
                term.setTextColor(colors.lightGray)
                local loadingText = "Loading"
                for i = 1, math.floor((elapsed * 3) % 4) do
                    loadingText = loadingText .. "."
                end
                term.write(loadingText)
                
                -- Процент загрузки
                term.setCursorPos(centerX - 2, centerY + radius + 4)
                term.setTextColor(colors.green)
                term.write(math.floor(progress * 100) .. "%")
                
                dotIndex = (dotIndex % #dots) + 1
                sleep(0.1 * settings.animationSpeed)
            end
            
            -- Финальный экран
            term.setBackgroundColor(colors.black)
            term.clear()
            term.setTextColor(colors.cyan)
            
            -- Логотип
            local logo = {
                "╔══════════════════╗",
                "║     ameOS       ║",
                "║   Lineage Style  ║",
                "╚══════════════════╝"
            }
            
            for i, line in ipairs(logo) do
                term.setCursorPos(centerX - math.floor(#line/2), centerY - 2 + i)
                term.write(line)
            end
            
            -- Анимация появления строк
            term.setTextColor(colors.white)
            local messages = {
                "Initializing system...",
                "Loading modules...",
                "Starting services...",
                "Welcome!"
            }
            
            for i, msg in ipairs(messages) do
                term.setCursorPos(centerX - math.floor(#msg/2), centerY + 2 + i)
                for j = 1, #msg do
                    term.write(msg:sub(j, j))
                    sleep(0.05 * settings.animationSpeed)
                end
                sleep(0.3 * settings.animationSpeed)
            end
            
            sleep(1)
            return true
        end)
        
        if success then
            break
        end
        sleep(0.1)
    end
end

-- 3. RENDERING
local function drawTopBar()
    local theme = themes[settings.themeIndex]
    local old = term.redirect(topWin)
    topWin.setCursorBlink(false)
    topWin.setBackgroundColor(theme.accent)
    topWin.setTextColor(theme.text)
    topWin.clear()
    topWin.setCursorPos(2, 1) topWin.write("ameOs | " .. activeTab)
    
    -- Добавляем дополнительные индикаторы
    if settings.showClock then
        topWin.setCursorPos(w - 10, 1)
        topWin.write(textutils.formatTime(os.time(), true))
    end
    
    if settings.showBattery then
        topWin.setCursorPos(w - 15, 1)
        topWin.write("[PWR]")
    end
    
    term.redirect(old)
end

local function drawUI()
    local theme = themes[settings.themeIndex]
    taskWin.setBackgroundColor(colors.black)
    taskWin.clear()
    taskWin.setCursorBlink(false)
    local tabs = { {n="HOME", x=1}, {n="FILE", x=8}, {n="SHLL", x=15}, {n="CONF", x=22}, {n="SYS", x=29} }
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
        if not fs.exists(home) then fs.makeDir(home) end
        local files = fs.list(home)
        for i, n in ipairs(files) do
            local col, row = ((i-1)%4)*12+3, math.floor((i-1)/4)*4+1
            mainWin.setCursorPos(col, row)
            mainWin.setTextColor(fs.isDir(fs.combine(home, n)) and colors.yellow or colors.blue)
            mainWin.write("[#]")
            mainWin.setCursorPos(col-1, row+1)
            mainWin.setTextColor(colors.white)
            mainWin.write(n:sub(1, 8))
        end
    elseif activeTab == "FILE" then
        mainWin.setCursorPos(1, 1) mainWin.setTextColor(colors.yellow)
        mainWin.write(" "..normalizePath(currentPath))
        local files = fs.list(currentPath)
        if currentPath ~= "/" then table.insert(files, 1, "..") end
        for i, n in ipairs(files) do
            if i > h-4 then break end
            mainWin.setCursorPos(1, i+1)
            mainWin.setTextColor(fs.isDir(fs.combine(currentPath, n)) and colors.cyan or colors.white)
            mainWin.write("> "..n)
        end
    elseif activeTab == "CONF" then
        local y = 2
        mainWin.setCursorPos(1, y) mainWin.write(" Theme: "..theme.name)
        y = y + 1
        mainWin.setCursorPos(1, y) mainWin.write(" [ NEXT THEME ]")
        y = y + 2
        mainWin.setCursorPos(1, y) mainWin.write(" Sound: " .. (settings.soundEnabled and "[ON]" or "[OFF]"))
        y = y + 1
        mainWin.setCursorPos(1, y) mainWin.write(" AutoStart: " .. (settings.autoStart and "[ON]" or "[OFF]"))
        y = y + 1
        mainWin.setCursorPos(1, y) mainWin.write(" Show Hidden: " .. (settings.showHidden and "[ON]" or "[OFF]"))
        y = y + 1
        mainWin.setCursorPos(1, y) mainWin.write(" Language: [" .. settings.language .. "]")
        y = y + 1
        mainWin.setCursorPos(1, y) mainWin.write(" Anim Speed: " .. string.format("[%.1f]", settings.animationSpeed))
        y = y + 1
        mainWin.setCursorPos(1, y) mainWin.write(" Show Clock: " .. (settings.showClock and "[ON]" or "[OFF]"))
        y = y + 1
        mainWin.setCursorPos(1, y) mainWin.write(" Show Battery: " .. (settings.showBattery and "[ON]" or "[OFF]"))
        y = y + 2
        mainWin.setCursorPos(1, y) mainWin.setTextColor(colors.yellow)
        mainWin.write(" [ UPDATE SYSTEM ]")
        y = y + 2
        mainWin.setCursorPos(1, y) mainWin.setTextColor(theme.text)
        mainWin.write(" [ SHUTDOWN ]")
    elseif activeTab == "SYS" then
        mainWin.setCursorPos(1, 2) mainWin.setTextColor(colors.cyan)
        mainWin.write("System Information:")
        mainWin.setCursorPos(1, 4) mainWin.setTextColor(colors.white)
        mainWin.write("OS: ameOS v46.0")
        mainWin.setCursorPos(1, 5) mainWin.write("User: " .. settings.user)
        mainWin.setCursorPos(1, 6) mainWin.write("Screen: " .. w .. "x" .. h)
        mainWin.setCursorPos(1, 7) mainWin.write("Theme: " .. theme.name)
        mainWin.setCursorPos(1, 8) mainWin.write("Files in Home: " .. #fs.list(getHomeDir()))
        
        mainWin.setCursorPos(1, 10) mainWin.setTextColor(colors.yellow)
        mainWin.write("System Actions:")
        mainWin.setCursorPos(1, 12) mainWin.setTextColor(colors.white)
        mainWin.write(" [ CLEAR CACHE ]")
        mainWin.setCursorPos(1, 13) mainWin.write(" [ REBOOT SYSTEM ]")
        mainWin.setCursorPos(1, 14) mainWin.write(" [ FACTORY RESET ]")
    end
end

-- 4. CONTEXT MENU
local function showContext(mx, my, file)
    local opts = file and {"Copy", "Rename", "Delete"} or {"New File", "New Folder", "Paste"}
    local menuWin = window.create(term.current(), mx, my, 12, #opts)
    menuWin.setBackgroundColor(colors.gray)
    menuWin.setTextColor(colors.white)
    menuWin.clear()
    menuWin.setCursorBlink(false)
    for i, o in ipairs(opts) do menuWin.setCursorPos(1, i) menuWin.write(" "..o) end
    
    local contextTimer = os.startTimer(1)
    local contextRunning = true
    
    while contextRunning do
        local ev, p1, p2, p3 = os.pullEvent()
        
        if ev == "timer" and (p1 == globalTimer or p1 == contextTimer) then
            if p1 == globalTimer then
                drawTopBar()
                globalTimer = os.startTimer(1)
            end
            if p1 == contextTimer then
                drawTopBar()
                contextTimer = os.startTimer(1)
            end
        
        elseif ev == "mouse_click" then
            local btn, cx, cy = p1, p2, p3
            if cx >= mx and cx < mx+12 and cy >= my and cy < my+#opts then
                local choice = opts[cy-my+1]
                local path = (activeTab == "HOME") and getHomeDir() or currentPath
                
                if choice == "New File" then 
                    mainWin.setCursorPos(1,1)
                    mainWin.write("Name: ") 
                    local n = read() 
                    if n~="" then 
                        local f = fs.open(getUniquePath(path, n), "w")
                        if f then f.close() end
                    end
                elseif choice == "New Folder" then 
                    mainWin.setCursorPos(1,1)
                    mainWin.write("Dir: ") 
                    local n = read() 
                    if n~="" then fs.makeDir(getUniquePath(path, n)) end
                elseif choice == "Delete" then 
                    fs.delete(fs.combine(path, file))
                elseif choice == "Rename" then 
                    mainWin.setCursorPos(1,1)
                    mainWin.write("New: ") 
                    local n = read() 
                    if n~="" then 
                        local newPath = getUniquePath(path, n)
                        fs.move(fs.combine(path, file), newPath)
                    end
                elseif choice == "Copy" then 
                    clipboard.path = fs.combine(path, file)
                elseif choice == "Paste" and clipboard.path then 
                    local newName = fs.getName(clipboard.path)
                    local destPath = getUniquePath(path, newName)
                    fs.copy(clipboard.path, destPath)
                end
                contextRunning = false
            else
                contextRunning = false
            end
        end
    end
    
    if contextTimer then
        os.cancelTimer(contextTimer)
    end
    
    drawUI()
end

-- 5. ENGINE
local function osEngine()
    drawUI()
    globalTimer = os.startTimer(1)
    
    while running do
        local ev, p1, p2, p3 = os.pullEvent()
        
        if ev == "timer" and p1 == globalTimer then
            drawTopBar()
            globalTimer = os.startTimer(1)
        
        elseif ev == "mouse_click" then
            local btn, x, y = p1, p2, p3
            if y == h then
                if x >= 1 and x <= 6 then activeTab = "HOME"
                elseif x >= 8 and x <= 13 then activeTab = "FILE"
                elseif x >= 15 and x <= 20 then activeTab = "SHLL"
                elseif x >= 22 and x <= 27 then activeTab = "CONF"
                elseif x >= 29 and x <= 34 then activeTab = "SYS" end
                
                if activeTab == "SHLL" then
                    drawUI()
                    local old = term.redirect(mainWin)
                    term.setBackgroundColor(colors.black) term.clear() term.setCursorPos(1,1)
                    term.setCursorBlink(true)
                    parallel.waitForAny(
                        function() shell.run("shell") end,
                        function()
                            local lt = os.startTimer(1)
                            while true do
                                local e, id, tx, ty = os.pullEvent()
                                if e == "timer" and id == lt then drawTopBar() lt = os.startTimer(1)
                                elseif e == "mouse_click" and ty == h then os.queueEvent("mouse_click", 1, tx, ty) return end
                            end
                        end
                    )
                    term.setCursorBlink(false) term.redirect(old)
                    activeTab = "HOME"
                end
                os.cancelTimer(globalTimer)
                globalTimer = os.startTimer(0.1)
                drawUI()
            elseif activeTab == "FILE" and y > 1 and y < h then
                local fList = fs.list(currentPath)
                if currentPath ~= "/" then table.insert(fList, 1, "..") end
                local sel = fList[y-2]
                if btn == 2 then 
                    showContext(x, y, sel)
                elseif sel then
                    local p = fs.combine(currentPath, sel)
                    if fs.isDir(p) then 
                        currentPath = normalizePath(p)
                        drawUI()
                    else 
                        local old = term.redirect(mainWin) 
                        term.setCursorBlink(true) 
                        shell.run("edit", p) 
                        term.setCursorBlink(false) 
                        term.redirect(old) 
                        drawUI() 
                    end
                end
            elseif activeTab == "HOME" and y > 1 and y < h then
                local home = getHomeDir()
                local fList = fs.list(home)
                local sel = nil
                for i, n in ipairs(fList) do
                    local col, row = ((i-1)%4)*12+3, math.floor((i-1)/4)*4+2
                    if x >= col and x <= col+6 and y >= row and y <= row+1 then sel = n break end
                end
                if btn == 2 then 
                    showContext(x, y, sel)
                elseif sel then 
                    local p = fs.combine(home, sel)
                    if fs.isDir(p) then 
                        activeTab = "FILE" 
                        currentPath = normalizePath(p)
                        drawUI()
                    else 
                        local old = term.redirect(mainWin) 
                        term.setCursorBlink(true) 
                        shell.run("edit", p) 
                        term.setCursorBlink(false) 
                        term.redirect(old) 
                        drawUI() 
                    end
                end
            elseif activeTab == "CONF" then
                local line = y - 1
                if line == 3 then -- NEXT THEME
                    settings.themeIndex = (settings.themeIndex % #themes) + 1 
                    saveSettings() 
                    drawUI()
                elseif line == 5 then -- SOUND
                    settings.soundEnabled = not settings.soundEnabled
                    saveSettings()
                    drawUI()
                elseif line == 6 then -- AUTOSTART
                    settings.autoStart = not settings.autoStart
                    saveSettings()
                    drawUI()
                elseif line == 7 then -- SHOW HIDDEN
                    settings.showHidden = not settings.showHidden
                    saveSettings()
                    drawUI()
                elseif line == 8 then -- LANGUAGE
                    settings.language = (settings.language == "EN") and "RU" or "EN"
                    saveSettings()
                    drawUI()
                elseif line == 9 then -- ANIM SPEED
                    settings.animationSpeed = settings.animationSpeed + 0.2
                    if settings.animationSpeed > 2.0 then
                        settings.animationSpeed = 0.4
                    end
                    saveSettings()
                    drawUI()
                elseif line == 10 then -- SHOW CLOCK
                    settings.showClock = not settings.showClock
                    saveSettings()
                    drawUI()
                elseif line == 11 then -- SHOW BATTERY
                    settings.showBattery = not settings.showBattery
                    saveSettings()
                    drawUI()
                elseif line == 14 then -- UPDATE SYSTEM
                    mainWin.clear() 
                    mainWin.setCursorPos(1,1) 
                    mainWin.setTextColor(colors.yellow)
                    mainWin.write("Updating system...")
                    
                    local tempFile = "startup_temp.lua"
                    local finalFile = "startup.lua"
                    local url = "https://github.com/JemmaperXD/jemmaperxd/raw/refs/heads/main/startup.lua"
                    
                    local downloadSuccess = false
                    for attempt = 1, 3 do
                        mainWin.setCursorPos(1, 2)
                        mainWin.write("Attempt " .. attempt .. "/3...")
                        
                        if fs.exists(tempFile) then
                            fs.delete(tempFile)
                        end
                        
                        if shell.run("wget", url, tempFile) then
                            if fs.exists(tempFile) then
                                local file = fs.open(tempFile, "r")
                                if file then
                                    local content = file.readAll()
                                    file.close()
                                    if content and #content > 100 then
                                        downloadSuccess = true
                                        break
                                    end
                                end
                            end
                        end
                        
                        if attempt < 3 then
                            sleep(2)
                        end
                    end
                    
                    if downloadSuccess then
                        if fs.exists(finalFile) then
                            fs.delete(finalFile)
                        end
                        
                        fs.move(tempFile, finalFile)
                        
                        mainWin.setCursorPos(1, 3)
                        mainWin.setTextColor(colors.lime)
                        mainWin.write("Update successful! Rebooting...")
                        sleep(2)
                        
                        os.reboot()
                    else
                        if fs.exists(tempFile) then
                            fs.delete(tempFile)
                        end
                        
                        mainWin.setCursorPos(1, 3)
                        mainWin.setTextColor(colors.red)
                        mainWin.write("Update failed! Check connection.")
                        sleep(3)
                        drawUI()
                    end
                elseif line == 16 then -- SHUTDOWN
                    running = false 
                end
            elseif activeTab == "SYS" then
                local line = y - 1
                if line == 12 then -- CLEAR CACHE
                    mainWin.clear()
                    mainWin.setCursorPos(1,1)
                    mainWin.setTextColor(colors.yellow)
                    mainWin.write("Clearing cache...")
                    sleep(1)
                    mainWin.setCursorPos(1,2)
                    mainWin.setTextColor(colors.lime)
                    mainWin.write("Cache cleared!")
                    sleep(1)
                    drawUI()
                elseif line == 13 then -- REBOOT
                    os.reboot()
                elseif line == 14 then -- FACTORY RESET
                    mainWin.clear()
                    mainWin.setCursorPos(1,1)
                    mainWin.setTextColor(colors.red)
                    mainWin.write("Factory Reset - Are you sure?")
                    mainWin.setCursorPos(1,3)
                    mainWin.setTextColor(colors.white)
                    mainWin.write("Type 'RESET' to confirm: ")
                    local confirm = read()
                    if confirm == "RESET" then
                        fs.delete(SETTINGS_PATH)
                        os.reboot()
                    else
                        drawUI()
                    end
                end
            end
        end
    end
end

-- 6. ENTRY POINT - С АВТОПЕРЕЗАПУСКОМ
local function safeStartup()
    while true do
        loadSettings()
        term.setBackgroundColor(colors.black)
        term.clear()
        
        -- Используем новую анимацию LineageOS
        lineageBootAnim()
        
        local loginComplete = false
        
        while not loginComplete do
            local success, result = pcall(function()
                if not settings.isRegistered then
                    term.setCursorBlink(true)
                    term.setCursorPos(w/2-6, h/2-2) term.setTextColor(colors.cyan) term.write("REGISTRATION")
                    term.setCursorPos(w/2-8, h/2) term.setTextColor(colors.white) term.write("User: ") 
                    
                    settings.user = read()
                    
                    term.setCursorPos(w/2-8, h/2+1) term.write("Pass: ") 
                    settings.pass = read("*")
                    
                    settings.isRegistered = true 
                    saveSettings()
                    term.setCursorBlink(false)
                    return "registered"
                else
                    local loginAttempts = 0
                    
                    while true do
                        term.setCursorBlink(true)
                        term.clear()
                        term.setCursorPos(w/2-6, h/2-1) term.setTextColor(colors.cyan) term.write("LOGIN: "..settings.user)
                        term.setCursorPos(w/2-8, h/2+1) term.setTextColor(colors.white) term.write("Pass: ")
                        
                        local password = read("*")
                        
                        if password == settings.pass then 
                            term.setCursorBlink(false)
                            return "login_success"
                        else
                            loginAttempts = loginAttempts + 1
                            term.setCursorPos(w/2-8, h/2+3)
                            term.setTextColor(colors.red)
                            term.write("Wrong password! Try: " .. loginAttempts)
                            sleep(1.5)
                        end
                    end
                end
            end)
            
            if success and (result == "registered" or result == "login_success") then
                loginComplete = true
                break
            end
        end
        
        local osSuccess, osError = pcall(osEngine)
        
        if not osSuccess then
            sleep(0.1)
        elseif osError == "restart" then
            sleep(0.1)
        else
            break
        end
    end
end

-- ЗАПУСКАЕМ ВСЁ С ЗАЩИТОЙ
safeStartup()
