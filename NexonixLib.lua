--[[
    Nexonix UI  -  reworked
    Same public API as the original library (Window / Page / Section / Toggle / Button /
    Slider / RangeSlider / Dropdown / Label / Textbox / Colorpicker / Keybind / Watermark /
    KeybindList / Notification), rebuilt with:
      * CanvasGroup based fades (no more per-instance transparency bookkeeping)
      * one popup system for dropdowns, colorpickers, keybinds and settings
      * sibling ZIndex layering (no ZIndex hacks)
      * smoothed window drag / resize, sliding tab indicator, springy toggles,
        ripple buttons, staggered dropdowns, animated notifications
    Accent colour: #00B8FF
]]

local Env = (getgenv and getgenv()) or _G

if type(Env.Library) == "table" and type(Env.Library.Exit) == "function" then
    pcall(Env.Library.Exit, Env.Library)
end

--// executor compatibility
local cloneref = cloneref or function(Object) return Object end
local gethui = gethui or function() return cloneref(game:GetService("CoreGui")) end

local HasFS = (isfolder and makefolder and isfile and writefile and readfile and listfiles and delfile) and true or false

--// services
local Players = cloneref(game:GetService("Players"))
local UserInputService = cloneref(game:GetService("UserInputService"))
local RunService = cloneref(game:GetService("RunService"))
local HttpService = cloneref(game:GetService("HttpService"))
local TweenService = cloneref(game:GetService("TweenService"))
local GuiService = cloneref(game:GetService("GuiService"))

local LocalPlayer = Players.LocalPlayer
local IsMobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled
local GuiInset = GuiService:GetGuiInset().Y

--// library table
local Library = {
    Flags = { },
    Setters = { },
    Connections = { },
    Keybinds = { },
    OpenPopups = { },

    Directory = "nexonix",
    Folders = { Configs = "/Configs", Assets = "/Assets" },
    ConfigIgnore = { Configs = true, ConfigName = true },

    FontSize = 14,
    MenuKeybind = Enum.KeyCode.RightShift,
    DefaultLogo = "rbxassetid://77749228793011",

    Animation = { Time = 0.25, Style = "Quint", Direction = "Out" },

    Theme = {
        ["Background"]      = Color3.fromRGB(16, 17, 21),
        ["Inline"]          = Color3.fromRGB(22, 23, 29),
        ["Element"]         = Color3.fromRGB(31, 33, 41),
        ["Hovered Element"] = Color3.fromRGB(41, 44, 55),
        ["Outline"]         = Color3.fromRGB(40, 43, 54),
        ["Liner"]           = Color3.fromRGB(33, 35, 44),
        ["Accent"]          = Color3.fromRGB(0, 184, 255),
        ["Tab"]             = Color3.fromRGB(12, 40, 56),
        ["Toggle"]          = Color3.fromRGB(52, 56, 70),
        ["Dark Icon"]       = Color3.fromRGB(96, 100, 116),
        ["Dark Text"]       = Color3.fromRGB(146, 150, 166),
        ["Text"]            = Color3.fromRGB(240, 242, 248),
    },

    ThemeObjects = setmetatable({ }, { __mode = "k" }),
}

--// folders
if HasFS then
    pcall(function()
        if not isfolder(Library.Directory) then makefolder(Library.Directory) end
        for _, Folder in pairs(Library.Folders) do
            if not isfolder(Library.Directory .. Folder) then makefolder(Library.Directory .. Folder) end
        end
    end)
end

--// font
do
    local Loaded
    pcall(function()
        if not (HasFS and getcustomasset) then return end
        local Path = Library.Directory .. Library.Folders.Assets .. "/Figtree-SemiBold.ttf"
        local FontPath = Library.Directory .. Library.Folders.Assets .. "/Figtree.font"
        if not isfile(Path) then
            writefile(Path, game:HttpGet("https://github.com/sametexe001/luas/raw/refs/heads/main/fonts/Figtree-SemiBold.ttf"))
        end
        writefile(FontPath, HttpService:JSONEncode({
            name = "Figtree",
            faces = { { name = "Regular", weight = 400, style = "normal", assetId = getcustomasset(Path) } }
        }))
        Loaded = Font.new(getcustomasset(FontPath))
    end)
    Library.Font = Loaded or Font.fromEnum(Enum.Font.GothamMedium)
end

--// ---------------------------------------------------------------- helpers
local function D(Multiplier)
    return Library.Animation.Time * (Multiplier or 1)
end

local function Tween(Object, Properties, Time, Style, Direction)
    if not Object then return end
    local Info = TweenInfo.new(
        Time or D(),
        Enum.EasingStyle[Style or Library.Animation.Style],
        Enum.EasingDirection[Direction or Library.Animation.Direction]
    )
    local NewTween = TweenService:Create(Object, Info, Properties)
    NewTween:Play()
    return NewTween
end

local function Clean(Number)
    return tonumber(string.format("%.10g", Number))
end

local function Round(Number, Step)
    Step = (type(Step) == "number" and Step > 0) and Step or 1
    return Clean(math.floor(Number / Step + 0.5) * Step)
end

local function StepDecimals(Step)
    local Text = string.format("%.10g", Step)
    local Decimals = Text:match("%.(%d+)$")
    return Decimals and #Decimals or 0
end

local function Normalize(Text)
    return (string.lower(tostring(Text or "")):gsub("%s+", ""))
end

function Library:Bind(Object, Map)
    local Entry = Library.ThemeObjects[Object]
    if not Entry then
        Entry = { }
        Library.ThemeObjects[Object] = Entry
    end
    for Property, Key in pairs(Map) do
        Entry[Property] = Key
        Object[Property] = Library.Theme[Key]
    end
end

local function Paint(Object, Property, Key, Time)
    local Entry = Library.ThemeObjects[Object]
    if not Entry then
        Entry = { }
        Library.ThemeObjects[Object] = Entry
    end
    Entry[Property] = Key
    Tween(Object, { [Property] = Library.Theme[Key] }, Time or D(0.6))
end

function Library:SetTheme(Key, Color)
    if Library.Theme[Key] == nil or Library.Theme[Key] == Color then return end
    Library.Theme[Key] = Color
    for Object, Entry in pairs(Library.ThemeObjects) do
        for Property, ThemeKey in pairs(Entry) do
            if ThemeKey == Key then
                Tween(Object, { [Property] = Color }, 0.2, "Quad", "Out")
            end
        end
    end
end

local TextClasses = { TextLabel = true, TextButton = true, TextBox = true }

local function New(Class, Properties, Theme)
    local Object = Instance.new(Class)
    Object.Name = "\0"

    if Class ~= "UICorner" and Object:IsA("GuiObject") then
        Object.BorderSizePixel = 0
        Object.BackgroundTransparency = 1
    end
    if Class == "TextButton" or Class == "ImageButton" then
        Object.AutoButtonColor = false
    end
    if TextClasses[Class] then
        Object.FontFace = Library.Font
        Object.TextSize = Library.FontSize
        Object.Text = ""
    end
    if Class == "ScrollingFrame" then
        Object.ScrollBarThickness = 3
        Object.ScrollBarImageColor3 = Library.Theme["Dark Icon"]
        Object.TopImage = "rbxassetid://81680855285439"
        Object.MidImage = "rbxassetid://81680855285439"
        Object.BottomImage = "rbxassetid://81680855285439"
        Object.CanvasSize = UDim2.new()
        Object.AutomaticCanvasSize = Enum.AutomaticSize.Y
        Object.ScrollingDirection = Enum.ScrollingDirection.Y
        Object.ElasticBehavior = Enum.ElasticBehavior.Never
        Library:Bind(Object, { ScrollBarImageColor3 = "Dark Icon" })
    end

    local Parent
    for Property, Value in pairs(Properties or { }) do
        if Property == "Parent" then
            Parent = Value
        else
            Object[Property] = Value
        end
    end

    if Theme then
        Library:Bind(Object, Theme)
        if Theme.BackgroundColor3 and (not Properties or Properties.BackgroundTransparency == nil) then
            Object.BackgroundTransparency = 0
        end
    end

    Object.Parent = Parent
    return Object
end

local function Corner(Parent, Radius)
    return New("UICorner", { CornerRadius = UDim.new(0, Radius), Parent = Parent })
end

local function Stroke(Parent, Key, Transparency, Thickness)
    local Object = New("UIStroke", {
        ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
        Thickness = Thickness or 1,
        Transparency = Transparency or 0,
        Parent = Parent
    })
    Library:Bind(Object, { Color = Key or "Outline" })
    return Object
end

local function Pad(Parent, Top, Right, Bottom, Left)
    return New("UIPadding", {
        PaddingTop = UDim.new(0, Top or 0),
        PaddingRight = UDim.new(0, Right or Top or 0),
        PaddingBottom = UDim.new(0, Bottom or Top or 0),
        PaddingLeft = UDim.new(0, Left or Right or Top or 0),
        Parent = Parent
    })
end

local function List(Parent, Padding, Horizontal, HAlign, VAlign)
    return New("UIListLayout", {
        Padding = UDim.new(0, Padding or 0),
        SortOrder = Enum.SortOrder.LayoutOrder,
        FillDirection = Horizontal and Enum.FillDirection.Horizontal or Enum.FillDirection.Vertical,
        HorizontalAlignment = HAlign or Enum.HorizontalAlignment.Left,
        VerticalAlignment = VAlign or Enum.VerticalAlignment.Top,
        Parent = Parent
    })
end

local KeyAliases = {
    LeftControl = "LCtrl", RightControl = "RCtrl", LeftShift = "LShift", RightShift = "RShift",
    LeftAlt = "LAlt", RightAlt = "RAlt", MouseButton1 = "M1", MouseButton2 = "M2", MouseButton3 = "M3",
    Return = "Enter", Backquote = "`", Minus = "-", Equals = "=", LeftBracket = "[", RightBracket = "]",
    BackSlash = "\\", Semicolon = ";", Quote = "'", Comma = ",", Period = ".", Slash = "/",
    Zero = "0", One = "1", Two = "2", Three = "3", Four = "4", Five = "5", Six = "6", Seven = "7",
    Eight = "8", Nine = "9", Escape = "Esc", CapsLock = "Caps", PageUp = "PgUp", PageDown = "PgDn",
    KeypadZero = "Num0", KeypadOne = "Num1", KeypadTwo = "Num2", KeypadThree = "Num3", KeypadFour = "Num4",
    KeypadFive = "Num5", KeypadSix = "Num6", KeypadSeven = "Num7", KeypadEight = "Num8", KeypadNine = "Num9",
}

local function KeyName(Key)
    if not Key then return "None" end
    return KeyAliases[Key.Name] or Key.Name
end

local function ParseKey(Value)
    if typeof(Value) == "EnumItem" then return Value end
    if type(Value) ~= "string" or Value == "None" or Value == "" then return nil end
    local Kind, Name = Value:match("^Enum%.(%w+)%.(%w+)$")
    local Success, Result = pcall(function()
        if Kind then return Enum[Kind][Name] end
        return Enum.KeyCode[Value]
    end)
    if Success then return Result end
    return nil
end

local function IsPress(Input)
    return Input.UserInputType == Enum.UserInputType.MouseButton1 or Input.UserInputType == Enum.UserInputType.Touch
end

local function IsEnd(Input)
    return Input.UserInputState == Enum.UserInputState.End or Input.UserInputState == Enum.UserInputState.Cancel
end

local function SafeCall(Function, ...)
    if type(Function) ~= "function" then return end
    local Success, Result = pcall(Function, ...)
    if not Success then warn("[Nexonix] " .. tostring(Result)) end
    return Success, Result
end
Library.SafeCall = function(Self, ...) return SafeCall(...) end

function Library:Connect(Signal, Callback)
    local Connection = Signal:Connect(Callback)
    table.insert(Library.Connections, Connection)
    return Connection
end

--// ---------------------------------------------------------------- gui roots
local Gui = Instance.new("ScreenGui")
Gui.Name = "\0"
Gui.IgnoreGuiInset = true
Gui.ResetOnSpawn = false
Gui.DisplayOrder = 10000
Gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
pcall(function() if syn and syn.protect_gui then syn.protect_gui(Gui) end end)
Gui.Parent = gethui()

local RootScale
local Root = New("Frame", { Size = UDim2.fromScale(1, 1), Parent = Gui })
RootScale = New("UIScale", { Scale = IsMobile and 0.7 or 1, Parent = Root })
Root.Size = UDim2.fromScale(1 / RootScale.Scale, 1 / RootScale.Scale)

local function Layer(Z)
    return New("Frame", { Size = UDim2.fromScale(1, 1), ZIndex = Z, Parent = Root })
end

local HudLayer = Layer(1)
local WindowLayer = Layer(2)
local PopupLayer = Layer(3)
local NotifLayer = Layer(4)
local TipLayer = Layer(5)

local function PointerOf(Input)
    if Input and Input.UserInputType == Enum.UserInputType.Touch then
        return Vector2.new(Input.Position.X, Input.Position.Y + GuiInset)
    end
    return UserInputService:GetMouseLocation()
end

local function ToRoot(Vector)
    return (Vector - Root.AbsolutePosition) / RootScale.Scale
end

local function RootSize()
    return Root.AbsoluteSize / RootScale.Scale
end

