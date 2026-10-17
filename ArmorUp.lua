----------------------------------------------------------------------
-- ArmorUp
-- Warlock-only. Warns you shortly before Demon Skin / Demon Armor drops (or
-- when it is down, if the warning time is 0) with a popup of the best rank
-- you know. Click it (or use a keybind) to refresh it.
-- Type /armorup for the settings window.
----------------------------------------------------------------------
local ADDON_NAME, AU = ...

local PREFIX = "|cff9482c9ArmorUp|r: "
local function Print(msg) print(PREFIX .. msg) end
AU.Print = Print

BINDING_HEADER_ARMORUP = "ArmorUp"
_G["BINDING_NAME_CLICK ArmorUpButton:LeftButton"] = "Cast best armor spell"

----------------------------------------------------------------------
-- Spell data (highest first)
----------------------------------------------------------------------
local ARMOR_SPELLS = {
    { id = 11735, level = 60, rank = 5, fallbackName = "Demon Armor" },
    { id = 11734, level = 50, rank = 4, fallbackName = "Demon Armor" },
    { id = 11733, level = 40, rank = 3, fallbackName = "Demon Armor" },
    { id = 1086,  level = 30, rank = 2, fallbackName = "Demon Armor" },
    { id = 706,   level = 20, rank = 1, fallbackName = "Demon Armor" },
    { id = 696,   level = 10, rank = 2, fallbackName = "Demon Skin"  },
    { id = 687,   level = 1,  rank = 1, fallbackName = "Demon Skin"  },
}
local ARMOR_IDS = {}
for _, s in ipairs(ARMOR_SPELLS) do ARMOR_IDS[s.id] = true end
local ARMOR_NAMES = { ["Demon Skin"] = true, ["Demon Armor"] = true }
local ARMOR_DURATION = 1800     -- seconds; only used to estimate the timer if the game hides buffs in combat

-- Alert sounds offered in the settings window
local SOUND_LIBRARY = {
    { name = "1H Armor Plate Critical", value = 148 },
    { name = "Ready Check",             value = 8960 },
    { name = "Raid Warning",            value = 8959 },
}
local WOWHEAD_URL = "https://www.wowhead.com/classic/sounds"

----------------------------------------------------------------------
-- API compatibility helpers
----------------------------------------------------------------------
local function SpellName(id, fallback)
    local name
    if C_Spell and C_Spell.GetSpellName then
        name = C_Spell.GetSpellName(id)
    elseif GetSpellInfo then
        name = GetSpellInfo(id)
    end
    return name or fallback
end

local function SpellTexture(id)
    if C_Spell and C_Spell.GetSpellTexture then
        return C_Spell.GetSpellTexture(id)
    elseif GetSpellTexture then
        return GetSpellTexture(id)
    end
end

local function SpellKnown(id)
    if IsPlayerSpell then
        local ok, res = pcall(IsPlayerSpell, id)
        if ok and res then return true end
    end
    if C_SpellBook and C_SpellBook.IsSpellKnown then
        local ok, res = pcall(C_SpellBook.IsSpellKnown, id)
        if ok and res then return true end
    end
    if IsSpellKnown then
        local ok, res = pcall(IsSpellKnown, id)
        if ok and res then return true end
    end
    return false
end

local function BestArmor()
    for _, s in ipairs(ARMOR_SPELLS) do
        if SpellKnown(s.id) then return s end
    end
    local lvl = UnitLevel("player") or 1      -- fallback if the lookups fail
    for _, s in ipairs(ARMOR_SPELLS) do
        if lvl >= s.level then return s end
    end
end

local function IsSecret(v)
    return issecretvalue and issecretvalue(v) and true or false
end

----------------------------------------------------------------------
-- Armor status.
-- ScanArmor reads your buffs and answers "active" (with seconds left, if
-- known), "missing", or "unknown" (the game hid the buff data, which can
-- happen in combat). ArmorStatus wraps it: when the answer is "unknown" it
-- falls back on the last known timer, so the popup stays correct in combat.
----------------------------------------------------------------------
local armorState = { active = false, expiry = nil }

