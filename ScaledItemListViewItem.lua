local UIListViewItem = import(".UIListViewItem")

local ScaledItemListViewItem = class("ScaledItemListViewItem", UIListViewItem)

function ScaledItemListViewItem:ctor(params)
    ScaledItemListViewItem.super.ctor(self, params)
end

function ScaledItemListViewItem:isLocked()
    local content = self:getContent()
    if not tolua.isnull(content) and content.isLocked then
        return content:isLocked()
    end

    return false
end

return ScaledItemListViewItem
