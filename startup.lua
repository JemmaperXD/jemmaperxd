-- JemmaOS v2.0 - Enhanced Desktop Environment for ComputerCraft
-- Author: JemmaperXD
-- GitHub: https://github.com/JemmaperXD

-- INITIALIZATION
local w, h = term.getSize()
local running = true
local activeTab = "HOME"
local currentPath = "/"
local globalTimer = nil
local settings = {
    themeIndex = 1,
    accentColor = colors.blue,
    showHiddenFiles = false,
    showFileExtensions = true,
    enableAnimations = true,
    enableSound = false,
    shellPrompt = "$ ",
    autoSave = true,
    language = "en",
    fontSize = 1,
    screenSaverTimeout = 300
}
local themes = {
    {name = "Classic", bg = colors.black, fg = colors.white, accent = colors.blue},
    {name = "Dark", bg = colors.gray, fg = colors.white, accent = colors.orange},
    {name = "Light", bg = colors.white, fg = colors.black, accent = colors.blue},
    {name = "Ocean", bg = colors.cyan, fg = colors.black, accent = colors.blue},
    {name = "Forest", bg = colors.green, fg = colors.black, accent = colors.lime},
    {name = "Midnight", bg = colors.purple, fg = colors.white, accent = colors.pink}
}

-- WINDOWS
local mainWin = window.create(term.current(), 1, 2, w, h-1)
local topBar = window.create(term.current(), 1, 1, w, 1)

-- UTILITY FUNCTIONS
local function normalizePath(path)
    return fs.combine("/", path)
end

local function getHomeDir()
    if fs.exists("/home") then
        return "/home"
    else
        return "/"
    end
end

local function loadSettings()
    if fs.exists("jemmaos.cfg") then
        local file = fs.open("jemmaos.cfg", "r")
        if file then
            local data = file.readAll()
            file.close()
            local loaded = textutils.unserialize(data)
            if loaded then
                for k, v in pairs(loaded) do
                    settings[k] = v
                end
            end
        end
    end
end

local function saveSettings()
    if settings.autoSave then
        local file = fs.open("jemmaos.cfg", "w")
        if file then
            file.write(textutils.serialize(settings))
            file.close()
        end
    end
end

local function showNotification(title, message, duration)
    if not settings.enableAnimations then duration = 0 end
    
    local notifWin = window.create(term.current(), 1, h-3, w, 3)
    notifWin.setBackgroundColor(themes[settings.themeIndex].bg)
    notifWin.setTextColor(themes[settings.themeIndex].accent)
    notifWin.clear()
    
    -- Title
    notifWin.setCursorPos(2, 1)
    notifWin.write("["..title.."]")
    
    -- Message
    notifWin.setCursorPos(2, 2)
    notifWin.setTextColor(themes[settings.themeIndex].fg)
    if #message > w-3 then
        notifWin.write(message:sub(1, w-6).."...")
    else
        notifWin.write(message)
    end
    
    -- Progress bar
    if duration > 0 then
        local startTime = os.clock()
        while os.clock() - startTime < duration do
            local progress = (os.clock() - startTime) / duration
            local barWidth = math.floor((w-2) * progress)
            notifWin.setCursorPos(1, 3)
            notifWin.setTextColor(settings.accentColor)
            notifWin.write(("\127"):rep(barWidth))
            notifWin.setTextColor(themes[settings.themeIndex].bg)
            notifWin.write(("\127"):rep(w-barWidth))
            os.startTimer(0.05)
            os.pullEvent("timer")
        end
    end
    
    notifWin.setVisible(false)
end