local function Over(Object, Point)
    local Position, Size = Object.AbsolutePosition, Object.AbsoluteSize
    return Point.X >= Position.X and Point.X <= Position.X + Size.X
        and Point.Y >= Position.Y and Point.Y <= Position.Y + Size.Y
end

--// ---------------------------------------------------------------- lifecycle
function Library:Exit()
    for _, Connection in ipairs(Library.Connections) do
        pcall(function() Connection:Disconnect() end)
    end
    Library.Connections = { }
    pcall(function() Gui:Destroy() end)
    if Env.Library == Library then Env.Library = nil end
end
Library.Unload = Library.Exit

--// ---------------------------------------------------------------- config
function Library:GetConfig()
    local Config = { }
    for Flag, Value in pairs(Library.Flags) do
        if not Library.ConfigIgnore[Flag] then
            if type(Value) == "table" and Value.Key ~= nil then
                Config[Flag] = { Key = tostring(Value.Key), Mode = Value.Mode }
            elseif type(Value) == "table" and Value.Color then
                Config[Flag] = { Color = "#" .. Value.HexValue, Alpha = Value.Alpha }
            else
                Config[Flag] = Value
            end
        end
    end
    return HttpService:JSONEncode(Config)
end

function Library:LoadConfig(Json)
    local Success, Result = pcall(function()
        local Decoded = HttpService:JSONDecode(Json)
        for Flag, Value in pairs(Decoded) do
            local Setter = Library.Setters[Flag]
            if Setter and not Library.ConfigIgnore[Flag] then
                if type(Value) == "table" and Value.Color then
                    Setter(Value.Color, Value.Alpha)
                else
                    Setter(Value)
                end
            end
        end
    end)
    return Success, Result
end

function Library:GetConfigsList(Dropdown)
    local Names = { }
    if HasFS then
        local Success, Files = pcall(listfiles, Library.Directory .. Library.Folders.Configs)
        if Success then
            for _, File in ipairs(Files) do
                local Name = File:match("([^/\\]+)%.json$")
                if Name then table.insert(Names, Name) end
            end
        end
    end
    table.sort(Names)
    Dropdown:Refresh(Names)
end

--// ---------------------------------------------------------------- tooltip
local TipState = { Token = 0 }

local function EnsureTip()
    if TipState.Frame then return end
    TipState.Frame = New("CanvasGroup", {
        Visible = false, GroupTransparency = 1,
        AutomaticSize = Enum.AutomaticSize.XY, Size = UDim2.fromOffset(0, 0),
        Parent = TipLayer
    }, { BackgroundColor3 = "Inline" })
    Corner(TipState.Frame, 8)
    Stroke(TipState.Frame, "Outline")
    Pad(TipState.Frame, 7, 10, 7, 10)
    TipState.Label = New("TextLabel", {
        TextSize = 13, TextWrapped = true, AutomaticSize = Enum.AutomaticSize.XY,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = TipState.Frame
    }, { TextColor3 = "Text" })
    New("UISizeConstraint", { MaxSize = Vector2.new(240, math.huge), Parent = TipState.Label })
end

local function PlaceTip()
    local Frame = TipState.Frame
    local Point = ToRoot(UserInputService:GetMouseLocation())
    local Size = Frame.AbsoluteSize / RootScale.Scale
    local Bounds = RootSize()
    local X = math.min(Point.X + 16, Bounds.X - Size.X - 8)
    local Y = math.min(Point.Y + 20, Bounds.Y - Size.Y - 8)
    Frame.Position = UDim2.fromOffset(X, Y)
end

local function ShowTip(Text)
    EnsureTip()
    TipState.Label.Text = Text
    TipState.Frame.Visible = true
    PlaceTip()
    Tween(TipState.Frame, { GroupTransparency = 0 }, D(0.6), "Quad", "Out")
    if TipState.Follow then TipState.Follow:Disconnect() end
    TipState.Follow = RunService.RenderStepped:Connect(PlaceTip)
end

local function HideTip()
    if not TipState.Frame then return end
    if TipState.Follow then
        TipState.Follow:Disconnect()
        TipState.Follow = nil
    end
    local Token = TipState.Token
    Tween(TipState.Frame, { GroupTransparency = 1 }, D(0.5), "Quad", "Out")
    task.delay(D(0.5), function()
        if TipState.Token == Token and TipState.Frame then TipState.Frame.Visible = false end
    end)
end

local function Tip(Object, Text)
    if type(Text) ~= "string" or Text == "" then return end
    local Hovering = false
    Object.MouseEnter:Connect(function()
        Hovering = true
        TipState.Token = TipState.Token + 1
        local Token = TipState.Token
        task.delay(0.4, function()
            if Hovering and TipState.Token == Token then ShowTip(Text) end
        end)
    end)
    Object.MouseLeave:Connect(function()
        Hovering = false
        TipState.Token = TipState.Token + 1
        HideTip()
    end)
end

--// ---------------------------------------------------------------- popups
local Popups = Library.OpenPopups
local PopupMeta = { }
PopupMeta.__index = PopupMeta

local function NewPopup(Options)
    local Popup = setmetatable({
        Anchor = Options.Anchor,
        ParentPopup = Options.Parent,
        Width = Options.Width or 220,
        Height = Options.Height or 200,
        Align = Options.Align or "Left",
        Open = false,
        Token = 0,
    }, PopupMeta)

    Popup.Frame = New("CanvasGroup", {
        Visible = false, GroupTransparency = 1, Active = true,
        Size = UDim2.fromOffset(Popup.Width, Popup.Height),
        Parent = PopupLayer
    }, { BackgroundColor3 = "Background" })
    Corner(Popup.Frame, 10)
    Stroke(Popup.Frame, "Outline")
    Popup.Scale = New("UIScale", { Scale = 0.96, Parent = Popup.Frame })
    return Popup
end

function PopupMeta:Compute()
    local Anchor = self.Anchor
    local Position = ToRoot(Anchor.AbsolutePosition)
    local AnchorSize = Anchor.AbsoluteSize / RootScale.Scale
    local Bounds = RootSize()

    local X = Position.X
    if self.Align == "Right" then
        X = Position.X + AnchorSize.X - self.Width
    elseif self.Align == "Center" then
        X = Position.X + (AnchorSize.X - self.Width) / 2
    end
    X = math.clamp(X, 8, math.max(8, Bounds.X - self.Width - 8))

    local Y = Position.Y + AnchorSize.Y + 6
    local From = Y - 8
    if Y + self.Height > Bounds.Y - 8 then
        Y = math.max(8, Position.Y - self.Height - 6)
        From = Y + 8
    end
    return X, Y, From
end

function PopupMeta:SetOpen(Bool)
    if self.Open == Bool then return end
    self.Open = Bool
    self.Token = self.Token + 1
    local Token = self.Token
    local Frame = self.Frame

    if Bool then
        local Chain = { }
        local Walker = self.ParentPopup
        while Walker do
            Chain[Walker] = true
            Walker = Walker.ParentPopup
        end
        for _, Other in ipairs(table.clone(Popups)) do
            if Other ~= self and not Chain[Other] then Other:SetOpen(false) end
        end

        if self.BeforeOpen then self.BeforeOpen() end
        table.insert(Popups, self)

        local X, Y, From = self:Compute()
        Frame.Size = UDim2.fromOffset(self.Width, self.Height)
        Frame.Position = UDim2.fromOffset(X, From)
        Frame.Visible = true
        Tween(Frame, { Position = UDim2.fromOffset(X, Y), GroupTransparency = 0 }, D(1.2), "Quint", "Out")
        Tween(self.Scale, { Scale = 1 }, D(1.3), "Back", "Out")
        if self.OnOpen then self.OnOpen() end
    else
        local Index = table.find(Popups, self)
        if Index then table.remove(Popups, Index) end
        for _, Other in ipairs(table.clone(Popups)) do
            if Other.ParentPopup == self then Other:SetOpen(false) end
        end

        Tween(Frame, { GroupTransparency = 1 }, D(0.7), "Quad", "In")
        Tween(self.Scale, { Scale = 0.97 }, D(0.7), "Quad", "In")
        task.delay(D(0.7), function()
            if self.Token == Token then Frame.Visible = false end
        end)
        if self.OnClose then self.OnClose() end
    end

    if self.Changed then self.Changed(Bool) end
end

function PopupMeta:Toggle()
    self:SetOpen(not self.Open)
end

Library:Connect(UserInputService.InputBegan, function(Input)
    if not IsPress(Input) or #Popups == 0 then return end
    local Point = PointerOf(Input)
    local Keep = { }
    for _, Popup in ipairs(Popups) do
        if Over(Popup.Frame, Point) or (Popup.Anchor and Over(Popup.Anchor, Point)) then
            local Walker = Popup
            while Walker do
                Keep[Walker] = true
                Walker = Walker.ParentPopup
            end
        end
    end
    for _, Popup in ipairs(table.clone(Popups)) do
        if not Keep[Popup] then Popup:SetOpen(false) end
    end
end)

local function CloseAllPopups()
    for _, Popup in ipairs(table.clone(Popups)) do Popup:SetOpen(false) end
end

--// ---------------------------------------------------------------- input helpers
-- Calls OnChange(scale Vector2, input) every frame while the pointer is held on Object.
local function Slide(Object, OnChange, OnBegin, OnEnd)
    local function Update(Input)
        local Point = PointerOf(Input)
        local Position, Size = Object.AbsolutePosition, Object.AbsoluteSize
        return Vector2.new(
            math.clamp((Point.X - Position.X) / math.max(Size.X, 1), 0, 1),
            math.clamp((Point.Y - Position.Y) / math.max(Size.Y, 1), 0, 1)
        )
    end

    Object.InputBegan:Connect(function(Input)
        if not IsPress(Input) then return end
        local Scale = Update(Input)
        if OnBegin then OnBegin(Scale, Input) end
        OnChange(Scale, Input)

        local Connection
        Connection = RunService.RenderStepped:Connect(function()
            OnChange(Update(Input), Input)
        end)
        Input.Changed:Connect(function()
            if IsEnd(Input) then
                Connection:Disconnect()
                if OnEnd then OnEnd() end
            end
        end)
    end)
end

-- smoothed drag / resize controller for a frame
local function MakeMotion(Target)
    local Motion = { Held = false }

    Library:Connect(RunService.RenderStepped, function(Delta)
        local Alpha = 1 - math.exp(-Delta * 24)

        if Motion.PosGoal then
            local Current = Target.Position
            local From = Vector2.new(Current.X.Offset, Current.Y.Offset)
            local To = From:Lerp(Motion.PosGoal, Alpha)
            if (Motion.PosGoal - To).Magnitude < 0.05 then
                To = Motion.PosGoal
                if not Motion.Held then Motion.PosGoal = nil end
            end
            Target.Position = UDim2.new(Current.X.Scale, To.X, Current.Y.Scale, To.Y)
        end

        if Motion.SizeGoal then
            local Current = Target.Size
            local From = Vector2.new(Current.X.Offset, Current.Y.Offset)
            local To = From:Lerp(Motion.SizeGoal, Alpha)
            if (Motion.SizeGoal - To).Magnitude < 0.05 then
                To = Motion.SizeGoal
                if not Motion.Held then Motion.SizeGoal = nil end
            end
            Target.Size = UDim2.new(Current.X.Scale, To.X, Current.Y.Scale, To.Y)
        end
    end)

    function Motion:Drag(Handle)
        Handle.InputBegan:Connect(function(Input)
            if not IsPress(Input) then return end

            local StartPointer = PointerOf(Input)
            local StartPosition = Target.Position
            local Base = Vector2.new(StartPosition.X.Offset, StartPosition.Y.Offset)
            Motion.Held = true
            Motion.PosGoal = Motion.PosGoal or Base

            local Connection
            Connection = RunService.RenderStepped:Connect(function()
                local Current = Target.Position
                local CurrentOffset = Vector2.new(Current.X.Offset, Current.Y.Offset)
                local Desired = Base + (PointerOf(Input) - StartPointer) / RootScale.Scale
                local Size = Target.AbsoluteSize / RootScale.Scale
                local Bounds = RootSize()
                local TopLeft = ToRoot(Target.AbsolutePosition) + (Desired - CurrentOffset)
                local Clamped = Vector2.new(
                    math.clamp(TopLeft.X, -(Size.X - 120), Bounds.X - 120),
                    math.clamp(TopLeft.Y, 0, Bounds.Y - 48)
                )
                Motion.PosGoal = Desired + (Clamped - TopLeft)
            end)

            Input.Changed:Connect(function()
                if IsEnd(Input) then
                    Connection:Disconnect()
                    Motion.Held = false
                end
            end)
        end)
    end

    function Motion:Resize(Handle, DirX, DirY, Minimum)
        Handle.InputBegan:Connect(function(Input)
            if not IsPress(Input) then return end

            local StartPointer = PointerOf(Input)
            local StartSize = Vector2.new(Target.Size.X.Offset, Target.Size.Y.Offset)
            local StartPosition = Vector2.new(Target.Position.X.Offset, Target.Position.Y.Offset)
            local Anchor = Target.AnchorPoint
            local Maximum = RootSize() - Vector2.new(24, 24)
            Motion.Held = true
            Motion.SizeGoal = Motion.SizeGoal or StartSize
            Motion.PosGoal = Motion.PosGoal or StartPosition

            local Connection
            Connection = RunService.RenderStepped:Connect(function()
                local Delta = (PointerOf(Input) - StartPointer) / RootScale.Scale
                local Width = math.clamp(StartSize.X + DirX * Delta.X, Minimum.X, math.max(Maximum.X, Minimum.X))
                local Height = math.clamp(StartSize.Y + DirY * Delta.Y, Minimum.Y, math.max(Maximum.Y, Minimum.Y))
                local DW, DH = Width - StartSize.X, Height - StartSize.Y

                local ShiftX = 0
                if DirX == 1 then ShiftX = Anchor.X * DW elseif DirX == -1 then ShiftX = -(1 - Anchor.X) * DW end
                local ShiftY = 0
                if DirY == 1 then ShiftY = Anchor.Y * DH elseif DirY == -1 then ShiftY = -(1 - Anchor.Y) * DH end

                Motion.SizeGoal = Vector2.new(Width, Height)
                Motion.PosGoal = StartPosition + Vector2.new(ShiftX, ShiftY)
            end)

            Input.Changed:Connect(function()
                if IsEnd(Input) then
                    Connection:Disconnect()
                    Motion.Held = false
                end
            end)
        end)
    end

    return Motion
