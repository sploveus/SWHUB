-- SW HUB optimized build: listener deduplication, player-state cleanup, cached character-name lookup, and throttled label updates.
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")

local LocalPlayer = Players.LocalPlayer
if not LocalPlayer then
    Players:GetPropertyChangedSignal("LocalPlayer"):Wait()
    LocalPlayer = Players.LocalPlayer
end

local FRIEND_COLOR  = Color3.fromRGB(100, 149, 237)
local ENEMY_COLOR   = Color3.fromRGB(220, 20, 60)
local NEUTRAL_COLOR = Color3.fromRGB(255, 255, 255)
local playerClasses = {}
local statusInfo = {cache = {}}  -- kalkan / ölü tespiti (aşağıda doldurulur)

-- GUI
local PlayerGui = LocalPlayer:WaitForChild("PlayerGui")
local old = PlayerGui:FindFirstChild("SW_HUB")
if old then old:Destroy() end

local gui = Instance.new("ScreenGui")
gui.Name = "SW_HUB"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = PlayerGui

-- WELCOME EKRANI (dark / dramatik): kararan ekran, harf harf beliren SW HUB, titreme, dağılarak çıkış
task.spawn(function()
    local HOLD_TIME = 1.6   -- yazının tam göründükten sonra ekranda kalma süresi (sn)

    -- ŞARKI AYARLARI (Manifest - Toz Pembe)
    local SONG_ID     = ""    -- Roblox ses ID'si (sadece sayı ya da rbxassetid://... yazabilirsin)
    local SONG_FILE   = ""    -- alternatif: executor workspace klasöründeki dosya, örn. "tozpembe.mp3"
    local SONG_START  = 0     -- şarkıda kaçıncı saniyeden başlasın
    local SONG_VOLUME = 0.8

    local BLACK = Color3.fromRGB(6, 6, 6)
    local LIGHT = Color3.fromRGB(228, 228, 228)
    local MID   = Color3.fromRGB(135, 135, 135)

    local splash = Instance.new("ScreenGui")
    splash.Name = "SW_WELCOME"
    splash.ResetOnSpawn = false
    splash.IgnoreGuiInset = true
    splash.DisplayOrder = 1000
    local okParent = pcall(function()
        splash.Parent = (gethui and gethui()) or game:GetService("CoreGui")
    end)
    if not okParent or not splash.Parent then splash.Parent = PlayerGui end

    local function tw(obj, t, props, style, dir)
        TweenService:Create(obj, TweenInfo.new(t, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), props):Play()
    end

    -- Ekranı karart
    local dim = Instance.new("Frame")
    dim.Size = UDim2.new(1, 0, 1, 0)
    dim.BackgroundColor3 = BLACK
    dim.BackgroundTransparency = 1
    dim.BorderSizePixel = 0
    dim.Parent = splash

    -- Ortada kenarları kararan koyu bant
    local band = Instance.new("Frame")
    band.AnchorPoint = Vector2.new(0.5, 0.5)
    band.Position = UDim2.new(0.5, 0, 0.5, 8)
    band.Size = UDim2.new(1, 0, 0, 240)
    band.BackgroundColor3 = BLACK
    band.BackgroundTransparency = 1
    band.BorderSizePixel = 0
    band.Parent = splash
    local bandGrad = Instance.new("UIGradient")
    bandGrad.Transparency = NumberSequence.new({
        NumberSequenceKeypoint.new(0, 1),
        NumberSequenceKeypoint.new(0.5, 0.05),
        NumberSequenceKeypoint.new(1, 1),
    })
    bandGrad.Parent = band

    -- Başlık: harfler tek tek belirir
    local titleBox = Instance.new("Frame")
    titleBox.AnchorPoint = Vector2.new(0.5, 0.5)
    titleBox.Position = UDim2.new(0.5, 0, 0.5, -18)
    titleBox.Size = UDim2.new(0, 0, 0, 70)
    titleBox.AutomaticSize = Enum.AutomaticSize.X
    titleBox.BackgroundTransparency = 1
    titleBox.Parent = splash
    local layout = Instance.new("UIListLayout")
    layout.FillDirection = Enum.FillDirection.Horizontal
    layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    layout.VerticalAlignment = Enum.VerticalAlignment.Center
    layout.SortOrder = Enum.SortOrder.LayoutOrder
    layout.Padding = UDim.new(0, 6)
    layout.Parent = titleBox

    local letters = {}
    local TITLE = "SW HUB"
    for i = 1, #TITLE do
        local ch = TITLE:sub(i, i)
        local l = Instance.new("TextLabel")
        l.LayoutOrder = i
        l.BackgroundTransparency = 1
        if ch == " " then
            l.Size = UDim2.new(0, 18, 0, 70)
            l.Text = ""
        else
            l.Size = UDim2.new(0, 0, 0, 70)
            l.AutomaticSize = Enum.AutomaticSize.X
            l.Text = ch
            l.Font = Enum.Font.GothamBlack
            l.TextSize = 66
            l.TextColor3 = LIGHT
            l.TextTransparency = 1
            l.TextStrokeColor3 = Color3.new(0, 0, 0)
            l.TextStrokeTransparency = 1
            table.insert(letters, l)
        end
        l.Parent = titleBox
    end

    -- İnce gri çizgi (ortadan açılır)
    local line = Instance.new("Frame")
    line.AnchorPoint = Vector2.new(0.5, 0.5)
    line.Position = UDim2.new(0.5, 0, 0.5, 28)
    line.Size = UDim2.new(0, 0, 0, 2)
    line.BackgroundColor3 = MID
    line.BackgroundTransparency = 0.15
    line.BorderSizePixel = 0
    line.Parent = splash

    local sub = Instance.new("TextLabel")
    sub.AnchorPoint = Vector2.new(0.5, 0.5)
    sub.Position = UDim2.new(0.5, 0, 0.5, 54)
    sub.Size = UDim2.new(0, 380, 0, 24)
    sub.BackgroundTransparency = 1
    sub.Text = "W E L C O M E"
    sub.Font = Enum.Font.GothamMedium
    sub.TextSize = 18
    sub.TextColor3 = MID
    sub.TextTransparency = 1
    sub.Parent = splash

    -- Şarkı: girişte çalar, çıkış başlayınca kısılıp durur (çıkışta ses yok)
    local song
    task.spawn(function()
        local ok = pcall(function()
            local id
            if SONG_FILE ~= "" and getcustomasset then
                id = getcustomasset(SONG_FILE)
            elseif SONG_ID ~= "" then
                id = tostring(SONG_ID)
                if id:match("^%d+$") then id = "rbxassetid://" .. id end
            end
            if not id then return end
            song = Instance.new("Sound")
            song.SoundId = id
            song.Volume = 0
            song.Parent = splash
            local waited = 0
            while not song.IsLoaded and waited < 3 do
                task.wait(0.1)
                waited = waited + 0.1
            end
            song.TimePosition = SONG_START
            song:Play()
            TweenService:Create(song, TweenInfo.new(0.4), {Volume = SONG_VOLUME}):Play()
        end)
        if not ok then song = nil end
    end)

    -- GİRİŞ
    tw(dim, 0.7, {BackgroundTransparency = 0.4})
    tw(band, 0.7, {BackgroundTransparency = 0})
    task.wait(0.4)
    tw(line, 0.7, {Size = UDim2.new(0, 380, 0, 2)}, Enum.EasingStyle.Quart)
    for _, l in ipairs(letters) do
        tw(l, 0.25, {TextTransparency = 0, TextStrokeTransparency = 0.5})
        task.wait(0.09)
    end

    -- Kısa titreme (glitch)
    local base = titleBox.Position
    for _ = 1, 6 do
        titleBox.Position = base + UDim2.fromOffset(math.random(-4, 4), math.random(-2, 2))
        task.wait(0.025)
    end
    titleBox.Position = base
    tw(sub, 0.6, {TextTransparency = 0.15})

    task.wait(HOLD_TIME)

    -- ÇIKIŞ: şarkı kısılıp durur; harfler dağılarak kaybolur, çizgi ortaya çekilir, ekran açılır
    if song then
        pcall(function()
            TweenService:Create(song, TweenInfo.new(0.35), {Volume = 0}):Play()
            task.delay(0.4, function() song:Stop() end)
        end)
    end
    tw(layout, 0.8, {Padding = UDim.new(0, 70)}, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
    for _, l in ipairs(letters) do
        tw(l, 0.7, {TextTransparency = 1, TextStrokeTransparency = 1}, Enum.EasingStyle.Quad, Enum.EasingDirection.In)
    end
    tw(sub, 0.4, {TextTransparency = 1})
    task.wait(0.4)
    tw(line, 0.35, {Size = UDim2.new(0, 0, 0, 2)}, Enum.EasingStyle.Quart, Enum.EasingDirection.In)
    tw(band, 0.7, {BackgroundTransparency = 1})
    tw(dim, 0.7, {BackgroundTransparency = 1})
    task.wait(0.8)
    splash:Destroy()
end)

-- SINIF
local function getClass(plr)
    return playerClasses[plr.Name] or "neutral"
end
local function setClass(plr, class)
    playerClasses[plr.Name] = class
end
local function cycleClass(plr)
    local c = getClass(plr)
    local n = c == "neutral" and "friend" or c == "friend" and "enemy" or "neutral"
    setClass(plr, n)
    return n
end

-- SES
local clickSound = Instance.new("Sound")
clickSound.SoundId = "rbxassetid://12221967"
clickSound.Volume = 0.6
clickSound.Parent = gui

-- TOGGLE
local soundEnabled = false
local radioEnabled = true
local scriptEnabled = true    -- SCRIPT OFF: HER ŞEYİ kapatır (ESP, VFX, bildirim, radyasyon, panel)
local espEnabled = true       -- ESP OFF: SADECE oyuncu yazılarını (ESP) kapatır, başka bir şeye dokunmaz
local damageAlertsEnabled = true
local espSettings = {
    name = true, character = true, hp = true, distance = true,
    shield = true, dead = true, charColors = true,
    maxDist = 1000, textScale = 1,
}
-- VFX: sadece KENDİ efektlerinin rengini değiştirir (client-side, sadece senin ekranında)
local vfx = {
    enabled = false,
    color = Color3.fromRGB(255, 45, 45),
    colorName = "Red",
    rainbow = false,
    neon = false,
    radius = 20,
    hue = 0, sat = 1, val = 1,   -- ton ayarı: renk kaydırma (derece), doygunluk ve parlaklık çarpanı
}
local forceESPRefresh -- ESP yazılarını hemen yenile (aşağıda tanımlanır)
local vfxRescan       -- mevcut efektleri yeniden boya (aşağıda tanımlanır)
local setScript       -- script ON/OFF (espGui'den sonra tanımlanır)
local setESPOn        -- sadece ESP ON/OFF (espGui'den sonra tanımlanır)
local setScriptSwitch -- hub sayfasındaki script anahtarının görünümünü günceller
local toggleKey    = "PageDown"
local capturingKey = false
local keyBox
local fpsBoostWanted = false  -- FPS Boost anahtarı (kullanıcının istediği durum)
local fpsBoostApply           -- FPS Boost motoru (aşağıda tanımlanır)
local skinPopulate            -- SKIN sekmesi: karakter listesini yeniler
local skinStopSearch          -- SKIN sekmesi: arama yakalamayı durdurur
local skinSetEnabled          -- SKIN sekmesi: script ON/OFF'a göre giydir / çıkar

-- ANA PANEL
local PANEL_W   = 600
local PANEL_H   = 430
local SIDEBAR_W = 128
local CONTENT_Y = 33
local PANEL_BG  = Color3.fromRGB(13, 13, 13)
local STRIP_BG  = Color3.fromRGB(19, 19, 19)
local ROW_BG    = Color3.fromRGB(25, 25, 28)
local ROW_LINE  = Color3.fromRGB(40, 40, 45)

local listFrame = Instance.new("Frame")
listFrame.Name = "listFrame"
listFrame.Size = UDim2.new(0, PANEL_W, 0, PANEL_H)
listFrame.AnchorPoint = Vector2.new(0.5, 0.5)
listFrame.Position = UDim2.new(0.5, 0, 0.5, 0)
listFrame.BackgroundColor3 = PANEL_BG
listFrame.BorderSizePixel = 0
listFrame.ClipsDescendants = true
listFrame.Visible = true
listFrame.Parent = gui
Instance.new("UICorner", listFrame).CornerRadius = UDim.new(0, 12)

local pStroke = Instance.new("UIStroke", listFrame)
pStroke.Color = Color3.fromRGB(55, 55, 55)
pStroke.Thickness = 1

-- Başlık
local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 32)
titleBar.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
titleBar.BorderSizePixel = 0
titleBar.Parent = listFrame

local titleLabel = Instance.new("TextLabel")
titleLabel.Size = UDim2.new(1, 0, 1, 0)
titleLabel.BackgroundTransparency = 1
titleLabel.Text = "SW HUB"
titleLabel.TextColor3 = Color3.new(1, 1, 1)
titleLabel.Font = Enum.Font.GothamBlack
titleLabel.TextSize = 16
titleLabel.Parent = titleBar

-- Drag panel by its title bar (declared after titleBar exists).
local dragging = false
local dragStart, startPosition

titleBar.Active = true
titleBar.InputBegan:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = true
        dragStart = input.Position
        startPosition = listFrame.Position
    end
end)

UserInputService.InputChanged:Connect(function(input)
    if dragging and input.UserInputType == Enum.UserInputType.MouseMovement then
        local delta = input.Position - dragStart
        listFrame.Position = UDim2.new(
            startPosition.X.Scale, startPosition.X.Offset + delta.X,
            startPosition.Y.Scale, startPosition.Y.Offset + delta.Y
        )
    end
end)

UserInputService.InputEnded:Connect(function(input)
    if input.UserInputType == Enum.UserInputType.MouseButton1 then
        dragging = false
    end
end)

local collapseBtn = Instance.new("TextButton")
collapseBtn.Name = "CollapseButton"
collapseBtn.Size = UDim2.new(0, 28, 0, 24)
collapseBtn.Position = UDim2.new(1, -32, 0, 4)
collapseBtn.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
collapseBtn.BorderSizePixel = 0
collapseBtn.Text = "—"
collapseBtn.TextColor3 = Color3.new(1, 1, 1)
collapseBtn.Font = Enum.Font.GothamBold
collapseBtn.TextSize = 16
collapseBtn.Parent = titleBar
Instance.new("UICorner", collapseBtn).CornerRadius = UDim.new(0, 6)

-- Panel kapalıyken sağ üstte kalan küçük butonlar: SW HUB (aç) + altında Rejoin
local reopenButton = Instance.new("TextButton")
reopenButton.Name = "SWHUBReopen"
reopenButton.Size = UDim2.new(0, 100, 0, 32)
reopenButton.Position = UDim2.new(1, -110, 0, 30)
reopenButton.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
reopenButton.BorderSizePixel = 0
reopenButton.Text = "SW HUB"
reopenButton.TextColor3 = Color3.new(1, 1, 1)
reopenButton.Font = Enum.Font.GothamBlack
reopenButton.TextSize = 14
reopenButton.Visible = false
reopenButton.Parent = gui
Instance.new("UICorner", reopenButton).CornerRadius = UDim.new(0, 8)
local reopenStroke = Instance.new("UIStroke", reopenButton)
reopenStroke.Color = Color3.fromRGB(55, 55, 55)
reopenStroke.Thickness = 1

local rejoinQuick = Instance.new("TextButton")
rejoinQuick.Name = "SWHUBRejoinQuick"
rejoinQuick.Size = UDim2.new(0, 76, 0, 20)
rejoinQuick.Position = UDim2.new(1, -98, 0, 66)
rejoinQuick.BackgroundColor3 = Color3.fromRGB(22, 22, 22)
rejoinQuick.BorderSizePixel = 0
rejoinQuick.Text = "🔄 Rejoin"
rejoinQuick.TextColor3 = Color3.new(1, 1, 1)
rejoinQuick.Font = Enum.Font.GothamBold
rejoinQuick.TextSize = 10
rejoinQuick.Visible = false
rejoinQuick.Parent = gui
Instance.new("UICorner", rejoinQuick).CornerRadius = UDim.new(0, 6)
local rejoinQuickStroke = Instance.new("UIStroke", rejoinQuick)
rejoinQuickStroke.Color = Color3.fromRGB(55, 55, 55)
rejoinQuickStroke.Thickness = 1

-- FPS göstergesi: panel kapalıyken SW HUB butonunun altında (rejoin'in da altında) görünür
local fpsLabel = Instance.new("TextLabel")
fpsLabel.Name = "SWHUBFps"
fpsLabel.Size = UDim2.new(0, 100, 0, 18)
fpsLabel.Position = UDim2.new(1, -110, 0, 8)
fpsLabel.BackgroundTransparency = 1
fpsLabel.Text = "FPS --"
fpsLabel.Font = Enum.Font.GothamBold
fpsLabel.TextSize = 14
fpsLabel.TextColor3 = Color3.new(1, 1, 1)
fpsLabel.TextStrokeColor3 = Color3.new(0, 0, 0)
fpsLabel.TextStrokeTransparency = 0
fpsLabel.Visible = false
fpsLabel.Parent = gui
do
    local frames, acc = 0, 0
    RunService.Heartbeat:Connect(function(dt)
        if not fpsLabel.Visible then frames, acc = 0, 0 return end
        frames = frames + 1
        acc = acc + dt
        if acc >= 0.5 then
            local fps = math.floor(frames / acc + 0.5)
            fpsLabel.Text = "FPS " .. fps
            frames, acc = 0, 0
        end
    end)
end

local function doRejoin(button)
    button.Text = "⏳ ..."
    local ok = pcall(function()
        if #Players:GetPlayers() <= 1 then
            TeleportService:Teleport(game.PlaceId, LocalPlayer)
        else
            TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId, LocalPlayer)
        end
    end)
    if not ok then button.Text = "❌ Failed" end
    task.delay(3, function() button.Text = "🔄 Rejoin" end)
end
rejoinQuick.MouseButton1Click:Connect(function() doRejoin(rejoinQuick) end)

-- Panel göster / gizle: panel kapanınca SW HUB + Rejoin butonları sağ üstte belirir.
-- Script tamamen kapalıyken (SCRIPT OFF) hiçbiri görünmez.
local function setPanelVisible(v)
    listFrame.Visible = v
    local showQuick = (not v) and scriptEnabled
    reopenButton.Visible = showQuick
    rejoinQuick.Visible = showQuick
    fpsLabel.Visible = showQuick
end

collapseBtn.MouseButton1Click:Connect(function() setPanelVisible(false) end)
reopenButton.MouseButton1Click:Connect(function() setPanelVisible(true) end)

local sep = Instance.new("Frame")
sep.Size = UDim2.new(1, 0, 0, 1)
sep.Position = UDim2.new(0, 0, 0, 32)
sep.BackgroundColor3 = Color3.fromRGB(50, 50, 50)
sep.BorderSizePixel = 0
sep.Parent = listFrame

-- YAN MENÜ (sol tarafta dikey sekmeler): SW HUB | ESP | VFX | PLAYER LIST
local sideBar = Instance.new("Frame")
sideBar.Name = "SideBar"
sideBar.Position = UDim2.new(0, 0, 0, CONTENT_Y)
sideBar.Size = UDim2.new(0, SIDEBAR_W, 1, -CONTENT_Y)
sideBar.BackgroundColor3 = STRIP_BG
sideBar.BorderSizePixel = 0
sideBar.Parent = listFrame

local sideLayout = Instance.new("UIListLayout")
sideLayout.Padding = UDim.new(0, 4)
sideLayout.SortOrder = Enum.SortOrder.LayoutOrder
sideLayout.Parent = sideBar
local sidePad = Instance.new("UIPadding")
sidePad.PaddingTop = UDim.new(0, 10)
sidePad.PaddingLeft = UDim.new(0, 8)
sidePad.PaddingRight = UDim.new(0, 8)
sidePad.Parent = sideBar

local sideLine = Instance.new("Frame")
sideLine.Position = UDim2.new(0, SIDEBAR_W, 0, CONTENT_Y)
sideLine.Size = UDim2.new(0, 1, 1, -CONTENT_Y)
sideLine.BackgroundColor3 = Color3.fromRGB(38, 38, 38)
sideLine.BorderSizePixel = 0
sideLine.Parent = listFrame

local TAB_DEFS = {
    {key = "hub",     text = "SW HUB"},
    {key = "esp",     text = "ESP"},
    {key = "vfx",     text = "VFX"},
    {key = "players", text = "PLAYER LIST"},
    {key = "skin",    text = "SKIN"},
}
local tabButtons, pages = {}, {}
for i, def in ipairs(TAB_DEFS) do
    local b = Instance.new("TextButton")
    b.Name = "Tab_" .. def.key
    b.LayoutOrder = i
    b.Size = UDim2.new(1, 0, 0, 34)
    b.BackgroundColor3 = Color3.fromRGB(33, 33, 38)
    b.BackgroundTransparency = 1
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Text = ""
    b.Parent = sideBar
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)

    local accent = Instance.new("Frame")
    accent.Name = "Accent"
    accent.Size = UDim2.new(0, 3, 0, 16)
    accent.Position = UDim2.new(0, 4, 0.5, -8)
    accent.BackgroundColor3 = Color3.fromRGB(235, 235, 235)
    accent.BorderSizePixel = 0
    accent.Visible = false
    accent.Parent = b
    Instance.new("UICorner", accent).CornerRadius = UDim.new(1, 0)

    local lab = Instance.new("TextLabel")
    lab.Name = "Label"
    lab.BackgroundTransparency = 1
    lab.Position = UDim2.new(0, 16, 0, 0)
    lab.Size = UDim2.new(1, -18, 1, 0)
    lab.Text = def.text
    lab.Font = Enum.Font.GothamBold
    lab.TextSize = 12
    lab.TextXAlignment = Enum.TextXAlignment.Left
    lab.TextColor3 = Color3.fromRGB(140, 140, 140)
    lab.Parent = b

    tabButtons[def.key] = b

    local page = Instance.new("Frame")
    page.Name = "Page_" .. def.key
    page.Position = UDim2.new(0, SIDEBAR_W + 1, 0, CONTENT_Y)
    page.Size = UDim2.new(1, -(SIDEBAR_W + 1), 1, -CONTENT_Y)
    page.BackgroundTransparency = 1
    page.ClipsDescendants = true
    page.Visible = false
    page.Parent = listFrame
    pages[def.key] = page
