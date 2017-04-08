local UIScrollView = import(".UIScrollView")
local ScaledItemListView = class("ScaledItemListView", UIScrollView)

local ScaledItemListViewItem = import(".ScaledItemListViewItem")
local scheduler = require("framework.scheduler")

local ITEM_ZORDERS = {
    [true]          = 1,
    [false]         = 0,
}

local function bool2number(bool)
    return bool and 1 or 0
end

ScaledItemListView.DELEGATE					= "ScaledItemListView_delegate"

ScaledItemListView.CELL_TAG					= "Cell"
ScaledItemListView.COUNT_TAG				= "Count"
ScaledItemListView.UNLOAD_CELL_TAG			= "UnloadCell"

ScaledItemListView.ALIGNMENT_LEFT			= 0
ScaledItemListView.ALIGNMENT_RIGHT			= 1
ScaledItemListView.ALIGNMENT_VCENTER		= 2
ScaledItemListView.ALIGNMENT_TOP			= 3
ScaledItemListView.ALIGNMENT_BOTTOM			= 4
ScaledItemListView.ALIGNMENT_HCENTER		= 5

--[[
FEATURE:
- There's one selected item displayed in the middle of the view rectangle,
and on top of other items.
- Support scaling items when scrolling the list view.
]]
function ScaledItemListView:ctor(params)
    ScaledItemListView.super.ctor(self, params)

    self.direction = params.direction or UIScrollView.DIRECTION_VERTICAL
    self.alignment = params.alignment or ScaledItemListView.ALIGNMENT_VCENTER
    local viewRect = params.viewRect
    self.itemMinScale = params.itemMinScale
    self.itemMaxScale = params.itemMaxScale or 1
    self.itemSize = params.itemSize

	self:setDirection(self.direction)
	self:setViewRect(viewRect)

	self.container = cc.Node:create()
	self:addScrollNode(self.container)

	self:onScroll(handler(self, self.scrollListener))

	self.size = {}
	self.items_ = {}
	self.itemsFree_ = {}
	self.delegate_ = {}
	self.redundancyViewVal = 0

    self:setNodeEventEnabled(true)

    self:removeNodeEventListenersByEvent(cc.NODE_ENTER_FRAME_EVENT)
end

function ScaledItemListView:setViewRect(viewRect)
	if UIScrollView.DIRECTION_VERTICAL == self.direction then
		self.redundancyViewVal = viewRect.height
	else
		self.redundancyViewVal = viewRect.width
	end

	ScaledItemListView.super.setViewRect(self, viewRect)
end

function ScaledItemListView:onCleanup()
	self:releaseAllFreeItems_()
end

function ScaledItemListView:releaseAllFreeItems_()
    for i, v in ipairs(self.itemsFree_) do
        v:removeAllChildren(true)
        v:release()
    end
    self.itemsFree_ = {}
end

function ScaledItemListView:addFreeItem_(item)
	item:retain()
	table.insert(self.itemsFree_, item)
end

function ScaledItemListView:removeAllItems()
    self.container:removeAllChildren()
    self.items_ = {}

    return self
end

function ScaledItemListView:setDelegate(delegate)
	self.delegate_[ScaledItemListView.DELEGATE] = delegate
end

function ScaledItemListView:goToItem(idx)
    self:stopAllActions()
    self:removeAllItems()
    self.container:setPosition(0, 0)
    self.container:setContentSize(cc.size(0, 0))

    self.items_ = {}

    local item, itemWidth, itemHeight = self:loadMiddleItem_(idx)
    self:loadItemsOnBothSides_({
        middleIdx = idx,
        middleItemWidth = itemWidth,
        middleItemHeight = itemHeight,
    })
end

function ScaledItemListView:getSelectedItemDist(idx)
    local item = self:getItemOfIdx_(idx)
    if not item then
        return
    end

    self.scrollNode:stopAllActions()
    local scrollNodePos = cc.p(self.scrollNode:getPosition())

    local currentPos = cc.p(item:getPosition())
    local finalPos = cc.p(self.viewRect_.width * 0.5 - scrollNodePos.x, self.viewRect_.height * 0.5 - scrollNodePos.y)
    return self:subPoint(finalPos, currentPos)
