-- ameOs v48.0 [NON-BLOCKING CONTEXT & PATH FIX]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local running = true
local activeTab = "HOME"
local currentPath = "/"
local clipboard = { path = nil }
local globalTimer = nil
local contextMenu = nil -- Состояние меню: {x, y, options, file}

local themes = {
    { name = "Night",     bg = colors.black, accent = colors.gray, text = colors.lightGray },
    { name = "Hacker",    bg = colors.black, accent = colors.lime, text = colors.lime }
}
local settings = { themeIndex = 1, user = "User", pass = "", isRegistered = false }

local topWin = window.create(term.current(), 1, 1, w, 1)
local mainWin = window.create(term.current(), 1, 2, w, h - 2)
local taskWin = window.create(term.current(), 1, h, w, 1)

-- 1. SYSTEM
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
        if type(decoded) == "table" then settings = decoded end
    end
end

-- 2. DRAWING
local function drawTopBar()
    local theme = themes[settings.themeIndex]
    local old = term.redirect(topWin)
    topWin.setCursorBlink(false)
    topWin.setBackgroundColor(theme.accent)
    topWin.setTextColor(theme.text)
    topWin.clear()
    topWin.setCursorPos(2, 1) topWin.write("ameOs | " .. activeTab)
    topWin.setCursorPos(w - 6, 1)
    topWin.write(textutils.formatTime(os.time(), true))
    term.redirect(old)
end

local function drawUI()
    local theme = themes[settings.themeIndex]
    -- Таскбар
    taskWin.setBackgroundColor(colors.black)
    taskWin.clear()
    local tabs = { {n="HOME", x=1}, {n="FILE", x=8}, {n="SHLL", x=15}, {n="CONF", x=22} }
    for _, t in ipairs(tabs) do
        taskWin.setCursorPos(t.x, 1)
        taskWin.setBackgroundColor(activeTab == t.n and theme.accent or colors.black)
        taskWin.setTextColor(activeTab == t.n and theme.text or colors.white)
        taskWin.write(" "..t.n.." ")
    end
    
    drawTopBar()
    
    -- Главное окно
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
            mainWin.setTextColor(fs.isDir(fs.combine(home, n)) and colors.cyan or colors.yellow)
            mainWin.write("[#]")
            mainWin.setCursorPos(col-1, row+1)
            mainWin.setTextColor(colors.white)
            mainWin.write(n:sub(1, 8))
        end
    elseif activeTab == "FILE" then
        mainWin.setCursorPos(1, 1) 
        mainWin.setTextColor(colors.yellow)
        mainWin.write(" " .. currentPath) -- ВСЕГДА ПИШЕМ ПУТЬ
        local files = fs.list(currentPath)
        if currentPath ~= "/" then table.insert(files, 1, "..") end
        for i, n in ipairs(files) do
            if i > h-4 then break end
            mainWin.setCursorPos(1, i+2) -- Сдвиг на 2, чтобы не тереть путь
            mainWin.setTextColor(fs.isDir(fs.combine(currentPath, n)) and colors.cyan or colors.white)
            mainWin.write("> "..n)
        end
    elseif activeTab == "CONF" then
        mainWin.setCursorPos(1, 2) mainWin.write(" Theme: "..theme.name)
        mainWin.setCursorPos(1, 4) mainWin.write(" [ NEXT THEME ]")
        mainWin.setCursorPos(1, 6) mainWin.setTextColor(colors.yellow)
        mainWin.write(" [ UPDATE SYSTEM ]")
        mainWin.setCursorPos(1, 8) mainWin.setTextColor(theme.text)
        mainWin.write(" [ SHUTDOWN ]")
    end

    -- Отрисовка контекстного меню (если открыто)
    if contextMenu then
        local mx, my = contextMenu.x, contextMenu.y
        for i, opt in ipairs(contextMenu.options) do
            term.setCursorPos(mx, my + i - 1)
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
            term.write(" " .. opt .. " ")
        end
    end
end

