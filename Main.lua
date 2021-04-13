local RunService = game:GetService('RunService');
local TweenService = game:GetService('TweenService');
local UserInputService = game:GetService('UserInputService');
local Players = game:GetService('Players');

local LocalPlayer = Players.LocalPlayer;
local Mouse = LocalPlayer:GetMouse();

local DrawingLibrary = {};
local DrawingLibraryPrivate = {};
local screenGUIs = {};
local Signal = {}

do  -- // Packages
    do -- // Signal
        Signal.__index = Signal
        Signal.ClassName = "Signal"
        
        function Signal.new()
            local self = setmetatable({}, Signal)
        
            self._bindableEvent = Instance.new("BindableEvent")
            self._argData = nil
            self._argCount = nil
        
            return self
        end
        
        function Signal:Fire(...)
            self._argData = {...}
            self._argCount = select("#", ...)
            self._bindableEvent:Fire()
            self._argData = nil
            self._argCount = nil
        end
        
        function Signal:Connect(handler)
            if not (type(handler) == "function") then
                error(("connect(%s)"):format(typeof(handler)), 2)
            end
        
            return self._bindableEvent.Event:Connect(function()
                handler(unpack(self._argData, 1, self._argCount))
            end)
        end
        
        function Signal:Wait()
            self._bindableEvent.Event:Wait()
            assert(self._argData, "Missing arg data, likely due to :TweenSize/Position corrupting threadrefs.")
            return unpack(self._argData, 1, self._argCount)
        end
        
        function Signal:Destroy()
            if self._bindableEvent then
                self._bindableEvent:Destroy()
                self._bindableEvent = nil
            end
        
            self._argData = nil
            self._argCount = nil
        end
    end;
end

do -- // Utils
    function DrawingLibrary:ConvertToOffset(childSize, parentSize)
        local scaleX = childSize.X.Scale;
        local scaleY = childSize.Y.Scale;
    
        local x = scaleX == 0 and childSize.X.Offset or scaleX * parentSize.X.Offset + childSize.X.Offset;
        local y = scaleY == 0 and childSize.Y.Offset or scaleY * parentSize.Y.Offset + childSize.Y.Offset;
        
        return Vector2.new(x, y);
    end;

    function DrawingLibrary:ConvertToDarkColor(color)
        local h, s, v = Color3.toHSV(color);
        v = v - 0.1;

        return Color3.fromHSV(h, s, v);
    end;

    function DrawingLibrary:ConvertToLightColor(color)
        local h, s, v = Color3.toHSV(color);
        v = v + 0.1;

        return Color3.fromHSV(h, s, v);
    end;
end;

do -- // Hooks
    if(not shared.DrawingLibrary) then
        shared.DrawingLibrary = true;

        local old;
        old = hookfunction(typeof, newcclosure(function(self)
            if(not checkcaller()) then return old(self) end;
    
            if(type(self) == 'table' and old(self.IsA) == 'function' and self:IsA('DrawingLibrary')) then
                return 'DrawingLibrary';
            end;

            return old(self);
        end))
    end;
end;