end

function ScaledItemListView:moveToItem(idx)
    if not self.items_ or #self.items_ == 0 then
        self:goToItem(idx)
    end

    local item = self:getItemOfIdx_(idx)
    if not item then
        self:goToItem(idx)
    end

    self:setScrollEnabled(false)

    for _, v in ipairs(self.items_) do
        self:setItemScale(v.idx_, idx, 0)
        self:setItemZOrder(v.idx_, v.idx_ == idx)
    end

    self.scrollNode:stopAllActions()
    local dist = self:getSelectedItemDist(idx)
    local scrollNodePos = cc.p(self.scrollNode:getPosition())
    self.scrollNode:setPosition(self:addPoint(scrollNodePos, dist))

    self:increaseOrReduceItem_()
    self.selectedIdx_ = idx
    self:setScrollEnabled(true)
end

function ScaledItemListView:scrollToItem(idx)
    if self.isScrollToItem_ then
        return
    end

    local item = self:getItemOfIdx_(idx)
    if not item then
        return
    end

    self.isScrollToItem_ = true
    self:setScrollEnabled(false)

    local dist = self:getSelectedItemDist(idx)

    for _, v in ipairs(self.items_) do
        self:setItemScale(v.idx_, idx, 0)
        self:setItemZOrder(v.idx_, v.idx_ == idx)
    end

    self.scrollNode:stopAllActions()
	transition.moveBy(self.scrollNode, {
        x = dist.x,
        y = dist.y,
        time = 0.3,
		onComplete = function()
            self:increaseOrReduceItem_()
            self.selectedIdx_ = idx
            self:setScrollEnabled(true)
            self.isScrollToItem_ = false

            -- TODO: a new kind of event?
            self:notifyListener_({name = "ended"})
        end,
    })
end

function ScaledItemListView:newItem(item)
    local item = ScaledItemListViewItem.new(item)
    -- NOTE: it's a typo from quickx source code
    item:setDirction(self.direction)
    item:onSizeChange(handler(self, self.itemSizeChangeListener))

    return item
end

function ScaledItemListView:itemSizeChangeListener()
end

function ScaledItemListView:dequeueItem()
	if #self.itemsFree_ < 1 then
		return
	end

	local item
	item = table.remove(self.itemsFree_, 1)
	item.bFromFreeQueue_ = true

	return item
end

function ScaledItemListView:setItemPos_(item, pos)
    local content = item:getContent()
    content:setAnchorPoint(0, 0)
    content:setPosition(0, 0)

    item:setAnchorPoint(0.5, 0.5)
    item:setPosition(pos)
end

function ScaledItemListView:getItemSize_(item)
    if self.itemSize then
        return self.itemSize.width, self.itemSize.height
    end

    if tolua.isnull(item) then
        return
    end

    local width, height = item:getItemSize()
    return width * self.itemMinScale, height * self.itemMinScale
end

function ScaledItemListView:addItem_(item, isBackward)
    self.items_ = self.items_ or {}
	if isBackward then
		table.insert(self.items_, 1, item)
	else
		table.insert(self.items_, item)
	end

	self.container:addChild(item)

	if item.bFromFreeQueue_ then
		item.bFromFreeQueue_ = nil
		item:release()
	end
end

function ScaledItemListView:getSelectedItemIdx()
    return self.selectedIdx_
end

function ScaledItemListView:loadMiddleItem_(idx)
    self.selectedIdx_ = idx

	local item = self.delegate_[ScaledItemListView.DELEGATE](self, ScaledItemListView.CELL_TAG, idx)
	item.idx_ = idx

    local posX = self.viewRect_.width * 0.5
    local posY = self.viewRect_.height * 0.5
    self:setItemPos_(item, cc.p(posX, posY))
    self:addItem_(item)

    item:setScale(self.itemMaxScale)
    item:setLocalZOrder(ITEM_ZORDERS[true])

    return item, self:getItemSize_(item)
end

function ScaledItemListView:loadItemsOnBothSides_(params)
    params.isBackward = true
    self:loadItemsOnOneSide_(params)
    params.isBackward = false
    self:loadItemsOnOneSide_(params)