end

--// ---------------------------------------------------------------- shared widgets
local function Segmented(Parent, Options, Size, Position, OnSelect)
    local Holder = New("Frame", { Size = Size, Position = Position, Parent = Parent }, { BackgroundColor3 = "Element" })
    Corner(Holder, 9)
    Pad(Holder, 3)

    local Count = #Options
    local Pill = New("Frame", { Size = UDim2.new(1 / Count, 0, 1, 0), Parent = Holder }, { BackgroundColor3 = "Accent" })
    Corner(Pill, 7)

    local Segment = { Buttons = { }, Current = nil }

    for Index, Name in ipairs(Options) do
        local Button = New("TextButton", {
            Size = UDim2.new(1 / Count, 0, 1, 0),
            Position = UDim2.new((Index - 1) / Count, 0, 0, 0),
            Text = Name, Parent = Holder
        }, { TextColor3 = "Dark Text" })
        Segment.Buttons[Name] = { Button = Button, Index = Index }
        Button.MouseButton1Click:Connect(function()
            Segment:Set(Name)
            if OnSelect then OnSelect(Name) end
        end)
    end

    function Segment:Set(Name, Instant)
        local Data = Segment.Buttons[Name]
        if not Data then return end
        Segment.Current = Name
        local Target = UDim2.new((Data.Index - 1) / Count, 0, 0, 0)
        if Instant then
            Pill.Position = Target
        else
            Tween(Pill, { Position = Target }, D(1.2), "Back", "Out")
        end
        for Other, Info in pairs(Segment.Buttons) do
            Paint(Info.Button, "TextColor3", Other == Name and "Background" or "Dark Text")
        end
    end

    return Segment
end

local function BuildButton(Parent, Text, Size, Callback)
    local Button = { }
    local Frame = New("CanvasGroup", { Size = Size, Parent = Parent }, { BackgroundColor3 = "Element" })
    Corner(Frame, 8)
    local Label = New("TextLabel", {
        Text = Text, Size = UDim2.fromScale(1, 1), Parent = Frame
    }, { TextColor3 = "Text" })
    local Hit = New("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 3, Parent = Frame })

    Frame.MouseEnter:Connect(function() Paint(Frame, "BackgroundColor3", "Hovered Element", D(0.5)) end)
    Frame.MouseLeave:Connect(function() Paint(Frame, "BackgroundColor3", "Element", D(0.5)) end)

    local function Ripple(Origin)
        local Ring = New("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromOffset(Origin.X, Origin.Y),
            Size = UDim2.fromOffset(0, 0), BackgroundTransparency = 0.55, ZIndex = 2, Parent = Frame
        }, { BackgroundColor3 = "Accent" })
        Ring.BackgroundTransparency = 0.55
        Corner(Ring, 999)
        local Diameter = (Frame.AbsoluteSize.Magnitude / RootScale.Scale) * 2
        Tween(Ring, { Size = UDim2.fromOffset(Diameter, Diameter), BackgroundTransparency = 1 }, D(2.2), "Quint", "Out")
        task.delay(D(2.2), function() Ring:Destroy() end)
    end

    Hit.MouseButton1Down:Connect(function(X, Y)
        Ripple((UserInputService:GetMouseLocation() - Frame.AbsolutePosition) / RootScale.Scale)
    end)
    Hit.MouseButton1Click:Connect(function()
        SafeCall(Callback)
    end)

    function Button:Press()
        Ripple(Frame.AbsoluteSize / RootScale.Scale / 2)
        SafeCall(Callback)
    end

    function Button:SetText(NewText) Label.Text = tostring(NewText) end

    Button.Frame = Frame
    Button.Label = Label
    return Button
end

--// ---------------------------------------------------------------- container (elements)
local Container = { }
local ContainerMeta = { __index = Container }

local function Register(Owner, Name, Row)
    if Owner.Window and Owner.Page and Owner.Window.RegisterSearch then
        Owner.Window:RegisterSearch({
            Name = Name, Page = Owner.Page, Row = Row, Section = Owner.Section,
            Height = Row.Size.Y.Offset, Shown = true
        })
    end
end

local function MakeRow(Owner, Height, Class)
    local Row = New(Class or "Frame", { Size = UDim2.new(1, 0, 0, Height), Parent = Owner.Content }, { BackgroundColor3 = "Element" })
    Row.BackgroundTransparency = 1
    Corner(Row, 8)
    Row.MouseEnter:Connect(function() Tween(Row, { BackgroundTransparency = 0.55 }, D(0.5), "Quad", "Out") end)
    Row.MouseLeave:Connect(function() Tween(Row, { BackgroundTransparency = 1 }, D(0.6), "Quad", "Out") end)
    return Row
end

local function SubHolder(Row, Offset)
    local Holder = New("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, Offset, 0.5, 0),
        Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Parent = Row
    })
    List(Holder, 6, true, Enum.HorizontalAlignment.Right, Enum.VerticalAlignment.Center)
    return Holder
end

--// colorpicker -------------------------------------------------------------
local function BuildColorpicker(Owner, Holder, Params, FallbackName)
    local Picker = {
        Flag = Params.Flag or Params.flag or Params.Name or Params.name or FallbackName,
        Callback = Params.Callback or Params.callback or function() end,
        Hue = 0, Sat = 0, Val = 1, Alpha = 0,
        Color = Color3.new(1, 1, 1), HexValue = "FFFFFF",
    }

    local Swatch = New("TextButton", { Size = UDim2.fromOffset(28, 16), BackgroundTransparency = 0, Parent = Holder })
    Swatch.BackgroundColor3 = Picker.Color
    Corner(Swatch, 5)
    Stroke(Swatch, "Outline", 0.2)

    local Popup = NewPopup({ Anchor = Swatch, Width = 216, Height = 216, Align = "Right", Parent = Owner.Popup })
    local Frame = Popup.Frame
    Pad(Frame, 10)

    -- saturation / value palette
    local Palette = New("TextButton", { Size = UDim2.new(1, 0, 0, 118), BackgroundTransparency = 0, Parent = Frame })
    Palette.BackgroundColor3 = Color3.fromHSV(0, 1, 1)
    Corner(Palette, 6)

    local White = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, Parent = Palette })
    White.BackgroundColor3 = Color3.new(1, 1, 1)
    Corner(White, 6)
    New("UIGradient", {
        Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
        Parent = White
    })

    local Black = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, Parent = Palette })
    Black.BackgroundColor3 = Color3.new(0, 0, 0)
    Corner(Black, 6)
    New("UIGradient", {
        Rotation = 90,
        Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 1), NumberSequenceKeypoint.new(1, 0) }),
        Parent = Black
    })

    local Cursor = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Size = UDim2.fromOffset(12, 12), Parent = Palette
    })
    Corner(Cursor, 6)
    New("UIStroke", { Color = Color3.new(1, 1, 1), Thickness = 2, Parent = Cursor })

    -- hue
    local Hue = New("TextButton", {
        Position = UDim2.new(0, 0, 0, 126), Size = UDim2.new(1, 0, 0, 12), BackgroundTransparency = 0, Parent = Frame
    })
    Hue.BackgroundColor3 = Color3.new(1, 1, 1)
    Corner(Hue, 6)
    New("UIGradient", {
        Color = ColorSequence.new({
            ColorSequenceKeypoint.new(0, Color3.fromRGB(255, 0, 0)),
            ColorSequenceKeypoint.new(0.17, Color3.fromRGB(255, 255, 0)),
            ColorSequenceKeypoint.new(0.33, Color3.fromRGB(0, 255, 0)),
            ColorSequenceKeypoint.new(0.5, Color3.fromRGB(0, 255, 255)),
            ColorSequenceKeypoint.new(0.67, Color3.fromRGB(0, 0, 255)),
            ColorSequenceKeypoint.new(0.83, Color3.fromRGB(255, 0, 255)),
            ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 0, 0)),
        }),
        Parent = Hue
    })
    local HueKnob = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 0, Parent = Hue
    })
    HueKnob.BackgroundColor3 = Color3.new(1, 1, 1)
    Corner(HueKnob, 7)
    New("UIStroke", { Color = Color3.fromRGB(20, 20, 24), Thickness = 2, Parent = HueKnob })

    -- alpha
    local Alpha = New("TextButton", {
        Position = UDim2.new(0, 0, 0, 146), Size = UDim2.new(1, 0, 0, 12), ClipsDescendants = true, Parent = Frame
    })
    Corner(Alpha, 6)
    New("ImageLabel", {
        Size = UDim2.fromScale(1, 1), Image = "rbxassetid://18274452449",
        ScaleType = Enum.ScaleType.Tile, TileSize = UDim2.fromOffset(6, 6), Parent = Alpha
    })
    local AlphaFill = New("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 0, Parent = Alpha })
    AlphaFill.BackgroundColor3 = Picker.Color
    New("UIGradient", {
        Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0), NumberSequenceKeypoint.new(1, 1) }),
        Parent = AlphaFill
    })
    local AlphaKnob = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
        Size = UDim2.fromOffset(14, 14), BackgroundTransparency = 0, ZIndex = 2, Parent = Frame
    })
    AlphaKnob.BackgroundColor3 = Color3.new(1, 1, 1)
    Corner(AlphaKnob, 7)
    New("UIStroke", { Color = Color3.fromRGB(20, 20, 24), Thickness = 2, Parent = AlphaKnob })
    AlphaKnob.Parent = Alpha
    AlphaKnob.ZIndex = 1

    -- hex
    local HexBox = New("TextBox", {
        Position = UDim2.new(0, 0, 0, 168), Size = UDim2.new(1, 0, 0, 28), ClearTextOnFocus = false,
        PlaceholderText = "#FFFFFF", BackgroundTransparency = 0, Parent = Frame
    }, { BackgroundColor3 = "Element", TextColor3 = "Text", PlaceholderColor3 = "Dark Text" })
    Corner(HexBox, 7)

    local Dragging = false

    function Picker:Refresh()
        Picker.Color = Color3.fromHSV(Picker.Hue, Picker.Sat, Picker.Val)
        Picker.HexValue = Picker.Color:ToHex()

        local Fast = Dragging and 0.06 or D(0.8)
        Tween(Swatch, { BackgroundColor3 = Picker.Color }, Fast, "Quad", "Out")
        Tween(Palette, { BackgroundColor3 = Color3.fromHSV(Picker.Hue, 1, 1) }, Fast, "Quad", "Out")
        Tween(AlphaFill, { BackgroundColor3 = Picker.Color }, Fast, "Quad", "Out")
        Tween(Cursor, { Position = UDim2.fromScale(Picker.Sat, 1 - Picker.Val) }, Fast, "Quad", "Out")
        Tween(HueKnob, { Position = UDim2.fromScale(Picker.Hue, 0.5) }, Fast, "Quad", "Out")
        Tween(AlphaKnob, { Position = UDim2.fromScale(Picker.Alpha, 0.5) }, Fast, "Quad", "Out")
        if not HexBox:IsFocused() then HexBox.Text = "#" .. Picker.HexValue end

        Library.Flags[Picker.Flag] = {
            Color = Picker.Color, HexValue = Picker.HexValue,
            Alpha = Picker.Alpha, Transparency = Picker.Alpha,
        }
        SafeCall(Picker.Callback, Picker.Color, Picker.Alpha)
    end

    function Picker:Set(Color, NewAlpha)
        if type(Color) == "table" then
            Color = Color3.fromRGB(Color[1], Color[2], Color[3])
        elseif type(Color) == "string" then
            local Success, Result = pcall(Color3.fromHex, Color)
            if not Success then return end
            Color = Result
        end
        if typeof(Color) ~= "Color3" then return end
        Picker.Hue, Picker.Sat, Picker.Val = Color:ToHSV()
        if type(NewAlpha) == "number" then Picker.Alpha = math.clamp(NewAlpha, 0, 1) end
        Picker:Refresh()
    end

    function Picker:SetVisibility(Bool) Swatch.Visible = Bool end

    local function Begin() Dragging = true end
    local function Finish() Dragging = false end

    Slide(Palette, function(Scale)
        Picker.Sat = Scale.X
        Picker.Val = 1 - Scale.Y
        Picker:Refresh()
    end, Begin, Finish)

    Slide(Hue, function(Scale)
        Picker.Hue = Scale.X
        Picker:Refresh()
    end, Begin, Finish)

    Slide(Alpha, function(Scale)
        Picker.Alpha = Scale.X
        Picker:Refresh()
    end, Begin, Finish)

    HexBox.FocusLost:Connect(function()
        local Success, Result = pcall(Color3.fromHex, HexBox.Text)
        if Success then Picker:Set(Result) else HexBox.Text = "#" .. Picker.HexValue end
    end)

    Swatch.MouseButton1Click:Connect(function() Popup:Toggle() end)

    Picker.Popup = Popup
    Library.Setters[Picker.Flag] = function(Color, NewAlpha) Picker:Set(Color, NewAlpha) end
    Picker:Set(Params.Default or Params.default or Color3.new(1, 1, 1), Params.Alpha or Params.alpha or 0)
    return Picker