-- 3. ACTIONS
local function handleContext(choice, file)
    local path = (activeTab == "HOME") and getHomeDir() or currentPath
    mainWin.setCursorPos(1,1)
    mainWin.setBackgroundColor(colors.black)
    mainWin.clearLine()
    if choice == "New File" then mainWin.write("Name: ") local n = read() if n~="" then fs.open(fs.combine(path, n), "w").close() end
    elseif choice == "New Folder" then mainWin.write("Dir: ") local n = read() if n~="" then fs.makeDir(fs.combine(path, n)) end
    elseif choice == "Delete" then fs.delete(fs.combine(path, file))
    elseif choice == "Rename" then mainWin.write("New: ") local n = read() if n~="" then fs.move(fs.combine(path, file), fs.combine(path, n)) end
    elseif choice == "Copy" then clipboard.path = fs.combine(path, file)
    elseif choice == "Paste" and clipboard.path then fs.copy(clipboard.path, fs.combine(path, fs.getName(clipboard.path))) end
    contextMenu = nil
    drawUI()
end

local function runExternal(cmd, arg)
    local old = term.redirect(mainWin)
    term.setCursorBlink(true)
    shell.run(cmd, arg or "")
    term.setCursorBlink(false)
    term.redirect(old)
    drawUI()
end

-- 4. ENGINE
local function osEngine()
    loadSettings()
    drawUI()
    globalTimer = os.startTimer(1)
    
    while running do
        local ev, p1, p2, p3 = os.pullEvent()
        
        if ev == "timer" and p1 == globalTimer then
            drawTopBar()
            globalTimer = os.startTimer(1)
        
        elseif ev == "mouse_click" then
            local btn, x, y = p1, p2, p3
            
            -- Если меню открыто, проверяем клик по нему
            if contextMenu then
                if x >= contextMenu.x and x <= contextMenu.x + 12 and y >= contextMenu.y and y < contextMenu.y + #contextMenu.options then
                    handleContext(contextMenu.options[y - contextMenu.y + 1], contextMenu.file)
                else
                    contextMenu = nil
                    drawUI()
                end
            elseif y == h then -- ТАСКБАР
                if x >= 1 and x <= 6 then activeTab = "HOME"
                elseif x >= 8 and x <= 13 then activeTab = "FILE"
                elseif x >= 15 and x <= 20 then activeTab = "SHLL"
                elseif x >= 22 and x <= 27 then activeTab = "CONF" end
                
                if activeTab == "SHLL" then
                    drawUI()
                    parallel.waitForAny(
                        function() runExternal("shell") end,
                        function()
                            local lt = os.startTimer(1)
                            while true do
                                local e, id, tx, ty = os.pullEvent()
                                if e == "timer" and id == lt then drawTopBar() lt = os.startTimer(1)
                                elseif e == "mouse_click" and ty == h then os.queueEvent("mouse_click", 1, tx, ty) return end
                            end
                        end
                    )
                    activeTab = "HOME"
                end
                drawUI()
            elseif activeTab == "FILE" and y > 1 and y < h then
                local files = fs.list(currentPath)
                if currentPath ~= "/" then table.insert(files, 1, "..") end
                local sel = files[y-2]
                if btn == 2 then
                    contextMenu = { x=x, y=y, options = sel and {"Copy", "Rename", "Delete"} or {"New File", "New Folder", "Paste"}, file = sel }
                    drawUI()
                elseif sel then
                    local p = fs.combine(currentPath, sel)
                    if fs.isDir(p) then currentPath = p drawUI() else runExternal("edit", p) end
                end
            elseif activeTab == "HOME" and y > 1 and y < h then
                local home = getHomeDir()
                local files = fs.list(home)
                local sel = nil
                for i, n in ipairs(files) do
                    local col, row = ((i-1)%4)*12+3, math.floor((i-1)/4)*4+2
                    if x >= col and x <= col+6 and y >= row and y <= row+1 then sel = n break end
                end
                if btn == 2 then
                    contextMenu = { x=x, y=y, options = sel and {"Copy", "Rename", "Delete"} or {"New File", "New Folder", "Paste"}, file = sel }
                    drawUI()
                elseif sel then 
                    local p = fs.combine(home, sel)
                    if fs.isDir(p) then activeTab = "FILE" currentPath = p drawUI() else runExternal("edit", p) end
                end
            elseif activeTab == "CONF" then
                if y == 5 then settings.themeIndex = (settings.themeIndex % #themes) + 1 saveSettings() drawUI()
                elseif y == 7 then 
                    mainWin.clear() mainWin.setCursorPos(1,1) print("Updating...")
                    fs.delete("startup.lua") shell.run("wget https://github.com/JemmaperXD/jemmaperxd/raw/refs/heads/main/startup.lua startup.lua")
                    os.reboot()
                elseif y == 9 then running = false end
            end
        end
    end
end

-- 5. START
if fs.exists("/startup.lua") then -- Анимация только при первом запуске
    bootAnim()
end
osEngine()
