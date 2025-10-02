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

--- Types
--- @class workspace
--- @field name string
--- @field layout mainLayout
--
--- @class mainLayout
--- @field main hs.window | nil
--- @field others hs.window[]
--- @field tempLarge hs.window | nil

--- @type table<string, workspace>
local workspaces = {}

--- @type hs.window[]
local floatingWindows = {}

--- @type workspace|nil
local currentWorkspace = nil

-- wm only works on one screen
local mainScreen = hs.screen.mainScreen()

local log = hs.logger.new('wm')

local menubar = hs.menubar.new(true, 'wm')

-- get a string representation of a window for debug
--- @param win hs.window
function F.windowString(win)
  --- @type hs.application
  ---@diagnostic disable-next-line: assign-type-mismatch
  local app = win:application()
  return string.format('%s \'%s\'(id=%d)', app:name(), win:title(), win:id())
end

-- get a string representation of a workspace for debug
--- @param workspace workspace
function F.workspaceString(workspace)
  local template = [[workspace %s:
  main: %s
  others:
    %s
  tempLarge: %s
]]
  local main = workspace.layout.main and F.windowString(workspace.layout.main) or 'nil'
  --- @type string[]
  --- @diagnostic disable-next-line: assign-type-mismatch
  local others = fnutils.map(workspace.layout.others, F.windowString)
  local tempLarge = workspace.layout.tempLarge and F.windowString(workspace.layout.tempLarge) or 'nil'
  return string.format(template, workspace.name, main, table.concat(others, '\n\t'), tempLarge)
end

-- to resolve issue with some apps like Firefox
-- see https://github.com/Hammerspoon/hammerspoon/issues/3224#issuecomment-1294359070
--- @param win hs.window
--- @param frame hs.geometry
function F.setFrame(win, frame)
  local axApp = hs.axuielement.applicationElement(win:application())
  if axApp then
    local wasEnhanced = axApp.AXEnhancedUserInterface
    if wasEnhanced then
      axApp.AXEnhancedUserInterface = false
    end
    win:setFrame(frame)
    if wasEnhanced then
      axApp.AXEnhancedUserInterface = true
    end
  else
    win:setFrame(frame)
  end
end

-- move the first window in others to main
--- @param layout mainLayout
--- @return nil
function F.popOthersToMain(layout)
  if #layout.others == 0 then return end
  layout.main = layout.others[1]
  table.remove(layout.others, 1)
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

