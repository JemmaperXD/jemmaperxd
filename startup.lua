-- ameOs v36.0 [7.5s BOOT FIX]
-- Полный рабочий вариант стартового скрипта для ComputerCraft / CC:Tweaked
-- Исправляет проблему "белого экрана": корректно инициализирует окна, тему и основной цикл
local w, h = term.getSize()
local CONFIG_DIR = "/.config"
local SETTINGS_PATH = CONFIG_DIR .. "/ame_settings.cfg"
local running = true
local activeTab = "HOME"
local currentPath = "/"
-- Утилиты
local function safeReadFile(path)
    if not fs.exists(path) then return nil end
    local f = fs.open(path, "r")
    if not f then return nil end
    local data = f.readAll()
    f.close()
    return data
end
local function ensureConfigDir()
    if not fs.exists(CONFIG_DIR) then
        fs.makeDir(CONFIG_DIR)
    end
end
-- Темы
local themes = {
    { name = "Dark Cyan", bg = colors.blue,  accent = colors.cyan,  text = colors.white },
    { name = "Night",     bg = colors.black, accent = colors.gray,  text = colors.lightGray },
    { name = "Hacker",    bg = colors.black, accent = colors.lime,  text = colors.green },
}
local theme = themes[1]
local function loadSettings()
    ensureConfigDir()
    local raw = safeReadFile(SETTINGS_PATH)
    if raw then
        local ok, saved = pcall(textutils.unserialise, raw)
        if ok and type(saved) == "table" and saved.theme then
            for _, t in ipairs(themes) do
                if t.name == saved.theme then
                    theme = t
                    return
                end
            end
        end
    end
end
local function saveSettings()
    ensureConfigDir()
    local tosave = { theme = theme.name }
    local f = fs.open(SETTINGS_PATH, "w")
    if f then
        f.write(textutils.serialise(tosave))
        f.close()
    end