end

--// keybind ------------------------------------------------------------------
local function AttachKeybindEntry(Keybind)
    if Library.KeyList and not Keybind.Entry then
        Keybind.Entry = Library.KeyList:Add(Keybind.Name)
        Keybind:UpdateList()
    end
end

local function BuildKeybind(Owner, Holder, Params, FallbackName)
    local Keybind = {
        Name = Params.Name or Params.name or FallbackName or "Keybind",
        Flag = Params.Flag or Params.flag or Params.Name or Params.name or FallbackName,
        Callback = Params.Callback or Params.callback or function() end,
        KeyChanged = Params.KeyChanged,
        Toggle = Params.Toggle,
        Mode = Params.Mode or Params.mode or "Toggle",
        Key = nil, Toggled = false, Picking = false,
    }

    local Pill = New("TextButton", {
        Size = UDim2.new(0, 0, 0, 22), AutomaticSize = Enum.AutomaticSize.X, BackgroundTransparency = 0, Parent = Holder
    }, { BackgroundColor3 = "Background" })
    Corner(Pill, 6)
    Stroke(Pill, "Outline", 0.3)
    Pad(Pill, 0, 9, 0, 9)
    local PillText = New("TextLabel", {
        Text = "None", TextSize = 12, Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, Parent = Pill
    }, { TextColor3 = "Dark Text" })

    local Popup = NewPopup({ Anchor = Pill, Width = 200, Height = 98, Align = "Right", Parent = Owner.Popup })
    Pad(Popup.Frame, 10)

    local KeyButton = New("TextButton", {
        Size = UDim2.new(1, 0, 0, 32), BackgroundTransparency = 0, Parent = Popup.Frame
    }, { BackgroundColor3 = "Element" })
    Corner(KeyButton, 8)
    local KeyLabel = New("TextLabel", { Text = "None", Size = UDim2.fromScale(1, 1), Parent = KeyButton }, { TextColor3 = "Text" })

    local Modes
    Modes = Segmented(Popup.Frame, { "Toggle", "Hold", "Always" }, UDim2.new(1, 0, 0, 32), UDim2.new(0, 0, 0, 44), function(Mode)
        Keybind:SetMode(Mode)
    end)

    function Keybind:UpdateList()
        if not Keybind.Entry then return end
        Keybind.Entry:Update(Keybind.Name, KeyName(Keybind.Key), Keybind.Toggled, Keybind.Mode)
    end

    local function Store()
        Library.Flags[Keybind.Flag] = {
            Mode = Keybind.Mode,
            Key = Keybind.Key and tostring(Keybind.Key) or "None",
            Toggled = Keybind.Toggled,
        }
    end

    function Keybind:SetState(Bool, FromToggle)
        if Keybind.Toggled == Bool then return end
        Keybind.Toggled = Bool
        Store()
        if Keybind.Toggle and not FromToggle then Keybind.Toggle:Set(Bool) end
        SafeCall(Keybind.Callback, Bool)
        Keybind:UpdateList()
    end

    function Keybind:Sync(Bool)
        if Keybind.Toggled ~= Bool and Keybind.Mode ~= "Always" then
            Keybind.Toggled = Bool
            Store()
            Keybind:UpdateList()
        end
    end

    function Keybind:SetMode(Mode)
        if Mode ~= "Toggle" and Mode ~= "Hold" and Mode ~= "Always" then return end
        Keybind.Mode = Mode
        Modes:Set(Mode)
        Store()
        if Mode == "Always" then
            Keybind:SetState(true)
        elseif Keybind.Toggled then
            Keybind:SetState(false)
        end
        Keybind:UpdateList()
    end

    function Keybind:SetKey(Key)
        Keybind.Key = Key
        Keybind.Picking = false
        local Name = KeyName(Key)
        PillText.Text = Name
        KeyLabel.Text = Name
        Paint(KeyLabel, "TextColor3", "Text")
        Store()
        if Keybind.KeyChanged then SafeCall(Keybind.KeyChanged, Key) end
        Keybind:UpdateList()
    end

    function Keybind:Set(Value)
        if typeof(Value) == "EnumItem" then
            Keybind:SetKey(Value)
        elseif type(Value) == "table" then
            if Value.Key ~= nil then Keybind:SetKey(ParseKey(Value.Key)) end
            if Value.Mode then Keybind:SetMode(Value.Mode) end
        elseif type(Value) == "string" then
            if Value == "Toggle" or Value == "Hold" or Value == "Always" then
                Keybind:SetMode(Value)
            else
                Keybind:SetKey(ParseKey(Value))
            end
        end
    end

    function Keybind:SetVisibility(Bool) Pill.Visible = Bool end

    local Listening
    KeyButton.MouseButton1Click:Connect(function()
        if Listening then return end
        Keybind.Picking = true
        KeyLabel.Text = "Press a key..."
        Paint(KeyLabel, "TextColor3", "Accent")
        Listening = UserInputService.InputBegan:Connect(function(Input)
            local Key
            if Input.UserInputType == Enum.UserInputType.Keyboard then
                Key = Input.KeyCode
            elseif string.find(Input.UserInputType.Name, "MouseButton") then
                Key = Input.UserInputType
            else
                return
            end
            Listening:Disconnect()
            Listening = nil
            if Key == Enum.KeyCode.Escape or Key == Enum.KeyCode.Backspace then Key = nil end
            task.defer(function() Keybind:SetKey(Key) end)
        end)
    end)

    Pill.MouseButton1Click:Connect(function() Popup:Toggle() end)
    Pill.MouseEnter:Connect(function() Paint(PillText, "TextColor3", "Text", D(0.5)) end)
    Pill.MouseLeave:Connect(function() Paint(PillText, "TextColor3", "Dark Text", D(0.5)) end)

    Library:Connect(UserInputService.InputBegan, function(Input, Processed)
        if Processed or Keybind.Picking or not Keybind.Key then return end
        if Input.KeyCode == Keybind.Key or Input.UserInputType == Keybind.Key then
            if Keybind.Mode == "Toggle" then
                Keybind:SetState(not Keybind.Toggled)
            elseif Keybind.Mode == "Hold" then
                Keybind:SetState(true)
            end
        end
    end)

    Library:Connect(UserInputService.InputEnded, function(Input)
        if Keybind.Mode ~= "Hold" or not Keybind.Key then return end
        if Input.KeyCode == Keybind.Key or Input.UserInputType == Keybind.Key then
            Keybind:SetState(false)
        end
    end)

    Keybind.Popup = Popup
    table.insert(Library.Keybinds, Keybind)
    Library.Setters[Keybind.Flag] = function(Value) Keybind:Set(Value) end

    Modes:Set(Keybind.Mode, true)
    Store()
    AttachKeybindEntry(Keybind)

    local Default = Params.Default or Params.default
    if Default then Keybind:Set(Default) end
    if Keybind.Mode == "Always" then Keybind:SetState(true) end

    return Keybind
end

--// toggle ---------------------------------------------------------------------
function Container:Toggle(Params)
    Params = Params or { }
    local Name = Params.Name or Params.name or "Toggle"
    local Toggle = {
        Name = Name, Value = false,
        Flag = Params.Flag or Params.flag or Name,
        Callback = Params.Callback or Params.callback or function() end,
        Window = self.Window, Page = self.Page, Section = self.Section, Popup = self.Popup,
    }

    local Row = MakeRow(self, 34, "TextButton")
    Tip(Row, Params.Tooltip or Params.tooltip)

    local Text = New("TextLabel", {
        Text = Name, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
        AutomaticSize = Enum.AutomaticSize.XY, TextXAlignment = Enum.TextXAlignment.Left, Parent = Row
    }, { TextColor3 = "Dark Text" })

    local Track = New("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0),
        Size = UDim2.fromOffset(34, 18), Parent = Row
    }, { BackgroundColor3 = "Toggle" })
    Corner(Track, 9)

    local Thumb = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 3, 0.5, 0),
        Size = UDim2.fromOffset(12, 12), Parent = Track
    }, { BackgroundColor3 = "Dark Text" })
    Corner(Thumb, 6)

    local Sub = SubHolder(Row, -54)

    function Toggle:Set(Bool)
        Bool = Bool and true or false
        local Changed = Toggle.Value ~= Bool
        Toggle.Value = Bool
        Library.Flags[Toggle.Flag] = Bool

        Paint(Track, "BackgroundColor3", Bool and "Accent" or "Toggle")
        Paint(Thumb, "BackgroundColor3", Bool and "Text" or "Dark Text")
        Paint(Text, "TextColor3", Bool and "Text" or "Dark Text")
        Tween(Thumb, {
            AnchorPoint = Vector2.new(Bool and 1 or 0, 0.5),
            Position = UDim2.new(Bool and 1 or 0, Bool and -3 or 3, 0.5, 0)
        }, D(1.2), "Quint", "Out")

        if Changed then
            -- squash & stretch while the thumb travels
            TweenService:Create(Thumb, TweenInfo.new(D(0.55), Enum.EasingStyle.Quad, Enum.EasingDirection.Out, 0, true), {
                Size = UDim2.fromOffset(18, 12)
            }):Play()
        end

        if Toggle.Linked then Toggle.Linked:Sync(Bool) end
        SafeCall(Toggle.Callback, Bool)
    end

    function Toggle:SetVisibility(Bool) Row.Visible = Bool end
    function Toggle:SetText(NewText) Text.Text = tostring(NewText) end

    function Toggle:Colorpicker(Data)
        return BuildColorpicker(Toggle, Sub, Data or { }, Name)
    end

    function Toggle:Keybind(Data)
        Data = Data or { }
        Data.Toggle = Toggle
        local Keybind = BuildKeybind(Toggle, Sub, Data, Name)
        Toggle.Linked = Keybind
        return Keybind
    end

    function Toggle:Settings(Height)
        local Gear = New("ImageButton", {
            Size = UDim2.fromOffset(18, 18), Image = "rbxassetid://128889160605702", Parent = Sub
        }, { ImageColor3 = "Dark Icon" })
        local Popup = NewPopup({
            Anchor = Gear, Width = 270, Height = (Height or 200) + 24, Align = "Right", Parent = Toggle.Popup
        })
        Pad(Popup.Frame, 12)
        local Scroll = New("ScrollingFrame", { Size = UDim2.fromScale(1, 1), Active = true, Parent = Popup.Frame })
        List(Scroll, 4)
        Pad(Scroll, 0, 8, 0, 0)

        Gear.MouseButton1Click:Connect(function() Popup:Toggle() end)
        Gear.MouseEnter:Connect(function() if not Popup.Open then Paint(Gear, "ImageColor3", "Text", D(0.5)) end end)
        Gear.MouseLeave:Connect(function() if not Popup.Open then Paint(Gear, "ImageColor3", "Dark Icon", D(0.5)) end end)
        Popup.Changed = function(Open)
            Paint(Gear, "ImageColor3", Open and "Accent" or "Dark Icon")
            Tween(Gear, { Rotation = Open and 60 or 0 }, D(1.2), "Back", "Out")
        end

        return setmetatable({ Window = Toggle.Window, Page = nil, Section = nil, Popup = Popup, Content = Scroll, IsSettings = true }, ContainerMeta)
    end

    Row.MouseButton1Click:Connect(function() Toggle:Set(not Toggle.Value) end)

    Register(self, Name, Row)
    Library.Setters[Toggle.Flag] = function(Value) Toggle:Set(Value) end
    Toggle:Set(Params.Default or Params.default or false)
    return Toggle
end

--// button ---------------------------------------------------------------------
function Container:Button(Params)
    Params = Params or { }
    local Name = Params.Name or Params.name or "Button"
    local Button = { Name = Name, Window = self.Window, Page = self.Page, Section = self.Section }

    local Row = New("Frame", { Size = UDim2.new(1, 0, 0, 36), Parent = self.Content })
    Tip(Row, Params.Tooltip or Params.tooltip)
    local Inner = BuildButton(Row, Name, UDim2.new(1, 0, 0, 32), Params.Callback or Params.callback)
    Inner.Frame.Position = UDim2.new(0, 0, 0, 2)

    function Button:Press() Inner:Press() end
    function Button:SetText(Text) Inner:SetText(Text) end
    function Button:SetVisibility(Bool) Row.Visible = Bool end

    Register(self, Name, Row)
    return Button
end

