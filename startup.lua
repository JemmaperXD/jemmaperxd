-- ameOs v68.0 [CURSOR, PATH, CLOCK & FS FIX]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local running = true
local activeTab = "HOME"
local currentPath = "/"
local clipboard = { path = nil }
local globalTimer = nil
local contextMenu = nil 

local themes = {
    { name = "Night",     bg = colors.black, accent = colors.gray, text = colors.lightGray },
    { name = "Hacker",    bg = colors.black, accent = colors.lime, text = colors.lime }
}
local settings = { themeIndex = 1, user = "User", pass = "", isRegistered = false }

local topWin = window.create(term.current(), 1, 1, w, 1)
local mainWin = window.create(term.current(), 1, 2, w, h - 2)
local taskWin = window.create(term.current(), 1, h, w, 1)

-- 1. СИСТЕМА И ЗАГРУЗКА [cite: 2, 3]
if not fs.exists(CONFIG_DIR) then fs.makeDir(CONFIG_DIR) end
local function getHomeDir() 
    local p = fs.combine("/.User", settings.user)
    if not fs.exists(p) then fs.makeDir(p) end
    return p
end

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

local function bootAnim() -- [cite: 3, 4, 5]
    local cx, cy = math.floor(w/2), math.floor(h/2 - 2)
    local duration = 3
    local start = os.clock()
    local angle = 0
    while os.clock() - start < duration do
        term.setBackgroundColor(colors.black)
        term.clear()
        local elapsed = os.clock() - start
        local fusion = 1.0
        if elapsed > (duration - 1) then fusion = math.max(0, 1 - (elapsed - (duration - 1))) end
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
end