end
-- Вспомогательные функции интерфейса
local function centerText(win, y, text)
    local ww, hh = win.getSize()
    local x = math.max(1, math.floor((ww - #text) / 2) + 1)
    win.setCursorPos(x, y)
    win.write(text)
end
local function getHomeDir()
    local home = os.getEnv and os.getEnv("HOME") or nil
    if home and fs.exists(home) then return home end
    if fs.exists("/home") then return "/home" end
    return "/"
end
-- Создание окон: top строка, строка меню, основная область
local function createWindows()
    term.clear()
    term.setCursorPos(1,1)
    local topWin = window.create(term.current(), 1, 1, w, 1, false)
    local taskWin = window.create(term.current(), 1, 2, w, 1, false)
    local mainWin = window.create(term.current(), 1, 3, w, h-2, false)
    return topWin, taskWin, mainWin
end
-- Рендер меню/интерфейса
local menu = {
    { n = "HOME" },
    { n = "FILES" },
    { n = "SETTINGS" },
    { n = "EXIT" },
}
local function drawAll(topWin, taskWin, mainWin)
    -- Защита от ошибок размеров
    w, h = term.getSize()
    -- Draw task bar (menu)
    taskWin.setBackgroundColor(colors.black)
    taskWin.setTextColor(colors.white)
    taskWin.clear()
    local x = 1
    for _, m in ipairs(menu) do
        taskWin.setCursorPos(x, 1)
        local isActive = (activeTab == m.n)
        taskWin.setBackgroundColor(isActive and theme.accent or colors.black)
        taskWin.setTextColor(isActive and theme.text or colors.white)
        taskWin.write(" " .. m.n .. " ")
        x = x + #(" " .. m.n .. " ")
    end
-- Top bar
topWin.setBackgroundColor(theme.accent)
topWin.setTextColor(theme.text)
topWin.clear()
topWin.setCursorPos(2, 1)
topWin.write("ameOs | " .. activeTab)
local timeStr = textutils.formatTime(os.time(), true)
topWin.setCursorPos(math.max(1, w - #timeStr - 1), 1)
topWin.write(timeStr)

-- Main area
mainWin.setBackgroundColor(theme.bg)
mainWin.setTextColor(theme.text)
mainWin.clear()

if activeTab == "HOME" then
    mainWin.setCursorPos(2, 1)
    mainWin.write("Добро пожаловать в ameOs")
    mainWin.setCursorPos(2, 2)
    mainWin.write("Текущий путь: " .. currentPath)
    mainWin.setCursorPos(2, 4)
    centerText(mainWin, 4, "Доступные файлы в домашней папке:")
    local homeFiles = {}
    local ok, list = pcall(fs.list, getHomeDir())
    if ok and type(list) == "table" then homeFiles = list end
    local row = 6
    for i, name in ipairs(homeFiles) do
        if row > (h - 2) then break end
        local full = fs.combine(getHomeDir(), name)
        local isD = fs.isDir(full)
        mainWin.setCursorPos(4, row)
        mainWin.setTextColor(isD and colors.cyan or colors.yellow)
        mainWin.write((isD and "[DIR] " or "[FILE] ") .. name)
        row = row + 1
    end
elseif activeTab == "FILES" then
    mainWin.setCursorPos(2,1)
    mainWin.write("Файловый менеджер")
    mainWin.setCursorPos(2,2)
    mainWin.write("Текущий путь: " .. currentPath)
    local files = {}
    local ok, list = pcall(fs.list, currentPath)
    if ok and type(list) == "table" then files = list end
    local row = 4
    for i, name in ipairs(files) do
        if row > (h - 2) then break end
        local full = fs.combine(currentPath, name)
        local isD = fs.isDir(full)
        mainWin.setCursorPos(3, row)
        mainWin.setTextColor(isD and colors.cyan or colors.white)
        mainWin.write((isD and "[DIR] " or "[FILE] ") .. name)
        row = row + 1
    end
elseif activeTab == "SETTINGS" then
    mainWin.setCursorPos(2,1)
    mainWin.write("Настройки")
    mainWin.setCursorPos(2,3)
    mainWin.write("Текущая тема: " .. theme.name)
    mainWin.setCursorPos(2,5)
    mainWin.write("Выберите тему: (1-" .. #themes .. ")")
    local row = 6
    for i, t in ipairs(themes) do
        mainWin.setCursorPos(4, row)
        if t.name == theme.name then
            mainWin.setTextColor(colors.green)
            mainWin.write(i .. ". " .. t.name .. " (выбрано)")
        else
            mainWin.setTextColor(colors.lightGray)
            mainWin.write(i .. ". " .. t.name)
        end
        row = row + 1
    end
    mainWin.setTextColor(theme.text)
elseif activeTab == "EXIT" then
    mainWin.setCursorPos(2,2)
    mainWin.write("Завершение работы... Нажмите любую клавишу для подтверждения.")
end

end
-- Обработка нажатий клавиш и мыши
local function handleEvent(ev)
    if ev[1] == "key" then
        local key = ev[2]
        if key == keys.leftCtrl or key == keys.leftAlt then
            return
        end
        -- Простая навигация по табам с цифр 1-4
        if key == keys.one then activeTab = menu[1].n end
        if key == keys.two then activeTab = menu[2].n end
        if key == keys.three then activeTab = menu[3].n end
        if key == keys.four then activeTab = menu[4].n end
        if key == keys.q then running = false end
        -- Если в настройках и нажата цифра темы
        if activeTab == "SETTINGS" then
            if key >= keys.one and key <= keys.nine then
                local n = key - keys.one + 1
                if themes[n] then
                    theme = themes[n]
                    saveSettings()
                end
            end
        end
        -- В EXIT любой key завершает
        if activeTab == "EXIT" then running = false end
    elseif ev[1] == "mouse_click" then
        local mx, my = ev[3], ev[4]
        -- Клики по меню (вторая строк)
        if my == 2 then
            local cx = 1
            for _, m in ipairs(menu) do
                local len = #(" " .. m.n .. " ")
                if mx >= cx and mx < cx + len then
                    activeTab = m.n
                    break
                end
                cx = cx + len
            end
        end
    elseif ev[1] == "term_resize" then
        w, h = term.getSize()
    end
end
-- Инициализация и запуск
local function main()
    loadSettings()
    term.clear()
    term.setCursorPos(1,1)
    local topWin, taskWin, mainWin = createWindows()
    -- Защитная очистка, чтобы не было "белого экрана"
    topWin.setBackgroundColor(theme.accent)
    topWin.clear()
    taskWin.setBackgroundColor(colors.black)
    taskWin.clear()
    mainWin.setBackgroundColor(theme.bg)
    mainWin.clear()
-- Главный цикл
drawAll(topWin, taskWin, mainWin)
while running do
    drawAll(topWin, taskWin, mainWin)
    local ev = { os.pullEvent() }
    -- Обрабатываем событие в защищённом вызове, чтобы избежать краша
    local ok, err = pcall(handleEvent, ev)
    if not ok then
        -- Показываем ошибку внизу mainWin, но продолжаем работу
        mainWin.setCursorPos(2, h-3 >= 1 and h-3 or 1)
        mainWin.setTextColor(colors.red)
        local msg = tostring(err)
        if #msg > w-4 then msg = msg:sub(1, w-7) .. "..." end
        mainWin.write("Ошибка: " .. msg)
        sleep(0.5)
    end
end

-- Финализация: очистка экрана и возврат в терминал
term.clear()
term.setCursorPos(1,1)
print("ameOs завершил работу.")

end
-- Запуск
local ok, err = pcall(main)
if not ok then
    term.setBackgroundColor(colors.black)
    term.clear()
    term.setCursorPos(1,1)
    print("Критическая ошибка при запуске:")
    print(err)
end
-- EOF