--// slider / range slider --------------------------------------------------------
local function BuildSlider(Owner, Params, IsRange)
    local Name = Params.Name or Params.name or (IsRange and "Range" or "Slider")
    local Slider = {
        Name = Name, IsRange = IsRange,
        Flag = Params.Flag or Params.flag or Name,
        Min = Params.Min or Params.min or 0,
        Max = Params.Max or Params.max or 100,
        Step = Params.Decimals or Params.decimals or 1,
        Gap = Params.Gap or Params.gap or 16,
        Suffix = Params.Suffix or Params.suffix or "",
        Callback = Params.Callback or Params.callback or function() end,
        Window = Owner.Window, Page = Owner.Page, Section = Owner.Section,
    }
    if type(Slider.Step) ~= "number" or Slider.Step <= 0 then Slider.Step = 1 end
    local Span = Slider.Max - Slider.Min

    local Row = MakeRow(Owner, 50)
    Tip(Row, Params.Tooltip or Params.tooltip)

    local Text = New("TextLabel", {
        Text = Name, Position = UDim2.new(0, 10, 0, 7), AutomaticSize = Enum.AutomaticSize.XY,
        TextXAlignment = Enum.TextXAlignment.Left, Parent = Row
    }, { TextColor3 = "Text" })
    local Value = New("TextLabel", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -10, 0, 7), AutomaticSize = Enum.AutomaticSize.XY,
        TextXAlignment = Enum.TextXAlignment.Right, Parent = Row
    }, { TextColor3 = "Dark Text" })

    local Track = New("Frame", {
        Position = UDim2.new(0, 10, 0, 34), Size = UDim2.new(1, -20, 0, 6), Parent = Row
    }, { BackgroundColor3 = "Background" })
    Corner(Track, 3)

    local Fill = New("Frame", { Size = UDim2.fromScale(0, 1), Parent = Track }, { BackgroundColor3 = "Accent" })
    Corner(Fill, 3)

    local function MakeThumb()
        local Thumb = New("Frame", {
            AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0, 0.5),
            Size = UDim2.fromOffset(12, 12), Parent = Track
        }, { BackgroundColor3 = "Text" })
        Corner(Thumb, 9)
        Stroke(Thumb, "Inline", 0, 2)
        return Thumb
    end
    local ThumbA = MakeThumb()
    local ThumbB = IsRange and MakeThumb() or nil

    local Hit = New("TextButton", { Position = UDim2.new(0, 0, 0, 22), Size = UDim2.new(1, 0, 0, 28), Parent = Row })

    local function ToScale(Number)
        if Span <= 0 then return 0 end
        return math.clamp((Number - Slider.Min) / Span, 0, 1)
    end

    local function Fit(Number)
        Number = math.clamp(Number, Slider.Min, Slider.Max)
        Number = Round(Number - Slider.Min, Slider.Step) + Slider.Min
        return Clean(math.clamp(Number, Slider.Min, Slider.Max))
    end

    local Decimals = StepDecimals(Slider.Step)
    local function Format(Number)
        return string.format("%." .. Decimals .. "f", Number)
    end

    local Dragging = false
    function Slider:Render()
        local Time = Dragging and 0.07 or D(0.9)
        if IsRange then
            local A, B = ToScale(Slider.Value[1]), ToScale(Slider.Value[2])
            Tween(Fill, { Position = UDim2.fromScale(A, 0), Size = UDim2.fromScale(B - A, 1) }, Time, "Quad", "Out")
            Tween(ThumbA, { Position = UDim2.fromScale(A, 0.5) }, Time, "Quad", "Out")
            Tween(ThumbB, { Position = UDim2.fromScale(B, 0.5) }, Time, "Quad", "Out")
            Value.Text = Format(Slider.Value[1]) .. " - " .. Format(Slider.Value[2]) .. Slider.Suffix
        else
            local A = ToScale(Slider.Value)
            Tween(Fill, { Size = UDim2.fromScale(A, 1) }, Time, "Quad", "Out")
            Tween(ThumbA, { Position = UDim2.fromScale(A, 0.5) }, Time, "Quad", "Out")
            Value.Text = Format(Slider.Value) .. Slider.Suffix
        end
    end

    function Slider:Set(A, B)
        if IsRange then
            if type(A) == "table" then A, B = A[1], A[2] end
            A = Fit(tonumber(A) or Slider.Min)
            B = Fit(tonumber(B) or Slider.Max)
            if A > B then A, B = B, A end
            Slider.Value = { A, B }
        else
            if type(A) == "table" then A = A[1] end
            Slider.Value = Fit(tonumber(A) or Slider.Min)
        end
        Library.Flags[Slider.Flag] = Slider.Value
        Slider:Render()
        SafeCall(Slider.Callback, Slider.Value)
    end

    function Slider:SetVisibility(Bool) Row.Visible = Bool end
    function Slider:SetText(NewText) Text.Text = tostring(NewText) end

    local ActiveThumb = ThumbA
    local ActiveIndex = 1

    local function Grow(Thumb, Size)
        Tween(Thumb, { Size = UDim2.fromOffset(Size, Size) }, D(0.6), "Back", "Out")
    end

    Slide(Hit, function(Scale)
        local Number = Slider.Min + Scale.X * Span
        if IsRange then
            local Gap = (Slider.Gap / math.max(Track.AbsoluteSize.X / RootScale.Scale, 1)) * Span
            if ActiveIndex == 1 then
                Slider:Set(math.min(Number, Slider.Value[2] - Gap), Slider.Value[2])
            else
                Slider:Set(Slider.Value[1], math.max(Number, Slider.Value[1] + Gap))
            end
        else
            Slider:Set(Number)
        end
    end, function(Scale)
        Dragging = true
        if IsRange then
            local Number = Slider.Min + Scale.X * Span
            local DistA = math.abs(Number - Slider.Value[1])
            local DistB = math.abs(Number - Slider.Value[2])
            if DistA < DistB or (DistA == DistB and Number < Slider.Value[1]) then
                ActiveIndex, ActiveThumb = 1, ThumbA
            else
                ActiveIndex, ActiveThumb = 2, ThumbB
            end
        end
        Grow(ActiveThumb, 17)
        Paint(Value, "TextColor3", "Accent")
    end, function()
        Dragging = false
        Grow(ActiveThumb, 12)
        Paint(Value, "TextColor3", "Dark Text")
        Slider:Render()
    end)

    Row.MouseEnter:Connect(function() if not Dragging then Grow(ThumbA, 15) if ThumbB then Grow(ThumbB, 15) end end end)
    Row.MouseLeave:Connect(function() if not Dragging then Grow(ThumbA, 12) if ThumbB then Grow(ThumbB, 12) end end end)

    Register(Owner, Name, Row)
    Library.Setters[Slider.Flag] = function(A, B) Slider:Set(A, B) end

    local Default = Params.Default or Params.default
    if IsRange then
        Default = type(Default) == "table" and Default or { Slider.Min, Slider.Max }
        Slider:Set(Default[1], Default[2])
    else
        Slider:Set(Default or Slider.Min)
    end
    return Slider
end

function Container:Slider(Params) return BuildSlider(self, Params or { }, false) end
function Container:RangeSlider(Params) return BuildSlider(self, Params or { }, true) end

--// dropdown -------------------------------------------------------------------
function Container:Dropdown(Params)
    Params = Params or { }
    local Name = Params.Name or Params.name or "Dropdown"
    local Dropdown = {
        Name = Name, Flag = Params.Flag or Params.flag or Name,
        Multi = Params.Multi or Params.multi or false,
        Callback = Params.Callback or Params.callback or function() end,
        Options = { }, List = { },
        Window = self.Window, Page = self.Page, Section = self.Section, Popup = self.Popup,
    }
    Dropdown.Value = Dropdown.Multi and { } or nil

    local Row = MakeRow(self, 38)
    Tip(Row, Params.Tooltip or Params.tooltip)

    local Text = New("TextLabel", {
        Text = Name, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
        AutomaticSize = Enum.AutomaticSize.XY, TextXAlignment = Enum.TextXAlignment.Left, Parent = Row
    }, { TextColor3 = "Text" })

    local Box = New("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(136, 26),
        BackgroundTransparency = 0, Parent = Row
    }, { BackgroundColor3 = "Background" })
    Corner(Box, 7)
    Stroke(Box, "Outline", 0.5)

    local ValueLabel = New("TextLabel", {
        Text = "...", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0), Size = UDim2.new(1, -32, 0, 16),
        TextXAlignment = Enum.TextXAlignment.Left, TextTruncate = Enum.TextTruncate.AtEnd, Parent = Box
    }, { TextColor3 = "Text" })
    local Arrow = New("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.new(1, -13, 0.5, 0), Size = UDim2.fromOffset(12, 12),
        Image = "rbxassetid://127296511745226", Parent = Box
    }, { ImageColor3 = "Dark Icon" })

    Box.MouseEnter:Connect(function() Paint(Box, "BackgroundColor3", "Element", D(0.5)) end)
    Box.MouseLeave:Connect(function() Paint(Box, "BackgroundColor3", "Background", D(0.5)) end)

    local Popup = NewPopup({ Anchor = Box, Width = 156, Height = 120, Align = "Right", Parent = Dropdown.Popup })
    Pad(Popup.Frame, 6)
    local Scroll = New("ScrollingFrame", { Size = UDim2.fromScale(1, 1), Active = true, Parent = Popup.Frame })
    List(Scroll, 2)
    Pad(Scroll, 0, 4, 0, 0)

    local function IsSelected(OptionName)
        if Dropdown.Multi then return table.find(Dropdown.Value, OptionName) ~= nil end
        return Dropdown.Value == OptionName
    end

    local function Visuals()
        for _, Option in pairs(Dropdown.Options) do
            local Selected = IsSelected(Option.Name)
            Option.Selected = Selected
            Paint(Option.Label, "TextColor3", Selected and "Accent" or "Dark Text")
            Tween(Option.Check, { ImageTransparency = Selected and 0 or 1 }, D(0.7), "Quad", "Out")
        end
        if Dropdown.Multi then
            ValueLabel.Text = #Dropdown.Value > 0 and table.concat(Dropdown.Value, ", ") or "..."
        else
            ValueLabel.Text = Dropdown.Value ~= nil and tostring(Dropdown.Value) or "..."
        end
    end

    local function Commit()
        Library.Flags[Dropdown.Flag] = Dropdown.Value
        Visuals()
        SafeCall(Dropdown.Callback, Dropdown.Value)
    end

    function Dropdown:Set(Value)
        if Dropdown.Multi then
            local Filtered = { }
            if type(Value) == "table" then
                for _, Item in ipairs(Value) do
                    if Dropdown.Options[Item] then table.insert(Filtered, Item) end
                end
            end
            Dropdown.Value = Filtered
        else
            if Value ~= nil and Dropdown.Options[Value] then
                Dropdown.Value = Value
            else
                Dropdown.Value = nil
            end
        end
        Commit()
    end

    function Dropdown:Add(OptionName)
        OptionName = tostring(OptionName)
        if Dropdown.Options[OptionName] then return Dropdown.Options[OptionName] end

        local Button = New("TextButton", { Size = UDim2.new(1, 0, 0, 28), Parent = Scroll }, { BackgroundColor3 = "Element" })
        Button.BackgroundTransparency = 1
        Corner(Button, 6)
        local Label = New("TextLabel", {
            Text = OptionName, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
            AutomaticSize = Enum.AutomaticSize.XY, Parent = Button
        }, { TextColor3 = "Dark Text" })
        local Check = New("ImageLabel", {
            AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.fromOffset(12, 12),
            Image = "rbxassetid://114461119629011", ImageTransparency = 1, Parent = Button
        }, { ImageColor3 = "Accent" })

        local Option = { Name = OptionName, Button = Button, Label = Label, Check = Check, Selected = false }

        Button.MouseEnter:Connect(function()
            Tween(Button, { BackgroundTransparency = 0.4 }, D(0.5), "Quad", "Out")
            if not Option.Selected then Paint(Label, "TextColor3", "Text", D(0.5)) end
        end)
        Button.MouseLeave:Connect(function()
            Tween(Button, { BackgroundTransparency = 1 }, D(0.5), "Quad", "Out")
            if not Option.Selected then Paint(Label, "TextColor3", "Dark Text", D(0.5)) end
        end)
        Button.MouseButton1Click:Connect(function()
            if Dropdown.Multi then
                local Index = table.find(Dropdown.Value, OptionName)
                if Index then table.remove(Dropdown.Value, Index) else table.insert(Dropdown.Value, OptionName) end
                Commit()
            else
                Dropdown.Value = OptionName
                Commit()
                task.delay(0.08, function() Popup:SetOpen(false) end)
            end
        end)

        Dropdown.Options[OptionName] = Option
        table.insert(Dropdown.List, Option)
        return Option
    end

    function Dropdown:Remove(OptionName)
        local Option = Dropdown.Options[OptionName]
        if not Option then return end
        Option.Button:Destroy()
        Dropdown.Options[OptionName] = nil
        table.remove(Dropdown.List, table.find(Dropdown.List, Option))
        if Dropdown.Multi then
            local Index = table.find(Dropdown.Value, OptionName)
            if Index then table.remove(Dropdown.Value, Index) end
        elseif Dropdown.Value == OptionName then
            Dropdown.Value = nil
        end
        Visuals()
    end

    function Dropdown:Refresh(Items)
        for _, Option in ipairs(Dropdown.List) do Option.Button:Destroy() end
        Dropdown.Options, Dropdown.List = { }, { }
        for _, Item in ipairs(Items or { }) do Dropdown:Add(Item) end

        if Dropdown.Multi then
            local Kept = { }
            for _, Item in ipairs(Dropdown.Value) do
                if Dropdown.Options[Item] then table.insert(Kept, Item) end
            end
            Dropdown.Value = Kept
        elseif Dropdown.Value ~= nil and not Dropdown.Options[Dropdown.Value] then
            Dropdown.Value = nil
        end
        Library.Flags[Dropdown.Flag] = Dropdown.Value
        Visuals()
    end

    function Dropdown:SetText(NewText) Text.Text = tostring(NewText) end
    function Dropdown:SetVisibility(Bool) Row.Visible = Bool end

    Popup.BeforeOpen = function()
        Popup.Height = math.clamp(#Dropdown.List * 30 + 12, 44, 212)
    end
    Popup.OnOpen = function()
        for Index, Option in ipairs(Dropdown.List) do
            if Index > 10 then break end
            Option.Label.Position = UDim2.new(0, 22, 0.5, 0)
            Option.Label.TextTransparency = 1
            local Info = TweenInfo.new(D(1.2), Enum.EasingStyle.Quint, Enum.EasingDirection.Out, 0, false, Index * 0.018)
            TweenService:Create(Option.Label, Info, { Position = UDim2.new(0, 10, 0.5, 0), TextTransparency = 0 }):Play()
        end
    end
    Popup.Changed = function(Open)
        Tween(Arrow, { Rotation = Open and 180 or 0 }, D(1.2), "Back", "Out")
        Paint(Arrow, "ImageColor3", Open and "Accent" or "Dark Icon")
    end

    Box.MouseButton1Click:Connect(function() Popup:Toggle() end)

    Register(self, Name, Row)
    Library.Setters[Dropdown.Flag] = function(Value) Dropdown:Set(Value) end

    for _, Item in ipairs(Params.Items or Params.items or { }) do Dropdown:Add(Item) end
    local Default = Params.Default or Params.default
    if Default ~= nil and Default ~= "" then Dropdown:Set(Default) else Visuals() end
    return Dropdown
end

--// label ----------------------------------------------------------------------
function Container:Label(Params)
    Params = Params or { }
    local Name = Params.Name or Params.name or "Label"
    local Label = { Name = Name, Window = self.Window, Page = self.Page, Section = self.Section, Popup = self.Popup }

    local Row = MakeRow(self, 32)
    Tip(Row, Params.Tooltip or Params.tooltip)
    local Text = New("TextLabel", {
        Text = Name, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
        AutomaticSize = Enum.AutomaticSize.XY, TextXAlignment = Enum.TextXAlignment.Left, Parent = Row
    }, { TextColor3 = "Text" })
    local Sub = SubHolder(Row, -10)

    function Label:SetText(NewText) Text.Text = tostring(NewText) end
    function Label:SetVisibility(Bool) Row.Visible = Bool end
    function Label:Colorpicker(Data) return BuildColorpicker(Label, Sub, Data or { }, Name) end
    function Label:Keybind(Data) return BuildKeybind(Label, Sub, Data or { }, Name) end

    Register(self, Name, Row)
    return Label
end

--// textbox --------------------------------------------------------------------
function Container:Textbox(Params)
    Params = Params or { }
    local Name = Params.Name or Params.name or "Textbox"
    local Textbox = {
        Name = Name, Value = "",
        Flag = Params.Flag or Params.flag or Name,
        Callback = Params.Callback or Params.callback or function() end,
        Finished = Params.Finished or Params.finished or false,
        Numeric = Params.Numeric or Params.numeric or false,
        Window = self.Window, Page = self.Page, Section = self.Section,
    }

    local Row = MakeRow(self, 40)
    Tip(Row, Params.Tooltip or Params.tooltip)
    local Text = New("TextLabel", {
        Text = Name, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 10, 0.5, 0),
        AutomaticSize = Enum.AutomaticSize.XY, TextXAlignment = Enum.TextXAlignment.Left, Parent = Row
    }, { TextColor3 = "Text" })

    local Box = New("Frame", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -8, 0.5, 0), Size = UDim2.new(0.56, 0, 0, 28),
        Parent = Row
    }, { BackgroundColor3 = "Background" })
    Corner(Box, 7)
    local BoxStroke = Stroke(Box, "Accent", 1)

    local Input = New("TextBox", {
        Position = UDim2.new(0, 10, 0, 0), Size = UDim2.new(1, -20, 1, 0), ClearTextOnFocus = false,
        PlaceholderText = Params.Placeholder or Params.placeholder or "", TextXAlignment = Enum.TextXAlignment.Left,
        TextTruncate = Enum.TextTruncate.AtEnd, Parent = Box
    }, { TextColor3 = "Text", PlaceholderColor3 = "Dark Text" })

    Input.Focused:Connect(function()
        Tween(BoxStroke, { Transparency = 0.2 }, D(0.7), "Quad", "Out")
        Paint(Box, "BackgroundColor3", "Element", D(0.7))
    end)
    Input.FocusLost:Connect(function(Enter)
        Tween(BoxStroke, { Transparency = 1 }, D(0.7), "Quad", "Out")
        Paint(Box, "BackgroundColor3", "Background", D(0.7))
        if Textbox.Finished and Enter then Textbox:Set(Input.Text) end
    end)

    function Textbox:Set(Value)
        Value = tostring(Value == nil and "" or Value)
        if Textbox.Numeric and Value ~= "" and not tonumber(Value) then Value = Textbox.Value end
        Textbox.Value = Value
        if Input.Text ~= Value then Input.Text = Value end
        Library.Flags[Textbox.Flag] = Value
        SafeCall(Textbox.Callback, Value)
    end

    function Textbox:SetText(NewText) Text.Text = tostring(NewText) end
    function Textbox:SetVisibility(Bool) Row.Visible = Bool end

    if not Textbox.Finished then
        Input:GetPropertyChangedSignal("Text"):Connect(function() Textbox:Set(Input.Text) end)
    end

    Register(self, Name, Row)
    Library.Setters[Textbox.Flag] = function(Value) Textbox:Set(Value) end
    Textbox:Set(Params.Default or Params.default or "")
    return Textbox
