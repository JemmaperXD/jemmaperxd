-- ameOs v71.0 [STABLE: FIXED CLOCK, PATH, CURSOR & FS PROTECTION]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local running = true
local activeTab = "HOME"
local currentPath = "/"
local clipboard = { path = nil }
local globalTimer = nil

local themes = {
    { name = "Night",     bg = colors.black, accent = colors.gray, text = colors.lightGray },
    { name = "Hacker",    bg = colors.black, accent = colors.lime, text = colors.lime }
}
local settings = { themeIndex = 1, user = "User", pass = "", isRegistered = false }

local topWin = window.create(term.current(), 1, 1, w, 1)
local mainWin = window.create(term.current(), 1, 2, w, h - 2)
local taskWin = window.create(term.current(), 1, h, w, 1)

-- 1. СИСТЕМА
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

-- 2. АНИМАЦИЯ
local function bootAnim()
    local cx, cy = math.floor(w/2), math.floor(h/2 - 2)
    local angle = 0
    for i = 1, 30 do
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setTextColor(colors.cyan)
        for j = 1, 3 do
            local a = angle + (j * 2.1)
            term.setCursorPos(cx + math.floor(math.cos(a)*2.5+0.5), cy + math.floor(math.sin(a)*1.5+0.5))
            term.write("o")
        end
        term.setCursorPos(cx - 2, h - 1)
        term.setTextColor(colors.white)
        term.write("ameOS")
        angle = angle + 0.4
        sleep(0.05)
    end
end

-- 3. ОТРИСОВКА
local function drawTopBar()
    local theme = themes[settings.themeIndex]
    local old = term.redirect(topWin)
    topWin.setBackgroundColor(theme.accent)
    topWin.setTextColor(theme.text)
    topWin.clear()
    
    topWin.setCursorPos(2, 1)
    local title = "ameOs | " .. activeTab
    if activeTab == "FILE" then title = title .. ": " .. currentPath end
    topWin.write(title:sub(1, w - 10))
    
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
end

-- 4. МЕНЮ И ЗАЩИТА ФС
local function showContext(mx, my, file)
    local opts = file and {"Copy", "Rename", "Delete"} or {"New File", "New Folder", "Paste"}
    local menuWin = window.create(term.current(), mx, my, 12, #opts)
    menuWin.setBackgroundColor(colors.gray)
    menuWin.setTextColor(colors.white)
    menuWin.clear()
    for i, o in ipairs(opts) do menuWin.setCursorPos(1, i) menuWin.write(" "..o) end
    
    local _, btn, cx, cy = os.pullEvent("mouse_click")
    if cx >= mx and cx < mx+12 and cy >= my and cy < my+#opts then
        local choice = opts[cy-my+1]
        local path = (activeTab == "HOME") and getHomeDir() or currentPath
        
        if choice == "New File" or choice == "New Folder" or choice == "Rename" then
            term.setCursorPos(1, h) term.setBackgroundColor(colors.black) term.clearLine()
            term.write("Name: ") term.setCursorBlink(true)
            local n = read() term.setCursorBlink(false)
            if n and n ~= "" then
                local target = fs.combine(path, n)
                -- ЗАЩИТА ОТ КРАША: Проверяем существование перед действием
                if not fs.exists(target) then
                    if choice == "New File" then fs.open(target, "w").close()
                    elseif choice == "New Folder" then fs.makeDir(target)
                    elseif choice == "Rename" and file then fs.move(fs.combine(path, file), target) end
                end
            end
        elseif choice == "Delete" and file then fs.delete(fs.combine(path, file))
        elseif choice == "Copy" and file then clipboard.path = fs.combine(path, file)
        elseif choice == "Paste" and clipboard.path then 
            local target = fs.combine(path, fs.getName(clipboard.path))
            if not fs.exists(target) then fs.copy(clipboard.path, target) end
        end
    end
    drawUI()
end

-- 5. ДВИЖОК
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
            if y == h then
                if x >= 1 and x <= 6 then activeTab = "HOME"
                elseif x >= 8 and x <= 13 then activeTab = "FILE"
                elseif x >= 15 and x <= 20 then activeTab = "SHLL"
                elseif x >= 22 and x <= 27 then activeTab = "CONF" end
                
                if activeTab == "SHLL" then
                    drawUI()
                    local old = term.redirect(mainWin)
                    term.setBackgroundColor(colors.black) term.clear() term.setCursorPos(1,1)
                    shell.run("shell")
                    term.redirect(old)
                    activeTab = "HOME"
                end
                drawUI()
            elseif activeTab == "FILE" and y > 1 and y < h then
                local fList = fs.list(currentPath)
                if currentPath ~= "/" then table.insert(fList, 1, "..") end
                local sel = fList[y-1]
                if btn == 2 then showContext(x, y, sel)
                elseif sel then
                    local p = fs.combine(currentPath, sel)
                    if fs.isDir(p) then currentPath = p drawUI() else 
                        local old = term.redirect(mainWin) shell.run("edit", p) term.redirect(old) drawUI()
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
                if btn == 2 then showContext(x, y, sel)
                elseif sel then 
                    local p = fs.combine(home, sel)
                    if fs.isDir(p) then activeTab = "FILE" currentPath = p drawUI() else
                        local old = term.redirect(mainWin) shell.run("edit", p) term.redirect(old) drawUI()
                    end
                end
            elseif activeTab == "CONF" then
                if y == 5 then settings.themeIndex = (settings.themeIndex % #themes) + 1 saveSettings() drawUI()
                elseif y == 7 then 
                    term.setBackgroundColor(colors.black) term.clear()
                    term.setCursorPos(w/2-6, h/2) print("Updating...")
                    fs.delete("startup.lua")
                    shell.run("wget https://github.com/JemmaperXD/jemmaperxd/raw/refs/heads/main/startup.lua startup.lua")
                    os.reboot()
                elseif y == 9 then running = false end
            end
        end
    end
end

-- 6. СТАРТ
loadSettings()
bootAnim()
term.setBackgroundColor(colors.black)
term.clear()

if not settings.isRegistered then
    term.setCursorPos(w/2-6, h/2-1) term.setTextColor(colors.cyan) term.write("REGISTRATION")
    term.setCursorBlink(true)
    term.setCursorPos(w/2-8, h/2+1) term.setTextColor(colors.white) term.write("User: ") settings.user = read()
    term.setCursorPos(w/2-8, h/2+2) term.write("Pass: ") settings.pass = read("*")
    settings.isRegistered = true saveSettings()
    term.setCursorBlink(false)
else
    local auth = false
    while not auth do
        term.clear()
        term.setCursorPos(w/2-6, h/2-1) term.setTextColor(colors.cyan) term.write("LOGIN: " .. settings.user)
        term.setCursorBlink(true)
        term.setCursorPos(w/2-8, h/2+1) term.setTextColor(colors.white) term.write("Pass: ")
        if read("*") == settings.pass then auth = true else
            term.setCursorPos(w/2-3, h/2+3) term.setTextColor(colors.red) term.write("FAIL") sleep(0.5)
        end
    end
    term.setCursorBlink(false)
end

osEngine()