end

function ScaledItemListView:loadItemsOnOneSide_(params)
    local middleIdx = params.middleIdx
    local middleItemWidth = params.middleItemWidth
    local middleItemHeight = params.middleItemHeight
    local isBackward = (params.isBackward == true)
    local backwardFlag = (bool2number(isBackward) * 2 - 1)

    local originPosX = 0
    local originPosY = 0
    local containerWidth = 0
    local containerHeight = 0
    if UIScrollView.DIRECTION_VERTICAL == self.direction then
        originPosY = self.viewRect_.height * 0.5 + middleItemHeight * 0.5 * backwardFlag
        containerHeight = self.viewRect_.height * 0.5 - middleItemHeight * 0.5 * backwardFlag
    else
        originPosX = self.viewRect_.width * 0.5 - middleItemWidth * 0.5 * backwardFlag
        containerWidth = self.viewRect_.width * 0.5 - middleItemHeight * 0.5 * backwardFlag
    end

    local function terminateCondition(containerWidth, containerHeight)
        if isBackward then
            return (containerWidth < 0) or (containerHeight < 0)
        else
            return (containerWidth > self.viewRect_.width + self.redundancyViewVal)
            or (containerHeight > self.viewRect_.height + self.redundancyViewVal)
        end
    end

    for _, idx in ipairs(self:getItemIndices(self.selectedIdx_, isBackward)) do
        local item, itemWidth, itemHeight = self:loadOneItem_(cc.p(originPosX, originPosY), idx, isBackward)

        item:setScale(self.itemMinScale)

        if UIScrollView.DIRECTION_VERTICAL == self.direction then
            originPosY = originPosY + itemHeight * backwardFlag
            containerHeight = containerHeight - itemHeight * backwardFlag
        else
            originPosX = originPosX - itemWidth * backwardFlag
            containerWidth = containerWidth - itemWidth * backwardFlag
        end

        if terminateCondition(containerWidth, containerHeight) then
            break
        end
    end
end

function ScaledItemListView:loadOneItem_(originPoint, idx, isBackward)
    local backwardFlag = (bool2number(isBackward) * 2 - 1)

	local item = self.delegate_[ScaledItemListView.DELEGATE](self, ScaledItemListView.CELL_TAG, idx)
	if nil == item then
		print("ERROR! Load nil item")
		return
	end
	item.idx_ = idx

    local width, height = self:getItemSize_(item)
    local posX = originPoint.x
    local posY = originPoint.y
    if UIScrollView.DIRECTION_VERTICAL == self.direction then
        posX = self.viewRect_.width * 0.5
        posY = posY + height * 0.5 * backwardFlag
    else
        posX = posX - width * 0.5 * backwardFlag
        posY = self.viewRect_.height * 0.5
    end
    self:setItemPos_(item, cc.p(posX, posY))
    self:addItem_(item, isBackward)

    item:setScale(self.itemMinScale)
    item:setLocalZOrder(ITEM_ZORDERS[idx == self.selectedIdx_])

    return item, self:getItemSize_(item)
end

function ScaledItemListView:unloadOneItem_(idx)
	local item = self.items_[1]
	if nil == item then
		return
	end
	if item.idx_ > idx then
		return
	end

	local unloadIdx = idx - item.idx_ + 1
	item = self.items_[unloadIdx]
	if nil == item then
		return
	end
	table.remove(self.items_, unloadIdx)
	self:addFreeItem_(item)
	self.container:removeChild(item, false)

	self.delegate_[ScaledItemListView.DELEGATE](self, ScaledItemListView.UNLOAD_CELL_TAG, idx)
end