end

--// ---------------------------------------------------------------- HUD: keybind list
function Library:KeybindList(Params)
    Params = Params or { }
    local List_ = { Name = Params.Name or Params.name or "Keybind List", HideInactive = Params.HideInactive or false }
    local Width = Params.Width or 200

    local Frame = New("CanvasGroup", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0),
        Size = UDim2.fromOffset(Width, 0), AutomaticSize = Enum.AutomaticSize.Y,
        GroupTransparency = 1, Parent = HudLayer
    }, { BackgroundColor3 = "Inline" })
    Corner(Frame, 10)
    Stroke(Frame, "Outline", 0.2)
    Pad(Frame, 10, 12, 10, 12)
    List(Frame, 8)

    local Title = New("TextLabel", {
        Text = List_.Name, Size = UDim2.new(1, 0, 0, 18), TextXAlignment = Enum.TextXAlignment.Left,
        LayoutOrder = 1, Parent = Frame
    }, { TextColor3 = "Text" })
    New("Frame", { Size = UDim2.new(1, 0, 0, 1), LayoutOrder = 2, Parent = Frame }, { BackgroundColor3 = "Liner" })
    local Content = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 3, Parent = Frame
    })
    List(Content, 4)

    MakeMotion(Frame):Drag(Frame)
    Tween(Frame, { GroupTransparency = 0 }, D(1.6), "Quint", "Out")

    function List_:SetText(Text) Title.Text = tostring(Text) end
    function List_:SetVisibility(Bool) Frame.Visible = Bool end

    function List_:Add(Name)
        local Entry = { }
        local Row = New("Frame", { Size = UDim2.new(1, 0, 0, 20), ClipsDescendants = false, Parent = Content })
        local Dot = New("Frame", {
            AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(6, 6), Parent = Row
        }, { BackgroundColor3 = "Dark Icon" })
        Corner(Dot, 3)
        local NameLabel = New("TextLabel", {
            Text = Name, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 0),
            AutomaticSize = Enum.AutomaticSize.XY, Parent = Row
        }, { TextColor3 = "Dark Text" })
        local KeyLabel = New("TextLabel", {
            Text = "[None]", TextSize = 12, AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0),
            AutomaticSize = Enum.AutomaticSize.XY, Parent = Row
        }, { TextColor3 = "Dark Icon" })

        local Shown = true
        function Entry:Update(NewName, Key, Active, Mode)
            NameLabel.Text = NewName
            KeyLabel.Text = "[" .. Key .. "]"
            Paint(Dot, "BackgroundColor3", Active and "Accent" or "Dark Icon")
            Paint(NameLabel, "TextColor3", Active and "Text" or "Dark Text")
            Paint(KeyLabel, "TextColor3", Active and "Dark Text" or "Dark Icon")
            Tween(Dot, { Size = UDim2.fromOffset(Active and 8 or 6, Active and 8 or 6) }, D(0.9), "Back", "Out")

            if List_.HideInactive then
                if Active and not Shown then
                    Shown = true
                    Row.Visible = true
                    Tween(Row, { Size = UDim2.new(1, 0, 0, 20) }, D(1), "Quint", "Out")
                elseif not Active and Shown then
                    Shown = false
                    Tween(Row, { Size = UDim2.new(1, 0, 0, 0) }, D(1), "Quint", "Out")
                    task.delay(D(1), function() if not Shown then Row.Visible = false end end)
                end
            end
        end
        return Entry
    end

    Library.KeyList = List_
    for _, Keybind in ipairs(Library.Keybinds) do AttachKeybindEntry(Keybind) end
    return List_
end

--// ---------------------------------------------------------------- notification
local NotifList = New("Frame", { Position = UDim2.fromOffset(14, 14), Size = UDim2.new(0, 300, 1, -28), Parent = NotifLayer })
List(NotifList, 8)