-- 2. ОТРИСОВКА [cite: 6, 7, 8, 9, 10, 11, 12]
local function drawTopBar()
    local theme = themes[settings.themeIndex]
    local old = term.redirect(topWin)
    topWin.setBackgroundColor(theme.accent)
    topWin.setTextColor(theme.text)
    topWin.clear()
    
    topWin.setCursorPos(2, 1)
    local pathDisplay = "ameOs | " .. activeTab
    if activeTab == "FILE" then pathDisplay = pathDisplay .. ": " .. currentPath end
    topWin.write(pathDisplay:sub(1, w - 10))
    
    local timeStr = textutils.formatTime(os.time(), true)
    topWin.setCursorPos(w - #timeStr, 1)
    topWin.write(timeStr)
    
    term.redirect(old)
end

local function drawUI()
    local theme = themes[settings.themeIndex]
    term.setCursorBlink(false)
    
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
    
    mainWin.setBackgroundColor(theme.bg)
    mainWin.setTextColor(theme.text)
    mainWin.clear()
    
    if activeTab == "HOME" then
        local home = getHomeDir()
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
        local files = fs.list(currentPath)
        if currentPath ~= "/" then table.insert(files, 1, "..") end
        for i, n in ipairs(files) do
            if i > (h-3) then break end
            mainWin.setCursorPos(1, i) 
            mainWin.setTextColor(fs.isDir(fs.combine(currentPath, n)) and colors.cyan or colors.white)
            mainWin.write("> " .. n)
        end
    elseif activeTab == "CONF" then
        mainWin.setCursorPos(2, 2) mainWin.write("Theme: "..theme.name)
        mainWin.setCursorPos(2, 4) mainWin.write("[ NEXT THEME ]")
        mainWin.setCursorPos(2, 6) mainWin.setTextColor(colors.yellow)
        mainWin.write("[ UPDATE SYSTEM ]")
        mainWin.setCursorPos(2, 8) mainWin.setTextColor(theme.text)
        mainWin.write("[ SHUTDOWN ]")
    end

    if contextMenu then
        local mw = 12
        for i, opt in ipairs(contextMenu.options) do
            term.setCursorPos(contextMenu.x, contextMenu.y + i - 1)
            term.setBackgroundColor(colors.gray)
            term.setTextColor(colors.white)
            local txt = " "..opt
            term.write(txt..string.rep(" ", mw - #txt))
        end
    end
end

-- 3. ДВИЖОК [cite: 15, 16, 17, 18, 19, 20, 21, 23, 24, 25, 26, 27, 28, 29]
local function osEngine()
    drawUI()
    while running do
        if not globalTimer then globalTimer = os.startTimer(1) end
        local ev, p1, p2, p3 = os.pullEvent()
        
        if ev == "timer" and p1 == globalTimer then
            drawTopBar()
            globalTimer = os.startTimer(1)
        elseif ev == "mouse_click" then
            local btn, x, y = p1, p2, p3
            
            if contextMenu then
                local mw, mh = 12, #contextMenu.options
                if x >= contextMenu.x and x < contextMenu.x + mw and y >= contextMenu.y and y < contextMenu.y + mh then
                    local choice = contextMenu.options[y - contextMenu.y + 1]
                    local file = contextMenu.file
                    local path = (activeTab == "HOME") and getHomeDir() or currentPath
                    contextMenu = nil
                    
                    if choice == "New File" or choice == "New Folder" or choice == "Rename" then
                        drawUI()
                        term.setCursorPos(1, h) term.setBackgroundColor(colors.black) term.setTextColor(colors.white)
                        term.clearLine() term.write("Name: ")
                        term.setCursorBlink(true) -- МОРГАЕТ ТУТ
                        local n = read() 
                        term.setCursorBlink(false)
                        if n and n ~= "" then
                            local target = fs.combine(path, n)
                            if not fs.exists(target) then
                                if choice == "New File" then fs.open(target, "w").close()
                                elseif choice == "New Folder" then fs.makeDir(target)
                                elseif choice == "Rename" then fs.move(fs.combine(path, file), target) end
                            end
                        end
                    elseif choice == "Delete" then fs.delete(fs.combine(path, file))
                    elseif choice == "Copy" then clipboard.path = fs.combine(path, file)
                    elseif choice == "Paste" and clipboard.path then 
                        local target = fs.combine(path, fs.getName(clipboard.path))
                        if not fs.exists(target) then fs.copy(clipboard.path, target) end
                    end
                    drawUI()
                else contextMenu = nil drawUI() end
            elseif y == h then
                if x >= 1 and x <= 6 then activeTab = "HOME"
                elseif x >= 8 and x <= 13 then activeTab = "FILE"
                elseif x >= 15 and x <= 20 then activeTab = "SHLL"
                elseif x >= 22 and x <= 27 then activeTab = "CONF" end
                
                if activeTab == "SHLL" then
                    drawUI()
                    local old = term.redirect(mainWin)
                    term.setBackgroundColor(colors.black) term.clear() term.setCursorPos(1,1)
                    term.setCursorBlink(true) -- МОРГАЕТ В SHELL
                    parallel.waitForAny(
                        function() shell.run("shell") end,
                        function()
                            while true do
                                local e, id, tx, ty = os.pullEvent()
                                if e == "timer" and id == globalTimer then drawTopBar() globalTimer = os.startTimer(1)
                                elseif e == "mouse_click" and ty == h then os.queueEvent("mouse_click", 1, tx, ty) return end
                            end
                        end
                    )
                    term.setCursorBlink(false) term.redirect(old)
                    activeTab = "HOME"
                end
                drawUI()
            elseif activeTab == "FILE" and y > 1 and y < h then
                local files = fs.list(currentPath)
                if currentPath ~= "/" then table.insert(files, 1, "..") end
                local sel = files[y - 1]
                if btn == 2 then
                    contextMenu = { x=x, y=y, options = (sel and sel ~= "..") and {"Copy", "Rename", "Delete"} or {"New File", "New Folder", "Paste"}, file = sel }
                    drawUI()
                elseif sel then
                    local p = fs.combine(currentPath, sel)
                    if fs.isDir(p) then currentPath = p drawUI() else 
                        local old = term.redirect(mainWin) term.setCursorBlink(true) shell.run("edit", p) term.setCursorBlink(false) term.redirect(old) drawUI()
                    end
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
                    if fs.isDir(p) then activeTab = "FILE" currentPath = p drawUI() else
                        local old = term.redirect(mainWin) term.setCursorBlink(true) shell.run("edit", p) term.setCursorBlink(false) term.redirect(old) drawUI()
                    end
                end
            elseif activeTab == "CONF" then
                if y == 5 then settings.themeIndex = (settings.themeIndex % #themes) + 1 saveSettings() drawUI()
                elseif y == 7 then 
                    term.setBackgroundColor(colors.black) term.clear()
                    term.setCursorPos(w/2-6, h/2) print("Updating...")
                    fs.delete("startup.lua")
                    shell.run("wget https://github.com/JemmaperXD/jemmaperxd/raw/refs/heads/stable/startup.lua startup.lua")
                    os.reboot()
                elseif y == 9 then running = false end
            end
        end
    end
end

-- 4. ВХОД [cite: 30, 31]
loadSettings()
bootAnim()
term.setBackgroundColor(colors.black)
term.clear()

local function centeredAuth(title)
    term.clear()
    term.setTextColor(colors.cyan)
    term.setCursorPos(math.floor(w/2 - #title/2), h/2 - 1)
    print(title)
    term.setTextColor(colors.white)
end

if not settings.isRegistered then
    centeredAuth("REGISTRATION")
    term.setCursorBlink(true)
    term.setCursorPos(math.floor(w/2 - 8), h/2 + 1) write("User: ") settings.user = read()
    term.setCursorPos(math.floor(w/2 - 8), h/2 + 2) write("Pass: ") settings.pass = read("*")
    settings.isRegistered = true saveSettings()
    term.setCursorBlink(false)
else
    local auth = false
    while not auth do
        centeredAuth("LOGIN: " .. settings.user)
        term.setCursorBlink(true)
        term.setCursorPos(math.floor(w/2 - 8), h/2 + 1) write("Pass: ")
        if read("*") == settings.pass then auth = true else
            term.setCursorPos(math.floor(w/2 - 2), h/2 + 3) term.setTextColor(colors.red) print("FAIL") sleep(0.5)
        end
    end
end

osEngine()
term.setBackgroundColor(colors.black)
term.clear()