end
local hubPage, espPage, vfxPage, playersPage = pages.hub, pages.esp, pages.vfx, pages.players

-- Satır / ayar yardımcıları
local function makeScrollPage(page)
    local sf = Instance.new("ScrollingFrame")
    sf.Position = UDim2.new(0, 10, 0, 8)
    sf.Size = UDim2.new(1, -20, 1, -14)
    sf.BackgroundTransparency = 1
    sf.BorderSizePixel = 0
    sf.ScrollBarThickness = 3
    sf.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 80)
    sf.CanvasSize = UDim2.new(0, 0, 0, 0)
    sf.Parent = page
    local lay = Instance.new("UIListLayout")
    lay.Padding = UDim.new(0, 6)
    lay.SortOrder = Enum.SortOrder.LayoutOrder
    lay.Parent = sf
    lay:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        sf.CanvasSize = UDim2.new(0, 0, 0, lay.AbsoluteContentSize.Y + 6)
    end)
    return sf
end

local function makeRow(parent, order, height)
    local row = Instance.new("Frame")
    row.LayoutOrder = order
    row.Size = UDim2.new(1, -6, 0, height or 32)
    row.BackgroundColor3 = ROW_BG
    row.BorderSizePixel = 0
    row.Parent = parent
    Instance.new("UICorner", row).CornerRadius = UDim.new(0, 8)
    local rs = Instance.new("UIStroke", row)
    rs.Color = ROW_LINE
    rs.Thickness = 1
    return row
end

local function rowLabel(row, text, rightSpace)
    local l = Instance.new("TextLabel")
    l.BackgroundTransparency = 1
    l.Position = UDim2.new(0, 12, 0, 0)
    l.Size = UDim2.new(1, -(rightSpace or 80), 1, 0)
    l.Text = text
    l.TextColor3 = Color3.fromRGB(230, 230, 230)
    l.Font = Enum.Font.GothamMedium
    l.TextSize = 12
    l.TextXAlignment = Enum.TextXAlignment.Left
    l.Parent = row
    return l
end

local function makeSmallButton(parent, text, size, position)
    local b = Instance.new("TextButton")
    b.Size = size
    b.Position = position
    b.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    b.BorderSizePixel = 0
    b.AutoButtonColor = true
    b.Text = text
    b.TextColor3 = Color3.new(1, 1, 1)
    b.Font = Enum.Font.GothamBold
    b.TextSize = 11
    b.Parent = parent
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    return b
end

-- Küçük gri bölüm başlığı (GENERAL, DISPLAY...)
local function makeHeader(parent, order, text)
    local h = Instance.new("TextLabel")
    h.LayoutOrder = order
    h.Size = UDim2.new(1, -6, 0, 18)
    h.BackgroundTransparency = 1
    h.Text = text
    h.TextColor3 = Color3.fromRGB(125, 125, 135)
    h.Font = Enum.Font.GothamBold
    h.TextSize = 10
    h.TextXAlignment = Enum.TextXAlignment.Left
    h.Parent = parent
    local hp = Instance.new("UIPadding", h)
    hp.PaddingLeft = UDim.new(0, 4)
    hp.PaddingTop = UDim.new(0, 4)
    return h
end

-- 2 sütunlu ızgara (aç/kapa satırlarını düzenli dizmek için)
local function makeGrid(parent, order, rows)
    local h = Instance.new("Frame")
    h.LayoutOrder = order
    h.Size = UDim2.new(1, -6, 0, rows * 32 + (rows - 1) * 6)
    h.BackgroundTransparency = 1
    h.Parent = parent
    local gl = Instance.new("UIGridLayout")
    gl.CellSize = UDim2.new(0.5, -3, 0, 32)
    gl.CellPadding = UDim2.new(0, 6, 0, 6)
    gl.SortOrder = Enum.SortOrder.LayoutOrder
    gl.Parent = h
    return h
end