function Library:Notification(Text, Duration, Color, Title)
    Duration = tonumber(Duration) or 4
    Color = Color or Library.Theme.Accent

    task.spawn(function()
        local Width = 290
        local Wrap = New("Frame", { Size = UDim2.fromOffset(Width, 40), Visible = false, Parent = NotifList })
        local Card = New("CanvasGroup", {
            Size = UDim2.fromScale(1, 1), Position = UDim2.new(-1.2, 0, 0, 0), GroupTransparency = 1, Parent = Wrap
        }, { BackgroundColor3 = "Inline" })
        Corner(Card, 10)
        Stroke(Card, "Outline", 0.2)

        local Body = New("Frame", { Position = UDim2.fromOffset(18, 12), Size = UDim2.new(1, -32, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = Card })
        List(Body, 3)
        if Title then
            New("TextLabel", {
                Text = tostring(Title), Size = UDim2.new(1, 0, 0, 16), TextXAlignment = Enum.TextXAlignment.Left, Parent = Body
            }, { TextColor3 = "Text" })
        end
        local Message = New("TextLabel", {
            Text = tostring(Text), TextWrapped = true, TextSize = Title and 13 or Library.FontSize,
            Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
            TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top, Parent = Body
        }, { TextColor3 = Title and "Dark Text" or "Text" })

        task.wait()
        task.wait()
        local Height = math.max(Body.AbsoluteSize.Y / RootScale.Scale, 16) + 12 + 20
        Wrap.Size = UDim2.fromOffset(Width, Height)

        local Bar = New("Frame", { Position = UDim2.fromOffset(8, 10), Size = UDim2.new(0, 3, 1, -20), BackgroundTransparency = 0, Parent = Card })
        Bar.BackgroundColor3 = Color
        Corner(Bar, 2)
        local Progress = New("Frame", {
            Position = UDim2.new(0, 18, 1, -8), Size = UDim2.new(1, -32, 0, 2), BackgroundTransparency = 0.25, Parent = Card
        })
        Progress.BackgroundColor3 = Color
        Corner(Progress, 1)
        local Hit = New("TextButton", { Size = UDim2.fromScale(1, 1), ZIndex = 5, Parent = Card })

        Wrap.Visible = true
        Tween(Card, { Position = UDim2.new(0, 0, 0, 0), GroupTransparency = 0 }, D(2), "Quint", "Out")
        TweenService:Create(Progress, TweenInfo.new(Duration, Enum.EasingStyle.Linear), { Size = UDim2.new(0, 0, 0, 2) }):Play()

        local Closed = false
        local function Close()
            if Closed then return end
            Closed = true
            Tween(Card, { Position = UDim2.new(-1.2, 0, 0, 0), GroupTransparency = 1 }, D(1.4), "Quint", "In")
            task.wait(D(1.4))
            Wrap.ClipsDescendants = true
            Tween(Wrap, { Size = UDim2.fromOffset(Width, 0) }, D(1.2), "Quint", "Out")
            task.wait(D(1.2))
            Wrap:Destroy()
        end

        Hit.MouseButton1Click:Connect(function() task.spawn(Close) end)
        task.delay(Duration, function() task.spawn(Close) end)
    end)
end

--// ---------------------------------------------------------------- window
local WindowMethods = { }
local WindowMeta = { __index = function(_, Key) return WindowMethods[Key] or Library[Key] end }

local PageMethods = { }
local PageMeta = { __index = function(_, Key) return PageMethods[Key] or Library[Key] end }

local TAB_TOP = 74
local TAB_STEP = 50

function WindowMethods:RegisterSearch(Item)
    table.insert(self.SearchItems, Item)
    return Item
end

local function ShowRow(Item, Show, Instant)
    if Item.Shown == Show then return end
    Item.Shown = Show
    Item.Token = (Item.Token or 0) + 1
    local Token = Item.Token
    local Row = Item.Row

    if Instant then
        Row.Visible = Show
        Row.Size = UDim2.new(1, 0, 0, Show and Item.Height or 0)
        return
    end

    Row.ClipsDescendants = true
    if Show then
        Row.Visible = true
        Tween(Row, { Size = UDim2.new(1, 0, 0, Item.Height) }, D(1.1), "Quint", "Out")
        task.delay(D(1.1), function()
            if Item.Token == Token then Row.ClipsDescendants = false end
        end)
    else
        Tween(Row, { Size = UDim2.new(1, 0, 0, 0) }, D(1.1), "Quint", "Out")
        task.delay(D(1.1), function()
            if Item.Token == Token then Row.Visible = false end
        end)
    end
end

function WindowMethods:RefreshSearch(Instant)
    local Query = Normalize(self.Search)
    local Current = self.Current
    local Has = { }

    for _, Item in ipairs(self.SearchItems) do
        if Item.Page == Current then
            local Match = Query == ""
                or Normalize(Item.Name):find(Query, 1, true) ~= nil
                or (Item.Section ~= nil and Normalize(Item.Section.Name):find(Query, 1, true) ~= nil)
            Item.Match = Match
            if Match and Item.Section then Has[Item.Section] = true end
        end
    end

    for _, Item in ipairs(self.SearchItems) do
        if Item.Page == Current then ShowRow(Item, Item.Match, Instant) end
    end

    if Current then
        for _, Section in ipairs(Current.Sections) do
            local Show = Query == "" or Has[Section] == true
            if Section.Shown ~= Show then
                Section.Shown = Show
                Section.Token = (Section.Token or 0) + 1
                local Token = Section.Token
                if Show then
                    Section.Card.Visible = true
                elseif Instant then
                    Section.Card.Visible = false
                else
                    task.delay(D(1.1), function()
                        if Section.Token == Token then Section.Card.Visible = false end
                    end)
                end
            end
        end
    end
end

function WindowMethods:SetOpen(Bool)
    local Window = self
    Window.IsOpen = Bool
    Window.OpenToken = (Window.OpenToken or 0) + 1
    local Token = Window.OpenToken
    local Items = Window.Items

    CloseAllPopups()

    if Bool then
        Items.Main.Visible = true
        Tween(Items.Main, { GroupTransparency = 0 }, D(1.2), "Quint", "Out")
        Tween(Items.WinScale, { Scale = 1 }, D(1.6), "Back", "Out")
    else
        Tween(Items.Main, { GroupTransparency = 1 }, D(0.8), "Quint", "In")
        Tween(Items.WinScale, { Scale = 0.94 }, D(0.8), "Quint", "In")
        task.delay(D(0.8), function()
            if Window.OpenToken == Token then Items.Main.Visible = false end
        end)
    end

    Items.PillText.Text = Bool and "Close" or "Open"
    Tween(Items.PillIcon, { Rotation = Bool and 0 or 180 }, D(1.2), "Back", "Out")
end

function WindowMethods:Toggle()
    self:SetOpen(not self.IsOpen)
end

function WindowMethods:Center()
    self.Items.Main.Position = UDim2.fromScale(0.5, 0.5)
end

function Library:Window(Params)
    Params = Params or { }

    local Window = setmetatable({
        Logo = Params.Logo or Params.logo or Library.DefaultLogo,
        Pages = { }, SearchItems = { }, Items = { },
        IsOpen = false, Search = "", Current = nil,
    }, WindowMeta)

    local Size = Params.Size or Vector2.new(760, 500)
    local Items = Window.Items

    Items.Main = New("CanvasGroup", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5),
        Size = UDim2.fromOffset(Size.X, Size.Y), GroupTransparency = 1, Visible = false, Active = true,
        Parent = WindowLayer
    }, { BackgroundColor3 = "Background" })
    Corner(Items.Main, 14)
    Stroke(Items.Main, "Outline", 0.2)
    Items.WinScale = New("UIScale", { Scale = 0.94, Parent = Items.Main })
    local Main = Items.Main

    --// rail
    local Rail = New("Frame", { Size = UDim2.new(0, 64, 1, 0), Parent = Main }, { BackgroundColor3 = "Inline" })
    New("Frame", { AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0), Size = UDim2.new(0, 1, 1, 0), Parent = Rail }, { BackgroundColor3 = "Liner" })

    New("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 18), Size = UDim2.fromOffset(30, 30),
        Image = Window.Logo, ScaleType = Enum.ScaleType.Fit, Parent = Rail
    })

    Items.TabPill = New("Frame", {
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, TAB_TOP), Size = UDim2.fromOffset(42, 42),
        Visible = false, Parent = Rail
    }, { BackgroundColor3 = "Tab" })
    Corner(Items.TabPill, 12)

    Items.TabBar = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0, TAB_TOP + 21), Size = UDim2.fromOffset(3, 18),
        Visible = false, Parent = Rail
    }, { BackgroundColor3 = "Accent" })
    Corner(Items.TabBar, 2)

    local Avatar = New("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(36, 36),
        BackgroundTransparency = 0, Parent = Rail
    }, { BackgroundColor3 = "Element" })
    Corner(Avatar, 18)
    Stroke(Avatar, "Outline", 0, 1.5)
    task.spawn(function()
        local Success, Image = pcall(Players.GetUserThumbnailAsync, Players, LocalPlayer.UserId, Enum.ThumbnailType.HeadShot, Enum.ThumbnailSize.Size100x100)
        if Success then Avatar.Image = Image end
    end)

    --// top bar
    local Top = New("Frame", { Position = UDim2.fromOffset(64, 0), Size = UDim2.new(1, -64, 0, 56), Parent = Main })
    New("Frame", { AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.new(1, 0, 0, 1), Parent = Top }, { BackgroundColor3 = "Liner" })

    local Search = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 16, 0.5, 0), Size = UDim2.fromOffset(230, 34), Parent = Top
    }, { BackgroundColor3 = "Element" })
    Corner(Search, 10)
    local SearchStroke = Stroke(Search, "Accent", 1)
    New("ImageLabel", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(15, 15),
        Image = "rbxassetid://115682280990954", Parent = Search
    }, { ImageColor3 = "Dark Icon" })
    local Input = New("TextBox", {
        Position = UDim2.new(0, 36, 0, 0), Size = UDim2.new(1, -46, 1, 0), PlaceholderText = "Search in this tab...",
        ClearTextOnFocus = false, TextXAlignment = Enum.TextXAlignment.Left, Parent = Search
    }, { TextColor3 = "Text", PlaceholderColor3 = "Dark Text" })

    Input.Focused:Connect(function()
        Tween(Search, { Size = UDim2.fromOffset(290, 34) }, D(1.2), "Quint", "Out")
        Tween(SearchStroke, { Transparency = 0.2 }, D(0.7), "Quad", "Out")
    end)
    Input.FocusLost:Connect(function()
        Tween(Search, { Size = UDim2.fromOffset(230, 34) }, D(1.2), "Quint", "Out")
        Tween(SearchStroke, { Transparency = 1 }, D(0.7), "Quad", "Out")
    end)
    Input:GetPropertyChangedSignal("Text"):Connect(function()
        Window.Search = Input.Text
        Window:RefreshSearch()
    end)

    local Gear = New("TextButton", {
        AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -16, 0.5, 0), Size = UDim2.fromOffset(34, 34), Parent = Top
    }, { BackgroundColor3 = "Element" })
    Corner(Gear, 10)
    local GearIcon = New("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(18, 18),
        Image = "rbxassetid://77336523487505", Parent = Gear
    }, { ImageColor3 = "Dark Icon" })
    Gear.MouseEnter:Connect(function() Paint(Gear, "BackgroundColor3", "Hovered Element", D(0.5)) end)
    Gear.MouseLeave:Connect(function() Paint(Gear, "BackgroundColor3", "Element", D(0.5)) end)

    --// page area
    Items.Content = New("Frame", {
        Position = UDim2.fromOffset(64, 57), Size = UDim2.new(1, -64, 1, -57), ClipsDescendants = true, Parent = Main
    })
    Items.Rail = Rail

    --// drag / resize
    local Motion = MakeMotion(Main)
    Motion:Drag(Top)
    Motion:Drag(Rail)

    local function Handle(Position, HandleSize, Anchor, DirX, DirY)
        local Button = New("TextButton", { Position = Position, Size = HandleSize, AnchorPoint = Anchor, ZIndex = 10, Parent = Main })
        Motion:Resize(Button, DirX, DirY, Size)
    end
    Handle(UDim2.new(1, 0, 0, 14), UDim2.new(0, 6, 1, -28), Vector2.new(1, 0), 1, 0)
    Handle(UDim2.new(0, 0, 0, 14), UDim2.new(0, 6, 1, -28), Vector2.new(0, 0), -1, 0)
    Handle(UDim2.new(0, 14, 1, 0), UDim2.new(1, -28, 0, 6), Vector2.new(0, 1), 0, 1)
    Handle(UDim2.new(0, 14, 0, 0), UDim2.new(1, -28, 0, 5), Vector2.new(0, 0), 0, -1)
    Handle(UDim2.new(1, 0, 1, 0), UDim2.fromOffset(14, 14), Vector2.new(1, 1), 1, 1)
    Handle(UDim2.new(0, 0, 1, 0), UDim2.fromOffset(14, 14), Vector2.new(0, 1), -1, 1)
    Handle(UDim2.new(1, 0, 0, 0), UDim2.fromOffset(14, 14), Vector2.new(1, 0), 1, -1)
    Handle(UDim2.new(0, 0, 0, 0), UDim2.fromOffset(14, 14), Vector2.new(0, 0), -1, -1)

    --// open / close pill
    local Pill = New("TextButton", {
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 12), Size = UDim2.fromOffset(108, 34),
        BackgroundTransparency = 0, Parent = HudLayer
    }, { BackgroundColor3 = "Inline" })
    Corner(Pill, 17)
    Stroke(Pill, "Outline", 0.2)
    Items.PillIcon = New("ImageLabel", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(20, 20),
        Image = Window.Logo, ScaleType = Enum.ScaleType.Fit, Parent = Pill
    })
    Items.PillText = New("TextLabel", {
        Text = "Close", AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 42, 0.5, 0),
        AutomaticSize = Enum.AutomaticSize.XY, Parent = Pill
    }, { TextColor3 = "Text" })
    Pill.MouseEnter:Connect(function() Paint(Pill, "BackgroundColor3", "Element", D(0.5)) end)
    Pill.MouseLeave:Connect(function() Paint(Pill, "BackgroundColor3", "Inline", D(0.5)) end)
    Pill.MouseButton1Click:Connect(function() Window:Toggle() end)

    Library:Connect(UserInputService.InputBegan, function(Input_)
        if Input_.KeyCode == Library.MenuKeybind or Input_.UserInputType == Library.MenuKeybind then
            if UserInputService:GetFocusedTextBox() then return end
            Window:Toggle()
        end
    end)

    --// settings popup
    local Settings = NewPopup({ Anchor = Gear, Width = 320, Height = 372, Align = "Right" })
    Pad(Settings.Frame, 12)
    Settings.Changed = function(Open)
        Paint(GearIcon, "ImageColor3", Open and "Accent" or "Dark Icon")
        Tween(GearIcon, { Rotation = Open and 90 or 0 }, D(1.4), "Back", "Out")
    end
    Gear.MouseButton1Click:Connect(function() Settings:Toggle() end)

    local TabHost = New("Frame", { Position = UDim2.fromOffset(0, 44), Size = UDim2.new(1, 0, 1, -44), Parent = Settings.Frame })
    local SettingTabs = { }
    local CurrentTab

    local function MakeSettingsTab(Name)
        local Group = New("CanvasGroup", { Size = UDim2.fromScale(1, 1), GroupTransparency = 1, Visible = false, Parent = TabHost })
        local Scroll = New("ScrollingFrame", { Size = UDim2.fromScale(1, 1), Active = true, Parent = Group })
        List(Scroll, 4)
        Pad(Scroll, 0, 8, 0, 0)
        local Tab = setmetatable({ Window = Window, Page = nil, Section = nil, Popup = Settings, Content = Scroll, IsSettings = true }, ContainerMeta)
        SettingTabs[Name] = { Group = Group, Tab = Tab }
        return Tab
    end

    local function SwitchSettingsTab(Name)
        if CurrentTab == Name then return end
        CurrentTab = Name
        for Other, Data in pairs(SettingTabs) do
            if Other == Name then
                Data.Group.Visible = true
                Data.Group.Position = UDim2.fromOffset(0, 12)
                Tween(Data.Group, { Position = UDim2.fromOffset(0, 0), GroupTransparency = 0 }, D(1.2), "Quint", "Out")
            elseif Data.Group.Visible then
                Tween(Data.Group, { GroupTransparency = 1 }, D(0.5), "Quad", "Out")
                task.delay(D(0.5), function()
                    if CurrentTab ~= Other then Data.Group.Visible = false end
                end)
            end
        end
    end

    local SettingsSegment = Segmented(Settings.Frame, { "Configs", "Theme", "Other" }, UDim2.new(1, 0, 0, 34), UDim2.new(0, 0, 0, 0), SwitchSettingsTab)

    local ConfigsTab = MakeSettingsTab("Configs")
    local ThemeTab = MakeSettingsTab("Theme")
    local OtherTab = MakeSettingsTab("Other")

    do -- configs
        local Selected, NewName
        local Folder = Library.Directory .. Library.Folders.Configs .. "/"

        local ConfigsDropdown = ConfigsTab:Dropdown({
            Name = "Configs", Flag = "Configs", Items = { },
            Callback = function(Value) Selected = Value end
        })
        ConfigsTab:Textbox({
            Name = "Config name", Flag = "ConfigName", Placeholder = "name...",
            Callback = function(Value) NewName = Value end
        })

        local function Pair(LeftText, LeftCallback, RightText, RightCallback)
            local Row = New("Frame", { Size = UDim2.new(1, 0, 0, 34), Parent = ConfigsTab.Content })
            List(Row, 6, true)
            BuildButton(Row, LeftText, UDim2.new(0.5, -3, 1, -2), LeftCallback)
            BuildButton(Row, RightText, UDim2.new(0.5, -3, 1, -2), RightCallback)
        end

        local function Need()
            if HasFS then return true end
            Library:Notification("Your executor has no file access", 3, Color3.fromRGB(255, 90, 90), "Configs")
            return false
        end

        Pair("Create", function()
            if not Need() or not NewName or NewName == "" then return end
            writefile(Folder .. NewName .. ".json", Library:GetConfig())
            Library:GetConfigsList(ConfigsDropdown)
            Library:Notification("Created config " .. NewName, 3, Color3.fromRGB(80, 220, 120), "Configs")
        end, "Delete", function()
            if not Need() or not Selected then return end
            if isfile(Folder .. Selected .. ".json") then
                delfile(Folder .. Selected .. ".json")
                Library:GetConfigsList(ConfigsDropdown)
                Library:Notification("Deleted config " .. Selected, 3, Color3.fromRGB(80, 220, 120), "Configs")
            end
        end)

        Pair("Load", function()
            if not Need() or not Selected then return end
            if isfile(Folder .. Selected .. ".json") then
                local Success, Error = Library:LoadConfig(readfile(Folder .. Selected .. ".json"))
                if Success then
                    Library:Notification("Loaded config " .. Selected, 3, Color3.fromRGB(80, 220, 120), "Configs")
                else
                    Library:Notification(tostring(Error), 4, Color3.fromRGB(255, 90, 90), "Failed to load")
                end
            end
        end, "Save", function()
            if not Need() or not Selected then return end
            if isfile(Folder .. Selected .. ".json") then
                local Success, Error = pcall(writefile, Folder .. Selected .. ".json", Library:GetConfig())
                if Success then
                    Library:Notification("Saved config " .. Selected, 3, Color3.fromRGB(80, 220, 120), "Configs")
                else
                    Library:Notification(tostring(Error), 4, Color3.fromRGB(255, 90, 90), "Failed to save")
                end
            end
        end)

        ConfigsTab:Button({ Name = "Refresh list", Callback = function() Library:GetConfigsList(ConfigsDropdown) end })
        Library:GetConfigsList(ConfigsDropdown)
    end

    do -- theme
        local Keys = { }
        for Key in pairs(Library.Theme) do table.insert(Keys, Key) end
        table.sort(Keys)
        for _, Key in ipairs(Keys) do
            ThemeTab:Label({ Name = Key }):Colorpicker({
                Flag = "Theme " .. Key, Default = Library.Theme[Key],
                Callback = function(Color) Library:SetTheme(Key, Color) end
            })
        end
    end

    do -- other
        OtherTab:Button({ Name = "Unload", Callback = function() Library:Exit() end })

        OtherTab:Label({ Name = "Menu bind" }):Keybind({
            Flag = "UIBind", Mode = "Toggle", Default = Library.MenuKeybind,
            KeyChanged = function(Key) if Key then Library.MenuKeybind = Key end end
        })

        OtherTab:Dropdown({
            Name = "Style", Flag = "AnimStyle",
            Items = { "Linear", "Sine", "Quad", "Cubic", "Quart", "Quint", "Exponential", "Circular", "Back", "Bounce", "Elastic" },
            Default = Library.Animation.Style,
            Callback = function(Value) if Value then Library.Animation.Style = Value end end
        })
        OtherTab:Dropdown({
            Name = "Direction", Flag = "AnimDirection",
            Items = { "In", "Out", "InOut" }, Default = Library.Animation.Direction,
            Callback = function(Value) if Value then Library.Animation.Direction = Value end end
        })
        OtherTab:Slider({
            Name = "Speed", Flag = "AnimTime", Min = 0, Max = 1, Default = Library.Animation.Time, Decimals = 0.01, Suffix = "s",
            Callback = function(Value) Library.Animation.Time = Value end
        })
    end

    SettingsSegment:Set("Configs", true)
    SwitchSettingsTab("Configs")

    Window.Settings = Settings

    Window:SetOpen(true)
    return Window
