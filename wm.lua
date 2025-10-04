local M = {}
local F = {}

local wf = hs.window.filter
local geo = hs.geometry
local fnutils = hs.fnutils
local bind = hs.hotkey.bind

-- simple window manager
-- only support one screen
-- only support one layout
-- switch between workspaces is instant
-- option-tab only switches between windows in current workspace

-- settings

-- margin for window snapping
M.margin = 5

-- windows with these titles will float by default
--- @type string[]
M.floatWindows = {}

-- applications with these bundleIDs will float by default
--- @type string[]
M.floatApps = {}

-- the default workspace for app
-- app id -> workspace name
--- @type table<string, string>
M.appWorkspace = {}

-- all workspaces
--- @type string[]
M.workspaces = {}

local log = hs.logger.new('wm')

--- Types
--- @class workspace
--- @field name string
--- @field layout mainLayout
---
--- @class mainLayout
--- @field main hs.window | nil
--- @field others hs.window[]
--- @field tempLarge hs.window | nil
---
--- @class floatingWindow
--- @field win hs.window
--- @field frame hs.geometry

--- @type table<string, workspace>
local workspaces = {}

--- @type table<number, floatingWindow>
local floatingWindows = {}

-- add a new floating window (not managed by wm)
--- @param win hs.window
--- @return nil
function F.addNewFloatingWindow(win)
  log.df('addNewFloatingWindow: %s', F.windowString(win))
  local id = win:id()
  if not id then return end
  floatingWindows[id] = { win = win, frame = win:frame() }
end

-- update the frame of a floating window
--- @param win hs.window
function F.updateFloatingWindow(win)
  local id = win:id()
  if not id then return end
  if floatingWindows[id] then
    local frame = win:frame()
    log.df('updateFloatingWindow: update %s to %s', F.windowString(win), frame)
    floatingWindows[id] = { win = win, frame = frame }
  end
end

-- remove a floating window
--- @param win hs.window
--- @return boolean status true if removed, false if not found
function F.removeFloatingWindow(win)
  local id = win:id()
  if not id then return false end
  if floatingWindows[id] then
    floatingWindows[id] = nil
    return true
  end
  return false
end

-- check if a window is floating
--- @param win hs.window
--- @return boolean
function F.isFloatingWindow(win)
  local id = win:id()
  if not id then return false end
  return floatingWindows[id] ~= nil
end

--- @type workspace|nil
local currentWorkspace = nil

local menubar = hs.menubar.new(true, 'wm')

-- get a string representation of a window for debug
--- @param win hs.window
function F.windowString(win)
  local app = win:application()
  local appStr = app and app:name() or 'Unknown App'
  return string.format('%s \'%s\'(id=%d)', appStr, win:title(), win:id())
end

-- get a string representation of a workspace for debug
--- @param workspace workspace
function F.workspaceString(workspace)
  local template = [[name: %s
  main: %s
  others: %s
  tempLarge: %s
]]
  local main = workspace.layout.main and F.windowString(workspace.layout.main) or 'nil'
  --- @type string[]
  local others = fnutils.map(workspace.layout.others, F.windowString)
  local tempLarge = workspace.layout.tempLarge and F.windowString(workspace.layout.tempLarge) or 'nil'
  return string.format(template, workspace.name, main, table.concat(others, '\n\t'), tempLarge)
end

-- to resolve issue with some apps like Firefox
-- see https://github.com/Hammerspoon/hammerspoon/issues/3224#issuecomment-1294359070
--- @param win hs.window
--- @param frame hs.geometry
function F.setFrame(win, frame)
  local app = win:application()
  if app then
    local axApp = hs.axuielement.applicationElement(app)
    if axApp then
      local wasEnhanced = axApp.AXEnhancedUserInterface
      if wasEnhanced then
        axApp.AXEnhancedUserInterface = false
      end
      win:setFrame(frame)
      if wasEnhanced then
        axApp.AXEnhancedUserInterface = true
      end
      return
    end
  end
  win:setFrame(frame)
end

-- get the bundle id of a window
--- @param win hs.window
--- @return string | nil
function F.windowBundleID(win)
  local app = win:application()
  if not app then return nil end
  return app:bundleID()