function ScaledItemListView:getContainerCascadeBoundingBox()
	local boundingBox
	for i, item in ipairs(self.items_) do
		self.boundingBox.width, self.boundingBox.height = item:getItemSize()
		self.boundingBox.x, self.boundingBox.y = item:getPosition()
		local anchor = item:getAnchorPoint()
		self.boundingBox.x = self.boundingBox.x - anchor.x * self.boundingBox.width
		self.boundingBox.y = self.boundingBox.y - anchor.y * self.boundingBox.height

		if boundingBox then
			self.nodePoint.x, self.nodePoint.y = boundingBox.x, boundingBox.y
			boundingBox.x = math.min(boundingBox.x, self.boundingBox.x)
		    boundingBox.y = math.min(boundingBox.y, self.boundingBox.y)
		    boundingBox.width = math.max(self.nodePoint.x + boundingBox.width, self.boundingBox.x + self.boundingBox.width) - boundingBox.x
		    boundingBox.height = math.max(self.nodePoint.y + boundingBox.height, self.boundingBox.y + self.boundingBox.height) - boundingBox.y
		else
			boundingBox = clone(self.boundingBox)
		end
	end

	local point = self.container:convertToWorldSpace(cc.p(boundingBox.x, boundingBox.y))
	boundingBox.x = point.x
	boundingBox.y = point.y
	return boundingBox
end