end

--// ---------------------------------------------------------------- page
function WindowMethods:Page(Params)
    Params = Params or { }
    local Window = self
    local Page = setmetatable({
        Icon = Params.Icon or Params.icon or "rbxassetid://129245697782918",
        Window = Window, Index = #Window.Pages + 1, Active = false, Sections = { }, Token = 0,
    }, PageMeta)

    local TabY = TAB_TOP + (Page.Index - 1) * TAB_STEP

    local Button = New("TextButton", {
        AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, TabY), Size = UDim2.fromOffset(42, 42),
        Parent = Window.Items.Rail
    }, { BackgroundColor3 = "Element" })
    Corner(Button, 12)
    local Icon = New("ImageLabel", {
        AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(22, 22),
        Image = Page.Icon, Parent = Button
    }, { ImageColor3 = "Dark Icon" })

    Button.MouseEnter:Connect(function()
        if Page.Active then return end
        Tween(Button, { BackgroundTransparency = 0.6 }, D(0.5), "Quad", "Out")
        Paint(Icon, "ImageColor3", "Text", D(0.5))
    end)
    Button.MouseLeave:Connect(function()
        if Page.Active then return end
        Tween(Button, { BackgroundTransparency = 1 }, D(0.5), "Quad", "Out")
        Paint(Icon, "ImageColor3", "Dark Icon", D(0.5))
    end)

    local Group = New("CanvasGroup", {
        Size = UDim2.fromScale(1, 1), GroupTransparency = 1, Visible = false, Parent = Window.Items.Content
    })
    local Scroll = New("ScrollingFrame", { Size = UDim2.fromScale(1, 1), Active = true, Parent = Group })
    List(Scroll, 0)
    Pad(Scroll, 14, 14, 16, 16)

    local Columns = New("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = Scroll })
    local Left = New("Frame", {
        Size = UDim2.new(0.5, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = Columns
    })
    List(Left, 12)
    local Right = New("Frame", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.fromScale(1, 0),
        Size = UDim2.new(0.5, -6, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, Parent = Columns
    })
    List(Right, 12)
    Page.Columns = { Left, Right }
    Page.Group = Group

    function Page:Show()
        Page.Token = Page.Token + 1
        Group.Visible = true
        Group.Position = UDim2.fromOffset(0, 18)
        Tween(Group, { Position = UDim2.fromOffset(0, 0), GroupTransparency = 0 }, D(1.4), "Quint", "Out")
    end

    function Page:Hide()
        Page.Token = Page.Token + 1
        local Token = Page.Token
        Tween(Group, { Position = UDim2.fromOffset(0, -10), GroupTransparency = 1 }, D(0.7), "Quad", "In")
        task.delay(D(0.7), function()
            if Page.Token == Token then Group.Visible = false end
        end)
    end

    function Page:Turn()
        local Old = Window.Current
        if Old == Page then return end
        Window.Current = Page
        Page.Active = true

        if Old then
            Old.Active = false
            Old:Hide()
            Tween(Old.TabButton, { BackgroundTransparency = 1 }, D(0.7), "Quad", "Out")
            Paint(Old.TabIcon, "ImageColor3", "Dark Icon")
        end

        local Pill, Bar = Window.Items.TabPill, Window.Items.TabBar
        if not Pill.Visible then
            Pill.Position = UDim2.new(0.5, 0, 0, TabY)
            Bar.Position = UDim2.new(0, 0, 0, TabY + 21)
            Pill.Visible = true
            Bar.Visible = true
        else
            Tween(Pill, { Position = UDim2.new(0.5, 0, 0, TabY) }, D(1.4), "Quint", "Out")
            Tween(Bar, { Position = UDim2.new(0, 0, 0, TabY + 21) }, D(1.4), "Back", "Out")
        end
        Tween(Button, { BackgroundTransparency = 1 }, D(0.5), "Quad", "Out")
        Paint(Icon, "ImageColor3", "Accent")

        Page:Show()
        Window:RefreshSearch(true)
    end

    Page.TabButton = Button
    Page.TabIcon = Icon
    Button.BackgroundTransparency = 1
    Button.MouseButton1Click:Connect(function() Page:Turn() end)

    table.insert(Window.Pages, Page)
    if #Window.Pages == 1 then Page:Turn() end
    return Page
end

--// ---------------------------------------------------------------- section
function PageMethods:Section(Params)
    Params = Params or { }
    local Page = self
    local Section = setmetatable({
        Name = Params.Name or Params.name or "Section",
        Side = Params.Side or Params.side or 1,
        Window = Page.Window, Page = Page, Shown = true,
    }, ContainerMeta)
    Section.Section = Section

    local Card = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
        Parent = Page.Columns[Section.Side] or Page.Columns[1]
    }, { BackgroundColor3 = "Inline" })
    Corner(Card, 12)
    Stroke(Card, "Outline", 0.45)
    List(Card, 0)

    local Header = New("Frame", { Size = UDim2.new(1, 0, 0, 38), LayoutOrder = 1, Parent = Card })
    local Dot = New("Frame", {
        AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 14, 0.5, 0), Size = UDim2.fromOffset(6, 6), Parent = Header
    }, { BackgroundColor3 = "Accent" })
    Corner(Dot, 3)
    New("TextLabel", {
        Text = Section.Name, AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 28, 0.5, 0),
        AutomaticSize = Enum.AutomaticSize.XY, Parent = Header
    }, { TextColor3 = "Text" })
    New("Frame", {
        AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.new(1, -28, 0, 1), Parent = Header
    }, { BackgroundColor3 = "Liner" })

    local Content = New("Frame", {
        Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = 2, Parent = Card
    })
    List(Content, 2)
    Pad(Content, 6, 6, 8, 6)

    Section.Card = Card
    Section.Content = Content
    table.insert(Page.Sections, Section)
    return Section
end

--// ---------------------------------------------------------------- watermark
function WindowMethods:Watermark(Params)
    Params = Params or { }
    local Watermark = { Name = Params.Name or Params.name or "Nexonix", Logo = Params.Logo or Params.logo or Library.DefaultLogo }

    local Frame = New("CanvasGroup", {
        AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 14), Size = UDim2.new(0, 0, 0, 38),
        AutomaticSize = Enum.AutomaticSize.X, GroupTransparency = 1, Parent = HudLayer
    }, { BackgroundColor3 = "Inline" })
    Corner(Frame, 10)
    Stroke(Frame, "Outline", 0.2)
    Pad(Frame, 0, 12, 0, 10)
    List(Frame, 10, true, Enum.HorizontalAlignment.Left, Enum.VerticalAlignment.Center)

    New("ImageLabel", { Size = UDim2.fromOffset(22, 22), Image = Watermark.Logo, ScaleType = Enum.ScaleType.Fit, LayoutOrder = 1, Parent = Frame })
    local Title = New("TextLabel", {
        Text = Watermark.Name, Size = UDim2.new(0, 0, 0, 16), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = 2, Parent = Frame
    }, { TextColor3 = "Text" })

    local Order = 2
    MakeMotion(Frame):Drag(Frame)
    Tween(Frame, { GroupTransparency = 0 }, D(1.6), "Quint", "Out")

    function Watermark:AddItem(Icon, Text)
        Order = Order + 1
        New("Frame", { Size = UDim2.fromOffset(1, 16), LayoutOrder = Order, Parent = Frame }, { BackgroundColor3 = "Liner" })
        Order = Order + 1

        local Item = New("Frame", { Size = UDim2.new(0, 0, 1, 0), AutomaticSize = Enum.AutomaticSize.X, LayoutOrder = Order, Parent = Frame })
        New("ImageLabel", {
            AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 0, 0.5, 0), Size = UDim2.fromOffset(16, 16),
            Image = Icon or "", Parent = Item
        }, { ImageColor3 = "Dark Icon" })
        local Label = New("TextLabel", {
            Text = tostring(Text), AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 24, 0.5, 0),
            AutomaticSize = Enum.AutomaticSize.XY, Parent = Item
        }, { TextColor3 = "Dark Text" })

        local Wrapper = { Instance = Label }
        function Wrapper:SetText(NewText) Label.Text = tostring(NewText) end
        return Wrapper, { Instance = Item }
    end

    function Watermark:SetText(Text) Title.Text = tostring(Text) end
    function Watermark:SetVisibility(Bool) Frame.Visible = Bool end

    return Watermark
end

Env.Library = Library
return Library