-- Kaydırmalı anahtar (ON/OFF). Üstteki açıklama (desc) verilirse satır iki satırlı olur.
local SWITCH_ON  = Color3.fromRGB(70, 170, 100)
local SWITCH_OFF = Color3.fromRGB(62, 62, 68)
local function makeToggleRow(parent, order, text, initial, onChange, desc)
    local row = makeRow(parent, order, desc and 46 or 32)
    local lbl = rowLabel(row, text, 64)
    if desc then
        lbl.Position = UDim2.new(0, 12, 0, 6)
        lbl.Size = UDim2.new(1, -64, 0, 18)
        local d = Instance.new("TextLabel")
        d.BackgroundTransparency = 1
        d.Position = UDim2.new(0, 12, 0, 24)
        d.Size = UDim2.new(1, -64, 0, 16)
        d.Text = desc
        d.TextColor3 = Color3.fromRGB(135, 135, 145)
        d.Font = Enum.Font.Gotham
        d.TextSize = 10
        d.TextXAlignment = Enum.TextXAlignment.Left
        d.TextTruncate = Enum.TextTruncate.AtEnd
        d.Parent = row
    end

    local track = Instance.new("TextButton")
    track.Size = UDim2.new(0, 38, 0, 20)
    track.Position = UDim2.new(1, -48, 0.5, -10)
    track.Text = ""
    track.AutoButtonColor = false
    track.BorderSizePixel = 0
    track.Parent = row
    Instance.new("UICorner", track).CornerRadius = UDim.new(1, 0)
    local knob = Instance.new("Frame")
    knob.Size = UDim2.new(0, 14, 0, 14)
    knob.BackgroundColor3 = Color3.new(1, 1, 1)
    knob.BorderSizePixel = 0
    knob.Parent = track
    Instance.new("UICorner", knob).CornerRadius = UDim.new(1, 0)

    local state = initial
    local function paint(animate)
        local trackColor = state and SWITCH_ON or SWITCH_OFF
        local knobPos = UDim2.new(0, state and 21 or 3, 0.5, -7)
        if animate then
            local info = TweenInfo.new(0.15, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
            TweenService:Create(track, info, {BackgroundColor3 = trackColor}):Play()
            TweenService:Create(knob, info, {Position = knobPos}):Play()
        else
            track.BackgroundColor3 = trackColor
            knob.Position = knobPos
        end
    end
    paint(false)
    track.MouseButton1Click:Connect(function()
        state = not state
        paint(true)
        onChange(state)
    end)
    return function(v) state = v paint(true) end
end

local function makeStepperRow(parent, order, text, getValue, minV, maxV, step, fmt, onChange)
    local row = makeRow(parent, order)
    rowLabel(row, text, 140)
    local minus = makeSmallButton(row, "-", UDim2.new(0, 24, 0, 22), UDim2.new(1, -128, 0.5, -11))
    local val = Instance.new("TextLabel")
    val.BackgroundTransparency = 1
    val.Size = UDim2.new(0, 56, 1, 0)
    val.Position = UDim2.new(1, -100, 0, 0)
    val.TextColor3 = Color3.new(1, 1, 1)
    val.Font = Enum.Font.GothamBold
    val.TextSize = 12
    val.Parent = row
    local plus = makeSmallButton(row, "+", UDim2.new(0, 24, 0, 22), UDim2.new(1, -36, 0.5, -11))
    local function refresh() val.Text = fmt(getValue()) end
    local function change(delta)
        local v = math.clamp(getValue() + delta, minV, maxV)
        v = math.floor(v * 100 + 0.5) / 100
        onChange(v)
        refresh()
    end
    minus.MouseButton1Click:Connect(function() change(-step) end)
    plus.MouseButton1Click:Connect(function() change(step) end)
    refresh()
end

-- ===== ESP SEKMESİ =====
do
    local espScroll = makeScrollPage(espPage)
    local function espChanged() if forceESPRefresh then forceESPRefresh() end end

    makeHeader(espScroll, 1, "ESP")
    makeToggleRow(espScroll, 2, "ESP ON / OFF", espEnabled, function(v)
        if setESPOn then setESPOn(v) end
    end, "Only hides the player labels. Everything else keeps working.")

    makeHeader(espScroll, 3, "DISPLAY")
    local grid = makeGrid(espScroll, 4, 4)
    makeToggleRow(grid, 1, "Player name", espSettings.name, function(v) espSettings.name = v espChanged() end)
    makeToggleRow(grid, 2, "Character name", espSettings.character, function(v) espSettings.character = v espChanged() end)
    makeToggleRow(grid, 3, "HP", espSettings.hp, function(v) espSettings.hp = v espChanged() end)
    makeToggleRow(grid, 4, "Distance", espSettings.distance, function(v) espSettings.distance = v espChanged() end)
    makeToggleRow(grid, 5, "🛡 Shield tag", espSettings.shield, function(v) espSettings.shield = v espChanged() end)
    makeToggleRow(grid, 6, "💀 Dead tag", espSettings.dead, function(v) espSettings.dead = v espChanged() end)
    makeToggleRow(grid, 7, "🎨 Character colors", espSettings.charColors, function(v) espSettings.charColors = v espChanged() end)

    makeHeader(espScroll, 5, "SIZE & RANGE")
    makeStepperRow(espScroll, 6, "Max distance", function() return espSettings.maxDist end,
        200, 2000, 100, function(v) return v .. "m" end,
        function(v) espSettings.maxDist = v end)
    makeStepperRow(espScroll, 7, "Text size", function() return espSettings.textScale end,
        0.6, 1.5, 0.1, function(v) return string.format("%.1fx", v) end,
        function(v) espSettings.textScale = v espChanged() end)

    makeHeader(espScroll, 8, "ALERTS")
    makeToggleRow(espScroll, 9, "☢ Radio marker (friend hit)", radioEnabled, function(v) radioEnabled = v end)
    makeToggleRow(espScroll, 10, "⚠ Damage alerts", damageAlertsEnabled, function(v) damageAlertsEnabled = v end)
end

-- ===== VFX SEKMESİ =====
do
    local vfxScroll = makeScrollPage(vfxPage)
    local setVfxToggle

    makeHeader(vfxScroll, 1, "VFX")
    setVfxToggle = makeToggleRow(vfxScroll, 2, "VFX ON / OFF", vfx.enabled, function(v)
        vfx.enabled = v
        if v and vfxRescan then vfxRescan() end
    end, "Recolors only YOUR skills / effects. Only you see it.")

    makeHeader(vfxScroll, 3, "COLOR")
    local colorNameRow = makeRow(vfxScroll, 4, 28)
    local colorNameLabel = rowLabel(colorNameRow, "Selected: " .. vfx.colorName, 16)

    local swatchHolder = Instance.new("Frame")
    swatchHolder.LayoutOrder = 5
    swatchHolder.Size = UDim2.new(1, -6, 0, 176)
    swatchHolder.BackgroundTransparency = 1
    swatchHolder.Parent = vfxScroll
    local swatchGrid = Instance.new("UIGridLayout")
    swatchGrid.CellSize = UDim2.new(0, 56, 0, 34)
    swatchGrid.CellPadding = UDim2.new(0, 8, 0, 8)
    swatchGrid.SortOrder = Enum.SortOrder.LayoutOrder
    swatchGrid.Parent = swatchHolder

    -- {isim, renk, rainbow?}
    local VFX_COLORS = {
        {"Red",    Color3.fromRGB(255, 45, 45)},
        {"Orange", Color3.fromRGB(255, 140, 25)},
        {"Yellow", Color3.fromRGB(255, 225, 50)},
        {"Green",  Color3.fromRGB(50, 230, 90)},
        {"Cyan",   Color3.fromRGB(40, 220, 230)},
        {"Blue",   Color3.fromRGB(60, 120, 255)},
        {"Purple", Color3.fromRGB(170, 85, 255)},
        {"Pink",   Color3.fromRGB(255, 105, 180)},
        {"White",  Color3.fromRGB(255, 255, 255)},
        {"Crimson", Color3.fromRGB(220, 20, 60)},
        {"Maroon", Color3.fromRGB(128, 0, 32)},
        {"Gold",   Color3.fromRGB(255, 200, 0)},
        {"Lime",   Color3.fromRGB(160, 255, 40)},
        {"Mint",   Color3.fromRGB(120, 255, 190)},
        {"Teal",   Color3.fromRGB(0, 170, 160)},
        {"Sky",    Color3.fromRGB(110, 200, 255)},
        {"Navy",   Color3.fromRGB(20, 40, 160)},
        {"Indigo", Color3.fromRGB(90, 40, 200)},
        {"Magenta", Color3.fromRGB(255, 0, 200)},
        {"Hot Pink", Color3.fromRGB(255, 50, 120)},
        {"Peach",  Color3.fromRGB(255, 170, 130)},
        {"Brown",  Color3.fromRGB(140, 85, 40)},
        {"Gray",   Color3.fromRGB(130, 130, 130)},
        {"Black",  Color3.fromRGB(15, 15, 15)},
        {"Rainbow", Color3.fromRGB(255, 255, 255), true},
    }
    local swatchStrokes = {}
    for i, def in ipairs(VFX_COLORS) do
        local b = Instance.new("TextButton")
        b.LayoutOrder = i
        b.Text = ""
        b.AutoButtonColor = false
        b.BackgroundColor3 = def[2]
        b.BorderSizePixel = 0
        b.Parent = swatchHolder
        Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
        if def[3] then
            -- Rainbow: gökkuşağı gradyanı + yazı
            local g = Instance.new("UIGradient")
            g.Color = ColorSequence.new({
                ColorSequenceKeypoint.new(0.00, Color3.fromRGB(255, 60, 60)),
                ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 160, 40)),
                ColorSequenceKeypoint.new(0.34, Color3.fromRGB(255, 235, 60)),
                ColorSequenceKeypoint.new(0.51, Color3.fromRGB(60, 230, 100)),
                ColorSequenceKeypoint.new(0.68, Color3.fromRGB(50, 200, 255)),
                ColorSequenceKeypoint.new(0.84, Color3.fromRGB(110, 90, 255)),
                ColorSequenceKeypoint.new(1.00, Color3.fromRGB(230, 80, 220)),
            })
            g.Parent = b
            local t = Instance.new("TextLabel")
            t.Size = UDim2.new(1, 0, 1, 0)
            t.BackgroundTransparency = 1
            t.Text = "RAINBOW"
            t.TextColor3 = Color3.new(1, 1, 1)
            t.Font = Enum.Font.GothamBlack
            t.TextSize = 9
            t.TextStrokeTransparency = 0.4
            t.Parent = b
        end
        local st = Instance.new("UIStroke", b)
        st.Color = Color3.new(1, 1, 1)
        st.Thickness = (def[1] == vfx.colorName) and 2 or 0
        swatchStrokes[i] = st
        b.MouseButton1Click:Connect(function()
            vfx.color = def[2]
            vfx.colorName = def[1]
            vfx.rainbow = def[3] == true
            for j, other in ipairs(swatchStrokes) do other.Thickness = (j == i) and 2 or 0 end
            colorNameLabel.Text = "Selected: " .. def[1]
            vfx.enabled = true
            setVfxToggle(true)
            if vfxRescan then vfxRescan() end
        end)
    end

    makeHeader(vfxScroll, 6, "TONE")
    makeStepperRow(vfxScroll, 7, "Hue shift", function() return vfx.hue end,
        0, 350, 10, function(v) return v .. "°" end,
        function(v) vfx.hue = v if vfx.enabled and vfxRescan then vfxRescan() end end)
    makeStepperRow(vfxScroll, 8, "Saturation", function() return vfx.sat end,
        0, 2, 0.1, function(v) return math.floor(v * 100 + 0.5) .. "%" end,
        function(v) vfx.sat = v if vfx.enabled and vfxRescan then vfxRescan() end end)
    makeStepperRow(vfxScroll, 9, "Brightness", function() return vfx.val end,
        0.2, 1.5, 0.1, function(v) return math.floor(v * 100 + 0.5) .. "%" end,
        function(v) vfx.val = v if vfx.enabled and vfxRescan then vfxRescan() end end)

    makeHeader(vfxScroll, 10, "OPTIONS")
    makeToggleRow(vfxScroll, 11, "Neon parts too", vfx.neon, function(v)
        vfx.neon = v
        if vfx.enabled and vfxRescan then vfxRescan() end
    end)
    makeStepperRow(vfxScroll, 12, "Detect radius", function() return vfx.radius end,
        10, 100, 5, function(v) return v .. " studs" end,
        function(v) vfx.radius = v end)
end

-- Search bar: oyunlar TextBox girişini bozabildiği için yazıyı kendimiz yakalıyoruz.
-- Çubuğa tıkla -> yaz -> Enter/Esc veya dışarı tıkla -> bitir. Oyuncu adı VE karakter adıyla arar.
local ContextActionService = game:GetService("ContextActionService")
local SEARCH_ACTION = "SW_HUB_SEARCH"
local searchQuery = ""
local searching = false
local cursorOn = true
local charNames = {}      -- plr -> karakter adı (küçük harf), render döngüsü doldurur
local playerButtons = {}

local searchBar = Instance.new("Frame")
searchBar.Name = "SearchBar"
searchBar.Size = UDim2.new(1, -16, 0, 24)
searchBar.Position = UDim2.new(0, 8, 0, 8)
searchBar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
searchBar.BorderSizePixel = 0
searchBar.Parent = playersPage
Instance.new("UICorner", searchBar).CornerRadius = UDim.new(0, 6)
local searchStroke = Instance.new("UIStroke", searchBar)
searchStroke.Color = Color3.fromRGB(55, 55, 55)
searchStroke.Thickness = 1

local searchBtn = Instance.new("TextButton")
searchBtn.Name = "SearchText"
searchBtn.Size = UDim2.new(1, -26, 1, 0)
searchBtn.BackgroundTransparency = 1
searchBtn.AutoButtonColor = false
searchBtn.Font = Enum.Font.GothamMedium
searchBtn.TextSize = 12
searchBtn.TextXAlignment = Enum.TextXAlignment.Left
searchBtn.TextTruncate = Enum.TextTruncate.AtEnd
searchBtn.Text = ""
searchBtn.Parent = searchBar
local searchPadding = Instance.new("UIPadding")
searchPadding.PaddingLeft = UDim.new(0, 8)
searchPadding.Parent = searchBtn

local clearBtn = Instance.new("TextButton")
clearBtn.Name = "SearchClear"
clearBtn.Size = UDim2.new(0, 20, 0, 20)
clearBtn.Position = UDim2.new(1, -24, 0.5, -10)
clearBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
clearBtn.BorderSizePixel = 0
clearBtn.Text = "✕"
clearBtn.TextColor3 = Color3.new(1, 1, 1)
clearBtn.Font = Enum.Font.GothamBold
clearBtn.TextSize = 11
clearBtn.Visible = false
clearBtn.Parent = searchBar
Instance.new("UICorner", clearBtn).CornerRadius = UDim.new(0, 5)

local function matchesSearch(plr)
    if searchQuery == "" then return true end
    return plr.Name:lower():find(searchQuery, 1, true) ~= nil
        or plr.DisplayName:lower():find(searchQuery, 1, true) ~= nil
        or (charNames[plr] ~= nil and charNames[plr]:find(searchQuery, 1, true) ~= nil)
end

local function applySearchFilter()
    for plr, btn in pairs(playerButtons) do
        if btn and btn.Parent then
            btn.Visible = matchesSearch(plr)
        end
    end
end

local function renderSearch()
    if searchQuery == "" and not searching then
        searchBtn.Text = "🔍 Oyuncu veya karakter ara..."
        searchBtn.TextColor3 = Color3.fromRGB(120, 120, 120)
    else
        searchBtn.Text = searchQuery .. ((searching and cursorOn) and "|" or "")
        searchBtn.TextColor3 = Color3.new(1, 1, 1)
    end
    clearBtn.Visible = searchQuery ~= ""
    searchStroke.Color = searching and Color3.fromRGB(100, 149, 237) or Color3.fromRGB(55, 55, 55)
end

local SEARCH_DIGITS = {
    Zero = "0", One = "1", Two = "2", Three = "3", Four = "4",
    Five = "5", Six = "6", Seven = "7", Eight = "8", Nine = "9",
    KeypadZero = "0", KeypadOne = "1", KeypadTwo = "2", KeypadThree = "3", KeypadFour = "4",
    KeypadFive = "5", KeypadSix = "6", KeypadSeven = "7", KeypadEight = "8", KeypadNine = "9",
}
local SEARCH_KEYS = {}
for i = string.byte("A"), string.byte("Z") do
    table.insert(SEARCH_KEYS, Enum.KeyCode[string.char(i)])
end
for name in pairs(SEARCH_DIGITS) do
    table.insert(SEARCH_KEYS, Enum.KeyCode[name])
end
for _, name in ipairs({"Space", "Backspace", "Return", "KeypadEnter", "Escape", "Minus", "Semicolon", "Quote", "Period"}) do
    table.insert(SEARCH_KEYS, Enum.KeyCode[name])
end

