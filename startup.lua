-- ameOs v46.0 [TOTAL CLOCK & NAVIGATION FIX]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local running = true
local activeTab = "HOME"
local currentPath = "/"
local clipboard = { path = nil }
local globalTimer = nil
local settingsPage = 1
local MAX_SETTINGS_PAGES = 3

local themes = {
    { name = "Dark Moss", bg = colors.black, accent = colors.green, text = colors.gray },
    { name = "Abyss",     bg = colors.black, accent = colors.cyan, text = colors.gray },
    { name = "Charcoal",  bg = colors.black, accent = colors.gray, text = colors.lightGray },
    { name = "Slate",     bg = colors.black, accent = colors.lightGray, text = colors.gray },
    { name = "Solarized", bg = colors.black, accent = colors.orange, text = colors.lightBlue },
    { name = "Midnight",  bg = colors.black, accent = colors.purple, text = colors.white }
}

local settings = { 
    themeIndex = 1, 
    user = "User", 
    pass = "", 
    isRegistered = false,
    showHidden = false,
    autoUpdate = true,
    animations = true,
    clock24h = true,
    soundEnabled = true,
    startupDelay = 0,
    screenSaver = true,
    screenSaverTime = 300
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

-- 2. БЕЗОПАСНАЯ БУТ АНИМАЦИЯ (с автоперезапуском)
local function safeBootAnim()
    while true do
        local success, error = pcall(function()
            local cx, cy = math.floor(w/2), math.floor(h/2 - 2)
            local duration = 5
            local start = os.clock()
            local angle = 0
            while os.clock() - start < duration do
                local elapsed = os.clock() - start
                term.setBackgroundColor(colors.black)
                term.clear()
                local fusion = 1.0
                if elapsed > (duration - 2) then fusion = math.max(0, 1 - (elapsed - (duration - 2)) / 2) end
                term.setTextColor(colors.cyan)
                local rX, rY = 2.5 * fusion, 1.5 * fusion
                for i = 1, 3 do
                    local a = angle + (i * 2.1)
                    term.setCursorPos(cx + math.floor(math.cos(a)*rX+0.5), cy + math.floor(math.sin(a)*rY+0.5))
                    term.write("o")
                end
                term.setCursorPos(cx - 2, h - 1)
                term.setTextColor(colors.white)
                term.write("ameOS")
                angle = angle + 0.4
                sleep(0.05)
            end
            return true
        end)
        
        if success then
            break
        end
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
    topWin.setCursorPos(w - 6, 1)
    topWin.write(textutils.formatTime(os.time(), settings.clock24h))
    term.redirect(old)
end

local function drawUI()
    local theme = themes[settings.themeIndex]
    taskWin.setBackgroundColor(colors.black)
    taskWin.clear()
    taskWin.setCursorBlink(false)
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
        local visibleFiles = {}
        for _, n in ipairs(files) do
            if settings.showHidden or not n:sub(1,1) == "." then
                table.insert(visibleFiles, n)
            end
        end
        for i, n in ipairs(visibleFiles) do
            if i > h-4 then break end
            mainWin.setCursorPos(1, i+1)
            mainWin.setTextColor(fs.isDir(fs.combine(currentPath, n)) and colors.cyan or colors.white)
            mainWin.write("> "..n)
        end
    elseif activeTab == "CONF" then
        mainWin.setCursorPos(1, 1)
        mainWin.setTextColor(theme.accent)
        mainWin.write("Settings (Page " .. settingsPage .. "/" .. MAX_SETTINGS_PAGES .. ")")
        
        if settingsPage == 1 then
            -- Page 1: Appearance
            mainWin.setCursorPos(1, 3)
            mainWin.setTextColor(theme.text)
            mainWin.write("Theme: " .. theme.name)
            mainWin.setCursorPos(1, 4)
            mainWin.write(" [ NEXT THEME ]")
            
            mainWin.setCursorPos(1, 6)
            mainWin.write("Animations: " .. (settings.animations and "ON" or "OFF"))
            mainWin.setCursorPos(1, 7)
            mainWin.write(" [ TOGGLE ANIMATIONS ]")
            
            mainWin.setCursorPos(1, 9)
            mainWin.write("Clock Format: " .. (settings.clock24h and "24H" or "12H"))
            mainWin.setCursorPos(1, 10)
            mainWin.write(" [ TOGGLE CLOCK ]")
            
            mainWin.setCursorPos(1, 12)
            mainWin.write("Show Hidden: " .. (settings.showHidden and "YES" or "NO"))
            mainWin.setCursorPos(1, 13)
            mainWin.write(" [ TOGGLE HIDDEN ]")
            
        elseif settingsPage == 2 then
            -- Page 2: System
            mainWin.setCursorPos(1, 3)
            mainWin.setTextColor(theme.text)
            mainWin.write("Auto Update: " .. (settings.autoUpdate and "ON" or "OFF"))
            mainWin.setCursorPos(1, 4)
            mainWin.write(" [ TOGGLE AUTO UPDATE ]")
            
            mainWin.setCursorPos(1, 6)
            mainWin.write("Sound: " .. (settings.soundEnabled and "ON" or "OFF"))
            mainWin.setCursorPos(1, 7)
            mainWin.write(" [ TOGGLE SOUND ]")
            
            mainWin.setCursorPos(1, 9)
            mainWin.write("Startup Delay: " .. settings.startupDelay .. "s")
            mainWin.setCursorPos(1, 10)
            mainWin.write(" [ SET DELAY (0-5) ]")
            
            mainWin.setCursorPos(1, 12)
            mainWin.write("Screen Saver: " .. (settings.screenSaver and "ON" or "OFF"))
            mainWin.setCursorPos(1, 13)
            mainWin.write(" [ TOGGLE SCREEN SAVER ]")
            
        elseif settingsPage == 3 then
            -- Page 3: Account & Power
            mainWin.setCursorPos(1, 3)
            mainWin.setTextColor(theme.text)
            mainWin.write("User: " .. settings.user)
            mainWin.setCursorPos(1, 4)
            mainWin.write(" [ CHANGE USERNAME ]")
            
            mainWin.setCursorPos(1, 6)
            mainWin.write(" [ CHANGE PASSWORD ]")
            
            mainWin.setCursorPos(1, 8)
            mainWin.write(" [ EXPORT SETTINGS ]")
            
            mainWin.setCursorPos(1, 10)
            mainWin.write(" [ IMPORT SETTINGS ]")
            
            mainWin.setCursorPos(1, 12)
            mainWin.setTextColor(colors.yellow)
            mainWin.write(" [ UPDATE SYSTEM ]")
            
            mainWin.setCursorPos(1, 14)
            mainWin.setTextColor(colors.red)
            mainWin.write(" [ SHUTDOWN ]")
        end
        
        -- Navigation
        mainWin.setCursorPos(w - 10, h - 3)
        mainWin.setTextColor(theme.accent)
        if settingsPage > 1 then
            mainWin.write("[ PREV ]")
        end
        mainWin.setCursorPos(w - 3, h - 3)
        if settingsPage < MAX_SETTINGS_PAGES then
            mainWin.write("[ NEXT ]")
        end
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
                elseif x >= 22 and x <= 27 then activeTab = "CONF" end
                
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
                local visibleFiles = {}
                for _, n in ipairs(fList) do
                    if settings.showHidden or not n:sub(1,1) == "." then
                        table.insert(visibleFiles, n)
                    end
                end
                local sel = visibleFiles[y-2]
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
                -- Navigation
                if x >= w - 10 and x <= w - 4 and y == h - 3 and settingsPage > 1 then
                    settingsPage = settingsPage - 1
                    drawUI()
                elseif x >= w - 3 and x <= w and y == h - 3 and settingsPage < MAX_SETTINGS_PAGES then
                    settingsPage = settingsPage + 1
                    drawUI()
                elseif settingsPage == 1 then
                    -- Page 1: Appearance
                    if y == 5 then 
                        settings.themeIndex = (settings.themeIndex % #themes) + 1 
                        saveSettings() 
                        drawUI()
                    elseif y == 8 then 
                        settings.animations = not settings.animations
                        saveSettings()
                        drawUI()
                    elseif y == 11 then 
                        settings.clock24h = not settings.clock24h
                        saveSettings()
                        drawUI()
                    elseif y == 14 then 
                        settings.showHidden = not settings.showHidden
                        saveSettings()
                        drawUI()
                    end
                elseif settingsPage == 2 then
                    -- Page 2: System
                    if y == 5 then 
                        settings.autoUpdate = not settings.autoUpdate
                        saveSettings()
                        drawUI()
                    elseif y == 8 then 
                        settings.soundEnabled = not settings.soundEnabled
                        saveSettings()
                        drawUI()
                    elseif y == 11 then 
                        mainWin.setCursorPos(1, 10)
                        mainWin.clearLine()
                        mainWin.write("Delay (0-5): ")
                        local delay = tonumber(read())
                        if delay and delay >= 0 and delay <= 5 then
                            settings.startupDelay = delay
                            saveSettings()
                        end
                        drawUI()
                    elseif y == 14 then 
                        settings.screenSaver = not settings.screenSaver
                        saveSettings()
                        drawUI()
                    end
                elseif settingsPage == 3 then
                    -- Page 3: Account & Power
                    if y == 5 then 
                        mainWin.setCursorPos(1, 4)
                        mainWin.clearLine()
                        mainWin.write("New username: ")
                        local newUser = read()
                        if newUser and newUser ~= "" then
                            local oldHome = getHomeDir()
                            settings.user = newUser
                            local newHome = getHomeDir()
                            if fs.exists(oldHome) and oldHome ~= newHome then
                                fs.move(oldHome, newHome)
                            end
                            saveSettings()
                        end
                        drawUI()
                    elseif y == 7 then 
                        mainWin.setCursorPos(1, 6)
                        mainWin.clearLine()
                        mainWin.write("Old password: ")
                        local oldPass = read("*")
                        if oldPass == settings.pass then
                            mainWin.setCursorPos(1, 7)
                            mainWin.write("New password: ")
                            local newPass = read("*")
                            settings.pass = newPass
                            saveSettings()
                            mainWin.setCursorPos(1, 8)
                            mainWin.setTextColor(colors.lime)
                            mainWin.write("Password changed!")
                            sleep(1.5)
                        else
                            mainWin.setCursorPos(1, 8)
                            mainWin.setTextColor(colors.red)
                            mainWin.write("Wrong password!")
                            sleep(1.5)
                        end
                        drawUI()
                    elseif y == 9 then 
                        -- Export settings
                        local exportPath = fs.combine(getHomeDir(), "ame_settings_export.cfg")
                        local f = fs.open(exportPath, "w")
                        local exportData = {
                            themeIndex = settings.themeIndex,
                            showHidden = settings.showHidden,
                            autoUpdate = settings.autoUpdate,
                            animations = settings.animations,
                            clock24h = settings.clock24h,
                            soundEnabled = settings.soundEnabled,
                            startupDelay = settings.startupDelay,
                            screenSaver = settings.screenSaver
                        }
                        f.write(textutils.serialize(exportData))
                        f.close()
                        mainWin.setCursorPos(1, 10)
                        mainWin.setTextColor(colors.lime)
                        mainWin.write("Settings exported!")
                        sleep(1.5)
                        drawUI()
                    elseif y == 11 then 
                        -- Import settings
                        mainWin.setCursorPos(1, 10)
                        mainWin.clearLine()
                        mainWin.write("Import file: ")
                        local importFile = read()
                        if fs.exists(importFile) then
                            local f = fs.open(importFile, "r")
                            local data = f.readAll()
                            f.close()
                            local importData = textutils.unserialize(data)
                            if importData then
                                for k, v in pairs(importData) do
                                    if k ~= "user" and k ~= "pass" and k ~= "isRegistered" then
                                        settings[k] = v
                                    end
                                end
                                saveSettings()
                                mainWin.setCursorPos(1, 11)
                                mainWin.setTextColor(colors.lime)
                                mainWin.write("Settings imported!")
                            else
                                mainWin.setCursorPos(1, 11)
                                mainWin.setTextColor(colors.red)
                                mainWin.write("Invalid file!")
                            end
                        else
                            mainWin.setCursorPos(1, 11)
                            mainWin.setTextColor(colors.red)
                            mainWin.write("File not found!")
                        end
                        sleep(2)
                        drawUI()
                    elseif y == 13 then 
                        -- UPDATE SYSTEM
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
                    elseif y == 15 then 
                        running = false 
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
        
        -- Добавляем задержку если настроено
        if settings.startupDelay > 0 then
            sleep(settings.startupDelay)
        end
        
        -- Безопасная загрузочная анимация с автоперезапуском
        if settings.animations then
            safeBootAnim()
        else
            term.setCursorPos(math.floor(w/2)-2, math.floor(h/2))
            term.setTextColor(colors.cyan)
            term.write("ameOS")
            sleep(1)
        end
        
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
