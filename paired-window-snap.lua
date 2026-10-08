--[[
Paired Window Snap — standalone module for Hammerspoon 1.x (Lua).
Author: Pavel Potasuev
Questions and contact: https://potasuev.ru
License: MIT; see LICENSE. No network calls or bundled third-party code.

Drag an actual window to a side edge, hold briefly, and release.
The previous working window fills the opposite half. The top edge maximizes.
Add this module to an existing init.lua; requiring it alone starts nothing.
]]

local M = {}

-- Modify before start(), or stop(), configure(), start().
M.CONFIG = {
  -- Side activation strip, in macOS points. Higher: easier to trigger;
  -- lower: get closer to the edge. Keep below half the screen width.
  edge = 32,
  -- Top activation strip, in points. Higher: easier top maximize;
  -- lower: reach nearer the top. Corners prefer left/right snapping.
  topEdge = 3,
  -- Hold time in seconds. Higher: slower, fewer accidental snaps;
  -- lower: faster, easier to trigger unintentionally. Zero disables the hold.
  dwell = 0.3,
  -- Required pointer travel in points. Higher: ignores more small gestures;
  -- lower: shorter drags qualify. Zero allows any dragged pointer movement.
  minDrag = 20,
  -- Required change in any window-frame coordinate, in points.
  -- Higher: rejects more tiny moves; lower: accepts smaller real moves.
  -- Helps reject dragging text or page content rather than moving a window.
  minFrameChange = 8,
}

local switcherFilter
local mouseSnap = {
  edge = 32,

  topEdge = 3,

  dwell = 0.3,
  minDrag = 20,
  minFrameChange = 8,
  startPoint = nil,
  startWindow = nil,
  partnerWindow = nil,
  startFrame = nil,
  moved = false,
  edgeKind = nil,
  edgeSince = nil,
}

local focusHistory = {
  current = nil,
  previous = nil,
}

local function pointInFrame(point, frame)
  return point.x >= frame.x
    and point.x <= frame.x + frame.w
    and point.y >= frame.y
    and point.y <= frame.y + frame.h
end

local function windowAtPoint(point)
  local ok, windows = pcall(function()
    return switcherFilter:getWindows(hs.window.filter.sortByFocusedLast)
  end)

  if ok and windows then
    for _, window in ipairs(windows) do
      local frameOK, frame = pcall(function() return window:frame() end)
      if frameOK and frame and pointInFrame(point, frame) then
        return window
      end
    end
  end

  return hs.window.focusedWindow()
end

local function sameWindow(a, b)
  if not a or not b then return false end
  local ok, aId, bId = pcall(function() return a:id(), b:id() end)
  return ok and aId ~= nil and aId == bId
end

local function usableWindow(window)
  if not window then return nil end
  local ok, id, visible, standard, full = pcall(function()
    return window:id(), window:isVisible(), window:isStandard(), window:isFullScreen()
  end)
  if ok and id and visible and standard and not full then return window end
  return nil
end

local function rememberFocusedWindow(window)
  window = usableWindow(window)
  if not window or sameWindow(window, focusHistory.current) then
    return
  end

  focusHistory.previous = focusHistory.current
  focusHistory.current = window
end

local function partnerForWindow(window)
  if not window then
    return nil
  end

  if sameWindow(window, focusHistory.current) then
    return usableWindow(focusHistory.previous)
  end

  return usableWindow(focusHistory.current)
end


local function distance(a, b)
  local dx = a.x - b.x
  local dy = a.y - b.y
  return math.sqrt(dx * dx + dy * dy)
end

local function frameChanged(a, b)
  return math.abs(a.x - b.x) > mouseSnap.minFrameChange
    or math.abs(a.y - b.y) > mouseSnap.minFrameChange
    or math.abs(a.w - b.w) > mouseSnap.minFrameChange
    or math.abs(a.h - b.h) > mouseSnap.minFrameChange
end

