
--[[

Copyright (c) 2011-2014 chukong-inc.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.

]]

--------------------------------
-- @module UIButton

--[[--

quick Button控件

]]

local UIButton = class("UIButton", function()
    return display.newNode()
end)

UIButton.CLICKED_EVENT = "CLICKED_EVENT"
UIButton.PRESSED_EVENT = "PRESSED_EVENT"
UIButton.RELEASE_EVENT = "RELEASE_EVENT"
UIButton.STATE_CHANGED_EVENT = "STATE_CHANGED_EVENT"

UIButton.IMAGE_ZORDER = -100
UIButton.LABEL_ZORDER = 0

-- start --

--------------------------------
-- UIButton构建函数
-- @function [parent=#UIButton] new
-- @param table events 按钮状态表
-- @param string initialState 初始状态
-- @param table options 参数表

-- end --

function UIButton:ctor(events, initialState, options)
    self.fsm_ = {}
    cc(self.fsm_)
        :addComponent("components.behavior.StateMachine")
        :exportMethods()
    self.fsm_:setupState({
        initial = {state = initialState, event = "startup", defer = false},
        events = events,
        callbacks = {
            onchangestate = handler(self, self.onChangeState_),
        }
    })

    makeUIControl_(self)
    self:setLayoutSizePolicy(display.FIXED_SIZE, display.FIXED_SIZE)
    self:setButtonEnabled(true)
    self:addNodeEventListener(cc.NODE_TOUCH_EVENT, handler(self, self.onTouch_))

    self.touchInSpriteOnly_ = options and options.touchInSprite
    self.currentImage_ = nil
    self.images_ = {}
    self.sprite_ = {}
    self.scale9_ = options and options.scale9
    self.capInsets_ = options and options.capInsets
    self.flipX_ = options and options.flipX
    self.flipY_ = options and options.flipY
    self.scale9Size_ = nil
    self.labels_ = {}
    self.labelOffset_ = {0, 0}
    self.labelAlign_ = display.CENTER
    self.initialState_ = initialState

    display.align(self, display.CENTER)

    if "boolean" ~= type(self.flipX_) then
        self.flipX_ = false
    end
    if "boolean" ~= type(self.flipY_) then
        self.flipY_ = false
    end

    self:addNodeEventListener(cc.NODE_EVENT, function(event)
        if event.name == "enter" then
            self:updateButtonImage_()
        end
    end)
end

-- start --

--------------------------------
-- 停靠位置
-- @function [parent=#UIButton] align
-- @param number align 锚点位置
-- @param number x
-- @param number y
-- @return UIButton#UIButton 

-- end --

function UIButton:align(align, x, y)
    display.align(self, align, x, y)
    
    -- initButtonImage if setButtonImage has not been called
    for state, _ in pairs(self.fsm_:getAllStates()) do
        local image = self.images_[state]
        self:initButtonImage_(state, image)
    end

    self:updateButtonImage_()

    self:updateButtonLabel_()

    local size = self:getCascadeBoundingBox().size
    local ap = self:getAnchorPoint()

    -- self:setPosition(x + size.width * (ap.x - 0.5), y + size.height * (0.5 - ap.y))
    return self
end

-- start --

--------------------------------
-- 设置按钮特定状态的图片
-- @function [parent=#UIButton] setButtonImage
-- @param string state 状态
-- @param string image 图片路径
-- @param boolean ignoreEmpty 是否忽略空的图片路径
-- @return UIButton#UIButton 

-- end --

function UIButton:setButtonImage(state, image, ignoreEmpty)
    if ignoreEmpty and image == nil then return end
    self:initButtonImage_(state, image)
    return self
end

-- start --

--------------------------------
-- 设置按钮特定状态的文字node
-- @function [parent=#UIButton] setButtonLabel
-- @param string state 状态
-- @param node label 文字node
-- @return UIButton#UIButton 

-- end --

function UIButton:setButtonLabel(state, label)
    if not label then
        label = state
        state = self:getDefaultState_()
    end
    assert(label ~= nil, "UIButton:setButtonLabel() - invalid label")

    if type(state) == "table" then state = state[1] end
    local currentLabel = self.labels_[state]
    if currentLabel then currentLabel:removeSelf() end

    self.labels_[state] = label
    self:addChild(label, UIButton.LABEL_ZORDER)
    self:updateButtonLabel_()
    return self
end

-- start --

--------------------------------
-- 返回按钮特定状态的文字
-- @function [parent=#UIButton] getButtonLabel
-- @param string state 状态
-- @return node#node  文字label

-- end --

function UIButton:getButtonLabel(state)
    if not state then
        state = self:getDefaultState_()
    end
    if type(state) == "table" then state = state[1] end
    return self.labels_[state]
end

-- start --

--------------------------------
-- 设置按钮特定状态的文字
-- @function [parent=#UIButton] setButtonLabelString
-- @param string state 状态
-- @param string text 文字
-- @return UIButton#UIButton 

-- end --

function UIButton:setButtonLabelString(state, text)
    assert(self.labels_ ~= nil, "UIButton:setButtonLabelString() - not add label")
    if text == nil then
        text = state
        for _, label in pairs(self.labels_) do
            label:setString(text)
        end
    else
        local label = self.labels_[state]
        if label then label:setString(text) end
    end
    return self
end

-- start --

--------------------------------
-- 返回文字标签的偏移
-- @function [parent=#UIButton] getButtonLabelOffset
-- @return number#number  x
-- @return number#number  y

-- end --

function UIButton:getButtonLabelOffset()
    return self.labelOffset_[1], self.labelOffset_[2]
end

-- start --

--------------------------------
-- 设置文字标签的偏移
-- @function [parent=#UIButton] setButtonLabelOffset
-- @param number x
-- @param number y
-- @return UIButton#UIButton 

-- end --

function UIButton:setButtonLabelOffset(ox, oy)
    self.labelOffset_ = {ox, oy}
    self:updateButtonLabel_()
    return self
end

-- start --

--------------------------------
-- 得到文字标签的停靠方式
-- @function [parent=#UIButton] getButtonLabelAlignment
-- @return number#number 

-- end --

function UIButton:getButtonLabelAlignment()
    return self.labelAlign_
end

-- start --

--------------------------------
-- 设置文字标签的停靠方式
-- @function [parent=#UIButton] setButtonLabelAlignment
-- @param number align
-- @return UIButton#UIButton 

-- end --

function UIButton:setButtonLabelAlignment(align)
    self.labelAlign_ = align
    self:updateButtonLabel_()
    return self
end

-- start --

--------------------------------
-- 设置按钮的大小
-- @function [parent=#UIButton] setButtonSize
-- @param number width
-- @param number height
-- @return UIButton#UIButton 

-- end --

function UIButton:setButtonSize(width, height)
    -- assert(self.scale9_, "UIButton:setButtonSize() - can't change size for non-scale9 button")
    self.scale9Size_ = {width, height}
    for state, renderers in pairs(self.sprite_) do
        for i, v in ipairs(renderers) do
            if self.scale9_ then
                v:setContentSize(cc.size(self.scale9Size_[1], self.scale9Size_[2]))
            else
                local size = v:getContentSize()
                local scaleX = v:getScaleX()
                local scaleY = v:getScaleY()
                scaleX = scaleX * self.scale9Size_[1]/size.width
                scaleY = scaleY * self.scale9Size_[2]/size.height
                v:setScaleX(scaleX)
                v:setScaleY(scaleY)
            end
        end
    end
    return self
end

-- start --

--------------------------------
-- 设置按钮是否有效
-- @function [parent=#UIButton] setButtonEnabled
-- @param boolean enabled 是否有效
-- @return UIButton#UIButton 

-- end --

function UIButton:setButtonEnabled(enabled)
    self:setTouchEnabled(enabled)
    if enabled and self.fsm_:canDoEvent("enable") then
        self.fsm_:doEventForce("enable")
        self:dispatchEvent({name = UIButton.STATE_CHANGED_EVENT, state = self.fsm_:getState()})
    elseif not enabled and self.fsm_:canDoEvent("disable") then
        self.fsm_:doEventForce("disable")
        self:dispatchEvent({name = UIButton.STATE_CHANGED_EVENT, state = self.fsm_:getState()})
    end
    return self
end

-- start --

--------------------------------
-- 返回按钮是否有效
-- @function [parent=#UIButton] isButtonEnabled
-- @return boolean#boolean 

-- end --

function UIButton:isButtonEnabled()
    return self.fsm_:canDoEvent("disable")
end

function UIButton:addButtonClickedEventListener(callback)
    return self:addEventListener(UIButton.CLICKED_EVENT, callback)
end

-- start --

--------------------------------
-- 注册用户点击监听
-- @function [parent=#UIButton] onButtonClicked
-- @param function callback 监听函数
-- @return UIButton#UIButton 

-- end --

function UIButton:onButtonClicked(callback)
    self:addButtonClickedEventListener(callback)
    return self
end

function UIButton:addButtonPressedEventListener(callback)
    return self:addEventListener(UIButton.PRESSED_EVENT, callback)
end

-- start --

--------------------------------
-- 注册用户按下监听
-- @function [parent=#UIButton] onButtonPressed
-- @param function callback 监听函数
-- @return UIButton#UIButton 

-- end --

function UIButton:onButtonPressed(callback)
    self:addButtonPressedEventListener(callback)
    return self
end

function UIButton:addButtonReleaseEventListener(callback)
    return self:addEventListener(UIButton.RELEASE_EVENT, callback)
end

-- start --

--------------------------------
-- 注册用户释放监听
-- @function [parent=#UIButton] onButtonRelease
-- @param function callback 监听函数
-- @return UIButton#UIButton 

-- end --

function UIButton:onButtonRelease(callback)
    self:addButtonReleaseEventListener(callback)
    return self
end

function UIButton:addButtonStateChangedEventListener(callback)
    return self:addEventListener(UIButton.STATE_CHANGED_EVENT, callback)
end

-- start --

--------------------------------
-- 注册按钮状态变化监听
-- @function [parent=#UIButton] onButtonStateChanged
-- @param function callback 监听函数
-- @return UIButton#UIButton 

-- end --

function UIButton:onButtonStateChanged(callback)
    self:addButtonStateChangedEventListener(callback)
    return self
end

function UIButton:onChangeState_(event)
    if self:isRunning() then
        self:updateButtonImage_()
        self:updateButtonLabel_()
    end
end

function UIButton:onTouch_(event)
    printError("UIButton:onTouch_() - must override in inherited class")
end

--[[
]]
function UIButton:updateButtonImageAlignment_()
    for state, renderers in pairs(self.sprite_) do
        for i, v in ipairs(renderers) do
            v:setAnchorPoint(self:getAnchorPoint())
            v:setPosition(0, 0)
        end
    end
end

--[[--
Init the images of the specified state, and each of them is guaranteed to be added once.
]]
function UIButton:initButtonImage_(state, image)
    if not image then
        for _, s in pairs(self:getDefaultState_()) do
            image = self.images_[s]
            if image then break end
        end
    end

    local function initRenderer(renderers, i, image, isNewImage)
        if not isNewImage then
            return
        end

        if self.scale9_ then
            renderers[i] = display.newScale9Sprite(image, 0, 0, self.scale9Size_, self.capInsets_)
            if not self.scale9Size_ then
                local size = renderers[i]:getContentSize()
                self.scale9Size_ = {size.width, size.height}
            else
                renderers[i]:setContentSize(cc.size(self.scale9Size_[1], self.scale9Size_[2]))
            end
        else
            renderers[i] = display.newSprite(image)
        end

        if renderers[i].setFlippedX then
            if self.flipX_ then
                renderers[i]:setFlippedX(self.flipX_ or false)
            end
            if self.flipY_ then
                renderers[i]:setFlippedY(self.flipY_ or false)
            end
        end

        self:addChild(renderers[i], UIButton.IMAGE_ZORDER)
        renderers[i]:setVisible(state == self.fsm_:getState())
    end

    if image then
        if not self.sprite_[state] then
            self.sprite_[state] = {}
        end

        local isNewImage = (self.images_[state] ~= image)

        if isNewImage then
            for i, v in ipairs(self.sprite_[state]) do
                v:removeFromParent(true)
            end
            self.sprite_[state] = {}
        end

        if "table" == type(image) then
            for i, v in ipairs(image) do
                initRenderer(self.sprite_[state], i, v, isNewImage)
            end
        else
            initRenderer(self.sprite_[state], 1, image, isNewImage)
        end

        self.images_[state] = image

        self:updateButtonImageAlignment_()
    elseif not self.labels_ then
        printError("UIButton:initButtonImage_() - not set image for state %s", state)
    end
end

--[[--
NOTE:
The original updateButtonImage_ function in quickx will only add the images of the current state.
When some SpriteFrame of another state is released, it will not be displayed.
Solution:
Add all the images of all the states and use setVisible instead.
]]
function UIButton:updateButtonImage_()
    self:updateButtonImageAlignment_()
    for state, renderers in pairs(self.sprite_) do
        for i, v in ipairs(renderers) do
            v:setVisible(state == self.fsm_:getState())
        end
    end
end

function UIButton:updateButtonLabel_()
    if not self.labels_ then return end
    local state = self.fsm_:getState()
    local label = self.labels_[state]

    if not label then
        for _, s in pairs(self:getDefaultState_()) do
            label = self.labels_[s]
            if label then break end
        end
    end

    local ox, oy = self.labelOffset_[1], self.labelOffset_[2]
    local defaultState = self:getDefaultState_()[1]
    local sprite = (self.sprite_[defaultState] or {})[1]
    if sprite then
        local ap = self:getAnchorPoint()
        local spriteSize = sprite:getContentSize()
        ox = ox + spriteSize.width * (0.5 - ap.x)
        oy = oy + spriteSize.height * (0.5 - ap.y)
    end

    for _, l in pairs(self.labels_) do
        l:setVisible(l == label)
        l:align(self.labelAlign_, ox, oy)
    end
end

function UIButton:getDefaultState_()
    return {self.initialState_}
end

function UIButton:checkTouchInSprite_(x, y)
    local defaultState = self:getDefaultState_()[1]
    local sprite = (self.sprite_[defaultState] or {})[1]
    if self.touchInSpriteOnly_ then
        return sprite and sprite:getCascadeBoundingBox():containsPoint(cc.p(x, y))
    else
        return self:getCascadeBoundingBox():containsPoint(cc.p(x, y))
    end
end

return UIButton