end

-- check if a window should be floating by default
--- @param win hs.window
--- @return boolean
function F.isFloat(win)
  if fnutils.contains(M.floatWindows, win:title()) then return true end
  local bundleID = F.windowBundleID(win)
  if not bundleID then return false end
  return fnutils.contains(M.floatApps, bundleID)
end

--- @param win hs.window
--- @return boolean
function F.isManagable(win)
  return win:isVisible() and win:isStandard()
end

-- get the default workspace name for a window
--- @param win hs.window
--- @return string | nil
function F.defaultWorkspaceOfWindow(win)
  local bundleID = F.windowBundleID(win)
  if not bundleID then return nil end
  return M.appWorkspace[bundleID]
end

--- create a new empty workspace
--- @param name string
--- @return workspace workspace
function F.newWorkspace(name)
  local workspace = {
    name = name,
    layout = {
      main = nil,
      tempLarge = nil,
      others = {},
    },
  }
  workspaces[name] = workspace
  return workspace
end

--- create the initial workspace from all windows
--- name is the first workspace in M.workspaces
--- main window is the frontmost window
--- @return workspace
function F.initWorkspace()
  log.d('initWorkspace')
  local name = M.workspaces[1]
  local windows = hs.window.allWindows()
  local workspace = F.newWorkspace(name)

  local focusedWindow = hs.window.frontmostWindow()

  if focusedWindow and F.isManagable(focusedWindow) then
    workspace.layout.main = focusedWindow
  end

  for _, win in pairs(windows) do
    if F.isManagable(win) then
      local w = F.tryToAddWindowToWorkspace(workspace, win)
      -- if window is added to its default workspace, hide it from current workspace
      if w and w ~= workspace then
        F.hideWindow(win)
      end
    end
  end

  return workspace
end

-- hide a window (move it out of screen)
--- @param win hs.window
function F.hideWindow(win)
  local screenFrame = hs.screen.mainScreen():frame()
  local winFrame = win:frame()
  if winFrame.w <= 0 or winFrame.h <= 0 then
    return
  end
  local hiddenFrame = geo.rect(
    screenFrame.w - 1,
    screenFrame.h - 1,
    winFrame.w,
    winFrame.h
  )
  F.setFrame(win, hiddenFrame)
end

-- hide all windows in a workspace
--- @param workspace workspace
function F.hideWorkspace(workspace)
  local layout = workspace.layout
  if layout.main then
    F.hideWindow(layout.main)
  end
  for _, win in pairs(layout.others) do
    F.hideWindow(win)
  end
end

