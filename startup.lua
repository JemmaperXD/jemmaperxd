-- ameOs v47.0 [ANIMATIONS & ENHANCED CUSTOMIZATION]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local running = true
local activeTab = "HOME"
local currentPath = "/"
local clipboard = { path = nil }
local globalTimer = nil

-- Расширенные темы с дополнительными параметрами
local themes = {
    { 
        name = "Dark Moss", 
        bg = colors.black, 
        accent = colors.green, 
        text = colors.gray,
        highlight = colors.lime,
        shadow = colors.gray
    },
    { 
        name = "Abyss",     
        bg = colors.black, 
        accent = colors.cyan, 
        text = colors.gray,
        highlight = colors.lightBlue,
        shadow = colors.blue
    },
    { 
        name = "Charcoal",  
        bg = colors.black, 
        accent = colors.gray, 
        text = colors.lightGray,
        highlight = colors.white,
        shadow = colors.gray
    },
    { 
        name = "Slate",     
        bg = colors.black, 
        accent = colors.lightGray, 
        text = colors.gray,
        highlight = colors.white,
        shadow = colors.gray
    },
    { 
        name = "Crimson",   
        bg = colors.black, 
        accent = colors.red, 
        text = colors.gray,
        highlight = colors.pink,
        shadow = colors.red
    },
    { 
        name = "Amber",     
        bg = colors.black, 
        accent = colors.orange, 
        text = colors.gray,
        highlight = colors.yellow,
        shadow = colors.orange
    }
}