-- ScaledItemListView:increaseOrReduceItem_() does the same thing as UIListView:increaseOrReduceItem_()
-- except that it' not called per frame
function ScaledItemListView:increaseOrReduceItem_()
	if 0 == #self.items_ then
		return
	end

	local getContainerCascadeBoundingBox = function ()
		local boundingBox
		for i, item in ipairs(self.items_) do
			local w,h = self:getItemSize_(item)
			local x,y = item:getPosition()
			local anchor = item:getAnchorPoint()
			x = x - anchor.x * w
			y = y - anchor.y * h

			if boundingBox then
				boundingBox = cc.rectUnion(boundingBox, cc.rect(x, y, w, h))
			else
				boundingBox = cc.rect(x, y, w, h)
			end
		end

		local point = self.container:convertToWorldSpace(cc.p(boundingBox.x, boundingBox.y))
		boundingBox.x = point.x
		boundingBox.y = point.y
		return boundingBox
	end

	local count = self.delegate_[ScaledItemListView.DELEGATE](self, ScaledItemListView.COUNT_TAG)
	local nNeedAdjust = 2
	local cascadeBound = getContainerCascadeBoundingBox()
    local localPos = self:convertToNodeSpace(cc.p(cascadeBound.x, cascadeBound.y))

	local item
	local itemW, itemH

	if UIScrollView.DIRECTION_VERTICAL == self.direction then
		-- ahead part of view
		local disH = localPos.y + cascadeBound.height - self.viewRect_.y - self.viewRect_.height
		local tempIdx
		item = self.items_[1]
		if not item then
			print("increaseOrReduceItem_ item is nil, all item count:" .. #self.items_)
			return
		end
		tempIdx = item.idx_
		if disH > self.redundancyViewVal then
			itemW, itemH = self:getItemSize_(item)
			if cascadeBound.height - itemH > self.viewRect_.height
				and disH - itemH > self.redundancyViewVal then
				self:unloadOneItem_(tempIdx)
			else
				nNeedAdjust = nNeedAdjust - 1
			end
		else
			item = nil
			tempIdx = tempIdx - 1
			if tempIdx > 0 and disH < self.redundancyViewVal then
				local localPoint = self.container:convertToNodeSpace(cc.p(cascadeBound.x, cascadeBound.y + cascadeBound.height))
				item = self:loadOneItem_(localPoint, tempIdx, true)
			end
			if nil == item then
				nNeedAdjust = nNeedAdjust - 1
			end
		end

		-- part after view
		disH = self.viewRect_.y - localPos.y
		item = self.items_[#self.items_]
		if not item then
			return
		end
		tempIdx = item.idx_
		if disH > self.redundancyViewVal then
			itemW, itemH = self:getItemSize_(item)
			if cascadeBound.height - itemH > self.viewRect_.height
				and disH - itemH > self.redundancyViewVal then
				self:unloadOneItem_(tempIdx)
			else
				nNeedAdjust = nNeedAdjust - 1
			end
		else
			item = nil
			tempIdx = tempIdx + 1
			if tempIdx <= count and disH < self.redundancyViewVal then
				local localPoint = self.container:convertToNodeSpace(cc.p(cascadeBound.x, cascadeBound.y))
				item = self:loadOneItem_(localPoint, tempIdx)
			end
			if nil == item then
				nNeedAdjust = nNeedAdjust - 1
			end
		end
	else
		-- left part of view
		local disW = self.viewRect_.x - localPos.x
		item = self.items_[1]
		local tempIdx = item.idx_
		if disW > self.redundancyViewVal then
			itemW, itemH = self:getItemSize_(item)
			if cascadeBound.width - itemW > self.viewRect_.width
				and disW - itemW > self.redundancyViewVal then
				self:unloadOneItem_(tempIdx)
			else
				nNeedAdjust = nNeedAdjust - 1
			end
		else
			item = nil
			tempIdx = tempIdx - 1
			if tempIdx > 0 and disW < self.redundancyViewVal then
				local localPoint = self.container:convertToNodeSpace(cc.p(cascadeBound.x, cascadeBound.y))
				item = self:loadOneItem_(localPoint, tempIdx, true)
			end
			if nil == item then
				nNeedAdjust = nNeedAdjust - 1
			end
		end

		-- right part of view
		disW = localPos.x + cascadeBound.width - self.viewRect_.x - self.viewRect_.width
		item = self.items_[#self.items_]
		tempIdx = item.idx_
		if disW > self.redundancyViewVal then
			itemW, itemH = self:getItemSize_(item)
			if cascadeBound.width - itemW > self.viewRect_.width
				and disW - itemW > self.redundancyViewVal then
				self:unloadOneItem_(tempIdx)
			else
				nNeedAdjust = nNeedAdjust - 1
			end
		else
			item = nil
			tempIdx = tempIdx + 1
			if tempIdx <= count and disW < self.redundancyViewVal then
				local localPoint = self.container:convertToNodeSpace(cc.p(cascadeBound.x + cascadeBound.width, cascadeBound.y))
				item = self:loadOneItem_(localPoint, tempIdx)
			end
			if nil == item then
				nNeedAdjust = nNeedAdjust - 1
			end
		end
	end
end

function ScaledItemListView:getItemOfIdx_(idx)
    for _, v in ipairs(self.items_) do
        if v.idx_ == idx then
            return v
        end
    end
end

function ScaledItemListView:onTouch(listener)
	self.touchListener_ = listener

	return self
end

function ScaledItemListView:notifyListener_(event)
	if not self.touchListener_ then
		return
	end

	self.touchListener_(event)
end

function ScaledItemListView:getItemIndices(beginIdx, isBackward)
    local indices = {}
    if isBackward then
        for i = beginIdx-1, 1, -1 do
            table.insert(indices, i)
        end
    else
        local count = self.delegate_[ScaledItemListView.DELEGATE](self, ScaledItemListView.COUNT_TAG)
        for i = beginIdx+1, count do
            table.insert(indices, i)
        end
    end
    return indices
end

function ScaledItemListView:getCurrentSelectedItemIdx_(dist, needsLoadingItem)
    local selectedItemIdx = self.selectedIdx_
    local isBackward
    local distance
    if UIScrollView.DIRECTION_VERTICAL == self.direction then
        distance = dist.y
        isBackward = (distance < 0)
    else
        distance = dist.x
        isBackward = (distance > 0)
    end
    if distance == 0 then
        return selectedItemIdx
    end

    local indices = self:getItemIndices(self.selectedIdx_, isBackward) or {}
    table.insert(indices, 1, self.selectedIdx_)

    local threshold = 0.3
    local leftDistance = math.abs(distance)
    for _, idx in ipairs(indices) do
        local item = self:getItemOfIdx_(idx)
        if not item and needsLoadingItem then
            item = self.delegate_[ScaledItemListView.DELEGATE](self, ScaledItemListView.CELL_TAG, idx)
        end

        if item then
            if item:isLocked() == true then
                break
            end

            selectedItemIdx = idx

            local width, height = self:getItemSize_(item)
            local step
            if UIScrollView.DIRECTION_VERTICAL == self.direction then
                step = height
            else
                step = width
            end

            if leftDistance - step * threshold <= 0 then
                break
            end
            leftDistance = leftDistance - step
        else
            local step
            if UIScrollView.DIRECTION_VERTICAL == self.direction then
                step = self.itemSize.height
            else
                step = self.itemSize.width
            end

            leftDistance = leftDistance - step
        end
    end

    return selectedItemIdx
end

function ScaledItemListView:setItemScale(idx, middleIdx, leftDistance)
    local item = self:getItemOfIdx_(idx)
    if tolua.isnull(item) then
        return
    end

    local width = self:getItemSize_(item)
    local factor = leftDistance / width

    if idx == middleIdx then
        factor = 1 - math.abs(leftDistance) / width
    end

    local scale = self.itemMinScale + (self.itemMaxScale - self.itemMinScale) * factor
    if scale < self.itemMinScale then
        scale = self.itemMinScale
    elseif scale > self.itemMaxScale then
        scale = self.itemMaxScale
    end

    item:setScale(scale)
end

function ScaledItemListView:setItemZOrder(idx, isSelected)
    local item = self:getItemOfIdx_(idx)
    if tolua.isnull(item) then
        return
    end

    item:setLocalZOrder(ITEM_ZORDERS[isSelected])
end

function ScaledItemListView:adjustItemsByDist(dist)
    local isBackward
    local distance
    if UIScrollView.DIRECTION_VERTICAL == self.direction then
        distance = dist.y
        isBackward = (distance < 0)
    else
        distance = dist.x
        isBackward = (distance > 0)
    end
    if distance == 0 then
        return
    end

    local indices = self:getItemIndices(self.selectedIdx_, isBackward) or {}
    table.insert(indices, 1, self.selectedIdx_)

    -- NOTE: middleIdx is the idx of item whose position is in the middle of the view
    -- and it can be different from the selectedIdx
    local leftDistance = math.abs(distance)
    local middleIdx = self.selectedIdx_
    for _, idx in ipairs(indices) do
        middleIdx = idx

        local item = self:getItemOfIdx_(idx)
        local width = self.itemSize.width
        local height = self.itemSize.height
        if item then
            width, height = self:getItemSize_(item)
        end

        local step
        if UIScrollView.DIRECTION_VERTICAL == self.direction then
            step = height
        else
            step = width
        end

        if leftDistance - step <= 0 then
            break
        end
        leftDistance = leftDistance - step
    end

    local indices = { middleIdx }
    if isBackward then
        table.insert(indices, middleIdx - 1)
    else
        table.insert(indices, middleIdx + 1)
    end

    local selectedIdx = self:getCurrentSelectedItemIdx_(dist)
    for _, i in ipairs(indices) do
        self:setItemScale(i, middleIdx, leftDistance)
        self:setItemZOrder(i, i == selectedIdx)
    end
end

function ScaledItemListView:isShake(event)
    return false
end

function ScaledItemListView:deaccelerateScrolling(dt)
    if self.deaccelerateScrollingHandle then
        scheduler.unscheduleGlobal(self.deaccelerateScrollingHandle)
        self.deaccelerateScrollingHandle = nil
    end
end

function ScaledItemListView:performedAnimatedScroll(dt)
    if self.performedAnimatedScrollHandle then
        scheduler.unscheduleGlobal(self.performedAnimatedScrollHandle)
        self.performedAnimatedScrollHandle = nil
    end
end

function ScaledItemListView:addPoint(p1, p2)
    return {
        x = p1.x + p2.x,
        y = p1.y + p2.y,
    }
end

function ScaledItemListView:subPoint(p1, p2)
    return {
        x = p1.x - p2.x,
        y = p1.y - p2.y,
    }
end

function ScaledItemListView:onTouch_(event)
    if self.isScrollToItem_ then
        return false
    end

    return ScaledItemListView.super.onTouch_(self, event)
end

function ScaledItemListView:scrollListener(event)
    self:increaseOrReduceItem_()

    if event.name == "began" then
        self.beganPos_ = cc.p(event.x, event.y)
    elseif event.name == "moved" then
        self:adjustItemsByDist(self:subPoint(event, self.beganPos_))
    elseif event.name == "ended" or event.name == "clicked" then
        local dist = self:subPoint(event, self.beganPos_)
        self:moveToItem(self:getCurrentSelectedItemIdx_(dist, true))
    end

    event.scrollView = self
    self:notifyListener_(event)
end

function ScaledItemListView:elasticScroll()
end

return ScaledItemListView