local function screenAtPoint(point)
  for _, screen in ipairs(hs.screen.allScreens()) do
    if pointInFrame(point, screen:fullFrame()) then
      return screen
    end
  end

  return nil
end

local function snapKindForPoint(point, screen)
  local fullFrame = screen:fullFrame()

  if point.x <= fullFrame.x + mouseSnap.edge then
    return "left"
  end

  if point.x >= fullFrame.x + fullFrame.w - mouseSnap.edge then
    return "right"
  end

  if point.y <= fullFrame.y + mouseSnap.topEdge then
    return "max"
  end

  return nil
end

local function frameForSnap(kind, screen)
  local frame = screen:frame()

  if kind == "left" then
    return {
      kind = "left",
      primary = {
        x = frame.x,
        y = frame.y,
        w = frame.w / 2,
        h = frame.h,
      },
      partner = {
        x = frame.x + frame.w / 2,
        y = frame.y,
        w = frame.w / 2,
        h = frame.h,
      },
    }
  end

  if kind == "right" then
    return {
      kind = "right",
      primary = {
        x = frame.x + frame.w / 2,
        y = frame.y,
        w = frame.w / 2,
        h = frame.h,
      },
      partner = {
        x = frame.x,
        y = frame.y,
        w = frame.w / 2,
        h = frame.h,
      },
    }
  end

  if kind == "max" then
    return {
      kind = "max",
      primary = {
        x = frame.x,
        y = frame.y,
        w = frame.w,
        h = frame.h,
      },
      partner = nil,
    }
  end

  return nil
end

mouseSnap.eventtap = hs.eventtap.new({
  hs.eventtap.event.types.leftMouseDown,
  hs.eventtap.event.types.leftMouseDragged,
  hs.eventtap.event.types.leftMouseUp,
}, function(event)
  if not M.running then return false end
  local eventType = event:getType()
  local point = event:location()

  if eventType == hs.eventtap.event.types.leftMouseDown then
    mouseSnap.startPoint = point
    mouseSnap.startWindow = nil
    mouseSnap.partnerWindow = nil
    mouseSnap.startFrame = nil
    mouseSnap.moved = false
    mouseSnap.edgeKind = nil
    mouseSnap.edgeSince = nil
    mouseSnap.seq = (mouseSnap.seq or 0) + 1
    local seq = mouseSnap.seq

    mouseSnap.downTimer = hs.timer.doAfter(0, function()
      if not M.running or mouseSnap.seq ~= seq then
        return
      end
      local window = usableWindow(windowAtPoint(point))
      if not window then return end
      local frameOK, frame = pcall(function() return window:frame() end)
      if not frameOK or not frame then return end
      mouseSnap.startWindow = window
      mouseSnap.partnerWindow = partnerForWindow(window)
      mouseSnap.startFrame = frame
    end)
    return false
  end

  if eventType == hs.eventtap.event.types.leftMouseDragged then
    if mouseSnap.startPoint and distance(mouseSnap.startPoint, point) >= mouseSnap.minDrag then
      mouseSnap.moved = true
    end

    local dragScreen = screenAtPoint(point)
    local kind = dragScreen and snapKindForPoint(point, dragScreen) or nil
    if kind ~= mouseSnap.edgeKind then
      mouseSnap.edgeKind = kind
      mouseSnap.edgeSince = kind and hs.timer.secondsSinceEpoch() or nil
    end

    return false
  end

  if eventType == hs.eventtap.event.types.leftMouseUp then
    local window = mouseSnap.startWindow
    local partnerCandidate = mouseSnap.partnerWindow
    local startFrame = mouseSnap.startFrame
    local edgeKind = mouseSnap.edgeKind
    local edgeSince = mouseSnap.edgeSince
    local moved = mouseSnap.moved

    mouseSnap.startPoint = nil
    mouseSnap.startWindow = nil
    mouseSnap.partnerWindow = nil
    mouseSnap.startFrame = nil
    mouseSnap.edgeKind = nil
    mouseSnap.edgeSince = nil
    mouseSnap.moved = false
    mouseSnap.seq = (mouseSnap.seq or 0) + 1

    local releaseSeq = mouseSnap.seq
    mouseSnap.upTimer = hs.timer.doAfter(0, function()
      if not M.running or mouseSnap.seq ~= releaseSeq then return end
      if not moved or not window or not startFrame then
        return
      end

      if not usableWindow(window) then
        return
      end

      local frameOK, currentFrame = pcall(function() return window:frame() end)
      if not frameOK or not currentFrame then return end
      if not frameChanged(startFrame, currentFrame) then
        return
      end

      local screen = screenAtPoint(point)
      if not screen then
        local screenOK, fallback = pcall(function() return window:screen() end)
        if screenOK then screen = fallback end
      end
      if not screen then
        return
      end

      local kind = snapKindForPoint(point, screen)
      if not kind or kind ~= edgeKind or not edgeSince then
        return
      end

      if hs.timer.secondsSinceEpoch() - edgeSince < mouseSnap.dwell then
        return
      end

      local targetFrame = frameForSnap(kind, screen)
      if targetFrame then
        local applied = pcall(function() window:setFrame(targetFrame.primary, 0) end)
        if not applied then return end

        local partnerWindow = usableWindow(partnerCandidate)
        if targetFrame.partner and partnerWindow and not sameWindow(window, partnerWindow) then
          pcall(function() partnerWindow:setFrame(targetFrame.partner, 0); window:focus() end)
        end
      end
    end)

    return false
  end

  return false
end)