-- ANIMATION FUNCTIONS
local function showLineageOSLoading(duration, message, showPercentage)
    local frames = {
        "▁▂▃▄▅▆▇█▇▆▅▄▃▂▁",
        "▂▃▄▅▆▇█▇▆▅▄▃▂▁▁",
        "▃▄▅▆▇█▇▆▅▄▃▂▁▁▂",
        "▄▅▆▇█▇▆▅▄▃▂▁▁▂▃",
        "▅▆▇█▇▆▅▄▃▂▁▁▂▃▄",
        "▆▇█▇▆▅▄▃▂▁▁▂▃▄▅",
        "▇█▇▆▅▄▃▂▁▁▂▃▄▅▆",
        "█▇▆▅▄▃▂▁▁▂▃▄▅▆▇",
        "▇▆▅▄▃▂▁▁▂▃▄▅▆▇█",
        "▆▅▄▃▂▁▁▂▃▄▅▆▇█▇",
        "▅▄▃▂▁▁▂▃▄▅▆▇█▇▆",
        "▄▃▂▁▁▂▃▄▅▆▇█▇▆▅",
        "▃▂▁▁▂▃▄▅▆▇█▇▆▅▄",
        "▂▁▁▂▃▄▅▆▇█▇▆▅▄▃",
        "▁▁▂▃▄▅▆▇█▇▆▅▄▃▂"
    }
    
    local colors_fade = {
        colors.blue,
        colors.lightBlue,
        colors.cyan,
        colors.lightBlue,
        colors.blue
    }
    
    local old = term.redirect(mainWin)
    term.setBackgroundColor(colors.black)
    term.clear()
    
    -- Message
    term.setTextColor(colors.white)
    term.setCursorPos((w - #message) / 2, math.floor(h/2) - 2)
    term.write(message)
    
    -- Animation
    local startTime = os.clock()
    local frame = 1
    local colorFrame = 1
    local lastUpdate = os.clock()
    
    while os.clock() - startTime < duration do
        local currentTime = os.clock()
        
        if currentTime - lastUpdate >= 0.05 then
            -- Clear animation area
            term.setCursorPos((w - 13) / 2, math.floor(h/2))
            term.write("             ")
            
            -- Draw current frame
            term.setCursorPos((w - 13) / 2, math.floor(h/2))
            term.setTextColor(colors_fade[colorFrame])
            term.write(frames[frame])
            
            -- Show percentage if requested
            if showPercentage then
                local percent = math.floor(((currentTime - startTime) / duration) * 100)
                term.setCursorPos((w - 3) / 2, math.floor(h/2) + 1)
                term.setTextColor(colors.lightGray)
                term.write(string.format("%3d%%", math.min(100, percent)))
            end
            
            -- Update frames
            frame = frame + 1
            if frame > #frames then frame = 1 end
            
            colorFrame = colorFrame + 1
            if colorFrame > #colors_fade then colorFrame = 1 end
            
            lastUpdate = currentTime
        end
        
        -- Process events without blocking
        local event = os.pullEventRaw()
        if event == "terminate" then
            term.redirect(old)
            return false
        end
    end
    
    -- Success animation
    for i = 1, 2 do
        term.setCursorPos((w - 13) / 2, math.floor(h/2))
        term.setTextColor(colors.green)
        term.write("█████████████")
        os.startTimer(0.08)
        os.pullEvent("timer")
        
        term.setCursorPos((w - 13) / 2, math.floor(h/2))
        term.setTextColor(colors.lime)
        term.write("█████████████")
        os.startTimer(0.08)
        os.pullEvent("timer")
    end
    
    term.redirect(old)
    return true
end

-- UI DRAWING FUNCTIONS
local function drawTopBar()
    topBar.setBackgroundColor(themes[settings.themeIndex].bg)
    topBar.setTextColor(themes[settings.themeIndex].fg)
    topBar.clear()
    
    -- Clock
    local timeText = textutils.formatTime(os.time(), false)
    topBar.setCursorPos(w - #timeText, 1)
    topBar.write(timeText)
    
    -- Battery indicator (simulated)
    topBar.setCursorPos(w - #timeText - 6, 1)
    topBar.write("[####    ]")
    
    -- Free memory
    local freeMem = math.floor(computer.freeMemory() / 1024)
    topBar.setCursorPos(w - #timeText - 15, 1)
    topBar.write(freeMem .. "K free")
end

local function drawTabs()
    local tabs = {
        {"HOME", 1, 6},
        {"FILE", 8, 13},
        {"SHLL", 15, 20},
        {"CONF", 22, 27},
        {"APPS", 29, 34}
    }
    
    for _, tab in ipairs(tabs) do
        local name, x1, x2 = tab[1], tab[2], tab[3]
        term.setCursorPos(x1, 1)
        
        if activeTab == name then
            term.setBackgroundColor(settings.accentColor)
            term.setTextColor(colors.white)
            term.write(" "..name.." ")
        else
            term.setBackgroundColor(themes[settings.themeIndex].bg)
            term.setTextColor(themes[settings.themeIndex].fg)
            term.write(" "..name.." ")
        end
    end
end

local function drawFileList()
    mainWin.setBackgroundColor(themes[settings.themeIndex].bg)
    mainWin.clear()
    
    local files = fs.list(currentPath)
    local y = 1
    
    -- Current path
    mainWin.setTextColor(settings.accentColor)
    mainWin.setCursorPos(1, 1)
    mainWin.write("Path: " .. currentPath)
    
    -- Parent directory
    if currentPath ~= "/" then
        mainWin.setCursorPos(1, 3)
        mainWin.setTextColor(colors.lightGray)
        mainWin.write("[..]")
        y = 4
    end
    
    -- Files and directories
    for _, file in ipairs(files) do
        if not file:find("^%.") or settings.showHiddenFiles then
            mainWin.setCursorPos(1, y)
            
            if fs.isDir(fs.combine(currentPath, file)) then
                mainWin.setTextColor(colors.yellow)
                mainWin.write("[D] " .. file)
            else
                local ext = file:match("%.(%w+)$") or ""
                if ext:lower() == "lua" then
                    mainWin.setTextColor(colors.green)
                elseif ext:lower() == "txt" then
                    mainWin.setTextColor(colors.white)
                else
                    mainWin.setTextColor(colors.lightGray)
                end
                
                if settings.showFileExtensions then
                    mainWin.write("[F] " .. file)
                else
                    local name = file:gsub("%.[^%.]+$", "")
                    mainWin.write("[F] " .. name)
                end
            end
            
            y = y + 1
            if y > h-1 then break end
        end
    end
end

local function drawHome()
    mainWin.setBackgroundColor(themes[settings.themeIndex].bg)
    mainWin.clear()
    
    mainWin.setTextColor(settings.accentColor)
    mainWin.setCursorPos(1, 1)
    mainWin.write("Home Directory")
    
    local home = getHomeDir()
    local files = fs.list(home)
    local x, y = 1, 3
    
    for i, file in ipairs(files) do
        if not file:find("^%.") or settings.showHiddenFiles then
            local row = math.floor((i-1) / 4)
            local col = ((i-1) % 4)
            local posX = col * 12 + 2
            local posY = row * 3 + 3
            
            if posY < h-1 then
                mainWin.setCursorPos(posX, posY)
                
                if fs.isDir(fs.combine(home, file)) then
                    mainWin.setTextColor(colors.yellow)
                    mainWin.write("\127")
                else
                    mainWin.setTextColor(colors.green)
                    mainWin.write("\131")
                end
                
                mainWin.setCursorPos(posX, posY + 1)
                mainWin.setTextColor(themes[settings.themeIndex].fg)
                
                if #file > 10 then
                    mainWin.write(file:sub(1, 8).."..")
                else
                    mainWin.write(file)
                end
            end
        end
    end
end

local function drawConfig()
    mainWin.setBackgroundColor(themes[settings.themeIndex].bg)
    mainWin.clear()
    
    mainWin.setTextColor(settings.accentColor)
    mainWin.setCursorPos(1, 1)
    mainWin.write("Settings")
    
    local options = {
        {"Theme: " .. themes[settings.themeIndex].name, 3},
        {"Accent Color", 4},
        {"Show Hidden Files: " .. (settings.showHiddenFiles and "ON" or "OFF"), 5},
        {"Show Extensions: " .. (settings.showFileExtensions and "ON" or "OFF"), 6},
        {"Animations: " .. (settings.enableAnimations and "ON" or "OFF"), 7},
        {"Sound: " .. (settings.enableSound and "ON" or "OFF"), 8},
        {"Auto Save: " .. (settings.autoSave and "ON" or "OFF"), 9},
        {"Shell Prompt: " .. settings.shellPrompt, 10},
        {"Language: " .. settings.language, 11},
        {"Font Size: " .. settings.fontSize, 12},
        {"Screen Saver: " .. settings.screenSaverTimeout .. "s", 13},
        {"Update System", 15},
        {"Save Settings", 16},
        {"Exit", 18}
    }
    
    for _, option in ipairs(options) do
        local text, line = option[1], option[2]
        mainWin.setCursorPos(3, line)
        
        if line >= 15 then
            mainWin.setTextColor(colors.yellow)
            if line == 18 then
                mainWin.setTextColor(colors.red)
            end
        else
            mainWin.setTextColor(themes[settings.themeIndex].fg)
        end
        
        mainWin.write(text)
    end
    
    -- Color palette
    if activeTab == "CONF" then
        local colorsList = {colors.blue, colors.red, colors.green, colors.orange, 
                          colors.purple, colors.cyan, colors.pink, colors.lime}
        local x = 20
        for i, color in ipairs(colorsList) do
            mainWin.setCursorPos(x + ((i-1)*2), 4)
            if color == settings.accentColor then
                mainWin.write("[")
                mainWin.setBackgroundColor(color)
                mainWin.write(" ")
                mainWin.setBackgroundColor(themes[settings.themeIndex].bg)
                mainWin.write("]")
            else
                mainWin.write(" ")
                mainWin.setBackgroundColor(color)
                mainWin.write(" ")
                mainWin.setBackgroundColor(themes[settings.themeIndex].bg)
                mainWin.write(" ")
            end
        end
    end
end

local function drawApps()
    mainWin.setBackgroundColor(themes[settings.themeIndex].bg)
    mainWin.clear()
    
    mainWin.setTextColor(settings.accentColor)
    mainWin.setCursorPos(1, 1)
    mainWin.write("Applications")
    
    local apps = {
        {"Paint", function() shell.run("paint") end},
        {"Music", function() shell.run("music") end},
        {"Calculator", function() shell.run("calc") end},
        {"Browser", function() shell.run("browse") end},
        {"Notepad", function() shell.run("edit") end},
        {"Terminal", function() shell.run("shell") end},
        {"Games", function() shell.run("games") end},
        {"Help", function() shell.run("help") end}
    }
    
    local x, y = 3, 3
    for i, app in ipairs(apps) do
        local name, _ = app[1], app[2]
        local row = math.floor((i-1) / 3)
        local col = ((i-1) % 3)
        local posX = col * 15 + 3
        local posY = row * 2 + 3
        
        mainWin.setCursorPos(posX, posY)
        mainWin.setTextColor(colors.lightBlue)
        mainWin.write("\149")
        
        mainWin.setCursorPos(posX + 2, posY)
        mainWin.setTextColor(themes[settings.themeIndex].fg)
        mainWin.write(name)
        
        mainWin.setCursorPos(posX, posY + 1)
        mainWin.setTextColor(colors.gray)
        mainWin.write(("─"):rep(#name + 2))
    end
end

local function drawUI()
    term.setBackgroundColor(themes[settings.themeIndex].bg)
    term.clear()
    
    drawTopBar()
    drawTabs()
    
    if activeTab == "HOME" then
        drawHome()
    elseif activeTab == "FILE" then
        drawFileList()
    elseif activeTab == "CONF" then
        drawConfig()
    elseif activeTab == "APPS" then
        drawApps()
    else
        mainWin.setBackgroundColor(themes[settings.themeIndex].bg)
        mainWin.clear()
        mainWin.setCursorPos(1, 1)
        mainWin.setTextColor(settings.accentColor)
        mainWin.write(activeTab .. " - Ready")
    end
end

local function showContext(x, y, selection)
    local contextWin = window.create(term.current(), x, y, 15, 5)
    contextWin.setBackgroundColor(colors.lightGray)
    contextWin.setTextColor(colors.black)
    contextWin.clear()
    
    local options = {"Open", "Edit", "Delete", "Rename", "Properties"}
    for i, option in ipairs(options) do
        contextWin.setCursorPos(1, i)
        contextWin.write(" "..option.." ")
    end
    
    local selected = nil
    while not selected do
        local ev, btn, mx, my = os.pullEvent("mouse_click")
        if mx >= x and mx <= x+14 and my >= y and my <= y+4 then
            selected = my - y + 1
        else
            contextWin.setVisible(false)
            return
        end
    end
    
    contextWin.setVisible(false)
    
    if selection then
        local path = fs.combine(currentPath, selection)
        if selected == 1 then -- Open
            if fs.isDir(path) then
                currentPath = path
                drawUI()
            else
                local old = term.redirect(mainWin)
                term.setCursorBlink(true)
                shell.run("edit", path)
                term.setCursorBlink(false)
                term.redirect(old)
                drawUI()
            end
        elseif selected == 2 then -- Edit
            local old = term.redirect(mainWin)
            term.setCursorBlink(true)
            shell.run("edit", path)
            term.setCursorBlink(false)
            term.redirect(old)
            drawUI()
        elseif selected == 3 then -- Delete
            mainWin.setCursorPos(1, 1)
            mainWin.setTextColor(colors.red)
            mainWin.write("Delete "..selection.."? (Y/N)")
            local event = os.pullEvent("char")
            if event:lower() == "y" then
                fs.delete(path)
                showNotification("File Manager", "Deleted: "..selection, 1)
            end
            drawUI()
        elseif selected == 5 then -- Properties
            local size = "?"
            if not fs.isDir(path) then
                local file = fs.open(path, "r")
                if file then
                    size = #file.readAll() .. " bytes"
                    file.close()
                end
            else
                size = "Directory"
            end
            showNotification("Properties", selection..": "..size, 2)
        end
    end
end

-- ENGINE
local function osEngine()
    loadSettings()
    drawUI()
    globalTimer = os.startTimer(1)
    
    -- Screen saver timeout
    local lastActivity = os.clock()
    
    while running do
        local ev, p1, p2, p3, p4 = os.pullEvent()
        lastActivity = os.clock()
        
        if ev == "timer" and p1 == globalTimer then
            drawTopBar()
            globalTimer = os.startTimer(1)
            
            -- Check screen saver
            if settings.screenSaverTimeout > 0 and 
               os.clock() - lastActivity > settings.screenSaverTimeout then
                if settings.enableAnimations then
                    showLineageOSLoading(5, "JemmaOS")
                end
                lastActivity = os.clock()
            end
        
        elseif ev == "mouse_click" then
            local btn, x, y = p1, p2, p3
            
            -- Tab switching
            if y == 1 then
                if x >= 1 and x <= 6 then activeTab = "HOME"
                elseif x >= 8 and x <= 13 then activeTab = "FILE"
                elseif x >= 15 and x <= 20 then activeTab = "SHLL"
                elseif x >= 22 and x <= 27 then activeTab = "CONF"
                elseif x >= 29 and x <= 34 then activeTab = "APPS" end
                
                -- Special handling for shell tab
                if activeTab == "SHLL" then
                    drawUI()
                    local old = term.redirect(mainWin)
                    term.setBackgroundColor(colors.black)
                    term.clear()
                    term.setCursorPos(1,1)
                    term.setCursorBlink(true)
                    
                    parallel.waitForAny(
                        function() 
                            shell.run("shell") 
                        end,
                        function()
                            local timer = os.startTimer(1)
                            while true do
                                local e, id, tx, ty = os.pullEvent()
                                if e == "timer" and id == timer then 
                                    drawTopBar() 
                                    timer = os.startTimer(1)
                                elseif e == "mouse_click" and ty == 1 then 
                                    os.queueEvent("mouse_click", 1, tx, ty) 
                                    return 
                                end
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
            
            -- FILE MANAGER
            elseif activeTab == "FILE" and y > 1 and y < h then
                local fList = {}
                local files = fs.list(currentPath)
                if currentPath ~= "/" then table.insert(fList, 1, "..") end
                for _, f in ipairs(files) do
                    if not f:find("^%.") or settings.showHiddenFiles then
                        table.insert(fList, f)
                    end
                end
                local line = y - 2
                if currentPath == "/" then line = y - 1 end
                
                local sel = fList[line]
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
            
            -- HOME
            elseif activeTab == "HOME" and y > 1 and y < h then
                local home = getHomeDir()
                local fList = fs.list(home)
                local sel = nil
                
                for i, n in ipairs(fList) do
                    if not n:find("^%.") or settings.showHiddenFiles then
                        local row = math.floor((i-1) / 4)
                        local col = ((i-1) % 4)
                        local posX = col * 12 + 2
                        local posY = row * 3 + 3
                        
                        if x >= posX and x <= posX+6 and y >= posY and y <= posY+1 then
                            sel = n
                            break
                        end
                    end
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
            
            -- CONFIGURATION
            elseif activeTab == "CONF" then
                local line = y
                
                if line == 3 then -- Theme
                    settings.themeIndex = (settings.themeIndex % #themes) + 1
                    if settings.enableAnimations then
                        showNotification("Settings", "Theme: "..themes[settings.themeIndex].name, 1)
                    end
                    drawUI()
                
                elseif line == 4 then -- Accent color
                    local colorsList = {colors.blue, colors.red, colors.green, colors.orange, 
                                      colors.purple, colors.cyan, colors.pink, colors.lime}
                    local colIndex = math.floor((x - 20) / 2) + 1
                    if colIndex >= 1 and colIndex <= #colorsList then
                        settings.accentColor = colorsList[colIndex]
                        if settings.enableAnimations then
                            showNotification("Settings", "Accent color changed", 1)
                        end
                        drawUI()
                    end
                
                elseif line == 5 then -- Show hidden files
                    settings.showHiddenFiles = not settings.showHiddenFiles
                    drawUI()
                
                elseif line == 6 then -- Show extensions
                    settings.showFileExtensions = not settings.showFileExtensions
                    drawUI()
                
                elseif line == 7 then -- Animations
                    settings.enableAnimations = not settings.enableAnimations
                    drawUI()
                
                elseif line == 8 then -- Sound
                    settings.enableSound = not settings.enableSound
                    drawUI()
                
                elseif line == 9 then -- Auto save
                    settings.autoSave = not settings.autoSave
                    drawUI()
                
                elseif line == 10 then -- Shell prompt
                    mainWin.setCursorPos(3, 10)
                    mainWin.setTextColor(colors.yellow)
                    mainWin.write("New prompt: ")
                    term.setCursorBlink(true)
                    local _, char = os.pullEvent("char")
                    settings.shellPrompt = char .. " "
                    term.setCursorBlink(false)
                    drawUI()
                
                elseif line == 11 then -- Language
                    settings.language = settings.language == "en" and "ru" or "en"
                    drawUI()
                
                elseif line == 12 then -- Font size
                    settings.fontSize = settings.fontSize % 3 + 1
                    drawUI()
                
                elseif line == 13 then -- Screen saver
                    settings.screenSaverTimeout = (settings.screenSaverTimeout + 60) % 600
                    if settings.screenSaverTimeout == 0 then
                        settings.screenSaverTimeout = 60
                    end
                    drawUI()
                
                elseif line == 15 then -- Update system
                    if settings.enableAnimations then
                        if not showLineageOSLoading(2, "Checking for updates", true) then
                            break
                        end
                    end
                    
                    mainWin.clear()
                    mainWin.setCursorPos(1,1)
                    mainWin.setTextColor(colors.yellow)
                    mainWin.write("Updating JemmaOS...")
                    
                    local tempFile = "startup_temp.lua"
                    local finalFile = "startup.lua"
                    local url = "https://github.com/JemmaperXD/jemmaperxd/raw/main/startup.lua"
                    
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
                            sleep(1)
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
                        saveSettings()
                        sleep(2)
                        os.reboot()
                    else
                        if fs.exists(tempFile) then
                            fs.delete(tempFile)
                        end
                        
                        mainWin.setCursorPos(1, 3)
                        mainWin.setTextColor(colors.red)
                        mainWin.write("Update failed!")
                        showNotification("Update", "Failed to download update", 2)
                        sleep(2)
                        drawUI()
                    end
                
                elseif line == 16 then -- Save settings
                    saveSettings()
                    showNotification("Settings", "Settings saved successfully", 1)
                
                elseif line == 18 then -- Exit
                    if settings.confirmationOnExit then
                        mainWin.setCursorPos(1, 18)
                        mainWin.setTextColor(colors.red)
                        mainWin.write("Exit JemmaOS? (Y/N)")
                        local event = os.pullEvent("char")
                        if event:lower() == "y" then
                            running = false
                        else
                            drawUI()
                        end
                    else
                        running = false
                    end
                end
            
            -- APPS
            elseif activeTab == "APPS" then
                local apps = {
                    {3, 3, function() shell.run("paint") end},
                    {18, 3, function() shell.run("music") end},
                    {33, 3, function() shell.run("calc") end},
                    {3, 5, function() shell.run("browse") end},
                    {18, 5, function() shell.run("edit") end},
                    {33, 5, function() shell.run("shell") end},
                    {3, 7, function() shell.run("games") end},
                    {18, 7, function() shell.run("help") end}
                }
                
                for _, app in ipairs(apps) do
                    local appX, appY, func = app[1], app[2], app[3]
                    if x >= appX and x <= appX+10 and y >= appY and y <= appY then
                        local old = term.redirect(mainWin)
                        term.setCursorBlink(true)
                        func()
                        term.setCursorBlink(false)
                        term.redirect(old)
                        drawUI()
                        break
                    end
                end
            end
        end
    end
    
    -- Clean exit
    os.cancelTimer(globalTimer)
    term.setBackgroundColor(colors.black)
    term.setTextColor(colors.white)
    term.clear()
    term.setCursorPos(1, 1)
    print("JemmaOS shutdown complete.")
    print("Goodbye!")
end

-- STARTUP
local function startup()
    term.clear()
    term.setCursorPos(1, 1)
    
    if settings.enableAnimations then
        showLineageOSLoading(2, "JemmaOS v2.0")
    end
    
    -- Check for first run
    if not fs.exists("jemmaos.cfg") then
        showNotification("Welcome", "First time setup complete!", 2)
        saveSettings()
    end
    
    -- Main loop
    local ok, err = pcall(osEngine)
    if not ok then
        term.setBackgroundColor(colors.black)
        term.setTextColor(colors.red)
        term.clear()
        term.setCursorPos(1, 1)
        print("JemmaOS crashed!")
        print("Error: " .. err)
        print("")
        print("Press any key to reboot...")
        os.pullEvent("key")
        os.reboot()
    end
end

-- RUN
startup()