local stopSearch
local function searchAction(_, state, input)
    if state ~= Enum.UserInputState.Begin then
        return Enum.ContextActionResult.Sink
    end
    local name = input.KeyCode.Name
    local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
        or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
    if name == "Return" or name == "KeypadEnter" or name == "Escape" then
        stopSearch()
        return Enum.ContextActionResult.Sink
    elseif name == "Backspace" then
        searchQuery = searchQuery:sub(1, -2)
    else
        local ch
        if #name == 1 and name:match("%a") then ch = name:lower()
        elseif SEARCH_DIGITS[name] then ch = SEARCH_DIGITS[name]
        elseif name == "Space" then ch = " "
        elseif name == "Minus" then ch = shift and "_" or "-"
        elseif name == "Semicolon" then ch = shift and ":" or ";"
        elseif name == "Quote" then ch = "'"
        elseif name == "Period" then ch = "."
        end
        if ch then searchQuery = (searchQuery .. ch):sub(1, 40) end
    end
    cursorOn = true
    applySearchFilter()
    renderSearch()
    return Enum.ContextActionResult.Sink
end

local function startSearch()
    if searching then return end
    searching = true
    cursorOn = true
    pcall(function()
        ContextActionService:BindActionAtPriority(SEARCH_ACTION, searchAction, false,
            Enum.ContextActionPriority.High.Value + 100, table.unpack(SEARCH_KEYS))
    end)
    renderSearch()
end
stopSearch = function()
    if not searching then return end
    searching = false
    pcall(function() ContextActionService:UnbindAction(SEARCH_ACTION) end)
    renderSearch()
end

searchBtn.MouseButton1Click:Connect(startSearch)
clearBtn.MouseButton1Click:Connect(function()
    searchQuery = ""
    applySearchFilter()
    renderSearch()
end)

-- Çubuğun dışına tıklayınca yazmayı bitir
UserInputService.InputBegan:Connect(function(input)
    if searching and input.UserInputType == Enum.UserInputType.MouseButton1 then
        local m = UserInputService:GetMouseLocation()
        local pos, size = searchBar.AbsolutePosition, searchBar.AbsoluteSize
        local inside = m.X >= pos.X and m.X <= pos.X + size.X and m.Y >= pos.Y and m.Y <= pos.Y + size.Y
        if not inside then stopSearch() end
    end
end)

-- İmleç yanıp sönsün; panel kapanırsa tuş yakalamayı bırak; karakter adları değişince filtreyi tazele
task.spawn(function()
    while gui.Parent do
        task.wait(0.4)
        if searching then
            if not listFrame.Visible or not playersPage.Visible then
                stopSearch()
            else
                cursorOn = not cursorOn
                renderSearch()
            end
        end
        if searchQuery ~= "" then applySearchFilter() end
    end
end)
renderSearch()

-- Scroll
local scrolling = Instance.new("ScrollingFrame")
scrolling.Position = UDim2.new(0, 8, 0, 42)
scrolling.Size = UDim2.new(1, -16, 1, -48)
scrolling.CanvasSize = UDim2.new(0, 0, 0, 0)
scrolling.BackgroundTransparency = 1
scrolling.BorderSizePixel = 0
scrolling.ScrollBarThickness = 3
scrolling.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 80)
scrolling.Parent = playersPage

local listLayout = Instance.new("UIListLayout")
listLayout.Padding = UDim.new(0, 5)
listLayout.Parent = scrolling
listLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
    scrolling.CanvasSize = UDim2.new(0, 0, 0, listLayout.AbsoluteContentSize.Y + 6)
end)

-- ===== SW HUB SEKMESİ (script on/off, ses, açma tuşu, rejoin) =====
local hubScroll = makeScrollPage(hubPage)
do
    local hero = makeRow(hubScroll, 1, 58)
    local heroTitle = rowLabel(hero, "SW HUB", 16)
    heroTitle.Font = Enum.Font.GothamBlack
    heroTitle.TextSize = 22
    heroTitle.Position = UDim2.new(0, 14, 0, 8)
    heroTitle.Size = UDim2.new(1, -28, 0, 28)
    local heroSub = rowLabel(hero, "ESP  •  VFX  •  PLAYER TOOLS", 16)
    heroSub.Font = Enum.Font.Gotham
    heroSub.TextSize = 10
    heroSub.TextColor3 = Color3.fromRGB(135, 135, 145)
    heroSub.Position = UDim2.new(0, 14, 0, 36)
    heroSub.Size = UDim2.new(1, -28, 0, 14)

    makeHeader(hubScroll, 2, "GENERAL")
    setScriptSwitch = makeToggleRow(hubScroll, 3, "Script ON / OFF", scriptEnabled, function(v)
        if setScript then setScript(v) end
    end, "Turns EVERYTHING off. The menu key brings it back.")
    makeToggleRow(hubScroll, 4, "⚡ FPS Boost", fpsBoostWanted, function(v)
        fpsBoostWanted = v
        if scriptEnabled and fpsBoostApply then fpsBoostApply(v) end
    end, "Lowers shadows, effects & quality. Turn off to restore.")
    makeToggleRow(hubScroll, 5, "🔊 Sound effects", soundEnabled, function(v) soundEnabled = v end)

    makeHeader(hubScroll, 6, "CONTROLS")
    local keyRow = makeRow(hubScroll, 7)
    rowLabel(keyRow, "🔑 Menu key (open / close)", 150)
    keyBox = makeSmallButton(keyRow, "🔑 " .. toggleKey, UDim2.new(0, 120, 0, 22), UDim2.new(1, -130, 0.5, -11))

    local rejoinRow = makeRow(hubScroll, 8)
    rowLabel(rejoinRow, "Rejoin the same server", 150)
    local rejoinBtn = makeSmallButton(rejoinRow, "🔄 Rejoin", UDim2.new(0, 120, 0, 22), UDim2.new(1, -130, 0.5, -11))
    rejoinBtn.MouseButton1Click:Connect(function() doRejoin(rejoinBtn) end)

    keyBox.MouseButton1Click:Connect(function()
        if capturingKey then return end
        capturingKey = true
        keyBox.Text = "Press a key..."
    end)
end

