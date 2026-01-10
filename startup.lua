-- ameOs v36.0 [7.5s BOOT FIX]
local w, h = term.getSize()
local CONFIG_DIR = "/.config"
local SETTINGS_PATH = "/.config/ame_settings.cfg"
local UPDATE_URL = "github.com"
local running = true
local activeTab = "HOME"
local currentPath = "/"

-- 1. ТЕМЫ
local themes = {
    { name = "Dark Cyan", bg = colors.blue,  accent = colors.cyan, text = colors.white },
    { name = "Night",     bg = colors.black, accent = colors.gray, text = colors.lightGray },
    { name = "Hacker",    bg = colors.black, accent = colors.lime, text = colors.lime }
}
local settings = { themeIndex = 1, user = "User", pass = "", isRegistered = false }

-- 2. СИСТЕМА
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
        local decoded = textutils.unserialize(data)
        if decoded then settings = decoded end
    end
end

-- 3. УСКОРЕННАЯ АНИМАЦИЯ (7.5 секунд)
local function bootAnim()
    local cx, cy = math.floor(w/2), math.floor(h/2 - 2)
    local duration = 7.5 -- В 2 раза короче
    local start = os.clock()
    local angle = 0
    term.setCursorBlink(false)
    while os.clock() - start < duration do
        local elapsed = os.clock() - start
        term.setBackgroundColor(colors.black)
        term.clear()
        
        -- Слияние в конце (последние 2 секунды)
        local fusion = 1.0
        if elapsed > (duration - 2) then
            fusion = math.max(0, 1 - (elapsed - (duration - 2)) / 2)
            term.setTextColor(colors.gray)
            term.setCursorPos(cx-2, cy-1) term.write("#####")
            term.setCursorPos(cx-3, cy)   term.write("#     #")
            term.setCursorPos(cx-2, cy+1) term.write("#####")
        end
        
        term.setTextColor(colors.cyan)
        local rx, ry = 2.5 * fusion, 1.5 * fusion
        for i = 1, 3 do
            local a = angle + (i * 2.1)
            local dx = math.floor(math.cos(a)*rx + 0.5)
            local dy = math.floor(math.sin(a)*ry + 0.5)
            term.setCursorPos(cx+dx, cy+dy) term.write(fusion > 0.2 and "o" or "@")
        end
        
        local progress = math.floor((elapsed / duration) * 14)
        term.setCursorPos(w/2 - 7, cy + 5)
        term.setTextColor(colors.gray)
        term.write("["..string.rep("=", progress)..string.rep(" ", 14-progress).."]")
        
        angle = angle + 0.5 -- Чуть быстрее вращение
        sleep(0.05)
    end
end

-- 4. АВТОРИЗАЦИЯ
local function systemAuth()
    loadSettings()
    term.setBackgroundColor(colors.gray)
    term.clear()
    term.setTextColor(colors.white)
    term.setCursorBlink(true)
    if not settings.isRegistered then
        term.setCursorPos(w/2-6, h/2-2) term.write("REGISTRATION")
        term.setCursorPos(w/2-8, h/2)   term.write("Name: ") settings.user = read()
        term.setCursorPos(w/2-8, h/2+1) term.write("Pass: ") settings.pass = read("*")
        settings.isRegistered = true
        saveSettings()
    else
        while true do
            term.setBackgroundColor(colors.gray) term.clear()
            term.setCursorPos(w/2-6, h/2-1) term.write("LOGIN: "..settings.user)
            term.setCursorPos(w/2-8, h/2+1) term.write("Pass: ")
            if read("*") == settings.pass then break end
        end
    end
    term.setCursorBlink(false)
    local home = getHomeDir()
    if not fs.exists(home) then fs.makeDir(home) end
    currentPath = home
end

