-- ameOs v33.0 [DESKTOP UPDATE]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local running = true
local activeTab = "HOME"
local currentPath = "/"
local clipboard = { path = nil, mode = nil } -- mode: "copy" or "cut"

-- 1. ТЕМЫ
local themes = {
    { name = "Night",     bg = colors.black, accent = colors.gray, text = colors.lightGray },
    { name = "Hacker",    bg = colors.black, accent = colors.lime, text = colors.lime }
}
local settings = { themeIndex = 1, user = "User", pass = "", isRegistered = false }

-- Окна
local topWin = window.create(term.current(), 1, 1, w, 1)
local mainWin = window.create(term.current(), 1, 2, w, h - 2)
local taskWin = window.create(term.current(), 1, h, w, 1)

-- 2. СИСТЕМА
if not fs.exists(CONFIG_DIR) then fs.makeDir(CONFIG_DIR) end
local function getHomeDir() return fs.combine("/.User", "." .. settings.user) end

local function saveSettings()
    local f = fs.open(SETTINGS_PATH, "w")
    f.write(textutils.serialize(settings))
    f.close()
end

-- 3. ВСПОМОГАТЕЛЬНЫЕ ФУНКЦИИ
local function getInput(prompt)
    local old = term.redirect(mainWin)
    mainWin.setCursorPos(2, h-4)
    mainWin.setBackgroundColor(colors.gray)
    mainWin.setTextColor(colors.white)
    mainWin.write(" " .. prompt .. ": ")
    term.setCursorBlink(true)
    local val = read()
    term.setCursorBlink(false)
    term.redirect(old)
    return val
end

-- 4. АНИМАЦИЯ FUSION (Краткая версия для скорости)
local function bootAnim()
    local cx, cy = math.floor(w/2), math.floor(h/2 - 2)
    local start = os.clock()
    while os.clock() - start < 3 do
        term.setBackgroundColor(colors.black)
        term.clear()
        term.setTextColor(colors.cyan)
        local a = os.clock() * 5
        for i = 1, 3 do
            local ang = a + (i * 2.1)
            term.setCursorPos(cx + math.floor(math.cos(ang)*3), cy + math.floor(math.sin(ang)*2))
            term.write("o")
        end
        sleep(0.05)
    end
end

-- 5. ОТРИСОВКА ИНТЕРФЕЙСА
local function drawUI()
    local theme = themes[settings.themeIndex]
    -- Taskbar
    taskWin.setBackgroundColor(colors.black)
    taskWin.clear()
    local menu = { {n="HOME", x=1}, {n="FILE", x=8}, {n="SHLL", x=15}, {n="CONF", x=22} }
    for _, m in ipairs(menu) do
        taskWin.setCursorPos(m.x, 1)
        taskWin.setBackgroundColor(activeTab == m.n and theme.accent or colors.black)
        taskWin.setTextColor(activeTab == m.n and theme.text or colors.white)
        taskWin.write(" "..m.n.." ")
    end
    -- Top
    topWin.setBackgroundColor(theme.accent)
    topWin.setTextColor(theme.text)
    topWin.clear()
    topWin.setCursorPos(2, 1) topWin.write("ameOs | " .. activeTab)
    topWin.setCursorPos(w - 6, 1)
    topWin.write(textutils.formatTime(os.time(), true))
    -- Main
    mainWin.setBackgroundColor(theme.bg)
    mainWin.setTextColor(theme.text)
    mainWin.clear()

    if activeTab == "HOME" then
        local files = fs.list(getHomeDir())
        for i, n in ipairs(files) do
            local col, row = ((i-1)%3)*8+2, math.floor((i-1)/3)*3+1
            mainWin.setCursorPos(col, row)
            mainWin.setTextColor(fs.isDir(fs.combine(getHomeDir(), n)) and colors.cyan or colors.yellow)
            mainWin.write("[#]")
            mainWin.setCursorPos(col - 1, row + 1)
            mainWin.setTextColor(colors.white)
            mainWin.write(n:sub(1, 7))
        end
    elseif activeTab == "FILE" then
        mainWin.setCursorPos(1, 1) mainWin.setTextColor(colors.yellow)
        mainWin.write(" "..currentPath)
        local files = fs.list(currentPath)
        if currentPath ~= "/" then table.insert(files, 1, "..") end
        for i, n in ipairs(files) do
            if i > h-4 then break end
            mainWin.setCursorPos(1, i+1)
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
end