-- ===== SKIN SEKMESİ (SKIN CHANGER) =====
-- SADECE sende görünür; sunucuya hiçbir şey göndermez.
-- ReplicatedStorage.Assets.Characters içindeki karakter modellerini kendi karakterine giydirir,
-- gerçek karakterin animasyonlarını (yürüme, uçma, yetenek) kopyaya aynen aktarır.
task.spawn(function()
    local ReplicatedStorage = game:GetService("ReplicatedStorage")
    local skinPage = pages.skin

    local ACTIVE_BG   = Color3.fromRGB(30, 110, 60)
    local INACTIVE_BG = Color3.fromRGB(32, 32, 36)

    local BODY_NAMES = {
        Head = true, Torso = true, UpperTorso = true, LowerTorso = true,
        LeftUpperArm = true, LeftLowerArm = true, LeftHand = true,
        RightUpperArm = true, RightLowerArm = true, RightHand = true,
        LeftUpperLeg = true, LeftLowerLeg = true, LeftFoot = true,
        RightUpperLeg = true, RightLowerLeg = true, RightFoot = true,
        ["Left Arm"] = true, ["Right Arm"] = true, ["Left Leg"] = true, ["Right Leg"] = true,
    }

    local currentFolder = nil   -- seçili karakter klasörü (respawn'da tekrar uygulanır)
    local clone = nil
    local cloneParts = {}
    local motorPairs = {}
    local hidden = {}           -- [inst] = orijinal Transparency (gerçek gövde)
    local mode = "clone"        -- "clone" | "orig" (ragdoll / ölüm durumunda orijinali göster)
    local fpHidden = false
    local hideUntil = 0
    local lastScan = 0
    local renderConn, addedConn
    local statusLabel
    local listEntries = {}
    local skinQuery = ""

    local function setStatus(t)
        if statusLabel then statusLabel.Text = t end
    end

    local function getCharactersFolder()
        local assets = ReplicatedStorage:FindFirstChild("Assets")
        return assets and assets:FindFirstChild("Characters")
    end

    local function findMorphModel(folder)
        local morph = folder:FindFirstChild("Morph")
        if not morph then return nil end
        if morph:IsA("Model") and morph:FindFirstChildWhichIsA("BasePart", true) then return morph end
        local m = morph:FindFirstChild(folder.Name)
        if m and m:IsA("Model") then return m end
        for _, c in ipairs(morph:GetChildren()) do
            if c:IsA("Model") then return c end
        end
        return nil
    end

    -- Gerçek gövdeyi sadece bu istemcide gizle
    local function isBodyPart(d, char)
        if not d or not d:IsA("BasePart") then return false end
        if d:FindFirstAncestorOfClass("Tool") then return false end
        local p = d.Parent
        return p == char or (p ~= nil and p:IsA("Accessory")) or BODY_NAMES[d.Name] == true
    end

    -- Karakterdeki her görünür parça (oyunun kendi Morph modeli dahil) gizlenir; aletler hariç
    local function shouldHide(d)
        if d:IsA("BasePart") then
            if d.Name == "HumanoidRootPart" then return false end
            if d:FindFirstAncestorOfClass("Tool") then return false end
            return true
        elseif d:IsA("Decal") or d:IsA("Texture") then
            local par = d.Parent
            return par ~= nil and par:IsA("BasePart") and shouldHide(par)
        end
        return false
    end

    local function hideInst(d)
        if shouldHide(d) then
            if hidden[d] == nil then hidden[d] = d.Transparency end
            d.Transparency = 1
        end
    end

    local function setCloneVisible(vis)
        local v = vis and 0 or 1
        for _, inst in ipairs(cloneParts) do
            pcall(function() inst.LocalTransparencyModifier = v end)
        end
    end

    local function setMode(m)
        if m == mode then return end
        mode = m
        if m == "clone" then
            for inst in pairs(hidden) do
                if inst.Parent then inst.Transparency = 1 end
            end
            setCloneVisible(not fpHidden)
        else
            for inst, t in pairs(hidden) do
                if inst.Parent then inst.Transparency = t end
            end
            setCloneVisible(false)
        end
    end

    local function clearSkin()
        if renderConn then renderConn:Disconnect() renderConn = nil end
        if addedConn then addedConn:Disconnect() addedConn = nil end
        for inst, t in pairs(hidden) do
            if inst.Parent then inst.Transparency = t end
        end
        hidden = {}
        if clone then clone:Destroy() clone = nil end
        cloneParts = {}
        motorPairs = {}
        mode = "clone"
        fpHidden = false
    end

    -- Kökten (HumanoidRootPart) eklemlerle bağlı parçaları bul
    local function connectedParts(root, model)
        local adj = {}
        for _, d in ipairs(model:GetDescendants()) do
            if d:IsA("JointInstance") or d:IsA("WeldConstraint") then
                local a, b = d.Part0, d.Part1
                if a and b then
                    adj[a] = adj[a] or {}
                    adj[b] = adj[b] or {}
                    table.insert(adj[a], b)
                    table.insert(adj[b], a)
                end
            end
        end
        local seen = {[root] = true}
        local queue, i = {root}, 1
        while queue[i] do
            local part = queue[i]
            i += 1
            for _, n in ipairs(adj[part] or {}) do
                if not seen[n] then
                    seen[n] = true
                    queue[#queue + 1] = n
                end
            end
        end
        return seen
    end

    local function buildSkin(folder, char, hrp)
        local src = findMorphModel(folder)
        if not src then error("Morph modeli bulunamadi") end

        local newClone = src:Clone()
        newClone:SetAttribute("SW_SKIN", true)

        -- Çalışan her şeyi temizle (script, ses, humanoid vb.)
        for _, d in ipairs(newClone:GetDescendants()) do
            if d:IsA("LuaSourceContainer") or d:IsA("Humanoid") or d:IsA("Sound")
                or d:IsA("ForceField") or d:IsA("BillboardGui") then
                d:Destroy()
            end
        end

        local root = newClone:FindFirstChild("HumanoidRootPart")
            or newClone.PrimaryPart
            or newClone:FindFirstChildWhichIsA("BasePart", true)
        if not root then
            newClone:Destroy()
            error("Modelde parca yok")
        end

        -- Kopyayı gerçek karakterin tam üstüne hizala (hepsini birlikte taşır)
        local delta = hrp.CFrame * root.CFrame:Inverse()
        newClone:PivotTo(delta * newClone:GetPivot())

        local parts = {}
        for _, d in ipairs(newClone:GetDescendants()) do
            if d:IsA("BasePart") then
                d.Anchored = false
                d.CanCollide = false
                d.CanTouch = false
                d.CanQuery = false
                d.Massless = true
                table.insert(parts, d)
                table.insert(cloneParts, d)
            elseif d:IsA("Decal") then
                table.insert(cloneParts, d)
            end
        end

        -- Eklemsiz kalan aksesuarları Attachment isimlerine göre vücuda bağla
        local seen = connectedParts(root, newClone)
        for _, acc in ipairs(newClone:GetDescendants()) do
            if acc:IsA("Accessory") then
                local handle = acc:FindFirstChild("Handle")
                if handle and handle:IsA("BasePart") and not seen[handle] then
                    for _, a0 in ipairs(handle:GetChildren()) do
                        if a0:IsA("Attachment") then
                            local done = false
                            for _, part in ipairs(parts) do
                                if seen[part] and part ~= handle and not part:FindFirstAncestorOfClass("Accessory") then
                                    local a1 = part:FindFirstChild(a0.Name)
                                    if a1 and a1:IsA("Attachment") then
                                        local w = Instance.new("Weld")
                                        w.Part0 = part
                                        w.Part1 = handle
                                        w.C0 = a1.CFrame
                                        w.C1 = a0.CFrame
                                        w.Parent = handle
                                        seen[handle] = true
                                        done = true
                                        break
                                    end
                                end
                            end
                            if done then break end
                        end
                    end
                end
            end
        end

        -- Hâlâ serbest kalan parçaları sabit ofsetle köke bağla (düşüp kaybolmasın)
        for _, part in ipairs(parts) do
            if not seen[part] then
                local w = Instance.new("Weld")
                w.Part0 = root
                w.Part1 = part
                w.C0 = root.CFrame:ToObjectSpace(part.CFrame)
                w.Parent = part
            end
        end

        -- Kopya kökünü gerçek HumanoidRootPart'a bağla
        local rootWeld = Instance.new("Weld")
        rootWeld.Part0 = hrp
        rootWeld.Part1 = root
        rootWeld.Parent = root

        newClone.Parent = workspace.CurrentCamera or workspace

        -- Animasyon aynalama: isimleri aynı olan Motor6D'lerin Transform'unu kopyala
        local real = {}
        for _, d in ipairs(char:GetDescendants()) do
            if d:IsA("Motor6D") and not real[d.Name] then real[d.Name] = d end
        end
        local pairsList, total = {}, 0
        for _, d in ipairs(newClone:GetDescendants()) do
            if d:IsA("Motor6D") then
                total += 1
                if real[d.Name] then
                    table.insert(pairsList, {d, real[d.Name]})
                end
            end
        end

        clone = newClone
        motorPairs = pairsList
        return #pairsList, total
    end

    local refreshHighlight

    local function applySkin(folder)
        clearSkin()
        currentFolder = folder
        if refreshHighlight then refreshHighlight() end
        if not folder then
            setStatus("Aktif: Orijinal")
            return
        end

        local char = LocalPlayer.Character
        local hrp = char and char:FindFirstChild("HumanoidRootPart")
        if not hrp then
            setStatus("Karakter yok, respawn sonrası uygulanır")
            return
        end

        local ok, matched, total = pcall(buildSkin, folder, char, hrp)
        if not ok then
            clearSkin()
            setStatus("Hata: " .. tostring(matched))
            return
        end

        for _, d in ipairs(char:GetDescendants()) do
            hideInst(d)
        end
        hideUntil = os.clock() + 10
        lastScan = 0
        addedConn = char.DescendantAdded:Connect(function(d)
            task.defer(function()
                if not clone then return end
                -- Oyun morph modelini geç yüklüyorsa ilk 10 sn'de gelen her şeyi gizle
                if os.clock() < hideUntil or isBodyPart(d, char)
                    or ((d:IsA("Decal") or d:IsA("Texture")) and hidden[d.Parent] ~= nil) then
                    hideInst(d)
                end
                if mode == "orig" and hidden[d] ~= nil then d.Transparency = hidden[d] end
            end)
        end)

        renderConn = RunService.RenderStepped:Connect(function()
            if not clone or not clone.Parent then return end
            local c = LocalPlayer.Character
            local hum = c and c:FindFirstChildOfClass("Humanoid")
            local ragdolled = (hum == nil) or hum.Health <= 0

            for i = 1, #motorPairs do
                local pr = motorPairs[i]
                local rm = pr[2]
                if rm.Parent then
                    if rm.Enabled == false then ragdolled = true end
                    pr[1].Transform = rm.Transform
                end
            end

            setMode(ragdolled and "orig" or "clone")
            if mode ~= "clone" then return end

            local nowT = os.clock()
            if c and nowT < hideUntil and nowT - lastScan > 0.5 then
                lastScan = nowT
                for _, d in ipairs(c:GetDescendants()) do hideInst(d) end
            end

            -- Oyun şeffaflığı geri açarsa gerçek gövdeyi tekrar gizle
            for inst in pairs(hidden) do
                if inst.Parent then
                    if inst.Transparency ~= 1 then inst.Transparency = 1 end
                else
                    hidden[inst] = nil
                end
            end

            -- Birinci şahıs: kopyayı gizle (kamera kafanın içinde kalmasın)
            local cam = workspace.CurrentCamera
            local head = c and c:FindFirstChild("Head")
            local fp = (head ~= nil and cam ~= nil and (cam.CFrame.Position - head.Position).Magnitude < 1.6) == true
            if fp ~= fpHidden then
                fpHidden = fp
                setCloneVisible(not fp)
            end
        end)

        setStatus(string.format("Aktif: %s\nEşleşen eklem: %d/%d", folder.Name, matched, total))
    end

    LocalPlayer.CharacterRemoving:Connect(function()
        clearSkin()   -- seçim (currentFolder) korunur
    end)
    LocalPlayer.CharacterAdded:Connect(function(char)
        if not currentFolder or not scriptEnabled then return end
        task.spawn(function()
            char:WaitForChild("HumanoidRootPart", 10)
            task.wait(1)
            if LocalPlayer.Character == char and currentFolder and scriptEnabled then
                applySkin(currentFolder)
            end
        end)
    end)

    -- ARAMA ÇUBUĞU (oyunlar TextBox girişini bozabildiği için yazıyı kendimiz yakalıyoruz)
    local SKIN_ACTION = "SW_HUB_SKIN_SEARCH"
    local skinSearching = false
    local skinCursor = true

    local skinBar = Instance.new("Frame")
    skinBar.Name = "SkinSearchBar"
    skinBar.Position = UDim2.new(0, 10, 0, 10)
    skinBar.Size = UDim2.new(1, -20, 0, 28)
    skinBar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
    skinBar.BorderSizePixel = 0
    skinBar.Parent = skinPage
    Instance.new("UICorner", skinBar).CornerRadius = UDim.new(0, 6)
    local skinBarStroke = Instance.new("UIStroke", skinBar)
    skinBarStroke.Color = Color3.fromRGB(55, 55, 55)
    skinBarStroke.Thickness = 1

    local skinBarBtn = Instance.new("TextButton")
    skinBarBtn.Size = UDim2.new(1, -30, 1, 0)
    skinBarBtn.BackgroundTransparency = 1
    skinBarBtn.AutoButtonColor = false
    skinBarBtn.Font = Enum.Font.GothamMedium
    skinBarBtn.TextSize = 12
    skinBarBtn.TextXAlignment = Enum.TextXAlignment.Left
    skinBarBtn.TextTruncate = Enum.TextTruncate.AtEnd
    skinBarBtn.Text = ""
    skinBarBtn.Parent = skinBar
    local skinBarPad = Instance.new("UIPadding")
    skinBarPad.PaddingLeft = UDim.new(0, 10)
    skinBarPad.Parent = skinBarBtn

    local skinClearBtn = Instance.new("TextButton")
    skinClearBtn.Size = UDim2.new(0, 22, 0, 22)
    skinClearBtn.Position = UDim2.new(1, -26, 0.5, -11)
    skinClearBtn.BackgroundColor3 = Color3.fromRGB(45, 45, 45)
    skinClearBtn.BorderSizePixel = 0
    skinClearBtn.Text = "✕"
    skinClearBtn.TextColor3 = Color3.new(1, 1, 1)
    skinClearBtn.Font = Enum.Font.GothamBold
    skinClearBtn.TextSize = 11
    skinClearBtn.Visible = false
    skinClearBtn.Parent = skinBar
    Instance.new("UICorner", skinClearBtn).CornerRadius = UDim.new(0, 5)

    local function applyFilter()
        for _, e in ipairs(listEntries) do
            e.btn.Visible = skinQuery == "" or e.key:find(skinQuery, 1, true) ~= nil
        end
    end

    local function renderSkinSearch()
        if skinQuery == "" and not skinSearching then
            skinBarBtn.Text = "🔍 Karakter ara..."
            skinBarBtn.TextColor3 = Color3.fromRGB(120, 120, 120)
        else
            skinBarBtn.Text = skinQuery .. ((skinSearching and skinCursor) and "|" or "")
            skinBarBtn.TextColor3 = Color3.new(1, 1, 1)
        end
        skinClearBtn.Visible = skinQuery ~= ""
        skinBarStroke.Color = skinSearching and Color3.fromRGB(100, 149, 237) or Color3.fromRGB(55, 55, 55)
    end

    local function stopSkinSearch()
        if not skinSearching then return end
        skinSearching = false
        pcall(function() ContextActionService:UnbindAction(SKIN_ACTION) end)
        renderSkinSearch()
    end

    local function skinSearchAction(_, state, input)
        if state ~= Enum.UserInputState.Begin then
            return Enum.ContextActionResult.Sink
        end
        local name = input.KeyCode.Name
        local shift = UserInputService:IsKeyDown(Enum.KeyCode.LeftShift)
            or UserInputService:IsKeyDown(Enum.KeyCode.RightShift)
        if name == "Return" or name == "KeypadEnter" or name == "Escape" then
            stopSkinSearch()
            return Enum.ContextActionResult.Sink
        elseif name == "Backspace" then
            skinQuery = skinQuery:sub(1, -2)
        else
            local ch
            if #name == 1 and name:match("%a") then ch = name:lower()
            elseif SEARCH_DIGITS[name] then ch = SEARCH_DIGITS[name]
            elseif name == "Space" then ch = " "
            elseif name == "Minus" then ch = shift and "_" or "-"
            elseif name == "Semicolon" then ch = shift and ":" or ";"
            elseif name == "Quote" then ch = "'"
            elseif name == "Period" then ch = "."
            end
            if ch then skinQuery = (skinQuery .. ch):sub(1, 40) end
        end
        skinCursor = true
        applyFilter()
        renderSkinSearch()
        return Enum.ContextActionResult.Sink
    end

    local function startSkinSearch()
        if skinSearching then return end
        skinSearching = true
        skinCursor = true
        pcall(function()
            ContextActionService:BindActionAtPriority(SKIN_ACTION, skinSearchAction, false,
                Enum.ContextActionPriority.High.Value + 100, table.unpack(SEARCH_KEYS))
        end)
        renderSkinSearch()
    end

    skinBarBtn.MouseButton1Click:Connect(startSkinSearch)
    skinClearBtn.MouseButton1Click:Connect(function()
        skinQuery = ""
        applyFilter()
        renderSkinSearch()
    end)

    -- Çubuğun dışına tıklayınca yazmayı bitir
    UserInputService.InputBegan:Connect(function(input)
        if skinSearching and input.UserInputType == Enum.UserInputType.MouseButton1 then
            local m = UserInputService:GetMouseLocation()
            local pos, size = skinBar.AbsolutePosition, skinBar.AbsoluteSize
            local inside = m.X >= pos.X and m.X <= pos.X + size.X and m.Y >= pos.Y and m.Y <= pos.Y + size.Y
            if not inside then stopSkinSearch() end
        end
    end)

    -- İmleç yanıp sönsün; panel kapanırsa / sekme değişirse tuş yakalamayı bırak
    task.spawn(function()
        while gui.Parent do
            task.wait(0.4)
            if skinSearching then
                if not listFrame.Visible or not skinPage.Visible then
                    stopSkinSearch()
                else
                    skinCursor = not skinCursor
                    renderSkinSearch()
                end
            end
        end
    end)

    -- KARAKTER LİSTESİ
    local skinScroll = Instance.new("ScrollingFrame")
    skinScroll.Position = UDim2.new(0, 10, 0, 46)
    skinScroll.Size = UDim2.new(1, -20, 1, -140)
    skinScroll.CanvasSize = UDim2.new(0, 0, 0, 0)
    skinScroll.BackgroundTransparency = 1
    skinScroll.BorderSizePixel = 0
    skinScroll.ScrollBarThickness = 3
    skinScroll.ScrollBarImageColor3 = Color3.fromRGB(80, 80, 80)
    skinScroll.Parent = skinPage

    local skinLayout = Instance.new("UIListLayout")
    skinLayout.Padding = UDim.new(0, 4)
    skinLayout.SortOrder = Enum.SortOrder.LayoutOrder
    skinLayout.Parent = skinScroll
    skinLayout:GetPropertyChangedSignal("AbsoluteContentSize"):Connect(function()
        skinScroll.CanvasSize = UDim2.new(0, 0, 0, skinLayout.AbsoluteContentSize.Y + 6)
    end)

    local skinResetBtn = makeSmallButton(skinPage, "↩ Orijinal", UDim2.new(0.5, -14, 0, 28), UDim2.new(0, 10, 1, -86))
    local skinReapplyBtn = makeSmallButton(skinPage, "🔄 Yenile", UDim2.new(0.5, -14, 0, 28), UDim2.new(0.5, 4, 1, -86))

    statusLabel = Instance.new("TextLabel")
    statusLabel.Size = UDim2.new(1, -24, 0, 40)
    statusLabel.Position = UDim2.new(0, 12, 1, -52)
    statusLabel.BackgroundTransparency = 1
    statusLabel.Text = "Aktif: Orijinal"
    statusLabel.TextColor3 = Color3.fromRGB(150, 150, 150)
    statusLabel.Font = Enum.Font.GothamMedium
    statusLabel.TextSize = 11
    statusLabel.TextWrapped = true
    statusLabel.TextXAlignment = Enum.TextXAlignment.Left
    statusLabel.TextYAlignment = Enum.TextYAlignment.Top
    statusLabel.Parent = skinPage

    refreshHighlight = function()
        for _, e in ipairs(listEntries) do
            e.btn.BackgroundColor3 = (e.folder == currentFolder) and ACTIVE_BG or INACTIVE_BG
        end
    end

    local function populate()
        for _, e in ipairs(listEntries) do e.btn:Destroy() end
        listEntries = {}
        local chars = getCharactersFolder()
        if not chars then
            setStatus("ReplicatedStorage.Assets.Characters bulunamadı")
            return
        end
        local folders = {}
        for _, f in ipairs(chars:GetChildren()) do
            if findMorphModel(f) then table.insert(folders, f) end
        end
        table.sort(folders, function(a, b) return a.Name:lower() < b.Name:lower() end)
        for i, f in ipairs(folders) do
            local b = Instance.new("TextButton")
            b.LayoutOrder = i
            b.Size = UDim2.new(1, -4, 0, 30)
            b.BackgroundColor3 = INACTIVE_BG
            b.TextColor3 = Color3.new(1, 1, 1)
            b.Font = Enum.Font.GothamMedium
            b.TextSize = 12
            b.TextXAlignment = Enum.TextXAlignment.Left
            b.TextTruncate = Enum.TextTruncate.AtEnd
            b.Text = f.Name
            b.BorderSizePixel = 0
            b.AutoButtonColor = true
            b.Parent = skinScroll
            Instance.new("UICorner", b).CornerRadius = UDim.new(0, 8)
            local pad = Instance.new("UIPadding", b)
            pad.PaddingLeft = UDim.new(0, 12)
            pad.PaddingRight = UDim.new(0, 12)
            b.MouseButton1Click:Connect(function() applySkin(f) end)
            table.insert(listEntries, {btn = b, folder = f, key = f.Name:lower()})
        end
        applyFilter()
        refreshHighlight()
    end

    skinResetBtn.MouseButton1Click:Connect(function() applySkin(nil) end)
    skinReapplyBtn.MouseButton1Click:Connect(function()
        if currentFolder then applySkin(currentFolder) end
    end)

    -- Dışarıya açılan fonksiyonlar (SCRIPT ON/OFF ve sekme geçişi kullanır)
    skinPopulate = populate
    skinStopSearch = stopSkinSearch
    skinSetEnabled = function(on)
        if on then
            if currentFolder and LocalPlayer.Character then applySkin(currentFolder) end
        else
            clearSkin()   -- seçim korunur, script tekrar açılınca geri giydirilir
            setStatus("Script OFF")
        end
    end

    renderSkinSearch()
    pcall(populate)
end)

-- Sekme geçişi
local TAB_ACTIVE_TEXT = Color3.new(1, 1, 1)
local TAB_IDLE_TEXT   = Color3.fromRGB(140, 140, 140)
local function setTab(key)
    if key ~= "players" and stopSearch then stopSearch() end
    if key ~= "skin" and skinStopSearch then skinStopSearch() end
    if key == "skin" and skinPopulate then skinPopulate() end
    for k, page in pairs(pages) do
        page.Visible = (k == key)
    end
    for k, b in pairs(tabButtons) do
        local active = (k == key)
        b.BackgroundTransparency = active and 0 or 1
        b.Label.TextColor3 = active and TAB_ACTIVE_TEXT or TAB_IDLE_TEXT
        b.Accent.Visible = active
    end
end
for key, b in pairs(tabButtons) do
    b.MouseButton1Click:Connect(function() setTab(key) end)
end
setTab("hub")

-- BİLDİRİM SİSTEMİ
local NOTIF_W     = 300
local NOTIF_H     = 52
local NOTIF_GAP   = 6
local NOTIF_BOT   = 14
local showTime    = 3.5
local fadeTime    = 0.4
local activeNotifs = {}
local damageCooldown = {}
local friendDamageConnections = {}
local rowHealthConnections = {}
local characterNameCache = {}
local lastTextUpdate = {}
forceESPRefresh = function()
    for k in pairs(lastTextUpdate) do lastTextUpdate[k] = nil end
end
local COOLDOWN    = 10

local function repositionNotifs()
    local y = NOTIF_BOT
    for i = #activeNotifs, 1, -1 do
        local n = activeNotifs[i]
        if n and n.Parent then
            TweenService:Create(n, TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
                Position = UDim2.new(1, -(NOTIF_W + 10), 1, -(y + NOTIF_H))
            }):Play()
            y = y + NOTIF_H + NOTIF_GAP
        end
    end
end

local function createNotification(text, accentColor)
    if not scriptEnabled then return end
    accentColor = accentColor or Color3.fromRGB(0, 140, 255)

    local frame = Instance.new("Frame")
    frame.Size = UDim2.new(0, NOTIF_W, 0, NOTIF_H)
    frame.Position = UDim2.new(1, -(NOTIF_W + 10), 1, 80)
    frame.BackgroundColor3 = Color3.fromRGB(18, 18, 18)
    frame.BorderSizePixel = 0
    frame.Parent = gui
    Instance.new("UICorner", frame).CornerRadius = UDim.new(0, 10)
    local fStroke = Instance.new("UIStroke", frame)
    fStroke.Color = Color3.fromRGB(60, 60, 60)
    fStroke.Thickness = 1

    -- Üst progress bar
    local barBg = Instance.new("Frame")
    barBg.Size = UDim2.new(1, -12, 0, 3)
    barBg.Position = UDim2.new(0, 6, 0, 0)
    barBg.BackgroundColor3 = Color3.fromRGB(40, 40, 40)
    barBg.BorderSizePixel = 0
    barBg.ZIndex = 3
    barBg.Parent = frame
    Instance.new("UICorner", barBg).CornerRadius = UDim.new(1, 0)

    local bar = Instance.new("Frame")
    bar.Size = UDim2.new(1, 0, 1, 0)
    bar.BackgroundColor3 = accentColor
    bar.BorderSizePixel = 0
    bar.ZIndex = 4
    bar.Parent = barBg
    Instance.new("UICorner", bar).CornerRadius = UDim.new(1, 0)

    -- Sol aksanı
    local accent = Instance.new("Frame")
    accent.Size = UDim2.new(0, 3, 1, -14)
    accent.Position = UDim2.new(0, 7, 0, 7)
    accent.BackgroundColor3 = accentColor
    accent.BorderSizePixel = 0
    accent.ZIndex = 2
    accent.Parent = frame
    Instance.new("UICorner", accent).CornerRadius = UDim.new(1, 0)

    -- Yazı
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, -22, 1, -6)
    label.Position = UDim2.new(0, 16, 0, 3)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(225, 225, 225)
    label.Font = Enum.Font.GothamMedium
    label.TextSize = 13
    label.TextXAlignment = Enum.TextXAlignment.Left
    label.TextYAlignment = Enum.TextYAlignment.Center
    label.TextWrapped = true
    label.ZIndex = 2
    label.Text = text
    label.Parent = frame

    if soundEnabled then pcall(function() clickSound:Play() end) end

    table.insert(activeNotifs, 1, frame)
    repositionNotifs()

    TweenService:Create(bar, TweenInfo.new(showTime, Enum.EasingStyle.Linear), {Size = UDim2.new(0, 0, 1, 0)}):Play()

    task.delay(showTime, function()
        TweenService:Create(frame,   TweenInfo.new(fadeTime), {BackgroundTransparency = 1}):Play()
        TweenService:Create(label,   TweenInfo.new(fadeTime), {TextTransparency = 1}):Play()
        TweenService:Create(fStroke, TweenInfo.new(fadeTime), {Transparency = 1}):Play()
        TweenService:Create(accent,  TweenInfo.new(fadeTime), {BackgroundTransparency = 1}):Play()
        TweenService:Create(barBg,   TweenInfo.new(fadeTime), {BackgroundTransparency = 1}):Play()
        TweenService:Create(bar,     TweenInfo.new(fadeTime), {BackgroundTransparency = 1}):Play()
        task.delay(fadeTime + 0.05, function()
            for i, n in ipairs(activeNotifs) do
                if n == frame then table.remove(activeNotifs, i) break end
            end
            if frame and frame.Parent then frame:Destroy() end
            repositionNotifs()
        end)
    end)