-- 5. ГЛАВНОЕ ПРИЛОЖЕНИЕ
local function mainApp()
    local topWin = window.create(term.current(), 1, 1, w, 1)
    local mainWin = window.create(term.current(), 1, 2, w, h - 2)
    local taskWin = window.create(term.current(), 1, h, w, 1)
    
    local fileList, homeFiles = {}, {}
    local menu = { {n="HOME", x=1}, {n="FILE", x=8}, {n="SHLL", x=15}, {n="CONF", x=22} }

    parallel.waitForAny(
        function()
            while running do
                local theme = themes[settings.themeIndex]
                taskWin.setBackgroundColor(colors.black)
                taskWin.clear()
                for _, m in ipairs(menu) do
                    taskWin.setCursorPos(m.x, 1)
                    taskWin.setBackgroundColor(activeTab == m.n and theme.accent or colors.black)
                    taskWin.setTextColor(activeTab == m.n and theme.text or colors.white)
                    taskWin.write(" "..m.n.." ")
                end
                topWin.setBackgroundColor(theme.accent)
                topWin.setTextColor(theme.text)
                topWin.clear()
                topWin.setCursorPos(2, 1) topWin.write("ameOs | " .. activeTab)
                topWin.setCursorPos(w-6, 1) topWin.write(textutils.formatTime(os.time(), true))
                mainWin.setBackgroundColor(theme.bg)
                mainWin.setTextColor(theme.text)
                mainWin.clear()
                if activeTab == "HOME" then
                    homeFiles = fs.list(getHomeDir())
                    for i, n in ipairs(homeFiles) do
                        local col = ((i-1) % 3) * 8 + 2
                        local row = math.floor((i-1) / 3) * 3 + 1
                        if row < h-2 then
                            mainWin.setCursorPos(col, row)
                            local isD = fs.isDir(fs.combine(getHomeDir(), n))
                            mainWin.setTextColor(isD and colors.cyan or colors.yellow)
                            mainWin.write(isD and "[#]" or "[f]")
                            mainWin.setCursorPos(col - 1, row + 1)
                            mainWin.setTextColor(colors.white)
                            mainWin.write(n:sub(1, 7))
                        end
                    end
                elseif activeTab == "FILE" then
                    mainWin.setBackgroundColor(colors.black)
                    mainWin.setTextColor(colors.yellow)
                    mainWin.setCursorPos(1, 1) mainWin.write(" "..currentPath)
                    fileList = fs.list(currentPath)
                    if currentPath ~= "/" then table.insert(fileList, 1, "..") end
                    for i, n in ipairs(fileList) do
                        if i > h-4 then break end
                        mainWin.setCursorPos(1, i+1)
                        local isD = fs.isDir(fs.combine(currentPath, n))
                        mainWin.setTextColor(isD and colors.cyan or colors.white)
                        mainWin.write((isD and "> " or "  ") .. n)
                    end
                elseif activeTab == "CONF" then
                    mainWin.setCursorPos(1, 2) mainWin.write(" Theme: "..theme.name)
                    mainWin.setCursorPos(1, 4) mainWin.write(" [ NEXT THEME ]")
                    mainWin.setCursorPos(1, 6) mainWin.setTextColor(colors.yellow)
                    mainWin.write(" [ UPDATE SYSTEM ]")
                    mainWin.setCursorPos(1, 8) mainWin.setTextColor(colors.red)
                    mainWin.write(" [ SHUTDOWN ]")
                end
                sleep(0.5)
            end
        end,
        function()
            while running do
                local ev, btn, x, y = os.pullEvent()
                if ev == "mouse_click" then
                    if y == h then
                        if x >= 1 and x <= 6 then activeTab = "HOME"
                        elseif x >= 8 and x <= 13 then activeTab = "FILE"
                        elseif x >= 15 and x <= 20 then activeTab = "SHLL"
                        elseif x >= 22 and x <= 27 then activeTab = "CONF" end
                    elseif activeTab == "HOME" and y > 1 and y < h then
                        local colIdx = math.floor((x - 2) / 8) + 1
                        local rowIdx = math.floor((y - 2) / 3) + 1
                        local fileIdx = (rowIdx - 1) * 3 + colIdx
                        if homeFiles[fileIdx] then
                            local p = fs.combine(getHomeDir(), homeFiles[fileIdx])
                            if fs.isDir(p) then activeTab = "FILE" currentPath = p
                            else 
                                local old = term.redirect(mainWin)
                                term.setCursorBlink(true) shell.run("edit", p) term.setCursorBlink(false)
                                term.redirect(old)
                            end
                        end
                    elseif activeTab == "FILE" and y > 2 and y < h then
                        local sel = fileList[y-2]
                        if sel then
                            local p = fs.combine(currentPath, sel)
                            if fs.isDir(p) then currentPath = p 
                            else 
                                local old = term.redirect(mainWin)
                                term.setCursorBlink(true) shell.run("edit", p) term.setCursorBlink(false)
                                term.redirect(old)
                            end
                        end
                    elseif activeTab == "CONF" then
                        if y == 5 then settings.themeIndex = (settings.themeIndex % #themes) + 1 saveSettings()
                        elseif y == 7 then 
                            local resp = http.get(UPDATE_URL)
                            if resp then
                                local f = fs.open("startup.lua", "w")
                                f.write(resp.readAll()) f.close() resp.close()
                                os.reboot()
                            end
                        elseif y == 9 then running = false end
                    end
                end
                if activeTab == "SHLL" then
                    mainWin.setVisible(true)
                    local old = term.redirect(mainWin)
                    term.setBackgroundColor(colors.black)
                    term.setCursorBlink(true)
                    term.clear() term.setCursorPos(1,1)
                    print("Shell Mode. Click Taskbar to exit.")
                    parallel.waitForAny(
                        function() shell.run("shell") end,
                        function()
                            while true do
                                local _, _, _, ty = os.pullEvent("mouse_click")
                                if ty == h then return end
                            end
                        end
                    )
                    term.setCursorBlink(false)
                    term.redirect(old)
                    activeTab = "HOME"
                end
            end
        end
    )
end

-- 6. СТАРТ
bootAnim()
systemAuth()
pcall(mainApp)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorBlink(true)
print("ameOs closed.")