-- 6. КОНТЕКСТНОЕ МЕНЮ
local function showContextMenu(mx, my, fileName)
    local theme = themes[settings.themeIndex]
    local options = {}
    if fileName then
        options = {"Copy", "Cut", "Rename", "Delete"}
    else
        options = {"New File", "New Folder", "Paste"}
    end

    local menuWin = window.create(term.current(), mx, my, 12, #options)
    menuWin.setBackgroundColor(colors.lightGray)
    menuWin.setTextColor(colors.black)
    menuWin.clear()
    for i, opt in ipairs(options) do
        menuWin.setCursorPos(1, i)
        menuWin.write(" " .. opt)
    end

    local _, _, ex, ey = os.pullEvent("mouse_click")
    local choice = (ex >= mx and ex <= mx+11 and ey >= my and ey < my+#options) and options[ey-my+1] or nil
    
    if choice == "New File" then
        local name = getInput("File Name")
        if name then local f = fs.open(fs.combine(getHomeDir(), name), "w") f.close() end
    elseif choice == "New Folder" then
        local name = getInput("Folder Name")
        if name then fs.makeDir(fs.combine(getHomeDir(), name)) end
    elseif choice == "Delete" then
        fs.delete(fs.combine(getHomeDir(), fileName))
    elseif choice == "Rename" then
        local newName = getInput("New Name")
        if newName then fs.move(fs.combine(getHomeDir(), fileName), fs.combine(getHomeDir(), newName)) end
    elseif choice == "Copy" then
        clipboard = { path = fs.combine(getHomeDir(), fileName), mode = "copy" }
    elseif choice == "Cut" then
        clipboard = { path = fs.combine(getHomeDir(), fileName), mode = "cut" }
    elseif choice == "Paste" and clipboard.path then
        local target = fs.combine(getHomeDir(), fs.getName(clipboard.path))
        if clipboard.mode == "copy" then fs.copy(clipboard.path, target)
        else fs.move(clipboard.path, target) clipboard.path = nil end
    end
    drawUI()
end

-- 7. ДВИЖОК
local function osEngine()
    drawUI()
    local clockTimer = os.startTimer(1)
    while running do
        local event, p1, p2, p3 = os.pullEvent()
        if event == "timer" and p1 == clockTimer then
            drawUI() clockTimer = os.startTimer(1)
        elseif event == "mouse_click" then
            local btn, x, y = p1, p2, p3
            if y == h then -- Taskbar logic
                if x >= 1 and x <= 6 then activeTab = "HOME"
                elseif x >= 8 and x <= 13 then activeTab = "FILE"
                elseif x >= 15 and x <= 20 then activeTab = "SHLL"
                elseif x >= 22 and x <= 27 then activeTab = "CONF" end
                if activeTab == "SHLL" then
                    drawUI()
                    local old = term.redirect(mainWin)
                    term.setBackgroundColor(colors.black) term.clear() term.setCursorPos(1,1) term.setCursorBlink(true)
                    parallel.waitForAny(function() shell.run("shell") end, function()
                        while true do local _, _, mx, my = os.pullEvent("mouse_click") if my == h then os.queueEvent("mouse_click", 1, mx, my) return end end
                    end)
                    term.setCursorBlink(false) term.redirect(old) activeTab = "HOME"
                end
                drawUI()
            elseif activeTab == "HOME" and y > 1 and y < h then
                -- Определение файла под мышкой
                local files = fs.list(getHomeDir())
                local selectedFile = nil
                for i, n in ipairs(files) do
                    local col, row = ((i-1)%3)*8+2, math.floor((i-1)/3)*3+2
                    if x >= col and x <= col+3 and y == row then selectedFile = n break end
                end

                if btn == 2 then -- ПРАВАЯ КНОПКА МЫШИ
                    showContextMenu(x, y, selectedFile)
                end
            elseif activeTab == "CONF" and y == 7 then
                -- Update logic
                fs.delete("startup.lua")
                shell.run("wget https://github.com/JemmaperXD/jemmaperxd/raw/refs/heads/main/startup.lua startup.lua")
                os.reboot()
            end
        end
    end
end

-- 8. СТАРТ
bootAnim()
if fs.exists(SETTINGS_PATH) then local f = fs.open(SETTINGS_PATH,"r") settings = textutils.unserialize(f.readAll()) f.close() end
currentPath = getHomeDir()
if not fs.exists(currentPath) then fs.makeDir(currentPath) end
osEngine()