end

-- RADYASYON EFEKTİ
local function setupRadioactiveEffect(plr)
    if not radioEnabled or not scriptEnabled then return end
    local char = plr.Character
    if not char then return end
    local root = char:FindFirstChild("HumanoidRootPart")
    if not root then return end
    if root:FindFirstChild("SW_RADIO") then return end

    local bb = Instance.new("BillboardGui")
    bb.Name = "SW_RADIO"
    bb.Size = UDim2.new(0, 50, 0, 50)
    bb.StudsOffset = Vector3.new(0, 7.5, 0)
    bb.AlwaysOnTop = true
    bb.Parent = root

    local lbl = Instance.new("TextLabel")
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.Text = "☢"
    lbl.TextColor3 = Color3.fromRGB(255, 165, 0)
    lbl.Font = Enum.Font.GothamBlack
    lbl.TextScaled = true
    lbl.Parent = bb

    local tw = TweenService:Create(lbl,
        TweenInfo.new(0.4, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
        {TextTransparency = 0.5})
    tw:Play()

    task.delay(6, function()
        tw:Cancel()
        if bb and bb.Parent then bb:Destroy() end
    end)
end

-- ARKADAŞ HASAR DİNLEYİCİSİ
local function setupFriendDamageListener(plr)
    local char = plr.Character
    if not char then return end
    local hum = char:FindFirstChildOfClass("Humanoid")
    if not hum then return end

    local existing = friendDamageConnections[plr]
    if existing and existing.humanoid == hum and existing.connection.Connected then
        return
    end
    if existing and existing.connection then
        existing.connection:Disconnect()
    end

    local lastHP = hum.Health
    local healthConnection
    healthConnection = hum.HealthChanged:Connect(function(newHP)
        if getClass(plr) ~= "friend" then lastHP = newHP return end
        if newHP < lastHP and not damageCooldown[plr.Name] then
            damageCooldown[plr.Name] = true
            local dist = 0
            local lr = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
            local pr = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
            if lr and pr then
                dist = math.floor((lr.Position - pr.Position).Magnitude)
            end
            if damageAlertsEnabled then
                createNotification("⚠ " .. plr.Name .. " took damage! (" .. dist .. "m)", FRIEND_COLOR)
            end
            setupRadioactiveEffect(plr)
            task.delay(COOLDOWN, function() damageCooldown[plr.Name] = nil end)
        end
        lastHP = newHP
    end)
    friendDamageConnections[plr] = {
        humanoid = hum,
        connection = healthConnection
    }
end

-- OYUNCU SATIRLARI
-- Satır arka planı sabit koyu kalır; friend / enemy seçilince sadece İSİM rengi değişir.
local rowUI = {}
local ROW_IDLE  = Color3.fromRGB(27, 27, 31)
local ROW_HOVER = Color3.fromRGB(37, 37, 43)

local function applyButtonColor(plr, btn)
    local ui = rowUI[plr]
    if not ui then return end
    local class = getClass(plr)
    ui.name.TextColor3 = class == "friend" and FRIEND_COLOR
        or class == "enemy" and ENEMY_COLOR
        or NEUTRAL_COLOR
end

local function refreshButton(plr, btn)
    local ui = rowUI[plr]
    if not ui then return end
    local hp = 0
    if plr.Character and plr.Character:FindFirstChildOfClass("Humanoid") then
        hp = math.floor(plr.Character:FindFirstChildOfClass("Humanoid").Health)
    end
    local dist = 0
    local lr = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local pr = plr.Character and plr.Character:FindFirstChild("HumanoidRootPart")
    if lr and pr then
        dist = math.floor((lr.Position - pr.Position).Magnitude)
    end
    local humR = plr.Character and plr.Character:FindFirstChildOfClass("Humanoid")
    local dead = humR ~= nil and humR.Health <= 0
    local text = (dead and "💀 DEAD" or ("♥ " .. hp)) .. "    " .. dist .. "m"
    if ui.stat.Text ~= text then ui.stat.Text = text end
end

local function refreshButtonFull(plr, btn)
    applyButtonColor(plr, btn)
    refreshButton(plr, btn)
end

-- SINIF MENÜSÜ: isme tıklayınca küçük bir tab açılır (Friend / Enemy / Neutral)
local CLASS_MENU_W, CLASS_MENU_H = 124, 100
local classMenu = Instance.new("Frame")
classMenu.Name = "ClassMenu"
classMenu.Size = UDim2.new(0, CLASS_MENU_W, 0, CLASS_MENU_H)
classMenu.BackgroundColor3 = Color3.fromRGB(20, 20, 24)
classMenu.BorderSizePixel = 0
classMenu.Visible = false
classMenu.ZIndex = 50
classMenu.Parent = gui
-- Menünün arkasında tam ekran görünmez buton: menü açıkken dışarı basınca menüyü kapatır (koordinat kontrolü yok)
local classCatcher = Instance.new("TextButton")
classCatcher.Name = "ClassMenuCatcher"
classCatcher.Size = UDim2.new(1, 0, 1, 0)
classCatcher.BackgroundTransparency = 1
classCatcher.BorderSizePixel = 0
classCatcher.AutoButtonColor = false
classCatcher.Text = ""
classCatcher.ZIndex = 40
classCatcher.Visible = false
classCatcher.Parent = gui
Instance.new("UICorner", classMenu).CornerRadius = UDim.new(0, 8)
local classMenuStroke = Instance.new("UIStroke", classMenu)
classMenuStroke.Color = Color3.fromRGB(60, 60, 68)
classMenuStroke.Thickness = 1
local classMenuLayout = Instance.new("UIListLayout")
classMenuLayout.Padding = UDim.new(0, 4)
classMenuLayout.SortOrder = Enum.SortOrder.LayoutOrder
classMenuLayout.Parent = classMenu
local classMenuPad = Instance.new("UIPadding")
classMenuPad.PaddingTop = UDim.new(0, 4)
classMenuPad.PaddingBottom = UDim.new(0, 4)
classMenuPad.PaddingLeft = UDim.new(0, 4)
classMenuPad.PaddingRight = UDim.new(0, 4)
classMenuPad.Parent = classMenu

local classMenuFor, classMenuClosedFor, classMenuClosedAt = nil, nil, 0
local classMenuBtns = {}
local MENU_IDLE, MENU_ACTIVE = Color3.fromRGB(30, 30, 36), Color3.fromRGB(55, 55, 64)

local function closeClassMenu()
    if classMenuFor then
        classMenuClosedFor = classMenuFor
        classMenuClosedAt = os.clock()
    end
    classMenuFor = nil
    classMenu.Visible = false
    classCatcher.Visible = false
end

for i, opt in ipairs({
    {"friend", "Friend", FRIEND_COLOR},
    {"enemy", "Enemy", ENEMY_COLOR},
    {"neutral", "Neutral", NEUTRAL_COLOR},
}) do
    local b = Instance.new("TextButton")
    b.LayoutOrder = i
    b.Size = UDim2.new(1, 0, 0, 28)
    b.BackgroundColor3 = MENU_IDLE
    b.BorderSizePixel = 0
    b.AutoButtonColor = false
    b.Text = opt[2]
    b.TextColor3 = opt[3]
    b.Font = Enum.Font.GothamBold
    b.TextSize = 12
    b.ZIndex = 51
    b.Parent = classMenu
    Instance.new("UICorner", b).CornerRadius = UDim.new(0, 6)
    classMenuBtns[opt[1]] = b
    b.MouseButton1Down:Connect(function()
        local plr = classMenuFor
        if plr then
            setClass(plr, opt[1])
            local row = playerButtons[plr]
            if row then refreshButtonFull(plr, row) end
            if opt[1] == "friend" then setupFriendDamageListener(plr) end
        end
        closeClassMenu()
    end)
end

local function openClassMenu(plr, row)
    classMenuFor = plr
    local cur = getClass(plr)
    for key, b in pairs(classMenuBtns) do
        b.BackgroundColor3 = (key == cur) and MENU_ACTIVE or MENU_IDLE
    end
    local pos, size = row.AbsolutePosition, row.AbsoluteSize
    local x = pos.X + size.X - CLASS_MENU_W - 8
    local y = pos.Y + size.Y + 4
    local limit = listFrame.AbsolutePosition.Y + listFrame.AbsoluteSize.Y - 6
    if y + CLASS_MENU_H > limit then y = pos.Y - CLASS_MENU_H - 4 end
    classMenu.Position = UDim2.fromOffset(x, y)
    classMenu.Visible = true
    classCatcher.Visible = true
end

-- dışarı basınca / panel kapanınca / sekme değişince menü kapanır
classCatcher.MouseButton1Down:Connect(closeClassMenu)
listFrame:GetPropertyChangedSignal("Visible"):Connect(closeClassMenu)
playersPage:GetPropertyChangedSignal("Visible"):Connect(closeClassMenu)

local function createPlayerRow(plr)
    if plr == LocalPlayer then return end
    if playerButtons[plr] then return end

    local btn = Instance.new("TextButton")
    btn.Size = UDim2.new(1, -4, 0, 34)
    btn.BackgroundColor3 = ROW_IDLE
    btn.BorderSizePixel = 0
    btn.AutoButtonColor = false
    btn.Text = ""
    btn.ClipsDescendants = true
    btn.Parent = scrolling
    Instance.new("UICorner", btn).CornerRadius = UDim.new(0, 8)
    local bs = Instance.new("UIStroke", btn)
    bs.Color = Color3.fromRGB(44, 44, 50)
    bs.Thickness = 1

    local nameLbl = Instance.new("TextLabel")
    nameLbl.BackgroundTransparency = 1
    nameLbl.Position = UDim2.new(0, 12, 0, 0)
    nameLbl.Size = UDim2.new(1, -136, 1, 0)
    nameLbl.Text = plr.Name
    nameLbl.Font = Enum.Font.GothamBold
    nameLbl.TextSize = 13
    nameLbl.TextXAlignment = Enum.TextXAlignment.Left
    nameLbl.TextTruncate = Enum.TextTruncate.AtEnd
    nameLbl.TextColor3 = NEUTRAL_COLOR
    nameLbl.Parent = btn

    local statLbl = Instance.new("TextLabel")
    statLbl.BackgroundTransparency = 1
    statLbl.Position = UDim2.new(1, -124, 0, 0)
    statLbl.Size = UDim2.new(0, 112, 1, 0)
    statLbl.Text = ""
    statLbl.Font = Enum.Font.GothamMedium
    statLbl.TextSize = 11
    statLbl.TextXAlignment = Enum.TextXAlignment.Right
    statLbl.TextColor3 = Color3.new(1, 1, 1)
    statLbl.Parent = btn

    rowUI[plr] = {name = nameLbl, stat = statLbl}
    btn.MouseEnter:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = ROW_HOVER}):Play()
    end)
    btn.MouseLeave:Connect(function()
        TweenService:Create(btn, TweenInfo.new(0.12), {BackgroundColor3 = ROW_IDLE}):Play()
    end)

    playerButtons[plr] = btn
    refreshButtonFull(plr, btn)
    btn.Visible = matchesSearch(plr)

    btn.MouseButton1Click:Connect(function()
        openClassMenu(plr, btn)
    end)

    local function onCharAdded(char)
        local hum = char:WaitForChild("Humanoid")
        if rowHealthConnections[plr] then
            rowHealthConnections[plr]:Disconnect()
            rowHealthConnections[plr] = nil
        end
        rowHealthConnections[plr] = hum.HealthChanged:Connect(function()
            if playerButtons[plr] then refreshButton(plr, playerButtons[plr]) end
        end)
        -- Lobiden oyuna geçince friend ise damage listener yeniden kur
        if getClass(plr) == "friend" then
            task.wait(0.5)
            setupFriendDamageListener(plr)
        end
    end
    if plr.Character then onCharAdded(plr.Character) end
    plr.CharacterAdded:Connect(onCharAdded)