-- Расширенные настройки
local settings = { 
    themeIndex = 1, 
    user = "User", 
    pass = "", 
    isRegistered = false,
    animations = true,
    animationSpeed = 1, -- 1 = normal, 2 = fast, 0.5 = slow
    uiScale = 1, -- 1 = normal, 2 = large
    showClock = true,
    showFileIcons = true,
    transparency = false,
    startupSound = false,
    cursorBlink = true,
    autoSave = true
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

-- Анимационные функции
local function playTransition(direction)
    if not settings.animations then return end
    
    local speed = settings.animationSpeed or 1
    local steps = 10
    local stepDelay = 0.02 / speed
    
    if direction == "in" then
        for i = 0, w do
            for y = 1, h do
                term.setCursorPos(i, y)
                term.setBackgroundColor(colors.black)
                term.write(" ")
            end
            sleep(stepDelay)
        end
    elseif direction == "out" then
        for i = w, 0, -1 do
            for y = 1, h do
                term.setCursorPos(i, y)
                term.setBackgroundColor(colors.black)
                term.write(" ")
            end
            sleep(stepDelay)
        end
    elseif direction == "fade" then
        local theme = themes[settings.themeIndex]
        for i = 1, 5 do
            term.setBackgroundColor(theme.bg)
            term.clear()
            sleep(0.05 / speed)
            term.setBackgroundColor(colors.black)
            term.clear()
            sleep(0.05 / speed)
        end
    end
end

local function buttonPressAnimation(x, y, width, height)
    if not settings.animations then return end
    
    local speed = settings.animationSpeed or 1
    local old = term.redirect(window.create(term.current(), x, y, width, height))
    
    for i = 1, 2 do
        term.setBackgroundColor(colors.lightGray)
        term.clear()
        sleep(0.05 / speed)
        term.setBackgroundColor(colors.gray)
        term.clear()
        sleep(0.05 / speed)
    end
    
    term.redirect(old)
end

local function rippleEffect(cx, cy)
    if not settings.animations then return end
    
    local speed = settings.animationSpeed or 1
    local theme = themes[settings.themeIndex]
    
    for r = 0, math.max(w, h) do
        for angle = 0, 360, 15 do
            local rad = math.rad(angle)
            local x = math.floor(cx + math.cos(rad) * r + 0.5)
            local y = math.floor(cy + math.sin(rad) * r + 0.5)
            
            if x >= 1 and x <= w and y >= 1 and y <= h then
                term.setCursorPos(x, y)
                term.setBackgroundColor(theme.accent)
                term.write(" ")
                sleep(0.001 / speed)
                term.setCursorPos(x, y)
                term.setBackgroundColor(theme.bg)
                term.write(" ")
            end
        end
    end
end

local function fadeText(text, x, y, color)
    if not settings.animations then return end
    
    local speed = settings.animationSpeed or 1
    local steps = 5
    
    for i = 1, steps do
        term.setCursorPos(x, y)
        local alpha = i / steps
        term.setTextColor(color)
        term.write(text)
        sleep(0.03 / speed)
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

-- 2. БЕЗОПАСНАЯ БУТ АНИМАЦИЯ (с улучшенной графикой)
local function safeBootAnim()
    while true do
        local success, error = pcall(function()
            local cx, cy = math.floor(w/2), math.floor(h/2 - 2)
            local duration = 4
            local start = os.clock()
            local angle = 0
            
            while os.clock() - start < duration do
                local elapsed = os.clock() - start
                term.setBackgroundColor(colors.black)
                term.clear()
                local progress = elapsed / duration
                
                -- Плавное исчезновение
                local fusion = 1.0
                if elapsed > (duration - 1) then 
                    fusion = math.max(0, 1 - (elapsed - (duration - 1)) / 1) 
                end
                
                -- Вращающиеся частицы
                term.setTextColor(colors.cyan)
                local rX, rY = 3.0 * fusion, 2.0 * fusion
                
                for i = 1, 5 do
                    local a = angle + (i * 1.256) -- 2π/5 ≈ 1.256
                    local particleX = cx + math.floor(math.cos(a)*rX+0.5)
                    local particleY = cy + math.floor(math.sin(a)*rY+0.5)
                    
                    term.setCursorPos(particleX, particleY)
                    term.write("●")
                    
                    -- Следы частиц
                    if settings.animations then
                        for j = 1, 3 do
                            local trailX = cx + math.floor(math.cos(a - j*0.2)*rX*0.7+0.5)
                            local trailY = cy + math.floor(math.sin(a - j*0.2)*rY*0.7+0.5)
                            if trailX >= 1 and trailX <= w and trailY >= 1 and trailY <= h then
                                term.setCursorPos(trailX, trailY)
                                term.setTextColor(colors.blue)
                                term.write("·")
                            end
                        end
                    end
                end
                
                -- Прогресс бар
                if settings.animations then
                    local barWidth = 20
                    local barStart = math.floor(w/2 - barWidth/2)
                    local barProgress = math.floor(progress * barWidth)
                    
                    term.setCursorPos(barStart, cy + 4)
                    term.setTextColor(colors.gray)
                    term.write("[")
                    term.setCursorPos(barStart + barWidth + 1, cy + 4)
                    term.write("]")
                    
                    term.setCursorPos(barStart + 1, cy + 4)
                    for i = 1, barWidth do
                        if i <= barProgress then
                            term.setTextColor(colors.cyan)
                            term.write("█")
                        else
                            term.setTextColor(colors.gray)
                            term.write("░")
                        end
                    end
                end
                
                -- Название системы с эффектом свечения
                term.setCursorPos(cx - 3, h - 2)
                if settings.animations and progress > 0.5 then
                    local glow = math.sin(angle * 3) * 0.5 + 0.5
                    if glow > 0.7 then
                        term.setTextColor(colors.white)
                    else
                        term.setTextColor(colors.lightGray)
                    end
                else
                    term.setTextColor(colors.white)
                end
                term.write("ameOS")
                
                -- Версия
                term.setCursorPos(cx - 1, h - 1)
                term.setTextColor(colors.gray)
                term.write("v47.0")
                
                angle = angle + 0.3 * (settings.animationSpeed or 1)
                sleep(0.05)
            end
            
            -- Финальный эффект
            if settings.animations then
                rippleEffect(cx, cy)
                sleep(0.3)
                playTransition("fade")
            end
            
            return true
        end)
        
        if success then break end
    end
end

-- 3. RENDERING с улучшениями
local function drawTopBar()
    local theme = themes[settings.themeIndex]
    local old = term.redirect(topWin)
    topWin.setCursorBlink(false)
    
    -- Анимированный фон верхней панели
    if settings.animations and settings.transparency then
        for i = 1, w do
            local intensity = math.sin(os.clock() * 2 + i * 0.3) * 0.3 + 0.7
            topWin.setBackgroundColor(theme.accent)
            topWin.setCursorPos(i, 1)
            topWin.write(" ")
        end
    else
        topWin.setBackgroundColor(theme.accent)
        topWin.clear()
    end
    
    topWin.setTextColor(theme.text)
    topWin.setCursorPos(2, 1) 
    topWin.write("ameOs | " .. activeTab)
    
    if settings.showClock then
        topWin.setCursorPos(w - 8, 1)
        topWin.write(textutils.formatTime(os.time(), true))
        
        -- Анимация двоеточия в часах
        if settings.animations then
            topWin.setCursorPos(w - 5, 1)
            if math.floor(os.clock() * 2) % 2 == 0 then
                topWin.write(":")
            else
                topWin.write(" ")
            end
        end
    end
    
    term.redirect(old)
end

local function drawUI()
    local theme = themes[settings.themeIndex]
    taskWin.setBackgroundColor(colors.black)
    taskWin.clear()
    taskWin.setCursorBlink(false)
    
    local tabs = { 
        {n="HOME", x=1}, 
        {n="FILE", x=8}, 
        {n="SHLL", x=15}, 
        {n="CONF", x=22},
        {n="APPS", x=29}
    }
    
    for _, t in ipairs(tabs) do
        taskWin.setCursorPos(t.x, 1)
        if activeTab == t.n then
            -- Анимированная активная вкладка
            if settings.animations then
                taskWin.setBackgroundColor(theme.highlight)
                taskWin.setTextColor(colors.black)
                taskWin.write(" "..t.n.." ")
            else
                taskWin.setBackgroundColor(theme.accent)
                taskWin.setTextColor(theme.text)
                taskWin.write(" "..t.n.." ")
            end
        else
            -- Неактивные вкладки с эффектом при наведении
            taskWin.setBackgroundColor(colors.black)
            taskWin.setTextColor(colors.white)
            taskWin.write(" "..t.n.." ")
        end
    end
    
    drawTopBar()
    mainWin.setBackgroundColor(theme.bg)
    mainWin.setTextColor(theme.text)
    mainWin.clear()
    
    -- Анимированный курсор
    mainWin.setCursorBlink(settings.cursorBlink)
    
    if activeTab == "HOME" then
        local home = getHomeDir()
        if not fs.exists(home) then fs.makeDir(home) end
        local files = fs.list(home)
        
        for i, n in ipairs(files) do
            local col, row = ((i-1)%4)*12+3, math.floor((i-1)/4)*4+1
            
            -- Анимация появления файлов
            if settings.animations then
                for y = 1, 2 do
                    mainWin.setCursorPos(col, row + y - 1)
                    mainWin.setBackgroundColor(theme.shadow)
                    mainWin.write("      ")
                    sleep(0.01)
                end
            end
            
            if settings.showFileIcons then
                mainWin.setCursorPos(col, row)
                mainWin.setTextColor(fs.isDir(fs.combine(home, n)) and colors.yellow or colors.blue)
                mainWin.write("[#]")
                mainWin.setCursorPos(col-1, row+1)
                mainWin.setTextColor(colors.white)
                mainWin.write(n:sub(1, 8))
            else
                mainWin.setCursorPos(col, row)
                mainWin.setTextColor(fs.isDir(fs.combine(home, n)) and colors.yellow or colors.white)
                mainWin.write(n:sub(1, 10))
            end
        end
        
    elseif activeTab == "FILE" then
        mainWin.setCursorPos(1, 1) 
        mainWin.setTextColor(colors.yellow)
        mainWin.write(" "..normalizePath(currentPath))
        
        local files = fs.list(currentPath)
        if currentPath ~= "/" then table.insert(files, 1, "..") end
        
        for i, n in ipairs(files) do
            if i > h-4 then break end
            
            -- Анимация строк
            if settings.animations then
                for x = 1, w do
                    mainWin.setCursorPos(x, i+1)
                    mainWin.setBackgroundColor(theme.shadow)
                    mainWin.write(" ")
                    sleep(0.001)
                end
            end
            
            mainWin.setCursorPos(1, i+1)
            mainWin.setTextColor(fs.isDir(fs.combine(currentPath, n)) and colors.cyan or colors.white)
            mainWin.write("> "..n)
        end
        
    elseif activeTab == "CONF" then
        local startY = 2
        local line = 0
        
        -- Заголовок
        fadeText("SYSTEM SETTINGS", 1, startY + line, theme.accent)
        line = line + 2
        
        -- Темы
        fadeText("Theme: "..theme.name, 1, startY + line, theme.text)
        line = line + 1
        fadeText("[ NEXT THEME ]", 1, startY + line, theme.highlight)
        line = line + 2
        
        -- Настройки анимаций
        fadeText("Animations: "..(settings.animations and "ON" or "OFF"), 1, startY + line, theme.text)
        line = line + 1
        fadeText("[ TOGGLE ANIMATIONS ]", 1, startY + line, theme.highlight)
        line = line + 2
        
        -- Скорость анимаций
        local speedText = "Normal"
        if settings.animationSpeed == 0.5 then speedText = "Slow"
        elseif settings.animationSpeed == 2 then speedText = "Fast" end
        fadeText("Animation Speed: "..speedText, 1, startY + line, theme.text)
        line = line + 1
        fadeText("[ CHANGE SPEED ]", 1, startY + line, theme.highlight)
        line = line + 2
        
        -- Иконки файлов
        fadeText("File Icons: "..(settings.showFileIcons and "ON" or "OFF"), 1, startY + line, theme.text)
        line = line + 1
        fadeText("[ TOGGLE ICONS ]", 1, startY + line, theme.highlight)
        line = line + 2
        
        -- Часы
        fadeText("Show Clock: "..(settings.showClock and "ON" or "OFF"), 1, startY + line, theme.text)
        line = line + 1
        fadeText("[ TOGGLE CLOCK ]", 1, startY + line, theme.highlight)
        line = line + 2
        
        -- Мерцание курсора
        fadeText("Cursor Blink: "..(settings.cursorBlink and "ON" or "OFF"), 1, startY + line, theme.text)
        line = line + 1
        fadeText("[ TOGGLE BLINK ]", 1, startY + line, theme.highlight)
        line = line + 2
        
        -- Автосохранение
        fadeText("Auto Save: "..(settings.autoSave and "ON" or "OFF"), 1, startY + line, theme.text)
        line = line + 1
        fadeText("[ TOGGLE AUTOSAVE ]", 1, startY + line, theme.highlight)
        line = line + 2
        
        -- Прозрачность
        fadeText("Transparency: "..(settings.transparency and "ON" or "OFF"), 1, startY + line, theme.text)
        line = line + 1
        fadeText("[ TOGGLE TRANSPARENCY ]", 1, startY + line, theme.highlight)
        line = line + 2
        
        -- Системные кнопки
        mainWin.setCursorPos(1, startY + line)
        mainWin.setTextColor(colors.yellow)
        mainWin.write(" [ UPDATE SYSTEM ]")
        line = line + 2
        
        mainWin.setCursorPos(1, startY + line)
        mainWin.setTextColor(colors.red)
        mainWin.write(" [ SHUTDOWN ]")
        
    elseif activeTab == "APPS" then
        fadeText("APPLICATIONS", 1, 2, theme.accent)
        
        local apps = {
            {"Notepad", "Simple text editor"},
            {"Calc", "Calculator"},
            {"Clock", "World clock"},
            {"Games", "Mini games"},
            {"Paint", "Drawing tool"},
            {"Music", "Audio player"}
        }
        
        for i, app in ipairs(apps) do
            local col = ((i-1)%3)*15+3
            local row = math.floor((i-1)/3)*3+4
            
            if settings.animations then
                for y = 0, 2 do
                    mainWin.setCursorPos(col, row + y)
                    mainWin.setBackgroundColor(theme.shadow)
                    mainWin.write("           ")
                    sleep(0.01)
                end
            end
            
            mainWin.setCursorPos(col, row)
            mainWin.setTextColor(theme.highlight)
            mainWin.write("[APP]")
            mainWin.setCursorPos(col-1, row+1)
            mainWin.setTextColor(colors.white)
            mainWin.write(app[1])
            mainWin.setCursorPos(col-1, row+2)
            mainWin.setTextColor(colors.gray)
            mainWin.write(app[2]:sub(1, 10))
        end
    end
end

-- 4. CONTEXT MENU с анимацией
local function showContext(mx, my, file)
    local opts = file and {"Copy", "Rename", "Delete"} or {"New File", "New Folder", "Paste"}
    local menuWin = window.create(term.current(), mx, my, 12, #opts)
    
    if settings.animations then
        -- Анимированное появление меню
        for i = 1, #opts do
            menuWin.setBackgroundColor(colors.gray)
            menuWin.setTextColor(colors.white)
            menuWin.setCursorPos(1, i)
            menuWin.write(" "..opts[i])
            sleep(0.03 / (settings.animationSpeed or 1))
        end
    else
        menuWin.setBackgroundColor(colors.gray)
        menuWin.setTextColor(colors.white)
        menuWin.clear()
        for i, o in ipairs(opts) do 
            menuWin.setCursorPos(1, i) 
            menuWin.write(" "..o) 
        end
    end
    
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
                
                -- Анимация выбора
                if settings.animations then
                    menuWin.setCursorPos(1, cy-my+1)
                    menuWin.setBackgroundColor(colors.white)
                    menuWin.setTextColor(colors.black)
                    menuWin.write(" "..choice.." ")
                    sleep(0.1)
                end
                
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

-- 5. ENGINE с улучшенной обработкой
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
                local oldTab = activeTab
                
                if x >= 1 and x <= 6 then activeTab = "HOME"
                elseif x >= 8 and x <= 13 then activeTab = "FILE"
                elseif x >= 15 and x <= 20 then activeTab = "SHLL"
                elseif x >= 22 and x <= 27 then activeTab = "CONF"
                elseif x >= 29 and x <= 34 then activeTab = "APPS" end
                
                -- Анимация переключения вкладок
                if settings.animations and oldTab ~= activeTab then
                    rippleEffect(x, y)
                end
                
                if activeTab == "SHLL" then
                    drawUI()
                    local old = term.redirect(mainWin)
                    term.setBackgroundColor(colors.black) 
                    term.clear() 
                    term.setCursorPos(1,1)
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
                    term.setCursorBlink(false) 
                    term.redirect(old)
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
                local line = math.floor((y - 2) / 2)
                
                if line == 2 then -- NEXT THEME
                    buttonPressAnimation(1, y, 15, 1)
                    settings.themeIndex = (settings.themeIndex % #themes) + 1 
                    saveSettings() 
                    drawUI()
                    
                elseif line == 4 then -- TOGGLE ANIMATIONS
                    buttonPressAnimation(1, y, 22, 1)
                    settings.animations = not settings.animations
                    saveSettings()
                    drawUI()
                    
                elseif line == 6 then -- CHANGE SPEED
                    buttonPressAnimation(1, y, 17, 1)
                    if settings.animationSpeed == 1 then
                        settings.animationSpeed = 0.5
                    elseif settings.animationSpeed == 0.5 then
                        settings.animationSpeed = 2
                    else
                        settings.animationSpeed = 1
                    end
                    saveSettings()
                    drawUI()
                    
                elseif line == 8 then -- TOGGLE ICONS
                    buttonPressAnimation(1, y, 17, 1)
                    settings.showFileIcons = not settings.showFileIcons
                    saveSettings()
                    drawUI()
                    
                elseif line == 10 then -- TOGGLE CLOCK
                    buttonPressAnimation(1, y, 17, 1)
                    settings.showClock = not settings.showClock
                    saveSettings()
                    drawUI()
                    
                elseif line == 12 then -- TOGGLE BLINK
                    buttonPressAnimation(1, y, 17, 1)
                    settings.cursorBlink = not settings.cursorBlink
                    saveSettings()
                    drawUI()
                    
                elseif line == 14 then -- TOGGLE AUTOSAVE
                    buttonPressAnimation(1, y, 20, 1)
                    settings.autoSave = not settings.autoSave
                    saveSettings()
                    drawUI()
                    
                elseif line == 16 then -- TOGGLE TRANSPARENCY
                    buttonPressAnimation(1, y, 24, 1)
                    settings.transparency = not settings.transparency
                    saveSettings()
                    drawUI()
                    
                elseif line == 18 then -- UPDATE SYSTEM
                    buttonPressAnimation(1, y, 17, 1)
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
                    
                elseif line == 20 then -- SHUTDOWN
                    buttonPressAnimation(1, y, 14, 1)
                    running = false 
                end
                
            elseif activeTab == "APPS" and y > 3 and y < h then
                local appIndex = math.floor((y - 4) / 3) * 3 + math.floor((x - 3) / 15)
                local apps = {"Notepad", "Calc", "Clock", "Games", "Paint", "Music"}
                
                if appIndex >= 1 and appIndex <= #apps then
                    buttonPressAnimation(((appIndex-1)%3)*15+3, 4+math.floor((appIndex-1)/3)*3, 11, 3)
                    
                    if apps[appIndex] == "Notepad" then
                        local old = term.redirect(mainWin)
                        term.setCursorBlink(true)
                        shell.run("edit")
                        term.setCursorBlink(false)
                        term.redirect(old)
                        drawUI()
                    elseif apps[appIndex] == "Calc" then
                        mainWin.clear()
                        mainWin.setCursorPos(1, 2)
                        mainWin.write("Calculator: (type expression)")
                        mainWin.setCursorPos(1, 4)
                        local expr = read()
                        local result = loadstring("return " .. expr)()
                        mainWin.setCursorPos(1, 6)
                        mainWin.write("Result: " .. tostring(result))
                        sleep(2)
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
        
        safeBootAnim()
        
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
