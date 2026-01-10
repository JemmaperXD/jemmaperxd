-- ameOs v17.0 [SMOOTH ENGINE 2026]
local w, h = term.getSize()
local CONFIG_DIR, SETTINGS_PATH = "/.config", "/.config/ame_settings.cfg"
local taskbarW = 9
local running = true
local activeTab = "Desktop"
local currentPath = "/"

-- 1. ТЕМЫ И НАСТРОЙКИ
local themes = {
    { name = "Ame Cyan",  bg = colors.blue,      accent = colors.cyan,    text = colors.white },
    { name = "Dark Mode", bg = colors.black,     accent = colors.gray,    text = colors.lightGray },
    { name = "Hacker",    bg = colors.black,     accent = colors.lime,    text = colors.lime }
}
local settings = { themeIndex = 1, user = "User", pass = "", isRegistered = false }

if not fs.exists(CONFIG_DIR) then fs.makeDir(CONFIG_DIR) end
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

-- 2. ПЛАВНАЯ АНИМАЦИЯ (Двойная буферизация)
local function bootAnim()
    -- Создаем буферное окно на весь экран
    local buffer = window.create(term.current(), 1, 1, w, h)
    local cx, cy = math.floor(w/2), math.floor(h/2 - 2)
    local angle = 0
    local frames = 50 
    
    for f = 1, frames do
        buffer.setBackgroundColor(colors.black)
        buffer.clear()
        
        -- Рисуем кольцо в буфер
        buffer.setTextColor(colors.gray)
        buffer.setCursorPos(cx-2, cy-1) buffer.write("#####")
        buffer.setCursorPos(cx-3, cy)   buffer.write("#     #")
        buffer.setCursorPos(cx-3, cy+1) buffer.write("#     #")
        buffer.setCursorPos(cx-2, cy+2) buffer.write("#####")
        
        -- Вращение точек в буфер
        buffer.setTextColor(colors.cyan)
        for i = 1, 3 do
            local a = angle + (i * (math.pi * 2 / 3))
            local dx = math.floor(math.cos(a) * 2.5 + 0.5)
            local dy = math.floor(math.sin(a) * 1.5 + 0.5)
            buffer.setCursorPos(cx + dx, cy + 1 + dy)
            buffer.write("o")
        end
        
        -- Прогресс-бар
        local progress = math.floor((f / frames) * 10)
        buffer.setCursorPos(cx-5, cy+5)
        buffer.setTextColor(colors.gray)
        buffer.write("[" .. string.rep("=", progress) .. string.rep(" ", 10-progress) .. "]")
        
        buffer.setCursorPos(w/2 - 2, h - 1)
        buffer.setTextColor(colors.white)
        buffer.write("ameOS")
        
        angle = angle + 0.2
        
        -- Отрисовка буфера на экран (мгновенно)
        buffer.setVisible(true) 
        buffer.setVisible(false) 
        
        sleep(0.05) -- Скорость вращения
    end
end

-- 3. АВТОРИЗАЦИЯ
local function systemAuth()
    loadSettings()
    term.setBackgroundColor(colors.gray)
    term.clear()
    term.setTextColor(colors.white)
    
    if not settings.isRegistered then
        term.setCursorPos(w/2-6, h/2-2) term.write("REGISTRATION")
        term.setCursorPos(w/2-8, h/2)   term.write("User: ") settings.user = read()
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
end

-- 4. ГЛАВНОЕ ПРИЛОЖЕНИЕ
local function mainApp()
    local topWin = window.create(term.current(), 1, 1, w - taskbarW, 1)
    local mainWin = window.create(term.current(), 1, 2, w - taskbarW, h - 1)
    local taskWin = window.create(term.current(), w - taskbarW + 1, 1, taskbarW, h)
    local fileList = {}

    while running do
        local theme = themes[settings.themeIndex]
        
        -- Taskbar
        taskWin.setBackgroundColor(colors.black)
        taskWin.clear()
        local btns = {"Desktop", "Files", "Shell", "Settings"}
        for i, n in ipairs(btns) do
            taskWin.setCursorPos(1, i*2)
            taskWin.setBackgroundColor(activeTab == n and theme.accent or colors.black)
            taskWin.setTextColor(activeTab == n and theme.text or colors.white)
            taskWin.write(string.format(" %-7s", n))
        end
        taskWin.setCursorPos(2, h) taskWin.setTextColor(colors.yellow) taskWin.setBackgroundColor(colors.black)
        taskWin.write(textutils.formatTime(os.time(), true))

        -- UI
        topWin.setBackgroundColor(theme.accent)
        topWin.setTextColor(theme.text)
        topWin.clear() topWin.setCursorPos(2, 1) topWin.write("ameOs")
        
        mainWin.setBackgroundColor(theme.bg)
        mainWin.setTextColor(theme.text)
        mainWin.clear()

        if activeTab == "Desktop" then
            mainWin.setCursorPos(2, 2) mainWin.write("User: " .. settings.user)
        elseif activeTab == "Files" then
            mainWin.setBackgroundColor(colors.black)
            mainWin.clear()
            mainWin.setTextColor(colors.yellow)
            mainWin.setCursorPos(1,1) mainWin.write(" " .. currentPath)
            fileList = fs.list(currentPath)
            if currentPath ~= "/" then table.insert(fileList, 1, "..") end
            for i, n in ipairs(fileList) do
                if i > h-3 then break end
                mainWin.setCursorPos(1, i+1)
                local isDir = fs.isDir(fs.combine(currentPath, n))
                mainWin.setTextColor(isDir and colors.cyan or colors.white)
                mainWin.write((isDir and "> " or "  ") .. n:sub(1, w-taskbarW-2))
            end
        elseif activeTab == "Shell" then
            mainWin.setVisible(true) term.redirect(mainWin)
            shell.run("shell") term.redirect(term.native())
            activeTab = "Desktop"
        elseif activeTab == "Settings" then
            mainWin.setCursorPos(1, 2) mainWin.write(" Theme: "..theme.name)
            mainWin.setCursorPos(1, 4) mainWin.write(" [ Switch Theme ]")
            mainWin.setCursorPos(1, 6) mainWin.setTextColor(colors.red)
            mainWin.write(" [ Shutdown ]")
        end

        local ev, button, x, y = os.pullEvent()
        if ev == "mouse_click" then
            if x > w - taskbarW then
                local row = math.floor(y/2)
                if row >= 1 and row <= 4 then activeTab = btns[row] end
            elseif activeTab == "Files" and y > 2 then
                local sel = fileList[y-2]
                if sel then
                    local p = fs.combine(currentPath, sel)
                    if fs.isDir(p) then currentPath = p 
                    else term.redirect(mainWin) shell.run("edit", p) term.redirect(term.native()) end
                end
            elseif activeTab == "Settings" then
                if y == 5 then
                    settings.themeIndex = (settings.themeIndex % #themes) + 1
                    saveSettings()
                elseif y == 7 then running = false end
            end
        end
    end
end

-- ПУСК
bootAnim()
systemAuth()
pcall(mainApp)
term.setBackgroundColor(colors.black)
term.clear()
term.setCursorPos(1,1)
print("ameOs closed.")