end

-- Roblox arkadaşlarını friend olarak işaretle
local friendSet = {}
pcall(function()
    local pages = Players:GetFriendsAsync(LocalPlayer.UserId)
    while true do
        for _, info in pairs(pages:GetCurrentPage()) do
            friendSet[info.Username] = true
        end
        if pages.IsFinished then break end
        pages:AdvanceToNextPageAsync()
    end
end)

local function autoFriend(plr)
    if friendSet[plr.Name] and getClass(plr) == "neutral" then
        setClass(plr, "friend")
        if playerButtons[plr] then
            refreshButtonFull(plr, playerButtons[plr])
        end
        setupFriendDamageListener(plr)
    end
end

-- GÖRÜNMEZ OYUNCU DESTEĞİ: karakteri / parçayı farklı yerlerde ara
local charCache, lastSearch = {}, {}
local function isUsableChar(c)
    if not c then return false end
    return c:FindFirstChildWhichIsA("BasePart", true) ~= nil
end
local function getChar(plr)
    local c = plr.Character
    if isUsableChar(c) then charCache[plr] = c return c end
    local cached = charCache[plr]
    if isUsableChar(cached) then return cached end
    -- Pahalı aramayı saniyede 1 kez yap
    local now = os.clock()
    if lastSearch[plr] and now - lastSearch[plr] < 1 then return nil end
    lastSearch[plr] = now
    local names = {plr.Name, plr.DisplayName}
    for _, n in ipairs(names) do
        local m = workspace:FindFirstChild(n, true)
        if m and m:IsA("Model") and isUsableChar(m) then charCache[plr] = m return m end
    end
    if getnilinstances then
        for _, v in ipairs(getnilinstances()) do
            if v:IsA("Model") and (v.Name == plr.Name or v.Name == plr.DisplayName) and isUsableChar(v) then
                charCache[plr] = v
                return v
            end
        end
    end
    return nil
end
local function getRoot(char)
    if not char then return nil end
    return char:FindFirstChild("HumanoidRootPart")
        or char:FindFirstChild("Head")
        or char:FindFirstChild("Torso")
        or char:FindFirstChild("UpperTorso")
        or char:FindFirstChildWhichIsA("BasePart")
end
local createESP -- forward declaration

for _, plr in pairs(Players:GetPlayers()) do
    createPlayerRow(plr)
    autoFriend(plr)
end
Players.PlayerAdded:Connect(function(plr)
    createPlayerRow(plr)
    autoFriend(plr)
    -- Yeni gelen oyuncunun karakteri henüz yüklenmemiş olabilir; yüklenince ESP kur
    task.wait(0.5)
    createESP(plr)
end)
Players.PlayerRemoving:Connect(function(plr)
    if playerButtons[plr] then
        playerButtons[plr]:Destroy()
        playerButtons[plr] = nil
    end
    rowUI[plr] = nil
    if classMenuFor == plr then closeClassMenu() end
    playerClasses[plr.Name] = nil
    damageCooldown[plr.Name] = nil
    charNames[plr] = nil
    characterNameCache[plr] = nil
    lastTextUpdate[plr] = nil
    statusInfo.cache[plr] = nil

    local damageEntry = friendDamageConnections[plr]
    if damageEntry and damageEntry.connection then
        damageEntry.connection:Disconnect()
    end
    friendDamageConnections[plr] = nil

    if rowHealthConnections[plr] then
        rowHealthConnections[plr]:Disconnect()
        rowHealthConnections[plr] = nil
    end
end)

-- ESP OLUŞTUR
local espGui = Instance.new("ScreenGui")
espGui.Name = "SW_ESP_GUI"
espGui.ResetOnSpawn = false
espGui.IgnoreGuiInset = true
espGui.DisplayOrder = 999
pcall(function() espGui.Parent = (gethui and gethui()) or game:GetService("CoreGui") end)
if not espGui.Parent then espGui.Parent = LocalPlayer:WaitForChild("PlayerGui") end
local espFrames = {}

-- ESP ON/OFF: SADECE oyuncu yazılarını (ESP) açar / kapatır. Bildirim, VFX, panel vs. etkilenmez.
setESPOn = function(on)
    espEnabled = on
    espGui.Enabled = on and scriptEnabled
end

-- SCRIPT ON/OFF: HER ŞEYİ kapatır (ESP, VFX, bildirim, radyasyon, panel).
-- Menü tuşuna (varsayılan PageDown) tekrar basınca script açılır, panel geri gelir.
-- Her özelliğin kendi ON/OFF ayarı korunur.
setScript = function(on)
    scriptEnabled = on
    espGui.Enabled = on and espEnabled
    if setScriptSwitch then setScriptSwitch(on) end
    setPanelVisible(on)
    if fpsBoostApply then fpsBoostApply(on and fpsBoostWanted) end
    if skinSetEnabled then skinSetEnabled(on) end
    if on then
        if vfx.enabled and vfxRescan then vfxRescan() end
    else
        -- ekranda kalan bildirimleri sil
        for k = #activeNotifs, 1, -1 do
            local n = activeNotifs[k]
            if n and n.Parent then n:Destroy() end
            table.remove(activeNotifs, k)
        end
        -- oyuncuların üstündeki ☢ radyasyon işaretlerini sil
        for _, plr in ipairs(Players:GetPlayers()) do
            local c = plr.Character
            local r = c and c:FindFirstChild("HumanoidRootPart")
            local mark = r and r:FindFirstChild("SW_RADIO")
            if mark then mark:Destroy() end
        end
    end
end

createESP = function(plr)
    if espFrames[plr] then return espFrames[plr] end
    local esp = Instance.new("Frame")
    esp.Name = "SW_ESP"
    esp.AnchorPoint = Vector2.new(0.5, 1)
    esp.Size = UDim2.new(0, 280, 0, 60)
    esp.BackgroundTransparency = 1
    esp.Visible = false
    esp.Parent = espGui

    local uiScale = Instance.new("UIScale")
    uiScale.Scale = 1
    uiScale.Parent = esp

    local lbl = Instance.new("TextLabel")
    lbl.Name = "Label"
    lbl.Size = UDim2.new(1, 0, 1, 0)
    lbl.BackgroundTransparency = 1
    lbl.TextSize = 13
    lbl.TextWrapped = true
    lbl.TextXAlignment = Enum.TextXAlignment.Center
    lbl.TextYAlignment = Enum.TextYAlignment.Bottom
    lbl.Font = Enum.Font.GothamBold
    lbl.TextStrokeTransparency = 0.35
    lbl.Parent = esp
    espFrames[plr] = esp
    return esp
end

Players.PlayerRemoving:Connect(function(plr)
    if espFrames[plr] then espFrames[plr]:Destroy() espFrames[plr] = nil end
    charCache[plr] = nil
    lastSearch[plr] = nil
end)

-- KARAKTER İSMİNE GÖRE RENK
-- Sadece buradaki karakterlere özel renk verilir; listede olmayanlar beyaz kalır.
-- İsimler küçük harfle yazılır. Yeni karakter eklemek için bir satır eklemen yeterli.
local CHARACTER_COLORS = {
    ["jean grey: dark phoenix"] = "#FF8C1A",
    ["dark phoenix"] = "#FF8C1A",
    ["dark phoenix: x-men"] = "#FF8C1A",
    ["jean grey: phoenix force"] = "#FFD93D",
    ["phoenix force: eternal flame"] = "#FFD93D",
    ["phoenix force: queen in black"] = "#FFD93D",
    ["agatha harkness: 50's"] = "#A855F7",
    ["agatha harkness: all along"] = "#A855F7",
    ["invisible woman"] = "#D8A7B1",
    ["susan: christmas 2022"] = "#D8A7B1",
    ["malice"] = "#D8A7B1",
    ["audrey: the good witch"] = "#FF69B4",
    ["selene gallio"] = "#A60F2D",
    ["selene gallio: summertime queen"] = "#A60F2D",
    ["madelyne pryor"] = "#2F8F6F",
    ["madelyne pryor: wardrobe"] = "#2F8F6F",
    ["madelyne pryor: the green witch"] = "#2F8F6F",
    ["scarlet witch"] = "#E5253D",
    ["scarlet witch: multiverse of madness"] = "#E5253D",
    ["scarlet witch: corrupted"] = "#E5253D",
    ["scarlet witch: hellfire gala"] = "#E5253D",
    ["scarlet witch: fortune teller"] = "#E5253D",
    ["scarlet witch: 50's"] = "#E5253D",
    ["wanda maximoff: earth 838"] = "#E5253D",
}
local function characterColorHex(name)
    local key = tostring(name):lower()
    key = key:gsub("\226\128\153", "'"):gsub("\226\128\152", "'")  -- ’ ‘ -> '
    key = key:gsub("^%s+", ""):gsub("%s+$", "")
    return CHARACTER_COLORS[key] or "#FFFFFF"
end

-- Character-name lookup is cached per character so GetDescendants is not
-- repeatedly called on every rendered frame.
local function getCharacterName(plr, char)
    local cached = characterNameCache[plr]
    if cached and cached.character == char then
        return cached.name
    end

    local characterName = plr:GetAttribute("CharacterName")
        or plr:GetAttribute("SelectedCharacter")
        or plr:GetAttribute("Character")
        or char:GetAttribute("CharacterName")
        or char:GetAttribute("SelectedCharacter")
        or char:GetAttribute("Character")

    if not characterName then
        for _, container in ipairs({plr, char}) do
            local value = container:FindFirstChild("CharacterName")
                or container:FindFirstChild("SelectedCharacter")
                or container:FindFirstChild("Character")
            if value and value:IsA("StringValue") then
                characterName = value.Value
                break
            end
        end
    end

    if not characterName then
        for _, item in ipairs(char:GetDescendants()) do
            if item:IsA("StringValue") then
                local key = item.Name:lower()
                if key:find("character") or key:find("hero") or key:find("champion") then
                    characterName = item.Value
                    if characterName ~= "" then break end
                end
            end
        end
    end

    characterName = characterName and tostring(characterName) or ""
    characterNameCache[plr] = {character = char, name = characterName}
    return characterName
end

-- KALKAN / ÖLÜ TESPİTİ (tek tablo: local sınırını aşmamak için)
statusInfo.detectShield = function(plr, char)
    if char:FindFirstChildOfClass("ForceField") then return true end
    for _, holder in ipairs({plr, char}) do
        for name, value in pairs(holder:GetAttributes()) do
            if name:lower():find("shield") then
                if value == true or (type(value) == "number" and value > 0) then
                    return true
                end
            end
        end
    end
    for _, item in ipairs(char:GetDescendants()) do
        if item.Name:lower():find("shield") then
            if item:IsA("BoolValue") then
                if item.Value then return true end
            elseif item:IsA("NumberValue") or item:IsA("IntValue") then
                if item.Value > 0 then return true end
            elseif item:IsA("ParticleEmitter") or item:IsA("Beam") or item:IsA("Trail") then
                if item.Enabled then return true end
            elseif item:IsA("BasePart") then
                if item.Transparency < 1 then return true end
            elseif item:IsA("Model") or item:IsA("Tool") then
                return true
            end
        end
    end
    return false
end

-- Pahalı tarama: oyuncu başına 0.4 sn'de bir
statusInfo.hasShield = function(plr, char)
    local now = os.clock()
    local c = statusInfo.cache[plr]
    if not c or c.char ~= char or now - c.t > 0.4 then
        c = {t = now, char = char, v = statusInfo.detectShield(plr, char)}
        statusInfo.cache[plr] = c
    end
    return c.v
end

statusInfo.isDead = function(hum)
    return hum ~= nil and (hum.Health <= 0 or hum:GetState() == Enum.HumanoidStateType.Dead)
end

