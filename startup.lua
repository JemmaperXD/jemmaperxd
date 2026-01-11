-- ameOs v46.1 [PATH IN BAR & AUTO-RENAME FIX]
local w, h = term.getSize() [cite: 1]
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg" [cite: 1]
local running = true [cite: 1]
local activeTab = "HOME" [cite: 1]
local currentPath = "/" [cite: 1]
local clipboard = { path = nil } [cite: 1]
local globalTimer = nil [cite: 1]

local themes = {
    { name = "Night",     bg = colors.black, accent = colors.gray, text = colors.lightGray }, [cite: 1]
    { name = "Hacker",    bg = colors.black, accent = colors.lime, text = colors.lime } [cite: 1]
}
local settings = { themeIndex = 1, user = "User", pass = "", isRegistered = false } [cite: 1]

local topWin = window.create(term.current(), 1, 1, w, 1) [cite: 1, 2]
local mainWin = window.create(term.current(), 1, 2, w, h - 2) [cite: 2]
local taskWin = window.create(term.current(), 1, h, w, 1) [cite: 2]

-- 1. SYSTEM UTILS
if not fs.exists(CONFIG_DIR) then fs.makeDir(CONFIG_DIR) end [cite: 2]
local function getHomeDir() return fs.combine("/.User", "." .. settings.user) end [cite: 2]

local function saveSettings()
    local f = fs.open(SETTINGS_PATH, "w") [cite: 2]
    f.write(textutils.serialize(settings)) [cite: 2]
    f.close() [cite: 2]
end

local function loadSettings()
    if fs.exists(SETTINGS_PATH) then [cite: 2]
        local f = fs.open(SETTINGS_PATH, "r") [cite: 2]
        local data = f.readAll() f.close() [cite: 2]
        local decoded = textutils.unserialize(data or "") [cite: 2]
        if type(decoded) == "table" then settings = decoded end [cite: 3]
    end
end

-- Функция для генерации уникального имени (защита от краша/перезаписи)
local function getUniquePath(basePath, name)
    local fullPath = fs.combine(basePath, name)
    if not fs.exists(fullPath) then return fullPath end
    
    local namePart = name:match("(.+)%..+") or name
    local extPart = name:match(".+(%.%w+)$") or ""
    local counter = 1
    
    while fs.exists(fs.combine(basePath, namePart .. " (" .. counter .. ")" .. extPart)) do
        counter = counter + 1
    end
    return fs.combine(basePath, namePart .. " (" .. counter .. ")" .. extPart)
end

-- 2. BOOT ANIMATION
local function bootAnim()
    local cx, cy = math.floor(w/2), math.floor(h/2 - 2) [cite: 3]
    local duration = 5 [cite: 3]
    local start = os.clock() [cite: 3]
    local angle = 0 [cite: 3]
    while os.clock() - start < duration do [cite: 3]
        local elapsed = os.clock() - start [cite: 4]
        term.setBackgroundColor(colors.black) [cite: 4]
        term.clear() [cite: 4]
        local fusion = 1.0 [cite: 4]
        if elapsed > (duration - 2) then fusion = math.max(0, 1 - (elapsed - (duration - 2)) / 2) end [cite: 4]
        term.setTextColor(colors.cyan) [cite: 4]
        local rX, rY = 2.5 * fusion, 1.5 * fusion [cite: 4]
        for i = 1, 3 do [cite: 4]
            local a = angle + (i * 2.1) [cite: 4]
            term.setCursorPos(cx + math.floor(math.cos(a)*rX+0.5), cy + math.floor(math.sin(a)*rY+0.5)) [cite: 5]
            term.write("o") [cite: 5]
        end
        term.setCursorPos(cx - 2, h - 1) [cite: 5]
        term.setTextColor(colors.white) [cite: 5]
        term.write("ameOS") [cite: 5]
        angle = angle + 0.4 [cite: 5]
        sleep(0.05) [cite: 5]
    end
end