-- show workspace to main screen
--- @param workspace workspace
--- @param win hs.window | nil | false window to focus, if nil focus main, if false dont change focus
--- @return nil
function F.showWorkspace(workspace, win)
  log.df('showWorkspace %s', F.workspaceString(workspace))
  local text = hs.styledtext.new(
    workspace.name,
    {
      font = { name = 'Sarasa Term SC Nerd' }
    }
  )
  menubar:setTitle(text)
  local layout = workspace.layout
  -- if there is no main window, nothing to show
  if not layout.main then return end

  -- arrange windows
  -- only works on main screen
  local screenFrame = hs.screen.mainScreen():frame()
  local width = screenFrame.w - 3 * M.margin
  local height = screenFrame.h - 2 * M.margin
  local frameWidth = math.floor(width / 2)

  local mainFrame = geo.rect(
    screenFrame.w - M.margin - frameWidth,
    screenFrame.y + M.margin,
    frameWidth,
    height
  )

  if #layout.others == 0 then
    mainFrame.x = screenFrame.x + M.margin
    mainFrame.w = width
  elseif layout.tempLarge and layout.tempLarge == layout.main then
    mainFrame.w = math.floor(width * 0.9)
    mainFrame.x = math.floor(screenFrame.w - M.margin - mainFrame.w)
  end

  F.setFrame(layout.main, mainFrame)

  local otherHeight = math.floor((height - M.margin * (#layout.others - 1)) / #layout.others)
  local otherX = screenFrame.x + M.margin
  for i, win in pairs(layout.others) do
    local othersFrame = geo.rect(
      otherX,
      screenFrame.y + M.margin * i + (otherHeight * (i - 1)),
      frameWidth,
      otherHeight
    )
    if layout.tempLarge and layout.tempLarge == win then
      othersFrame.y = mainFrame.y
      othersFrame.h = mainFrame.h
      othersFrame.w = math.floor(width * 0.9)
    end
    F.setFrame(win, othersFrame)
  end

  -- focus window
  if win == false then
    return
  elseif win == nil then
    if layout.main then layout.main:focus() end
  else
    win:focus()
  end
end

-- switch to a workspace
-- first hide current workspace then show the target workspace
--- @param name string
function F.switchToWorkspace(name)
  -- switch to current workspace, do nothing
  if currentWorkspace and currentWorkspace.name == name then return end

  local workspace = F.getWorkspace(name)

  -- first show new workspace then hide old workspace to reduce flicker
  local lastCurrentWorkspace = currentWorkspace
  currentWorkspace = workspace
  F.showWorkspace(workspace)

  if lastCurrentWorkspace then
    F.hideWorkspace(lastCurrentWorkspace)
  end
end

local filter = wf.new(true)

--- add window to workspace
--- @param workspace workspace
--- @param win hs.window
function F.doAddWindowToWorkspace(workspace, win)
  local layout = workspace.layout
  if layout.main then
    if layout.main == win then return end
    if fnutils.contains(layout.others, win) then return end
    layout.others[#layout.others + 1] = win
  else
    layout.main = win
  end
end

--- try to add window to workspace
--- the window might be floating or added to another workspace based on appWorkspace
--- @param workspace workspace
--- @param win hs.window
--- @return workspace | nil workspace the workspace the window is actually added to, nil if not added
function F.tryToAddWindowToWorkspace(workspace, win)
  log.df([[ tryToAddWindowToWorkspace
workspace: %s
window: %s
]], F.workspaceString(workspace), F.windowString(win))

  if F.isFloat(win) then
    return F.addNewFloatingWindow(win)
  end
  local defaultWorkspaceName = F.defaultWorkspaceOfWindow(win)
  if defaultWorkspaceName and defaultWorkspaceName ~= workspace.name then
    local targetWorkspace = F.getWorkspace(defaultWorkspaceName)
    F.doAddWindowToWorkspace(targetWorkspace, win)
    return targetWorkspace
  end
  F.doAddWindowToWorkspace(workspace, win)
  return workspace
end

-- find window in current workspace
--- @param win hs.window
--- @return number index index in others (0 if main, -1 if not found)
function F.findWindowInCurrentWorkspace(win)
  if not currentWorkspace then return -1 end
  local layout = currentWorkspace.layout
  if layout.main and layout.main == win then
    return 0
  end
  local index = fnutils.indexOf(layout.others, win)
  if index then
    return index
  end
  return -1
end

-- remove window from workspace
--- @param workspace workspace
--- @param win hs.window
--- @return hs.window | nil win the window to focus after remove, nil if no window to focus
function F.removeWindowFromWorkspace(workspace, win)
  local layout = workspace.layout
  if layout.tempLarge == win then
    layout.tempLarge = nil
  end
  if layout.main and layout.main == win then
    if #layout.others > 0 then
      layout.main = layout.others[1]
      table.remove(layout.others, 1)
    else
      layout.main = nil
    end
    return layout.main
  else
    local index = fnutils.indexOf(layout.others, win)
    if index then
      table.remove(layout.others, index)
      if #layout.others == 0 then
        return layout.main
      elseif index > #layout.others then
        return layout.others[#layout.others]
      else
        return layout.others[index]
      end
    else
      return nil
    end
  end
end

-- find which workspace a window belongs to
--- @param win hs.window
--- @return workspace|nil
function F.findWindowInWorkspaces(win)
  for _, workspace in pairs(workspaces) do
    local layout = workspace.layout
    if layout.main and layout.main == win then
      return workspace
    end
    local index = fnutils.indexOf(layout.others, win)
    if index then
      return workspace
    end
  end
  return nil
end

local eventNames = {
  [wf.windowCreated] = 'windowCreated',
  [wf.windowDestroyed] = 'windowDestroyed',
  [wf.windowMoved] = 'windowMoved',
  [wf.windowFocused] = 'windowFocused',
}

-- handle window events
--- @param win hs.window
function F.onWindowEvent(win, _, event)
  if not currentWorkspace then return end
  log.df('onWindowEvent %s %s', eventNames[event], F.windowString(win))

  if event == wf.windowDestroyed then
    -- try to remove from floating windows first
    if F.removeFloatingWindow(win) then return end
    local workspace = F.findWindowInWorkspaces(win)
    if not workspace then return end
    local toFocus = F.removeWindowFromWorkspace(workspace, win)
    if workspace ~= currentWorkspace then return end
    F.showWorkspace(currentWorkspace, toFocus)
    return
  end

  if not F.isManagable(win) then return end

  if event == wf.windowCreated then
    local workspace = F.tryToAddWindowToWorkspace(currentWorkspace, win)
    if not workspace then
      F.showWorkspace(currentWorkspace, win)
    else
      F.showWorkspace(workspace, win)
    end
    return
  end

  if event == wf.windowMoved then
    -- update floating window position if it is floating
    F.updateFloatingWindow(win)

    local index = F.findWindowInCurrentWorkspace(win)
    if index == -1 then return end
    F.showWorkspace(currentWorkspace, false)
    return
  end
end

-- get workspace by name, create a new one if not exists
--- @param name string
--- @return workspace
function F.getWorkspace(name)
  local workspace = workspaces[name]
  if not workspace then
    workspace = F.newWorkspace(name)
  end
  return workspace
end

-- send current focused window to another workspace
--- @param name string
--- @return hs.window | nil win the window to focus after move
function F.sendToWorkspace(name)
  if not currentWorkspace then return end
  local win = hs.window.focusedWindow()
  if not win then return end
  if F.isFloatingWindow(win) then return end
  if currentWorkspace.name == name then return end

  F.hideWindow(win)
  local targetWorkspace = F.getWorkspace(name)
  F.doAddWindowToWorkspace(targetWorkspace, win)
  return F.removeWindowFromWorkspace(currentWorkspace, win)
end

-- enlarge current focused window
function F.toggleEnlargeWindow()
  if not currentWorkspace then return end
  local win = hs.window.focusedWindow()
  if not win then return end
  local layout = currentWorkspace.layout
  if layout.tempLarge and layout.tempLarge == win then
    layout.tempLarge = nil
  else
    layout.tempLarge = win
  end
  F.showWorkspace(currentWorkspace, win)
end

local directionLeft <const> = 1
local directionRight <const> = 2
local directionUp <const> = 3
local directionDown <const> = 4

-- focus window in a direction
--- @param direction number
function F.focus(direction)
  if not currentWorkspace then return end
  local win = hs.window.focusedWindow()
  if not win then return end
  local index = F.findWindowInCurrentWorkspace(win)
  if index == -1 then return end

  local layout = currentWorkspace.layout
  if direction == directionLeft then
    if index == 0 and #layout.others > 0 then
      layout.others[1]:focus()
    end
  elseif direction == directionRight then
    if index > 0 then
      layout.main:focus()
    end
  elseif direction == directionDown then
    if index > 0 and index < #layout.others then
      layout.others[index + 1]:focus()
    end
  elseif direction == directionUp then
    if index > 1 then
      layout.others[index - 1]:focus()
    end
  end
end

function F.move(direction)
  if not currentWorkspace then return end
  local win = hs.window.focusedWindow()
  if not win then return end
  local index = F.findWindowInCurrentWorkspace(win)
  if index == -1 then return end

  local layout = currentWorkspace.layout
  if direction == directionLeft then
    if index == 0 and #layout.others > 0 then
      local oldFocus = layout.main
      local newMain = layout.others[1]
      layout.others[1] = layout.main
      layout.main = newMain
      F.showWorkspace(currentWorkspace, oldFocus)
    end
  elseif direction == directionRight then
    if index > 0 then
      local newMain = layout.others[index]
      layout.others[index] = layout.main
      layout.main = newMain
      F.showWorkspace(currentWorkspace, newMain)
    end
  elseif direction == directionDown then
    if index > 0 and index < #layout.others then
      win = layout.others[index]
      layout.others[index] = layout.others[index + 1]
      layout.others[index + 1] = win
      F.showWorkspace(currentWorkspace, win)
    end
  elseif direction == directionUp then
    if index > 1 then
      win = layout.others[index]
      layout.others[index] = layout.others[index - 1]
      layout.others[index - 1] = win
      F.showWorkspace(currentWorkspace, win)
    end
  end
end

function F.closeWindow()
  local win = hs.window.focusedWindow()
  if win then
    win:close()
  end
end

local switchfilter = wf.new(function(win)
  return F.isFloatingWindow(win) or F.findWindowInCurrentWorkspace(win) ~= -1
end)

local switch = hs.window.switcher.new(
  switchfilter,
  {
    showThumbnails = false,
    showSelectedThumbnail = false
  }
)

-- toggle float the focused window
-- float window will be the frontmost in every workspace
function F.toggleFloatWindow()
  log.d('toggleFloatWindow called')
  if not currentWorkspace then return end
  local win = hs.window.focusedWindow()
  if not win then
    log.d('toggleFloatWindow: no focused window')
    return
  end

  if F.isFloatingWindow(win) then
    log.d('toggleFloatWindow: already floating, making window managed')
    F.removeFloatingWindow(win)
    F.doAddWindowToWorkspace(currentWorkspace, win)
    F.showWorkspace(currentWorkspace, win)
  else
    log.d('toggleFloatWindow: making window floating')
    F.addNewFloatingWindow(win)
    F.removeWindowFromWorkspace(currentWorkspace, win)
    F.showWorkspace(currentWorkspace, false)
  end
end

-- create key bindings for a workspace
--- @param name string
function F.workspaceHotkeys(name)
  if name:len() ~= 1 then
    error('workspace name must be a single character')
  end

  bind({ 'option' }, name, function()
    F.switchToWorkspace(name)
  end)

  bind({ 'option', 'shift' }, name, function()
    if not currentWorkspace then return end
    local toFocus = F.sendToWorkspace(name)
    F.showWorkspace(currentWorkspace, toFocus)
  end)
end

function M:init()
  -- check if workspaces are defined
  if #M.workspaces == 0 then
    error('no workspaces defined')
  end

  -- check if appWorkspace are valid
  for app, ws in pairs(M.appWorkspace) do
    if not fnutils.contains(M.workspaces, ws) then
      error(string.format('appWorkspace %s -> %s is invalid', app, ws))
    end
  end

  for _, k in pairs(M.workspaces) do
    F.workspaceHotkeys(k)
  end

  bind({ 'option' }, 'tab', function() switch:next() end)
  bind({ 'option', 'shift' }, 'tab', function() switch:previous() end)
  bind({ 'option' }, 'W', F.closeWindow)
  bind({ 'option' }, 'space', F.toggleFloatWindow)
  bind({ 'option' }, 'E', F.toggleEnlargeWindow)
  bind({ 'option' }, 'H', function() F.focus(directionLeft) end)
  bind({ 'option' }, 'L', function() F.focus(directionRight) end)
  bind({ 'option' }, 'J', function() F.focus(directionDown) end)
  bind({ 'option' }, 'K', function() F.focus(directionUp) end)
  bind({ 'option', 'shift' }, 'H', function() F.move(directionLeft) end)
  bind({ 'option', 'shift' }, 'L', function() F.move(directionRight) end)
  bind({ 'option', 'shift' }, 'J', function() F.move(directionDown) end)
  bind({ 'option', 'shift' }, 'K', function() F.move(directionUp) end)

  currentWorkspace = F.initWorkspace()
  F.showWorkspace(currentWorkspace)
  filter:subscribe(
    { wf.windowCreated, wf.windowDestroyed, wf.windowMoved },
    F.onWindowEvent
  )
end

return M