-- RENDER LOOP: ESP güncelle
RunService.RenderStepped:Connect(function()
    if not scriptEnabled then return end
    if not espEnabled then
        -- ESP kapalıyken sadece açık olan oyuncu listesinin HP / mesafe yazıları güncellenir
        if listFrame.Visible and playersPage.Visible then
            for plr, btn in pairs(playerButtons) do refreshButton(plr, btn) end
        end
        return
    end
    local localChar = LocalPlayer.Character
    local localRoot = localChar and localChar:FindFirstChild("HumanoidRootPart")

    for _, plr in pairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local char = getChar(plr)
            local root = getRoot(char)
            if char and root then
                -- ESP oluştur (her zaman, panel kapalıysa da)
                local esp = createESP(plr)
                if esp then
                    local cam = workspace.CurrentCamera
                    if not cam then
                        esp.Visible = false
                        continue
                    end
                    local rawDist = localRoot and (localRoot.Position - root.Position).Magnitude or 0
                    local sp, onScreen = cam:WorldToViewportPoint(root.Position + Vector3.new(0, 3.5, 0))
                    esp.Visible = onScreen and sp.Z > 0 and rawDist <= espSettings.maxDist
                    esp.Position = UDim2.fromOffset(sp.X, sp.Y)
                    local hum = char:FindFirstChildOfClass("Humanoid")
                    local lbl = esp:FindFirstChild("Label")
                    local now = os.clock()
                    if lbl and (not lastTextUpdate[plr] or now - lastTextUpdate[plr] >= 0.2) then
                        lastTextUpdate[plr] = now
                        local hp   = hum and math.floor(hum.Health) or 0
                        local dist = 0
                        if localRoot then
                            dist = math.floor((localRoot.Position - root.Position).Magnitude)
                        end
                        -- Mesafeye göre küçült
                        local sc = esp:FindFirstChildOfClass("UIScale")
                        if sc then
                            sc.Scale = (0.5 + 0.3 * math.clamp(1 - dist / 300, 0, 1)) * espSettings.textScale
                        end
                        local class = getClass(plr)
                        local nameColor = class == "friend" and "#6495ED"
                            or class == "enemy" and "#DC143C"
                            or "#FFFFFF"
                        local hpPercent = (hum and hum.MaxHealth > 0) and (hum.Health / hum.MaxHealth) * 100 or 100
                        local hpColor = hpPercent <= 45 and "#FF0000" or "#00FF00"

                        local characterName = getCharacterName(plr, char)

                        lbl.RichText = true
                        lbl.TextColor3 = Color3.new(1, 1, 1)
                        charNames[plr] = characterName and tostring(characterName):lower() or ""
                        local lines = {}
                        if espSettings.dead and statusInfo.isDead(hum) then
                            lines[#lines + 1] = '<font color="#FF3B3B" size="16">💀 DEAD</font>'
                        elseif espSettings.shield and scriptEnabled and statusInfo.hasShield(plr, char) then
                            lines[#lines + 1] = '<font color="#00BFFF" size="14">🛡 SHIELD</font>'
                        end
                        if espSettings.character and characterName and tostring(characterName) ~= "" then
                            lines[#lines + 1] = '<font color="' .. (espSettings.charColors and characterColorHex(characterName) or "#FFFFFF") .. '">' .. tostring(characterName) .. '</font>'
                        end
                        if espSettings.name then
                            lines[#lines + 1] = string.format('<font color="%s" size="18">%s</font>', nameColor, plr.Name)
                        end
                        local stats = {}
                        if espSettings.hp then
                            stats[#stats + 1] = string.format('<font color="%s" size="12">HP %d</font>', hpColor, hp)
                        end
                        if espSettings.distance then
                            stats[#stats + 1] = string.format('<font color="#FFFFFF" size="12">DISTANCE %dm</font>', dist)
                        end
                        if #stats > 0 then
                            lines[#lines + 1] = table.concat(stats, " / ")
                        end
                        lbl.Text = table.concat(lines, "\n")
                    end
                end
                -- Buton mesafe güncelle
                if playerButtons[plr] then
                    refreshButton(plr, playerButtons[plr])
                end
            elseif espFrames[plr] then
                espFrames[plr].Visible = false
            end
        end
    end
end)

-- VFX: sadece KENDİ efektlerini boya (client-side; sadece senin ekranında görünür)
local VFX_CLASSES = {
    ParticleEmitter = true, Beam = true, Trail = true, Fire = true, Smoke = true,
    Sparkles = true, PointLight = true, SpotLight = true, SurfaceLight = true, Highlight = true,
}
local vfxTracked = setmetatable({}, {__mode = "k"})  -- benim olduğu anlaşılan efektler (rainbow bunları döndürür)
local rbHue = 0

local function rainbowSeq(h)
    local pts = {}
    local sat = math.clamp(0.85 * vfx.sat, 0, 1)
    local val = math.clamp(vfx.val, 0, 1)
    for i = 0, 4 do
        pts[#pts + 1] = ColorSequenceKeypoint.new(i / 4, Color3.fromHSV((h + i * 0.12) % 1, sat, val))
    end
    return ColorSequence.new(pts)
end

-- Seçili renge ton ayarını uygular (hue kaydırma, doygunluk, parlaklık)
local function toneColor(c)
    if vfx.hue == 0 and vfx.sat == 1 and vfx.val == 1 then return c end
    local h, s, v = c:ToHSV()
    h = (h + vfx.hue / 360) % 1
    s = math.clamp(s * vfx.sat, 0, 1)
    v = math.clamp(v * vfx.val, 0, 1)
    return Color3.fromHSV(h, s, v)
end

local function vfxApplyRaw(inst, h)
    local rb = vfx.rainbow
    local c = rb and Color3.fromHSV(h, math.clamp(0.85 * vfx.sat, 0, 1), math.clamp(vfx.val, 0, 1)) or toneColor(vfx.color)
    local cn = inst.ClassName
    if cn == "ParticleEmitter" or cn == "Beam" or cn == "Trail" then
        inst.Color = rb and rainbowSeq(h) or ColorSequence.new(c)
    elseif cn == "Fire" then
        inst.Color = c
        inst.SecondaryColor = c
    elseif cn == "Smoke" then
        inst.Color = c
    elseif cn == "Sparkles" then
        inst.SparkleColor = c
    elseif cn == "Highlight" then
        inst.FillColor = c
        inst.OutlineColor = c
    elseif cn == "PointLight" or cn == "SpotLight" or cn == "SurfaceLight" then
        inst.Color = c
    elseif inst:IsA("BasePart") then
        inst.Color = c
    end
end

local function vfxRecolor(inst)
    vfxTracked[inst] = true
    pcall(vfxApplyRaw, inst, rbHue)
end

local function vfxPosition(inst)
    if inst:IsA("Beam") then
        local a0 = inst.Attachment0
        if a0 then return a0.WorldPosition end
    end
    if inst:IsA("BasePart") then return inst.Position end
    local p = inst.Parent
    if p then
        if p:IsA("Attachment") then return p.WorldPosition end
        if p:IsA("BasePart") then return p.Position end
    end
    local bp = inst:FindFirstAncestorWhichIsA("BasePart")
    if bp then return bp.Position end
    return nil
end

-- Sahip etiketi: efektin (veya üst objelerinin) Owner / Creator gibi bir attribute / Value'su varsa
-- kimin olduğu kesin bellidir. "me" = benim, "other" = başkasının, nil = bilinmiyor.
local OWNER_KEYS = {"Owner", "Creator", "Caster", "Player", "User", "Source"}
local function vfxOwner(inst)
    local node = inst
    for _ = 1, 5 do
        if not node or node == workspace then break end
        for _, k in ipairs(OWNER_KEYS) do
            local v = node:GetAttribute(k)
            if v == nil then
                local child = node:FindFirstChild(k)
                if child and child:IsA("ValueBase") then v = child.Value end
            end
            if v ~= nil then
                if typeof(v) == "Instance" then
                    if v == LocalPlayer or (LocalPlayer.Character and v == LocalPlayer.Character) then return "me" end
                    if v:IsA("Player") or Players:GetPlayerFromCharacter(v) then return "other" end
                elseif type(v) == "string" then
                    if v == LocalPlayer.Name or v == LocalPlayer.DisplayName then return "me" end
                    if Players:FindFirstChild(v) then return "other" end
                elseif type(v) == "number" then
                    if v == LocalPlayer.UserId then return "me" end
                    if Players:GetPlayerByUserId(v) then return "other" end
                end
            end
        end
        node = node.Parent
    end
    return nil
end

-- "Benim mi?" (sıkı kontrol):
--  1) karakterimin içindeyse -> evet
--  2) başka oyuncunun karakterinin içindeyse -> hayır
--  3) sahip etiketi varsa ona göre
--  4) etiket yoksa: yarıçap içinde VE başka hiçbir oyuncu bana yakın değilse -> evet (şüpheli durumda boyamaz)
local function vfxIsMine(inst)
    local myChar = LocalPlayer.Character
    if not myChar then return false end
    if inst:IsDescendantOf(myChar) then return true end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local c = plr.Character
            if c and inst:IsDescendantOf(c) then return false end
        end
    end
    local owner = vfxOwner(inst)
    if owner == "me" then return true end
    if owner == "other" then return false end

    local myRoot = myChar:FindFirstChild("HumanoidRootPart")
    if not myRoot then return false end
    local pos = vfxPosition(inst)
    if not pos then return false end
    local dMine = (pos - myRoot.Position).Magnitude
    if dMine > vfx.radius then return false end
    for _, plr in ipairs(Players:GetPlayers()) do
        if plr ~= LocalPlayer then
            local c = plr.Character
            local r = c and c:FindFirstChild("HumanoidRootPart")
            if r and (pos - r.Position).Magnitude < dMine * 1.5 + 6 then return false end
        end
    end
    return true
end

workspace.DescendantAdded:Connect(function(inst)
    if not scriptEnabled or not vfx.enabled then return end
    if not VFX_CLASSES[inst.ClassName] then
        if not vfx.neon then return end
        local ok, isNeon = pcall(function()
            return inst:IsA("BasePart") and inst.Material == Enum.Material.Neon
        end)
        if not (ok and isNeon) then return end
    end
    task.defer(function()
        if inst.Parent and scriptEnabled and vfx.enabled and vfxIsMine(inst) then
            vfxRecolor(inst)
        end
    end)
end)

vfxRescan = function()
    if not vfx.enabled or not scriptEnabled then return end
    local myChar = LocalPlayer.Character
    if myChar then
        for _, d in ipairs(myChar:GetDescendants()) do
            if VFX_CLASSES[d.ClassName] then
                vfxRecolor(d)
            elseif vfx.neon then
                local ok, isNeon = pcall(function()
                    return d:IsA("BasePart") and d.Material == Enum.Material.Neon
                end)
                if ok and isNeon then vfxRecolor(d) end
            end
        end
    end
    -- daha önce "benim" diye tanınan (workspace'e düşen) efektleri de yeni renge çevir
    for inst in pairs(vfxTracked) do
        if inst.Parent then
            pcall(vfxApplyRaw, inst, rbHue)
        else
            vfxTracked[inst] = nil
        end
    end
end

-- RAINBOW: sadece benim efektlerimin rengini sürekli döndürür
local rbAcc = 0
RunService.Heartbeat:Connect(function(dt)
    if not (scriptEnabled and vfx.enabled and vfx.rainbow) then return end
    rbAcc = rbAcc + dt
    if rbAcc < 0.05 then return end
    rbAcc = 0
    rbHue = (rbHue + 0.012) % 1
    for inst in pairs(vfxTracked) do
        if inst.Parent then
            pcall(vfxApplyRaw, inst, rbHue)
        else
            vfxTracked[inst] = nil
        end
    end
end)

LocalPlayer.CharacterAdded:Connect(function()
    task.wait(1)
    vfxRescan()
end)

-- FPS BOOST: gölge / ekran efekti / kalite düşürülür; kapatınca eski haline döner
do
    local Lighting = game:GetService("Lighting")
    local EFFECTS = {
        BloomEffect = true, BlurEffect = true, ColorCorrectionEffect = true,
        DepthOfFieldEffect = true, SunRaysEffect = true,
    }
    local boostOn = false
    local saved = {}
    local effectState = setmetatable({}, {__mode = "k"})   -- [efekt] = eski Enabled
    local shadowState = setmetatable({}, {__mode = "k"})   -- [parça] = true (gölgesi kapatıldı)
    local conns = {}

    local function disableEffect(e)
        if EFFECTS[e.ClassName] and effectState[e] == nil then
            effectState[e] = e.Enabled
            e.Enabled = false
        end
    end
    local function noShadow(p)
        if p:IsA("BasePart") and p.CastShadow and shadowState[p] == nil then
            shadowState[p] = true
            p.CastShadow = false
        end
    end

    fpsBoostApply = function(on)
        on = on == true
        if on == boostOn then return end
        boostOn = on
        if on then
            saved.shadows = Lighting.GlobalShadows
            Lighting.GlobalShadows = false
            pcall(function()
                saved.quality = settings().Rendering.QualityLevel
                settings().Rendering.QualityLevel = Enum.QualityLevel.Level01
            end)
            pcall(function()
                saved.decoration = workspace.Terrain.Decoration
                workspace.Terrain.Decoration = false
            end)
            for _, e in ipairs(Lighting:GetDescendants()) do disableEffect(e) end
            local cam = workspace.CurrentCamera
            if cam then
                for _, e in ipairs(cam:GetDescendants()) do disableEffect(e) end
            end
            conns[#conns + 1] = Lighting.DescendantAdded:Connect(disableEffect)
            conns[#conns + 1] = workspace.DescendantAdded:Connect(noShadow)
            -- haritadaki parçaların gölgesini parça parça kapat (takılma olmasın)
            task.spawn(function()
                local n = 0
                for _, d in ipairs(workspace:GetDescendants()) do
                    if not boostOn then return end
                    noShadow(d)
                    n = n + 1
                    if n % 400 == 0 then task.wait() end
                end
            end)
        else
            for _, c in ipairs(conns) do c:Disconnect() end
            conns = {}
            if saved.shadows ~= nil then Lighting.GlobalShadows = saved.shadows end
            if saved.quality ~= nil then
                pcall(function() settings().Rendering.QualityLevel = saved.quality end)
            end
            if saved.decoration ~= nil then
                pcall(function() workspace.Terrain.Decoration = saved.decoration end)
            end
            for e, en in pairs(effectState) do
                if e.Parent then e.Enabled = en end
                effectState[e] = nil
            end
            for part in pairs(shadowState) do
                if part.Parent then part.CastShadow = true end
                shadowState[part] = nil
            end
        end
    end
end

-- KLAVYE
UserInputService.InputBegan:Connect(function(input, gp)
    if capturingKey then
        if input.UserInputType == Enum.UserInputType.Keyboard then
            toggleKey = input.KeyCode.Name
            keyBox.Text = "🔑 " .. toggleKey
            capturingKey = false
        end
        return
    end

    -- Handle the hub toggle even if Roblox marks the key as game-processed.
    if input.UserInputType == Enum.UserInputType.Keyboard and input.KeyCode.Name == toggleKey then
        if not scriptEnabled then
            setScript(true)
        else
            setPanelVisible(not listFrame.Visible)
        end
        return
    end

    if gp then return end
end)

-- Açılışta bildirim
task.wait(0.5)
createNotification("✓ SW HUB loaded!", Color3.fromRGB(80, 200, 120))