do -- // validations
    DrawingLibrary.Validations = {};

    function DrawingLibrary.Validations:Parent(value)
        if(typeof(value) ~= 'DrawingLibrary' and value ~= nil and value ~= self) then
            return string.format('invalid argument #3 (DrawingLibrary expected, got %s)', typeof(value))
        end;

        if (value) then
            if (not table.find(value._childrens, self)) then
                table.insert(value._childrens, self);
            end;
        elseif(self._props.Parent) then
            table.remove(self._props.Parent._childrens, table.find(self._props.Parent._childrens, self));
        end;

        if(not self:IsA('ScreenGui')) then
            self._drawing.Visible = not not value;
        end;
    end;

    function DrawingLibrary.Validations:Visible(value)
        if(typeof(value) ~= 'boolean') then
            return string.format('invalid argument #3 (boolean expected, got %s)', typeof(value))
        end;
    end;

    function DrawingLibrary.Validations:Size(value)
        if(typeof(value) ~= 'UDim2') then
            return string.format('invalid argument #3 (UDim2 expected, got %s)', typeof(value))
        end;

        local parentSize = self._props.Parent and self._props.Parent.AbsoluteSize;
        if(not parentSize) then return end;

        local mySize = DrawingLibrary:ConvertToOffset(value, UDim2.new(0, parentSize.X, 0, parentSize.Y));

        self._drawing.Size = mySize;
        self._props.AbsoluteSize = mySize;
    end;

    function DrawingLibrary.Validations:BackgroundColor3(value)
        if(typeof(value) ~= 'Color3') then
            return string.format('invalid argument #3 (Color3 expected, got %s)', typeof(value))
        end;

        self._drawing.Color = value;
    end;

    function DrawingLibrary.Validations:BackgroundTransparency(value)
        if(typeof(value) ~= 'number') then
            return string.format('invalid argument #3 (number expected, got %s)', typeof(value))
        end;

        self._drawing.Transparency = 1 - value;
    end;

    function DrawingLibrary.Validations:Position(value)
        if(typeof(value) ~= 'UDim2') then
            return string.format('invalid argument #3 (UDim2 expected, got %s)', typeof(value))
        end;

        local parentSize = self._props.Parent and self._props.Parent.AbsoluteSize;
        if(not parentSize) then return end;

        local myPosition = DrawingLibrary:ConvertToOffset(value, UDim2.new(0, parentSize.X, 0, parentSize.Y));
        local mySize = self._props.AbsoluteSize;

        local anchorPoint = self._props.AnchorPoint;
        myPosition = Vector2.new(myPosition.X - mySize.X * (1 - (1 - anchorPoint.X)), myPosition.Y - mySize.Y * (1 - (1 - anchorPoint.Y)));
        myPosition = myPosition + self._props.Parent.AbsolutePosition;

        self._drawing.Position = myPosition;
        self._props.AbsolutePosition = myPosition;

        local borderSize = Vector2.new(self._props.BorderSizePixel, self._props.BorderSizePixel);

        self._border.Position = myPosition - borderSize/2;
        self._border.Size = self._props.AbsoluteSize + borderSize;

        if(self:IsA('TextLabel') or self:IsA('TextButton') or self:IsA('TextBox')) then
            local alignmentX = self._props.TextXAlignment;
            local alignmentY = self._props.TextYAlignment;

            local textSize = self._text.TextBounds;
            local frameSize = self._props.AbsoluteSize;
            local textPosition = myPosition;

            if(alignmentX == Enum.TextXAlignment.Center) then
                textPosition = textPosition + frameSize / 2 - Vector2.new(0, textSize.Y / 2);
            elseif(alignmentX == Enum.TextXAlignment.Right) then
                textPosition = textPosition + Vector2.new(frameSize.X, frameSize.Y / 2) - textSize / 2;
            elseif(alignmentX == Enum.TextXAlignment.Left) then
                textPosition = textPosition + Vector2.new(0, frameSize.Y / 2) - Vector2.new(-(textSize.X / 2), textSize.Y / 2);
            end;

            -- if(alignmentY == Enum.TextYAlignment.Top) then
            --     textSize = Vector2.new(textSize.X, textSize.Y * 2);
            -- elseif(alignmentY == Enum.TextYAlignment.Bottom) then
            --     textSize = Vector2.new(textSize.X, 0);
            -- end;
            -- + Vector2.new(self._text.TextBounds.X, 0) / 2
            
            self._text.Position = textPosition;
            -- self._text.Position = myPosition + self._props.AbsoluteSize/2 - Vector2.new(0, self._text.TextBounds.Y/2); -- Center
            -- self._text.Position = myPosition + Vector2.new(self._props.AbsoluteSize.X, self._props.AbsoluteSize.Y/2) - self._text.TextBounds / 2; -- Right
            -- self._text.Position = myPosition + Vector2.new(0, self._props.AbsoluteSize.Y/2) - Vector2.new(-(self._text.TextBounds.X/2), self._text.TextBounds.Y / 2); -- Left
        end;
    end;

    function DrawingLibrary.Validations:BorderSizePixel(value)
        if(typeof(value) ~= 'number') then
            return string.format('invalid argument #3 (number expected, got %s)', typeof(value))
        end;

        self._border.Visible = value > 0;
        self._border.Thickness = value;
    end;

    function DrawingLibrary.Validations:BorderColor3(value)
        if(typeof(value) ~= 'Color3') then
            return string.format('invalid argument #3 (Color3 expected, got %s)', typeof(value))
        end;

        self._border.Color = value;
    end;

    function DrawingLibrary.Validations:AnchorPoint(value)
        if(typeof(value) ~= 'Vector2') then
            return string.format('invalid argument #3 (Vector2 expected, got %s)', typeof(value))
        end;
    end;

    function DrawingLibrary.Validations:AbsoluteSize(value)
        if(typeof(value) ~= 'Vector2') then
            return string.format('invalid argument #3 (Vector2 expected, got %s)', typeof(value))
        end;
    end;

    function DrawingLibrary.Validations:Enabled(value)
        if(typeof(value) ~= 'boolean') then
            return string.format('invalid argument #3 (boolean expected, got %s)', typeof(value))
        end;
    end;

    function DrawingLibrary.Validations:Name(value)
        if(typeof(value) ~= 'string') then
            return string.format('invalid argument #3 (string expected, got %s)', typeof(value))
        end;
    end;

    function DrawingLibrary.Validations:TextColor3(value)
        if(typeof(value) ~= 'Color3') then
            return string.format('invalid argument #3 (Color3 expected, got %s)', typeof(value))
        end;

        self._text.Color = value;
    end;

    function DrawingLibrary.Validations:TextStrokeTransparency(value)
        if(typeof(value) ~= 'number') then
            return string.format('invalid argument #3 (number expected, got %s)', typeof(value))
        end;

        self._text.Outline = value == 0;
    end;
    
    function DrawingLibrary.Validations:TextStrokeColor3(value)
        if(typeof(value) ~= 'Color3') then
            return string.format('invalid argument #3 (Color3 expected, got %s)', typeof(value))
        end;

        self._text.OutlineColor = value;
    end;
    
    function DrawingLibrary.Validations:Text(value)
        if(typeof(value) ~= 'string') then
            return string.format('invalid argument #3 (string expected, got %s)', typeof(value))
        end;

        self.Position = self._props.Position;
        self._text.Text = value;
    end;

    function DrawingLibrary.Validations:TextXAlignment(value)
        if(typeof(value) ~= 'EnumItem') then
            return string.format('invalid argument #3 (EnumItem expected, got %s)', typeof(value))
        end;
    end;

    function DrawingLibrary.Validations:TextYAlignment(value)
        if(typeof(value) ~= 'EnumItem') then
            return string.format('invalid argument #3 (EnumItem expected, got %s)', typeof(value))
        end;
    end;

    function DrawingLibrary.Validations:AutoButtonColor(value)
        if(typeof(value) ~= 'boolean') then
            return string.format('invalid argument #3 (boolean expected, got %s)', typeof(value))
        end;
    end;