-- 3. RENDERING
local function drawTopBar()
    local theme = themes[settings.themeIndex] [cite: 5]
    local old = term.redirect(topWin) [cite: 5]
    topWin.setCursorBlink(false) [cite: 6]
    topWin.setBackgroundColor(theme.accent) [cite: 6]
    topWin.setTextColor(theme.text) [cite: 6]
    topWin.clear() [cite: 6]
    topWin.setCursorPos(2, 1)
    
    -- ПУТЬ В БАРЕ: Если мы в FILE, пишем путь, иначе название вкладки 
    local headerText = activeTab
    if activeTab == "FILE" then headerText = "PATH: " .. currentPath end
    topWin.write("ameOs | " .. headerText) [cite: 6, 7]
    
    topWin.setCursorPos(w - 6, 1) [cite: 7]
    topWin.write(textutils.formatTime(os.time(), true)) [cite: 7]
    term.redirect(old) [cite: 7]
end

local function drawUI()
    local theme = themes[settings.themeIndex] [cite: 7]
    taskWin.setBackgroundColor(colors.black) [cite: 7]
    taskWin.clear() [cite: 7]
    taskWin.setCursorBlink(false) [cite: 7]
    local tabs = { {n="HOME", x=1}, {n="FILE", x=8}, {n="SHLL", x=15}, {n="CONF", x=22} } [cite: 7]
    for _, t in ipairs(tabs) do [cite: 7]
        taskWin.setCursorPos(t.x, 1) [cite: 7]
        taskWin.setBackgroundColor(activeTab == t.n and theme.accent or colors.black) [cite: 7]
        taskWin.setTextColor(activeTab == t.n and theme.text or colors.white) [cite: 7, 8]
        taskWin.write(" "..t.n.." ") [cite: 8]
    end
    drawTopBar() [cite: 8]
    mainWin.setBackgroundColor(theme.bg) [cite: 8]
    mainWin.setTextColor(theme.text) [cite: 8]
    mainWin.clear() [cite: 8]
    
    if activeTab == "HOME" then [cite: 8]
        local home = getHomeDir() [cite: 8]
        if not fs.exists(home) then fs.makeDir(home) end [cite: 8]
        local files = fs.list(home) [cite: 8]
        for i, n in ipairs(files) do [cite: 8]
            local col, row = ((i-1)%4)*12+3, math.floor((i-1)/4)*4+1 [cite: 9]
            mainWin.setCursorPos(col, row) [cite: 9]
            mainWin.setTextColor(fs.isDir(fs.combine(home, n)) and colors.cyan or colors.yellow) [cite: 9]
            mainWin.write("[#]") [cite: 9]
            mainWin.setCursorPos(col-1, row+1) [cite: 9]
            mainWin.setTextColor(colors.white) [cite: 9]
            mainWin.write(n:sub(1, 8)) [cite: 9]
        end
    elseif activeTab == "FILE" then [cite: 10]
        local files = fs.list(currentPath) [cite: 10]
        if currentPath ~= "/" then table.insert(files, 1, "..") end [cite: 10]
        for i, n in ipairs(files) do [cite: 10]
            if i > h-4 then break end [cite: 10]
            mainWin.setCursorPos(1, i) [cite: 10]
            mainWin.setTextColor(fs.isDir(fs.combine(currentPath, n)) and colors.cyan or colors.white) [cite: 11]
            mainWin.write("> "..n) [cite: 11]
        end
    elseif activeTab == "CONF" then [cite: 11]
        mainWin.setCursorPos(1, 2) mainWin.write(" Theme: "..theme.name) [cite: 11]
        mainWin.setCursorPos(1, 4) mainWin.write(" [ NEXT THEME ]") [cite: 11]
        mainWin.setCursorPos(1, 6) mainWin.setTextColor(colors.yellow) [cite: 11]
        mainWin.write(" [ UPDATE SYSTEM ]") [cite: 11]
        mainWin.setCursorPos(1, 8) mainWin.setTextColor(theme.text) [cite: 11, 12]
        mainWin.write(" [ SHUTDOWN ]") [cite: 12]
    end
end