local function ScanArmor()
    local sawSecret = false

    if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
        for i = 1, 60 do
            local ok, data = pcall(C_UnitAuras.GetAuraDataByIndex, "player", i, "HELPFUL")
            if not ok then sawSecret = true; break end
            if not data then break end
            local ok2, status, left = pcall(function()
                if IsSecret(data) then return "secret" end
                local name, spellId = data.name, data.spellId
                if IsSecret(name) or IsSecret(spellId) then return "secret" end
                if ARMOR_NAMES[name] or ARMOR_IDS[spellId] then
                    local exp, l = data.expirationTime, nil
                    if exp and not IsSecret(exp) and exp > 0 then l = exp - GetTime() end
                    return "hit", l
                end
                return "no"
            end)
            if not ok2 or status == "secret" then
                sawSecret = true
            elseif status == "hit" then
                return "active", left
            end
        end
    elseif UnitBuff then
        for i = 1, 60 do
            local ok, name, _, _, _, _, expires, _, _, _, spellId = pcall(UnitBuff, "player", i)
            if not ok then sawSecret = true; break end
            if not name then break end
            local ok2, status, left = pcall(function()
                if IsSecret(name) or IsSecret(spellId) then return "secret" end
                if ARMOR_NAMES[name] or ARMOR_IDS[spellId] then
                    local l
                    if expires and not IsSecret(expires) and expires > 0 then l = expires - GetTime() end
                    return "hit", l
                end
                return "no"
            end)
            if not ok2 or status == "secret" then
                sawSecret = true
            elseif status == "hit" then
                return "active", left
            end
        end
    end
    return sawSecret and "unknown" or "missing"
end

-- returns active (bool), secondsLeft (number or nil)
local function ArmorStatus()
    local state, left = ScanArmor()
    local now = GetTime()
    if state == "active" then
        armorState.active = true
        armorState.expiry = left and (now + left) or nil
        return true, left
    elseif state == "missing" then
        armorState.active = false
        armorState.expiry = nil
        return false
    end
    -- unknown: use the last known timer
    if armorState.active then
        if not armorState.expiry then return true, nil end
        local l = armorState.expiry - now
        if l > 0 then return true, l end
        armorState.active = false
    end
    return false
end

-- Called when we see ourselves cast an armor spell (keeps the estimate right in combat)
local function NoteArmorCast()
    armorState.active = true
    armorState.expiry = GetTime() + ARMOR_DURATION
end

AU.SpellName, AU.BestArmor, AU.ArmorStatus = SpellName, BestArmor, ArmorStatus

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function FormatTime(sec)
    sec = math.max(0, math.floor(sec))
    return string.format("%d:%02d", math.floor(sec / 60), sec % 60)
end

----------------------------------------------------------------------
-- Saved variables
----------------------------------------------------------------------
local DB_VERSION = 3
local DEFAULTS = {
    sound = true,
    soundId = 148,          -- 1H Armor Plate Critical
    scale = 1.0,
    refresh = 15,           -- warn when this many seconds remain (0 = only when the armor is down)
    hideMounted = true,
    showInCombat = true,
    dbVersion = DB_VERSION,
    point = { "CENTER", "UIParent", "CENTER", 0, 150 },
}
AU.DEFAULTS = DEFAULTS

local function InitDB()
    ArmorUpDB = ArmorUpDB or {}
    local oldVersion = ArmorUpDB.dbVersion or 0
    for k, v in pairs(DEFAULTS) do
        if ArmorUpDB[k] == nil then
            ArmorUpDB[k] = (type(v) == "table") and { unpack(v) } or v
        end
    end
    -- Version 1.1.0 saved a warning time of 0; the default is now 15 seconds.
    if oldVersion < 2 then ArmorUpDB.refresh = 15 end
    ArmorUpDB.dbVersion = DB_VERSION
end

----------------------------------------------------------------------
-- Alert sound
----------------------------------------------------------------------
local function PlaySelection(sel)
    local id = tonumber(sel)
    if not id then return false end
    return (pcall(PlaySound, id, "Master"))
end

function AU.PlayAlertSound()
    PlaySelection(ArmorUpDB and ArmorUpDB.soundId or 148)
end

local function SoundLabel(sel)
    for _, e in ipairs(SOUND_LIBRARY) do
        if e.value == tonumber(sel) then return e.name .. " (" .. e.value .. ")" end
    end
    return "custom " .. tostring(sel)
end

----------------------------------------------------------------------
-- The popup. Visuals live on a plain container; the secure button on top is
-- just an invisible click layer (same layout PetHealthWatch uses). The
-- container is not a protected frame, so it can be shown and hidden in combat.
----------------------------------------------------------------------
local container, button, icon, nameText
local settings
local wasShown = false
AU.testShow = false