end;

do -- // Types
    local viewportSize = Vector2.new();

    DrawingLibrary.Types = {};
    local keyCodesArray = {};
    local digits = {};

    for i, v in next, Enum.KeyCode:GetEnumItems() do
        keyCodesArray[v.Value] = v;
    end;

    for i = 48, 57 do
        digits[keyCodesArray[i]] = tostring(9 - (57 - i));
    end;
    
    function DrawingLibrary.Types:ScreenGui()
        self._props.Enabled = true;
        self._props.AbsoluteSize = viewportSize;
        self._props.AbsolutePosition = Vector2.new();

        table.insert(screenGUIs, self);
    end;

    function DrawingLibrary.Types:Frame()
        self._props.BackgroundColor3 = Color3.fromRGB(255, 255, 255);
        self._props.Visible = false;
        self._props.Position = UDim2.new()
        self._props.AnchorPoint = Vector2.new();
        self._props.Size = UDim2.new();
        self._props.BorderSizePixel = 1;
        self._props.BorderColor3 = Color3.fromRGB(27, 42, 53);

        self._drawing = Drawing.new('Square');
        self._drawing.Filled = true;
        self._drawing.Color = self._props.BackgroundColor3;
        self._drawing.Visible = false;
        self._drawing.Transparency = 1;

        self._border = Drawing.new('Square');
        self._border.Filled = false;
        self._border.Thickness = 1;
        self._border.Color = self._props.BorderColor3;
        self._border.Visible = false;
        self._border.Transparency = 1;

        self.TweenSize = DrawingLibraryPrivate.TweenSize;
        self.TweenPosition = DrawingLibraryPrivate.TweenPosition;
        self.TweenSizeAndPosition = DrawingLibraryPrivate.TweenSizeAndPosition;
    end;

    function DrawingLibrary.Types:TextLabel()
        DrawingLibrary.Types.Frame(self);

        self._props.TextXAlignment = Enum.TextXAlignment.Center;
        self._props.TextYAlignment = Enum.TextXAlignment.Center;

        self._text = Drawing.new('Text');
        self._text.Visible = true;
        self._text.Size = 22;
        self._text.Center = true;
        self._text.Text = "Text";
        self._text.Transparency = 1;
    end;

    function DrawingLibrary.Types:TextButton()
        DrawingLibrary.Types.TextLabel(self);

        self._props.MouseEnter = Signal.new();
        self._props.MouseLeave = Signal.new();
        
        self._props.MouseButton1Click = Signal.new();
        self._props.MouseButton1Down = Signal.new();
        self._props.MouseButton1Up = Signal.new();

        self._props.MouseButton2Click = Signal.new();
        self._props.MouseButton2Down = Signal.new();
        self._props.MouseButton2Up = Signal.new();

        self._props.InputBegan:Connect(function(input, gpe)
            print(input.UserInputState, input.UserInputType, input.KeyCode, gpe);

            if(input.UserInputType == Enum.UserInputType.MouseButton1) then
                if(self._props.AutoButtonColor) then
                    self._drawing.Color = DrawingLibrary:ConvertToLightColor(self._props.BackgroundColor3);
                end;

                self._props.MouseButton1Down:Fire(input.Position.X, input.Position.Y);
            elseif(input.UserInputType == Enum.UserInputType.MouseButton2) then
                self._props.MouseButton2Down:Fire(input.Position.X, input.Position.Y);
            end;
        end);

        self._props.InputEnded:Connect(function(input, gpe)
            warn(input.UserInputState, input.UserInputType, input.KeyCode, gpe);

            if(input.UserInputType == Enum.UserInputType.MouseButton1) then
                if(self._props.AutoButtonColor) then
                    self._drawing.Color = self._props.BackgroundColor3;
                end;

                self._props.MouseButton1Up:Fire(input.Position.X, input.Position.Y);
                self._props.MouseButton1Click:Fire();
            elseif(input.UserInputType == Enum.UserInputType.MouseButton2) then
                self._props.MouseButton2Up:Fire(input.Position.X, input.Position.Y);
                self._props.MouseButton2Click:Fire();
            end;
        end);

        self._props.InputChanged:Connect(function(input, gpe)
            if(input.UserInputType == Enum.UserInputType.MouseMovement) then
                local inputBegin = input.UserInputState == Enum.UserInputState.Begin;
                local backgroundColor = self._props.BackgroundColor3;

                if(self._props.AutoButtonColor) then
                    self._drawing.Color = inputBegin and DrawingLibrary:ConvertToDarkColor(backgroundColor) or backgroundColor;
                end;

                if(inputBegin) then
                    self._props.MouseEnter:Fire();
                else
                    self._props.MouseLeave:Fire();
                end;
            end;
            print('Changed', input, input.UserInputState, input.UserInputType, input.KeyCode, gpe);
        end);
    end;

    function DrawingLibrary.Types:TextBox()
        DrawingLibrary.Types.TextLabel(self);

        local isActive = false;
        self._props.InputBegan:Connect(function(input)
            if(input.UserInputType == Enum.UserInputType.MouseButton1) then
                isActive = true;
                self.Text = "";
                return
            end;
        end);

        local proxyID = 0;

        UserInputService.InputBegan:Connect(function(input)
            if(not isActive or not input.KeyCode) then return end;
            proxyID = proxyID + 1;
            local currentProxyID = proxyID;

            local str = digits[input.KeyCode] or UserInputService:GetStringForKeyCode(input.KeyCode);
            if(not input:IsModifierKeyDown(Enum.ModifierKey.Shift)) then
                str = string.lower(str);
            end;
            
            if(input.KeyCode == Enum.KeyCode.Backspace) then
                self.Text = self.Text:sub(1, #self.Text-1);
            else
                self.Text = self.Text .. str;
            end;

            wait(0.5);
            if(currentProxyID ~= proxyID) then return end;

            if(input.UserInputState == Enum.UserInputState.Begin) then
                repeat
                    if(input.KeyCode == Enum.KeyCode.Backspace) then
                        self.Text = self.Text:sub(1, #self.Text-1);
                    else
                        self.Text = self.Text .. str;
                    end;

                    wait();
                until input.UserInputState == Enum.UserInputState.End;
            end;
        end);

        UserInputService.InputEnded:Connect(function(input)
            if(input.KeyCode == Enum.KeyCode.Return) then
                isActive = false;
                return
            end;
        end);
    end;

    local function updateSize()
        if(not workspace.CurrentCamera) then return end;
        local newViewportSize = workspace.CurrentCamera.ViewportSize;

        viewportSize = newViewportSize;

        for i, v in next, screenGUIs do
            if(v._props.AbsoluteSize ~= viewportSize) then
                v.AbsoluteSize = viewportSize;
            end;
        end;
    end;

    updateSize()
    RunService.Heartbeat:Connect(updateSize);
end;

do -- // DrawingLibrary
    DrawingLibrary.__index = DrawingLibrary;
    DrawingLibraryPrivate.AllObjects = {};

    function DrawingLibrary.__index(self, p)
        local data = DrawingLibrary[p] or rawget(self._props, p);

        if(data == nil and p ~= 'Parent') then
            return error(string.format('%s is not a valid member of %s "%s"', p, rawget(self._props, 'ClassName'), DrawingLibrary.GetFullName(self)), -1);
        end;

        return data;
    end;

    function DrawingLibrary.__newindex(self, p, v, forced)
        local validationFunction = DrawingLibrary.Validations[p];
        if(not validationFunction) then
            if(not forced) then
                return warn(p, v, debug.traceback())
            end;

            return;
        end;

        local validationError = validationFunction(self, v);
        if(validationError) then
            return error(validationError);
        end;

        rawset(self._props, p, v);

        if (not forced) then
            self:_Update();
        end;

        local childrens = self._childrens;

        for i = 1, #childrens do
            childrens[i]:_Update();
        end;
    end;
    
    function DrawingLibraryPrivate:PerformTween(tweenType, endValue, easingDirection, easingStyle, time, override_NOT_USED, callback)
        if(typeof(override_NOT_USED) == 'function') then
            callback = override_NOT_USED;
        end;

        callback = callback or function() end;

        if(typeof(endValue) ~= 'UDim2') then
            return error(string.format('invalid argument #1 (UDim2 expected, got %s)', typeof(endValue)), -1);
        elseif(typeof(easingDirection) ~= 'string') then
            return error(string.format('invalid argument #2 (string expected, got %s)', typeof(easingDirection)), -1);
        elseif(typeof(easingStyle) ~= 'string') then
            return error(string.format('invalid argument #3 (string expected, got %s)', typeof(easingDirection)), -1);
        elseif(typeof(time) ~= 'number') then
            return error(string.format('invalid argument #4 (number expected, got %s)', typeof(time)), -1);
        elseif(typeof(callback) ~= 'function') then
            return error(string.format('invalid argument #5 (function expected, got %s)', typeof(callback)), -1);
        end;

        local connection;
        local alpha = 0;
        local startValue = self._props[tweenType];

        connection = RunService.Heartbeat:Connect(function(delta)
            alpha = alpha + (delta / time);

            if(alpha >= 1) then
                connection:Disconnect();
                connection = nil;
                callback();
            end;

            local value = TweenService:GetValue(alpha, easingStyle, easingDirection);
            local tweenValue = startValue:lerp(endValue, value);

            self[tweenType] = tweenValue;
        end);
    end;

    function DrawingLibraryPrivate:TweenSize(...)
        return DrawingLibraryPrivate.PerformTween(self, 'Size', ...);
    end;

    function DrawingLibraryPrivate:GiveChildrens(descendants, object)
        table.insert(descendants, object);

        for i, v in next, object._childrens do
            DrawingLibraryPrivate:GiveChildrens(descendants, v);    
        end;
    end;

    function DrawingLibraryPrivate:TweenPosition(...)
        return DrawingLibraryPrivate.PerformTween(self, 'Position', ...);
    end;

    function DrawingLibraryPrivate:TweenSizeAndPosition(endSize, endPosition, ...)
        DrawingLibraryPrivate.PerformTween(self, 'Size', endSize, ...);
        DrawingLibraryPrivate.PerformTween(self, 'Position', endPosition, ...);
    end;

    function DrawingLibrary:IsA(className)
        if(className == 'DrawingLibrary') then return true end;
        return className == self._props.ClassName;
    end;

    function DrawingLibrary:GetFullName()
        return 'NotImplementedYet' .. self._props.ClassName;
    end;

    function DrawingLibrary:GetChildren()
        return self._childrens;
    end;

    function DrawingLibrary:GetDescendants()
        local descendants = {};

        DrawingLibraryPrivate:GiveChildrens(descendants, self);

        return descendants;
    end;

    function DrawingLibrary:Destroy()
        self._drawing:Remove();

        if(rawget(self, '_border')) then
            self._border:Remove();
        end;

        for i, v in next, self:GetChildren() do
            v:Destroy();
        end;
    end;

    function DrawingLibrary:_Update()
        DrawingLibrary.__newindex(self, 'Parent', self._props.Parent, true);

        if(not self:IsA('ScreenGui')) then
            DrawingLibrary.__newindex(self, 'Size', self._props.Size, true);
            DrawingLibrary.__newindex(self, 'Position', self._props.Position, true);
        end;

        -- for i, v in next, self._props do -- // trigger mts to update
        --     DrawingLibrary.__newindex(self, i, v, true);
        -- end;
    end;

    function DrawingLibrary.new(name, parent)
        if (not DrawingLibrary.Types[name]) then
            return error(string.format('Unable to create an DrawingLibrary of type "%s"', name));
        end;

        local self = {};

        self._props = {};
        self._childrens = {};
        self._hiddenProperties = {};
        
        self._props.InputBegan = Signal.new();
        self._props.InputEnded = Signal.new();
        self._props.InputChanged = Signal.new();

        self._props.ClassName = name;
        self._props.Parent = parent or nil;
        self._props.Name = name;
        self._props.AbsolutePosition = Vector2.new();
        self._props.AbsoluteRotation = 0;
        self._props.AbsoluteSize = Vector2.new();

        DrawingLibrary.Types[name](self);
        setmetatable(self, DrawingLibrary);

        table.insert(DrawingLibraryPrivate.AllObjects, self);
        return self;
    end;

    local function handleInputEvent(inputType, input, gpe)
        -- body
        local position = UserInputService:GetMouseLocation();
        local isMouse = input.UserInputType == Enum.UserInputType.MouseMovement;

        for i, v in next, DrawingLibraryPrivate.AllObjects do
            local difference = position - v.AbsolutePosition;
            local frameSize = v.AbsoluteSize;
            
            if(difference.X <= frameSize.X and difference.X >= 0 and difference.Y <= frameSize.Y and difference.Y >= 0) then
                if(isMouse) then
                    if(inputType == 'InputChanged' and not v._hiddenProperties.MouseIn) then
                        input.UserInputState = Enum.UserInputState.Begin;
                        v._hiddenProperties.MouseIn = true;
                        v[inputType]:Fire(input, gpe);
                    end;
                else
                    v[inputType]:Fire(input, gpe);
                end;
            elseif(isMouse and v._hiddenProperties.MouseIn) then
                input.UserInputState = Enum.UserInputState.End;
                v._hiddenProperties.MouseIn = false;
                v['InputChanged']:Fire(input, gpe);
            end;
        end;
    end;

    UserInputService.InputBegan:Connect(function(...) handleInputEvent('InputBegan', ...) end);
    UserInputService.InputChanged:Connect(function(...) handleInputEvent('InputChanged', ...) end);
    UserInputService.InputEnded:Connect(function(...) handleInputEvent('InputEnded', ...) end);
end;

local Instance = DrawingLibrary;

local ScreenGui = Instance.new("ScreenGui")
local Frame = Instance.new("Frame")
local Frame_2 = Instance.new("Frame")
local Label = Instance.new('TextLabel');
local TextButton = Instance.new('TextButton');
local TextBox = Instance.new('TextBox');

Frame.Parent = ScreenGui
Frame.AnchorPoint = Vector2.new(0.5, 0.5)
Frame.BackgroundColor3 = Color3.fromRGB(255, 255, 255)
Frame.Position = UDim2.new(0.5, 0, 0.5, 0)
Frame.Size = UDim2.new(0, 100, 0, 100)
Frame.BorderSizePixel = 10;
Frame.BorderColor3 = Color3.fromRGB(255, 0, 0);
Frame.BackgroundTransparency = 0.5;

Label.Parent = ScreenGui;
Label.TextColor3 = Color3.fromRGB(255, 0, 0);
Label.Text = "Hello!";
Label.Size = UDim2.new(0, 100, 0, 40);
Label.Position = UDim2.new(0.8, 0, 0.8, 0);
Label.TextStrokeColor3 = Color3.new();
Label.TextStrokeTransparency = 0;

TextButton.Parent = ScreenGui;
TextButton.BackgroundColor3 = Color3.fromRGB(100, 100, 100);
TextButton.Size = UDim2.new(0, 100, 0, 20);
TextButton.Position = UDim2.new(0.3, 0, 0.3, 0);
TextButton.Text = "Click Me!";
TextButton.AutoButtonColor = true;
TextButton.TextColor3 = Color3.fromRGB(255, 255, 255);

TextBox.Parent = ScreenGui;
TextBox.BackgroundColor3 = Color3.fromRGB(100, 100, 100);
TextBox.Size = UDim2.new(0, 250, 0, 20);
TextBox.Position = UDim2.new(0.5, 0, 0.8, 0);
TextBox.Text = "Text Box";
TextBox.TextColor3 = Color3.fromRGB(255, 255, 255);

TextButton.MouseButton1Click:Connect(function()
    TextBox.TextXAlignment = Enum.TextXAlignment.Left;
    print('click');
end);

TextButton.MouseButton1Down:Connect(function()
    print('down');
end);

TextButton.MouseButton1Up:Connect(function()
    print('up');
end);

Frame_2.AnchorPoint = Vector2.new(0.5, 0.5)
Frame_2.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
Frame_2.Position = UDim2.new(0.5, 0, 0.5, 0)
Frame_2.Size = UDim2.new(0.100000001, 0, 0.100000001, 0)
Frame_2.Parent = Frame

wait(2);
Label.TextXAlignment = Enum.TextXAlignment.Center;