-- 4. CONTEXT MENU
local function showContext(mx, my, file)
    local opts = file and {"Copy", "Rename", "Delete"} or {"New File", "New Folder", "Paste"} [cite: 12]
    local menuWin = window.create(term.current(), mx, my, 12, #opts) [cite: 12]
    menuWin.setBackgroundColor(colors.gray) [cite: 12]
    menuWin.setTextColor(colors.white) [cite: 12]
    menuWin.clear() [cite: 12]
    menuWin.setCursorBlink(false) [cite: 12]
    for i, o in ipairs(opts) do menuWin.setCursorPos(1, i) menuWin.write(" "..o) end [cite: 12]
    
    local _, btn, cx, cy = os.pullEvent("mouse_click") [cite: 12]
    if cx >= mx and cx < mx+12 and cy >= my and cy < my+#opts then [cite: 12, 13]
        local choice = opts[cy-my+1] [cite: 13]
        local path = (activeTab == "HOME") and getHomeDir() or currentPath [cite: 13]
        mainWin.setCursorPos(1,1) [cite: 13]
        
        -- ПРИМЕНЕНИЕ ЗАЩИТЫ ОТ ПЕРЕЗАПИСИ 
        if choice == "New File" then 
            mainWin.write("Name: ") local n = read() 
            if n~="" then fs.open(getUniquePath(path, n), "w").close() end
        elseif choice == "New Folder" then 
            mainWin.write("Dir: ") local n = read() 
            if n~="" then fs.makeDir(getUniquePath(path, n)) end
        elseif choice == "Delete" then 
            fs.delete(fs.combine(path, file)) [cite: 14]
        elseif choice == "Rename" then 
            mainWin.write("New: ") local n = read() 
            if n~="" then fs.move(fs.combine(path, file), getUniquePath(path, n)) end
        elseif choice == "Copy" then 
            clipboard.path = fs.combine(path, file) [cite: 14]
        elseif choice == "Paste" and clipboard.path then 
            fs.copy(clipboard.path, getUniquePath(path, fs.getName(clipboard.path))) [cite: 14]
        end
    end
    drawUI() [cite: 14]
end

-- 5. ENGINE
local function osEngine()
    drawUI() [cite: 14]
    globalTimer = os.startTimer(1) [cite: 14]
    
    while running do [cite: 15]
        local ev, p1, p2, p3 = os.pullEvent() [cite: 15]
        
        if ev == "timer" and p1 == globalTimer then [cite: 15]
            drawTopBar() [cite: 15]
            globalTimer = os.startTimer(1) [cite: 15]
        
        elseif ev == "mouse_click" then [cite: 15]
            local btn, x, y = p1, p2, p3 [cite: 16]
            if y == h then [cite: 16]
                if x >= 1 and x <= 6 then activeTab = "HOME" [cite: 16]
                elseif x >= 8 and x <= 13 then activeTab = "FILE" [cite: 16]
                elseif x >= 15 and x <= 20 then activeTab = "SHLL" [cite: 16, 17]
                elseif x >= 22 and x <= 27 then activeTab = "CONF" end [cite: 17]
                
                if activeTab == "SHLL" then [cite: 17]
                    drawUI() [cite: 17]
                    local old = term.redirect(mainWin) [cite: 18]
                    term.setBackgroundColor(colors.black) term.clear() term.setCursorPos(1,1) [cite: 18]
                    term.setCursorBlink(true) [cite: 18]
                    parallel.waitForAny( [cite: 18]
                        function() shell.run("shell") end, [cite: 18, 19]
                        function()
                            local lt = os.startTimer(1) [cite: 19]
                            while true do [cite: 19]
                                local e, id, tx, ty = os.pullEvent() [cite: 20]
                                if e == "timer" and id == lt then drawTopBar() lt = os.startTimer(1) [cite: 20]
                                elseif e == "mouse_click" and ty == h then os.queueEvent("mouse_click", 1, tx, ty) return end [cite: 21]
                            end
                        end
                    )
                    term.setCursorBlink(false) term.redirect(old) [cite: 22]
                    activeTab = "HOME" [cite: 22]
                end
                os.cancelTimer(globalTimer) [cite: 22]
                globalTimer = os.startTimer(0.1) [cite: 23]
                drawUI() [cite: 23]
            elseif activeTab == "FILE" and y > 1 and y < h then [cite: 23]
                local fList = fs.list(currentPath) [cite: 23]
                if currentPath ~= "/" then table.insert(fList, 1, "..") end [cite: 23]
                local sel = fList[y] [cite: 24]
                if btn == 2 then showContext(x, y, sel) [cite: 24]
                elseif sel then [cite: 24]
                    local p = fs.combine(currentPath, sel) [cite: 24]
                    if fs.isDir(p) then currentPath = p drawUI() [cite: 24]
                    else local old = term.redirect(mainWin) term.setCursorBlink(true) shell.run("edit", p) term.setCursorBlink(false) term.redirect(old) drawUI() end [cite: 25]
                end
            elseif activeTab == "HOME" and y > 1 and y < h then [cite: 25]
                local home = getHomeDir() [cite: 25]
                local fList = fs.list(home) [cite: 26]
                local sel = nil [cite: 26]
                for i, n in ipairs(fList) do [cite: 26]
                    local col, row = ((i-1)%4)*12+3, math.floor((i-1)/4)*4+2 [cite: 26]
                    if x >= col and x <= col+6 and y >= row and y <= row+1 then sel = n break end [cite: 27]
                end
                if btn == 2 then showContext(x, y, sel) [cite: 27]
                elseif sel then [cite: 27]
                    local p = fs.combine(home, sel) [cite: 27]
                    if fs.isDir(p) then activeTab = "FILE" currentPath = p drawUI() [cite: 28]
                    else local old = term.redirect(mainWin) term.setCursorBlink(true) shell.run("edit", p) term.setCursorBlink(false) term.redirect(old) drawUI() end [cite: 28]
                end
            elseif activeTab == "CONF" then [cite: 28]
                if y == 5 then settings.themeIndex = (settings.themeIndex % #themes) + 1 saveSettings() drawUI() [cite: 29]
                elseif y == 7 then [cite: 29]
                    mainWin.clear() mainWin.setCursorPos(1,1) print("Updating...") [cite: 29]
                    if fs.exists("startup.lua") then fs.delete("startup.lua") end [cite: 29]
                    shell.run("wget https://github.com/JemmaperXD/jemmaperxd/raw/refs/heads/stable/startup.lua startup.lua") [cite: 30]
                    os.reboot() [cite: 30]
                elseif y == 9 then running = false end [cite: 30]
            end
        end
    end
end

-- 6. ENTRY POINT
bootAnim() [cite: 30]
loadSettings() [cite: 30]
term.setBackgroundColor(colors.black) [cite: 30]
term.clear() [cite: 30]
if not settings.isRegistered then [cite: 30]
    term.setCursorBlink(true) [cite: 30]
    term.setCursorPos(w/2-6, h/2-2) term.setTextColor(colors.cyan) term.write("REGISTRATION") [cite: 30]
    term.setCursorPos(w/2-8, h/2) term.setTextColor(colors.white) term.write("User: ") settings.user = read() [cite: 30]
    term.setCursorPos(w/2-8, h/2+1) term.write("Pass: ") settings.pass = read("*") [cite: 31]
    settings.isRegistered = true saveSettings() [cite: 31]
    term.setCursorBlink(false) [cite: 31]
else
    while true do [cite: 31]
        term.setCursorBlink(true) [cite: 31]
        term.clear() [cite: 31]
        term.setCursorPos(w/2-6, h/2-1) term.setTextColor(colors.cyan) term.write("LOGIN: "..settings.user) [cite: 31]
        term.setCursorPos(w/2-8, h/2+1) term.setTextColor(colors.white) term.write("Pass: ") [cite: 31]
        if read("*") == settings.pass then break end [cite: 31]
    end
end
term.setCursorBlink(false) [cite: 31]
osEngine() [cite: 31]