local function BuildPopup()
    container = CreateFrame("Frame", "ArmorUpContainer", UIParent)
    container:SetSize(56, 56)
    container:SetFrameStrata("MEDIUM")
    container:SetMovable(true)
    container:SetClampedToScreen(true)
    local p = ArmorUpDB.point
    container:SetPoint(p[1], _G[p[2]] or UIParent, p[3], p[4], p[5])
    container:SetScale(ArmorUpDB.scale or 1)
    container:Hide()

    local border = container:CreateTexture(nil, "BACKGROUND")
    border:SetPoint("TOPLEFT", -2, 2)
    border:SetPoint("BOTTOMRIGHT", 2, -2)
    border:SetColorTexture(0.53, 0.53, 0.93, 1)       -- warlock purple

    icon = container:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints(container)
    icon:SetTexCoord(0.07, 0.93, 0.07, 0.93)

    local title = container:CreateFontString(nil, "OVERLAY")
    title:SetFont("Fonts\\FRIZQT__.TTF", 16, "OUTLINE")
    title:SetPoint("TOP", container, "BOTTOM", 0, -4)
    title:SetText("Armor Up!")

    nameText = container:CreateFontString(nil, "OVERLAY")
    nameText:SetFont("Fonts\\FRIZQT__.TTF", 11, "OUTLINE")
    nameText:SetPoint("TOP", title, "BOTTOM", 0, -2)

    button = CreateFrame("Button", "ArmorUpButton", container, "SecureActionButtonTemplate")
    button:SetAllPoints(container)
    button:EnableMouse(true)
    button:RegisterForClicks("LeftButtonUp", "LeftButtonDown")
    button:SetAttribute("type", "spell")
    button:SetAttribute("useOnKeyDown", false)
    if button.SetPassThroughButtons then button:SetPassThroughButtons("RightButton") end

    button:RegisterForDrag("LeftButton")
    button:SetScript("OnDragStart", function()
        if not InCombatLockdown() then container:StartMoving() end
    end)
    button:SetScript("OnDragStop", function()
        container:StopMovingOrSizing()
        local point, rel, relPoint, x, y = container:GetPoint()
        ArmorUpDB.point = { point, (rel and rel:GetName()) or "UIParent", relPoint, x, y }
    end)
    button:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:AddLine("ArmorUp")
        local best = BestArmor()
        if best then GameTooltip:AddLine("Click to cast " .. SpellName(best.id, best.fallbackName), 1, 1, 1) end
        GameTooltip:AddLine("Drag to move (out of combat)", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    button:SetScript("OnLeave", function() GameTooltip:Hide() end)
end

local function ShouldRemind()
    if UnitIsDeadOrGhost("player") then return false end
    if ArmorUpDB.hideMounted and IsMounted and IsMounted() then return false end
    if UnitOnTaxi and UnitOnTaxi("player") then return false end
    if UnitHasVehicleUI and UnitHasVehicleUI("player") then return false end
    local active, left = ArmorStatus()
    if not active then return true end
    local threshold = ArmorUpDB.refresh or 0
    if threshold > 0 and left and left < threshold then return true end
    return false
end

local function Refresh()
    if not container then return end
    local inCombat = InCombatLockdown()

    if inCombat and not ArmorUpDB.showInCombat then
        container:Hide()
        wasShown = false
        return
    end

    local best = BestArmor()
    if not best then container:Hide(); return end

    local name = SpellName(best.id, best.fallbackName)
    -- Secure attributes can't change in combat; they are set whenever we're out of it.
    if not inCombat then button:SetAttribute("spell", name) end
    icon:SetTexture(SpellTexture(best.id))
    nameText:SetText(name)

    if AU.testShow then
        container:Show()
    elseif ShouldRemind() then
        container:Show()
        if not wasShown and ArmorUpDB.sound then AU.PlayAlertSound() end
        wasShown = true
    else
        container:Hide()
        wasShown = false
    end
    if AU.RefreshUI then AU.RefreshUI() end
end
AU.Refresh = Refresh

local debounce
local function QueueRefresh()
    if debounce then return end
    debounce = true
    C_Timer.After(0.2, function() debounce = false; Refresh() end)
end

function AU.TestPopup()
    AU.testShow = true
    Refresh()
    C_Timer.After(8, function() AU.testShow = false; Refresh() end)
end

----------------------------------------------------------------------
-- Settings window widgets. Same construction as PetHealthWatch / RangeHelper:
-- the game's own frame template, radio buttons, arrow steppers, standard
-- buttons and text boxes.
----------------------------------------------------------------------
local refreshers = {}
local UI = {}
local editCounter = 0

local function TryCreate(frameType, name, parent, templates)
    for _, tpl in ipairs(templates) do
        local ok, obj = pcall(CreateFrame, frameType, name, parent, tpl)
        if ok and obj then return obj, tpl end
    end
    return CreateFrame(frameType, name, parent)
end

local function WLabel(parent, fontObject, text, x, y, width)
    local fs = parent:CreateFontString(nil, "OVERLAY", fontObject)
    fs:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    fs:SetJustifyH("LEFT")
    if width then fs:SetWidth(width) end
    fs:SetText(text)
    return fs
end

local function WHeader(parent, text, x, y)
    return WLabel(parent, "GameFontHighlightLarge", text, x, y)
end

local function TextHeight(fs)
    local h = fs.GetStringHeight and fs:GetStringHeight()
    if type(h) ~= "number" or h <= 0 then h = 12 end
    return h
end

local function HasAtlas(name)
    return C_Texture and C_Texture.GetAtlasInfo and C_Texture.GetAtlasInfo(name) ~= nil
end

local function ArrowButton(parent, direction)
    local base = "Minimal_SliderBar_Button_" .. direction
    if HasAtlas(base) then
        local b = CreateFrame("Button", nil, parent)
        b:SetSize(14, 20)
        pcall(function()
            b:SetNormalAtlas(base)
            if HasAtlas(base .. "_Pressed") then b:SetPushedAtlas(base .. "_Pressed") end
            if HasAtlas(base .. "_Disabled") then b:SetDisabledAtlas(base .. "_Disabled") end
            if HasAtlas(base .. "_Highlight") then b:SetHighlightAtlas(base .. "_Highlight") end
        end)
        return b
    end
    local b = TryCreate("Button", nil, parent, { "UIPanelButtonTemplate" })
    b:SetSize(22, 22)
    b:SetText(direction == "Left" and "-" or "+")
    return b
end

-- [<] value [>]; click = one step, Shift+click = big step
local function WStepper(parent, x, y, text, rangeFn, getFn, setFn, tip)
    local st = {}
    st.label = WLabel(parent, "GameFontNormal", text, x, y - 4)
    local minus = ArrowButton(parent, "Left")
    minus:SetPoint("TOPLEFT", parent, "TOPLEFT", x + 185, y - 1)

    local valueFS = parent:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    valueFS:SetPoint("LEFT", minus, "RIGHT", 0, 0)
    valueFS:SetWidth(40)
    valueFS:SetJustifyH("CENTER")

    local plus = ArrowButton(parent, "Right")
    plus:SetPoint("LEFT", minus, "RIGHT", 40, 0)

    local function change(dir)
        local lo, hi, step, big = rangeFn()
        local amount = ((IsShiftKeyDown and IsShiftKeyDown()) and big or step) * dir
        setFn(Clamp((getFn() or lo) + amount, lo, hi))
        AU.RefreshUI()
    end
    minus:SetScript("OnClick", function() change(-1) end)
    plus:SetScript("OnClick", function() change(1) end)

    if tip then
        for _, w in ipairs({ minus, plus }) do
            w:SetScript("OnEnter", function(self)
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetText(tip, 1, 1, 1, 1, true)
            end)
            w:SetScript("OnLeave", function() GameTooltip:Hide() end)
        end
    end
    refreshers[#refreshers + 1] = function() valueFS:SetText(tostring(getFn() or "")) end
    st.y = y - 28
    return st
end

local function WButton(parent, text, width, point, rel, relPoint, x, y, onClick)
    local b = TryCreate("Button", nil, parent, { "UIPanelButtonTemplate" })
    b:SetSize(width, 22)
    b:SetText(text)
    b:SetPoint(point, rel, relPoint, x, y)
    b:SetScript("OnClick", onClick)
    return b
end

local function WCheck(parent, x, y, text, onClick)
    local c = TryCreate("CheckButton", nil, parent, { "UICheckButtonTemplate" })
    c:SetSize(26, 26)
    c:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    c:SetHitRectInsets(0, -220, 0, 0)
    WLabel(parent, "GameFontNormal", text, x + 30, y - 6)
    c:SetScript("OnClick", function(self) onClick(self:GetChecked() and true or false) end)
    return c
end

-- A group of radio buttons that all edit one setting.
-- items = { { value, label, hit = clickableWidth }, ... }; returns next free y, entries
local function WRadioGroup(parent, x, y, items, getFn, setFn)
    local entries = {}
    for _, item in ipairs(items) do
        local value, label = item[1], item[2]
        local b = TryCreate("CheckButton", nil, parent, { "UIRadioButtonTemplate", "UICheckButtonTemplate" })
        b:SetSize(22, 22)
        b:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
        b:SetHitRectInsets(0, -(item.hit or 230), 0, 0)
        WLabel(parent, "GameFontNormal", label, x + 26, y - 4)
        b:SetScript("OnClick", function()
            setFn(value)
            AU.RefreshUI()
        end)
        entries[#entries + 1] = { button = b, value = value, y = y }
        y = y - 28
    end
    refreshers[#refreshers + 1] = function()
        local cur = getFn()
        for _, e in ipairs(entries) do e.button:SetChecked(cur == e.value) end
    end
    return y, entries
end

-- Standard game text box (falls back to a plain dark box)
local function WEdit(parent, w, x, y)
    editCounter = editCounter + 1
    local e, tpl = TryCreate("EditBox", "ArmorUpEdit" .. editCounter, parent, { "InputBoxTemplate" })
    if tpl ~= "InputBoxTemplate" then
        e:SetFont("Fonts\\FRIZQT__.TTF", 12, "")
        e:SetTextInsets(6, 6, 0, 0)
        local bg = e:CreateTexture(nil, "BACKGROUND")
        bg:SetAllPoints(e)
        bg:SetColorTexture(0, 0, 0, 0.6)
    end
    e:SetAutoFocus(false)
    e:SetSize(w, 22)
    e:SetPoint("TOPLEFT", parent, "TOPLEFT", x, y)
    e:SetScript("OnEnterPressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEscapePressed", function(self) self:ClearFocus() end)
    e:SetScript("OnEditFocusLost", function() AU.RefreshUI() end)
    return e
end

function AU.RefreshUI()
    if not settings or not settings:IsShown() or not ArmorUpDB then return end
    for _, fn in ipairs(refreshers) do fn() end
end

function AU.StatusText()
    local best = BestArmor()
    local active, left = ArmorStatus()
    local spell = "|cffff5555none known|r"
    if best then
        spell = "|cff00ff00" .. SpellName(best.id, best.fallbackName) .. " (Rank " .. best.rank .. ")|r"
    end
    local state = active and "|cff00ff00Active|r" or "|cffff5555Missing|r"
    if active and left then state = state .. " (" .. FormatTime(left) .. " left)" end
    return "Best spell: " .. spell .. "\nArmor: " .. state
end

----------------------------------------------------------------------
-- The settings window
----------------------------------------------------------------------
local function BuildSettings()
    local win, tpl = TryCreate("Frame", "ArmorUpSettingsFrame", UIParent,
        { "ButtonFrameTemplateNoPortrait", "ButtonFrameTemplate", "BasicFrameTemplateWithInset", "BackdropTemplate" })
    settings = win
    win:SetSize(700, 570)
    win:SetPoint("CENTER", UIParent, "CENTER", 0, 20)
    win:SetFrameStrata("DIALOG")
    win:SetMovable(true)
    win:SetClampedToScreen(true)
    win:EnableMouse(true)
    win:RegisterForDrag("LeftButton")
    win:SetScript("OnDragStart", function(self) self:StartMoving() end)
    win:SetScript("OnDragStop", function(self) self:StopMovingOrSizing() end)

    local isButtonFrame = (tpl == "ButtonFrameTemplateNoPortrait" or tpl == "ButtonFrameTemplate")
    if tpl == "ButtonFrameTemplate" then
        pcall(function()
            if ButtonFrameTemplate_HidePortrait then ButtonFrameTemplate_HidePortrait(win) end
        end)
    end
    if isButtonFrame and win.Inset then
        win.Inset:ClearAllPoints()
        win.Inset:SetPoint("TOPLEFT", win, "TOPLEFT", 4, -26)
        win.Inset:SetPoint("BOTTOMRIGHT", win, "BOTTOMRIGHT", -6, 28)
    end
    if not isButtonFrame and tpl ~= "BasicFrameTemplateWithInset" then
        if win.SetBackdrop then
            win:SetBackdrop({
                bgFile = "Interface\\DialogFrame\\UI-DialogBox-Background",
                edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
                tile = true, tileSize = 32, edgeSize = 32,
                insets = { left = 8, right = 8, top = 8, bottom = 8 },
            })
        end
        local closeBtn = TryCreate("Button", nil, win, { "UIPanelCloseButton" })
        closeBtn:SetPoint("TOPRIGHT", win, "TOPRIGHT", -4, -4)
    end
    if isButtonFrame and win.SetTitle then
        win:SetTitle("ArmorUp Settings")
    else
        local title = win:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        title:SetPoint("TOP", win, "TOP", 0, -6)
        title:SetText("ArmorUp Settings")
    end
    table.insert(UISpecialFrames, "ArmorUpSettingsFrame")     -- Escape closes it

    -- ===== LEFT COLUMN: warning, looks, status =====
    local lx = 20
    local y = -38
    WHeader(win, "Warning", lx, y); y = y - 28

    local warnStep = WStepper(win, lx, y, "Warn before it drops (sec)",
        function() return 0, 1800, 15, 60 end,
        function() return ArmorUpDB.refresh or 0 end,
        function(v) ArmorUpDB.refresh = v; QueueRefresh() end,
        "How many seconds before the armor runs out to warn you. Arrows change it by 15; hold Shift for 60.")
    y = warnStep.y
    WLabel(win, "GameFontDisableSmall", "0 = warn only when the armor is already down.", lx + 4, y + 4, 300)
    y = y - 22

    local combatCheck = WCheck(win, lx - 2, y, "Show the popup during combat", function(c)
        ArmorUpDB.showInCombat = c
        QueueRefresh()
    end)
    y = y - 28
    local mountCheck = WCheck(win, lx - 2, y, "Hide the popup while mounted", function(c)
        ArmorUpDB.hideMounted = c
        QueueRefresh()
    end)
    refreshers[#refreshers + 1] = function()
        combatCheck:SetChecked(ArmorUpDB.showInCombat ~= false)
        mountCheck:SetChecked(ArmorUpDB.hideMounted ~= false)
    end
    y = y - 36

    WHeader(win, "How it looks", lx, y); y = y - 28
    local sizeStep = WStepper(win, lx, y, "Popup size (%)",
        function() return 50, 200, 10, 25 end,
        function() return math.floor((ArmorUpDB.scale or 1) * 100 + 0.5) end,
        function(v)
            ArmorUpDB.scale = v / 100
            if container and not InCombatLockdown() then container:SetScale(ArmorUpDB.scale) end
        end,
        "Click an arrow for one step; hold Shift for a bigger step.")
    y = sizeStep.y
    WLabel(win, "GameFontDisableSmall", "Drag the popup itself to move it.", lx + 4, y + 4, 300)
    y = y - 30

    WHeader(win, "Status", lx, y); y = y - 28
    local statusFS = WLabel(win, "GameFontHighlight", AU.StatusText(), lx + 4, y, 300)
    refreshers[#refreshers + 1] = function() statusFS:SetText(AU.StatusText()) end
    local leftEnd = y - 36

    -- ===== RIGHT COLUMN: alert sound =====
    local rx = 350
    local ry = -38
    WHeader(win, "Alert sound", rx, ry); ry = ry - 28
    local soundCheck = WCheck(win, rx - 2, ry, "Play a sound with the warning", function(c)
        ArmorUpDB.sound = c
    end)
    ry = ry - 28
    local nowUsing = WLabel(win, "GameFontHighlightSmall", "", rx + 4, ry)
    ry = ry - 20
    refreshers[#refreshers + 1] = function()
        soundCheck:SetChecked(ArmorUpDB.sound ~= false)
        nowUsing:SetText("Now using: |cff00ff00" .. SoundLabel(ArmorUpDB.soundId) .. "|r")
    end

    local soundItems = {}
    for i, entry in ipairs(SOUND_LIBRARY) do
        soundItems[i] = { entry.value, entry.name .. "   |cff888888" .. tostring(entry.value) .. "|r", hit = 200 }
    end
    local soundEntries
    ry, soundEntries = WRadioGroup(win, rx, ry, soundItems,
        function() return tonumber(ArmorUpDB.soundId) end,
        function(v)
            ArmorUpDB.soundId = v
            UI.customDirty = false
            PlaySelection(v)
        end)
    for _, e in ipairs(soundEntries) do
        WButton(win, "Play", 54, "TOPLEFT", win, "TOPLEFT", rx + 266, e.y + 2, function() PlaySelection(e.value) end)
    end

    -- custom sound: radio + ID box + Play
    local function ApplyCustom()
        local id = tonumber(UI.customEdit:GetText())
        if id and id > 0 then
            ArmorUpDB.soundId = math.floor(id)
            UI.customDirty = false
            PlaySelection(id)
        else
            Print("type a sound ID number in the box first.")
        end
        AU.RefreshUI()
    end
    UI.customRadio = TryCreate("CheckButton", nil, win, { "UIRadioButtonTemplate", "UICheckButtonTemplate" })
    UI.customRadio:SetSize(22, 22)
    UI.customRadio:SetPoint("TOPLEFT", win, "TOPLEFT", rx, ry)
    UI.customRadio:SetHitRectInsets(0, -76, 0, 0)
    WLabel(win, "GameFontNormal", "Custom ID", rx + 26, ry - 4)
    UI.customRadio:SetScript("OnClick", ApplyCustom)

    UI.customEdit = WEdit(win, 130, rx + 112, ry)
    UI.customEdit:SetScript("OnTextChanged", function(self, user)
        if user then UI.customDirty = true end
    end)
    UI.customEdit:SetScript("OnEnterPressed", function(self)
        ApplyCustom()
        self:ClearFocus()
    end)
    WButton(win, "Play", 54, "TOPLEFT", win, "TOPLEFT", rx + 266, ry + 2, function()
        local id = tonumber(UI.customEdit:GetText())
        if id then PlaySelection(id) else Print("type a sound ID number first.") end
    end)
    refreshers[#refreshers + 1] = function()
        local cur = tonumber(ArmorUpDB.soundId)
        local inLibrary = false
        for _, e in ipairs(SOUND_LIBRARY) do
            if e.value == cur then inLibrary = true end
        end
        local customActive = (cur ~= nil) and not inLibrary
        UI.customRadio:SetChecked(customActive)
        -- Don't overwrite the box while the user is typing in it
        if not UI.customEdit:HasFocus() and not UI.customDirty then
            UI.customEdit:SetText(customActive and tostring(cur) or "")
        end
    end
    ry = ry - 30

    WLabel(win, "GameFontDisableSmall",
        "Type an ID and press Play to hear it. Select Custom ID (or press Enter) to use it.",
        rx + 4, ry, 320)
    ry = ry - 34

    WLabel(win, "GameFontHighlightSmall", "Find more sound IDs (select and copy the link):", rx + 4, ry)
    ry = ry - 18
    local url = WEdit(win, 320, rx + 2, ry)
    url:SetText(WOWHEAD_URL)
    url:SetCursorPosition(0)
    url:SetScript("OnTextChanged", function(self, user)
        if user then self:SetText(WOWHEAD_URL) end
    end)
    url:SetScript("OnEditFocusGained", function(self) self:HighlightText() end)
    url:SetScript("OnEditFocusLost", function(self) self:HighlightText(0, 0) end)
    local rightEnd = ry - 30

    -- ===== BOTTOM: how it works (full width) =====
    local by = math.min(leftEnd, rightEnd) - 4
    WHeader(win, "How it works", lx, by); by = by - 28
    local function para(text)
        local fs = WLabel(win, "GameFontHighlightSmall", text, lx + 4, by, 630)
        by = by - TextHeight(fs) - 8
    end
    para("ArmorUp warns you shortly before your Demon Skin / Demon Armor runs out, so you can refresh " ..
         "it before it drops. A popup shows the best rank you know and a sound plays. Click the popup " ..
         "to recast. Set the warning time to 0 and it warns you only once the armor is already down.")
    para("The popup also shows during combat (you can turn that off above) and hides while you are dead. " ..
         "Keybind: Key Bindings > AddOns > ArmorUp, or a macro with /click ArmorUpButton. " ..
         "Type /armorup to open this window.")

    -- ===== Bottom bar =====
    WButton(win, "Test popup", 100, "BOTTOMLEFT", win, "BOTTOMLEFT", 12, 4, function() AU.TestPopup() end)
    WButton(win, "Reset popup position", 150, "BOTTOMLEFT", win, "BOTTOMLEFT", 118, 4, function()
        if InCombatLockdown() then Print("can't move the popup in combat."); return end
        container:ClearAllPoints()
        container:SetPoint("CENTER", UIParent, "CENTER", 0, 150)
        ArmorUpDB.point = { "CENTER", "UIParent", "CENTER", 0, 150 }
    end)
    WButton(win, "Reset defaults", 110, "BOTTOMLEFT", win, "BOTTOMLEFT", 274, 4, function()
        for k, v in pairs(DEFAULTS) do
            if k ~= "point" then ArmorUpDB[k] = v end
        end
        UI.customDirty = false
        if container and not InCombatLockdown() then container:SetScale(ArmorUpDB.scale) end
        Refresh()
        AU.RefreshUI()
    end)
    WButton(win, "Close", 90, "BOTTOMRIGHT", win, "BOTTOMRIGHT", -10, 4, function() win:Hide() end)

    win:SetScript("OnShow", function() AU.RefreshUI() end)
    win:Hide()
end

function AU.OpenSettings()
    if not ArmorUpDB then return end
    if not settings then BuildSettings() end
    if not settings:IsShown() then settings:Show() end
end

function AU.ToggleSettings()
    if not ArmorUpDB then return end
    if not settings then BuildSettings() end
    if settings:IsShown() then settings:Hide() else settings:Show() end
end

----------------------------------------------------------------------
-- Entry in Options > AddOns: a short explanation and a button that opens
-- the settings window.
----------------------------------------------------------------------
local function RegisterOptionsPanel()
    local panel = CreateFrame("Frame", "ArmorUpOptionsPanel")
    panel.name = "ArmorUp"

    local version = ""
    pcall(function()
        local getMeta = (C_AddOns and C_AddOns.GetAddOnMetadata) or GetAddOnMetadata
        version = getMeta and getMeta(ADDON_NAME, "Version") or ""
    end)

    local title = panel:CreateFontString(nil, "ARTWORK", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -16)
    title:SetText("ArmorUp " .. version)

    local function paragraph(text, y)
        local fs = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        fs:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -y)
        fs:SetWidth(560)
        fs:SetJustifyH("LEFT")
        fs:SetText(text)
        return fs
    end

    paragraph("A Warlock armor reminder. ArmorUp warns you shortly before your Demon Skin or " ..
              "Demon Armor drops (15 seconds by default), so you can refresh it before it runs " ..
              "out. If you set the warning time to 0, it warns you only when the armor is " ..
              "already down. A popup shows the best rank you know and a sound plays. Click the " ..
              "popup (or use a keybind) to recast.", 52)

    local open = TryCreate("Button", nil, panel, { "UIPanelButtonTemplate" })
    open:SetSize(160, 26)
    open:SetText("Open settings")
    open:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -150)
    open:SetScript("OnClick", function()
        pcall(function()
            if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        end)
        AU.OpenSettings()
    end)

    local test = TryCreate("Button", nil, panel, { "UIPanelButtonTemplate" })
    test:SetSize(160, 26)
    test:SetText("Show test popup")
    test:SetPoint("LEFT", open, "RIGHT", 10, 0)
    test:SetScript("OnClick", function()
        pcall(function()
            if SettingsPanel and SettingsPanel:IsShown() then HideUIPanel(SettingsPanel) end
        end)
        AU.TestPopup()
    end)

    local good = panel:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    good:SetPoint("TOPLEFT", panel, "TOPLEFT", 16, -196)
    good:SetText("Good to know")
    paragraph("WoW does not let addons cast spells on their own, so ArmorUp asks for your click. " ..
              "The popup also shows during combat (this can be turned off in the settings). " ..
              "Type /armorup at any time to open the settings window.", 220)

    pcall(function()
        if Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory then
            local category = Settings.RegisterCanvasLayoutCategory(panel, "ArmorUp")
            Settings.RegisterAddOnCategory(category)
        elseif InterfaceOptions_AddCategory then
            InterfaceOptions_AddCategory(panel)
        end
    end)
end

----------------------------------------------------------------------
-- Slash commands
----------------------------------------------------------------------
SLASH_ARMORUP1 = "/armorup"
SLASH_ARMORUP2 = "/au"
SlashCmdList["ARMORUP"] = function(msg)
    if not AU.isWarlock then
        Print("inactive - this character is not a Warlock.")
        return
    end
    local cmd = (msg or ""):match("^(%S*)"):lower()
    if cmd == "" or cmd == "settings" or cmd == "options" or cmd == "config" then
        AU.ToggleSettings()
    elseif cmd == "test" then
        AU.TestPopup()
    elseif cmd == "status" then
        Print((AU.StatusText():gsub("\n", " | ")))
    else
        Print("type /armorup to open the settings window. Also: /armorup test, /armorup status")
    end
end

----------------------------------------------------------------------
-- Events
----------------------------------------------------------------------
local events = CreateFrame("Frame")
events:RegisterEvent("ADDON_LOADED")
events:RegisterEvent("PLAYER_LOGIN")
events:SetScript("OnEvent", function(self, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 ~= ADDON_NAME then return end
        local _, class = UnitClass("player")
        if class == "WARLOCK" then
            InitDB()
            RegisterOptionsPanel()          -- Options > AddOns > ArmorUp
        end
        return
    end

    if event == "PLAYER_LOGIN" then
        local _, class = UnitClass("player")
        if class ~= "WARLOCK" then
            self:UnregisterAllEvents()
            self:SetScript("OnEvent", nil)
            Print("|cffff5555did not load|r - " .. (UnitName("player") or "this character") ..
                  " is not a Warlock.")
            return
        end
        AU.isWarlock = true
        if not ArmorUpDB then InitDB() end
        BuildPopup()

        for _, e in ipairs({ "PLAYER_ENTERING_WORLD", "PLAYER_LEVEL_UP", "SPELLS_CHANGED",
                             "LEARNED_SPELL_IN_TAB", "PLAYER_REGEN_ENABLED",
                             "PLAYER_REGEN_DISABLED", "PLAYER_DEAD", "PLAYER_ALIVE",
                             "PLAYER_UNGHOST", "PLAYER_MOUNT_DISPLAY_CHANGED" }) do
            pcall(self.RegisterEvent, self, e)
        end
        -- only our own buffs and casts
        pcall(self.RegisterUnitEvent, self, "UNIT_AURA", "player")
        pcall(self.RegisterUnitEvent, self, "UNIT_SPELLCAST_SUCCEEDED", "player")

        Print("loaded for Warlock. Type /armorup for settings.")
        QueueRefresh()
        -- once a second, so the "seconds left" warning fires on time (also in combat)
        C_Timer.NewTicker(1, Refresh)

    elseif event == "UNIT_AURA" then
        if arg1 == "player" then QueueRefresh() end
    elseif event == "UNIT_SPELLCAST_SUCCEEDED" then
        if arg1 == "player" then
            local ok, hit = pcall(function() return ARMOR_IDS[arg3] end)
            if ok and hit then NoteArmorCast(); QueueRefresh() end
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        if container and not ArmorUpDB.showInCombat then
            container:Hide()
            wasShown = false
        else
            QueueRefresh()
        end
    else
        QueueRefresh()
    end
end)