-- create workspace from windows
-- the main window is the focused window
--- @param windows hs.window[]
--- @param name string
--- @return workspace
function F.createWorkspace(windows, name)
  --- @type mainLayout
  local mainLayout = {
    main = nil,
    tempLarge = nil,
    others = {},
  }

  --- @type workspace
  local workspace = {
    name = name,
    layout = mainLayout,
  }

  workspaces[name] = workspace

  --- @type hs.window[]
  local manageWindows = {}

  for _, win in pairs(windows) do
    local defaultWorkspace = F.defaultWorkspaceOfWindow(win)
    if F.isFloat(win) then
      floatingWindows[#floatingWindows + 1] = win
    elseif defaultWorkspace and defaultWorkspace ~= name then
      local targetWorkspace = F.getWorkspace(defaultWorkspace)
      F.addWindowToWorkspace(targetWorkspace, win)
    elseif F.isManagable(win) then
      manageWindows[#manageWindows + 1] = win
    end
  end

  if #manageWindows == 0 then
    return workspace
  end
  local focusedWindow = hs.window.frontmostWindow()
  for _, win in pairs(manageWindows) do
    local id = win:id()
    if focusedWindow and id == focusedWindow:id() then
      mainLayout.main = win
      goto continue
    end
    mainLayout.others[#mainLayout.others + 1] = win
    ::continue::
  end

  if not mainLayout.main then
    F.popOthersToMain(mainLayout)
  end
  return workspace
end

-- hide a window (move it out of screen)
--- @param win hs.window
function F.hideWindow(win)
  local winFrame = win:frame()
  local hiddenFrame = geo.rect(
    -winFrame.w + 1,
    -winFrame.h + 1,
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
  log.i('try to show', F.workspaceString(workspace))
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
  local screenFrame = mainScreen:frame()
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

  -- make floating windows frontmost
  for _, fwin in pairs(floatingWindows) do
    fwin:raise()
  end
end

-- switch to a workspace
-- first hide current workspace then show the target workspace
--- @param name string
--- @param win hs.window | nil window to focus, if nil focus main, if false dont change focus
function F.switchToWorkspace(name, win)
  -- switch to current workspace, do nothing
  if currentWorkspace and currentWorkspace.name == name then return end

  local workspace = workspaces[name]
  if not workspace then
    log.i('switchToWorkspace: target workspace not exists, creating new one')
    workspace = F.createWorkspace({}, name)
  end

  -- first show new workspace then hide old workspace to reduce flicker
  local lastCurrentWorkspace = currentWorkspace
  currentWorkspace = workspace
  F.showWorkspace(workspace, win)

  if lastCurrentWorkspace then
    F.hideWorkspace(lastCurrentWorkspace)
  end
end

local filter = wf.new(true)

--- add window to workspace
--- @param workspace workspace
--- @param win hs.window
function F.addWindowToWorkspace(workspace, win)
  local layout = workspace.layout
  if layout.main then
    layout.others[#layout.others + 1] = win
  else
    layout.main = win
  end
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
    -- remove main window
    -- should focus on the new main window after remove
    if #layout.others > 0 then
      F.popOthersToMain(layout)
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

-- handle window events
--- @param win hs.window
function F.onWindowEvent(win, _, event)
  if not currentWorkspace then return end
  if not F.isManagable(win) then return end
  if event == wf.windowCreated then
    if F.isFloat(win) then
      floatingWindows[#floatingWindows + 1] = win
    else
      local targetWorkspaceName = F.defaultWorkspaceOfWindow(win)
      if targetWorkspaceName then
        local targetWorkspace = F.getWorkspace(targetWorkspaceName)
        F.addWindowToWorkspace(targetWorkspace, win)
        F.showWorkspace(targetWorkspace, win)
        return
      end
      F.addWindowToWorkspace(currentWorkspace, win)
    end
    F.showWorkspace(currentWorkspace, win)
  elseif event == wf.windowDestroyed then
    if not currentWorkspace then return end
    local index = F.findWindowInCurrentWorkspace(win)
    if index == -1 then return end
    local toFocus = F.removeWindowFromWorkspace(currentWorkspace, win)
    F.showWorkspace(currentWorkspace, toFocus)
  elseif event == wf.windowMoved then
    local index = F.findWindowInCurrentWorkspace(win)
    if index == -1 then return end
    F.showWorkspace(currentWorkspace, false)
  elseif event == wf.windowFocused then
    local index = F.findWindowInCurrentWorkspace(win)
    if index == -1 then
      -- focus a window not in current workspace
      -- switch to the workspace of that window
      local workspace = F.findWindowInWorkspaces(win)
      if not workspace then return end
      F.switchToWorkspace(workspace.name, win)
    end
  end
end

-- get workspace by name, create a new one if not exists
--- @param name string
--- @return workspace
function F.getWorkspace(name)
  local workspace = workspaces[name]
  if not workspace then
    workspace = F.createWorkspace({}, name)
  end
  return workspace
end

-- move window from current workspace to another workspace
--- @param win hs.window
--- @param name string
--- @return nil win window to focus after move
function F.moveWindowToWorkspace(win, name)
  if not currentWorkspace then return end
  if currentWorkspace.name == name then return end
  local targetWorkspace = F.getWorkspace(name)
  F.addWindowToWorkspace(targetWorkspace, win)
  return F.removeWindowFromWorkspace(currentWorkspace, win)
end

-- send current focused window to another workspace
--- @param name string
--- @return hs.window | nil win the window to focus after move
function F.sendToWorkspace(name)
  local win = hs.window.focusedWindow()
  if not win then return end

  F.hideWindow(win)
  return F.moveWindowToWorkspace(win, name)
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
  local layout = currentWorkspace.layout
  local index = F.findWindowInCurrentWorkspace(win)

  if index == -1 then return end

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
  local layout = currentWorkspace.layout
  local index = F.findWindowInCurrentWorkspace(win)

  if index == -1 then return end

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
  local index = F.findWindowInCurrentWorkspace(win)
  if index == -1 then
    return fnutils.contains(floatingWindows, win)
  else
    return true
  end
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
  if not currentWorkspace then return end
  local win = hs.window.focusedWindow()
  if not win then return end

  local index = fnutils.indexOf(floatingWindows, win)

  if index then
    -- already floating, make it managed
    table.remove(floatingWindows, index)
    F.addWindowToWorkspace(currentWorkspace, win)
    F.showWorkspace(currentWorkspace, win)
  else
    -- make it floating
    floatingWindows[#floatingWindows + 1] = win
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

  filter:subscribe(
    { wf.windowCreated, wf.windowDestroyed, wf.windowMoved, wf.windowFocused, },
    F.onWindowEvent
  )
  local windows = hs.window.allWindows()
  currentWorkspace = F.createWorkspace(windows, M.workspaces[1])
  F.showWorkspace(currentWorkspace)
end

return M