function M:configure(options)
  assert(not self.running, "Stop Paired Window Snap before changing configuration")
  local nextConfig = {}
  for key,value in pairs(self.CONFIG) do nextConfig[key]=value end
  for key,value in pairs(options or {}) do
    assert(self.CONFIG[key] ~= nil, "Unknown option: "..tostring(key))
    assert(type(value)=="number" and value==value and value<math.huge and value>=0,
      "Settings must be finite nonnegative numbers")
    nextConfig[key]=value
  end
  assert(nextConfig.edge>0,"edge must be positive")
  for key,value in pairs(nextConfig) do self.CONFIG[key]=value end
  return self
end

function M:start()
  if self.running then return self end
  if not hs.accessibilityState() then return nil,"Enable Hammerspoon Accessibility permission first" end
  self:configure(self.CONFIG)
  for key,value in pairs(self.CONFIG) do mouseSnap[key]=value end
  switcherFilter = hs.window.filter.new():setCurrentSpace(true)
  switcherFilter:subscribe(hs.window.filter.windowFocused, rememberFocusedWindow)
  focusHistory.current,focusHistory.previous=nil,nil
  rememberFocusedWindow(hs.window.focusedWindow())
  self.running=true
  mouseSnap.eventtap:start()
  if not mouseSnap.eventtap:isEnabled() then
    self:stop()
    return nil,"Mouse observer could not start; check Hammerspoon input permissions"
  end
  return self
end

function M:stop()
  self.running=false
  mouseSnap.seq=(mouseSnap.seq or 0)+1
  mouseSnap.eventtap:stop()
  for _,key in ipairs({"downTimer","upTimer"}) do
    if mouseSnap[key] then mouseSnap[key]:stop();mouseSnap[key]=nil end
  end
  if switcherFilter then
    switcherFilter:unsubscribe(hs.window.filter.windowFocused,rememberFocusedWindow)
    switcherFilter:pause()
    switcherFilter=nil
  end
  mouseSnap.startPoint,mouseSnap.startWindow,mouseSnap.partnerWindow=nil,nil,nil
  mouseSnap.startFrame,mouseSnap.edgeKind,mouseSnap.edgeSince=nil,nil,nil
  mouseSnap.moved=false
  focusHistory.current,focusHistory.previous=nil,nil
  return self
end

-- No hotkeys, global filters, switcher code, or background prewarming.
return M
