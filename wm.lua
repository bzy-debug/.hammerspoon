local M = {}

local wf = hs.window.filter
local geo = hs.geometry
local bind = hs.hotkey.bind

-- simple window manager
-- only support one screen
-- only support one layout
-- switch between workspaces is instant
-- option-tab only switches between windows in current workspace

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

-- wm only work on one screen for now
local mainScreen = hs.screen.mainScreen()

local margin = 5

local log = hs.logger.new('wm')

local menubar = hs.menubar.new(true, 'wm')

-- get a string representation of a window for debug
--- @param win hs.window
local function windowString(win)
  --- @type hs.application
  ---@diagnostic disable-next-line: assign-type-mismatch
  local app = win:application()
  return string.format('%s \'%s\'(id=%d)', app:name(), win:title(), win:id())
end

-- get a string representation of a workspace for debug
--- @param workspace workspace
local function workspaceString(workspace)
  local template = [[workspace %s:
  main: %s
  others:
    %s
]]
  local main = workspace.layout.main and windowString(workspace.layout.main) or 'nil'
  --- @type string[]
  --- @diagnostic disable-next-line: assign-type-mismatch
  local others = hs.fnutils.map(workspace.layout.others, windowString)
  return string.format(template, workspace.name, main, table.concat(others, '\n\t'))
end


-- to resolve issue with some apps like Firefox
-- see https://github.com/Hammerspoon/hammerspoon/issues/3224#issuecomment-1294359070
--- @param win hs.window
--- @param frame hs.geometry
local function setFrame(win, frame)
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
local function popOthersToMain(layout)
  if #layout.others == 0 then return end
  layout.main = layout.others[1]
  table.remove(layout.others, 1)
end

local floatWindows = {
  'Picture-in-Picture'
}

local floatApps = {
  'com.apple.systempreferences'
}

-- check if a window should be floating by default
--- @param win hs.window
--- @return boolean
local function isFloat(win)
  if hs.fnutils.contains(floatWindows, win:title()) then
    return true
  end

  local app = win:application()
  if not app then return false end
  local bundleID = app:bundleID()
  return hs.fnutils.contains(floatApps, bundleID)
end

--- @param win hs.window
--- @return boolean
local function isManagable(win)
  return win:isVisible() and win:isStandard()
end

-- create workspace from windows
-- the main window is the focused window
--- @param windows hs.window[]
--- @param name string
--- @return workspace
local function createWorkspace(windows, name)
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
  --- @diagnostic disable-next-line: assign-type-mismatch
  local manageWindows = hs.fnutils.ifilter(windows, function(win)
    if isFloat(win) then
      floatingWindows[#floatingWindows + 1] = win
      return false
    end
    return isManagable(win)
  end)
  if #manageWindows == 0 then
    return workspace
  end
  log.i('found ' .. #manageWindows .. ' manageable windows')
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
    popOthersToMain(mainLayout)
  end
  return workspace
end

-- hide a window (move it out of screen)
--- @param win hs.window
local function hideWindow(win)
  local winFrame = win:frame()
  local hiddenFrame = geo.rect(
    -winFrame.w + 1,
    -winFrame.h + 1,
    winFrame.w,
    winFrame.h
  )
  setFrame(win, hiddenFrame)
end

-- hide all windows in a workspace
--- @param workspace workspace
local function hideWorkspace(workspace)
  local layout = workspace.layout
  if layout.main then
    hideWindow(layout.main)
  end
  for _, win in pairs(layout.others) do
    hideWindow(win)
  end
end

-- show workspace to main screen
--- @param workspace workspace
--- @param win hs.window | nil | false window to focus, if nil focus main, if false dont change focus
--- @return nil
local function showWorkspace(workspace, win)
  log.i('showing ', workspaceString(workspace))
  local text = hs.styledtext.new(
    workspace.name,
    {
      font = { name = 'Sarasa Term SC Nerd' }
    }
  )
  menubar:setTitle(text)
  local layout = workspace.layout
  if not layout.main then return end
  local screenFrame = mainScreen:frame()
  local width = screenFrame.w - 3 * margin
  local height = screenFrame.h - 2 * margin
  local frameWidth = math.floor(width / 2)

  local mainFrame = geo.rect(
    screenFrame.w - margin - frameWidth,
    screenFrame.y + margin,
    frameWidth,
    height
  )

  if #layout.others == 0 then
    mainFrame.x = screenFrame.x + margin
    mainFrame.w = width
  elseif layout.tempLarge and layout.tempLarge == layout.main then
    mainFrame.w = math.floor(width * 0.85)
    mainFrame.x = math.floor(screenFrame.w - margin - mainFrame.w)
  end

  setFrame(layout.main, mainFrame)

  local otherHeight = math.floor((height - margin * (#layout.others - 1)) / #layout.others)
  local otherX = screenFrame.x + margin
  for i, win in pairs(layout.others) do
    local othersFrame = geo.rect(
      otherX,
      screenFrame.y + margin * i + (otherHeight * (i - 1)),
      frameWidth,
      otherHeight
    )
    if layout.tempLarge and layout.tempLarge == win then
      othersFrame.y = mainFrame.y
      othersFrame.h = mainFrame.h
      othersFrame.w = math.floor(width * 0.9)
    end
    setFrame(win, othersFrame)
  end

  if win == false then
    return
  elseif win == nil then
    if layout.main then
      layout.main:focus()
    end
  else
    win:focus()
  end

  -- make floating windows frontmost
  for _, fwin in pairs(floatingWindows) do
    fwin:raise()
  end
end


-- switch to a workspace
--- @param name string
--- @param win hs.window | nil window to focus, if nil focus main, if false dont change focus
local function switchToWorkspace(name, win)
  if currentWorkspace and currentWorkspace.name == name then return end
  local workspace = workspaces[name]
  if not workspace then
    log.i('workspace not found, creating new one')
    workspace = createWorkspace({}, name)
  end
  if currentWorkspace then
    hideWorkspace(currentWorkspace)
  end
  currentWorkspace = workspace
  showWorkspace(workspace, win)
end

local filter = wf.new(true)

local function addWindowToWorkspace(workspace, win)
  local layout = workspace.layout
  if layout.main then
    layout.others[#layout.others + 1] = win
  else
    layout.main = win
  end
end


-- find window in current workspace
--- @param win hs.window
--- @return number index in others (0 if main, -1 if not found)
local function findWindowInCurrentWorkspace(win)
  if not currentWorkspace then return -1 end
  local layout = currentWorkspace.layout
  if layout.main and layout.main == win then
    return 0
  end
  local index = hs.fnutils.indexOf(layout.others, win)
  if index then
    return index
  end
  return -1
end

--- @param win hs.window
local function onWindowCreated(win)
  if not isManagable(win) then return end
  if not currentWorkspace then return end
  if isFloat(win) then
    floatingWindows[#floatingWindows + 1] = win
  else
    addWindowToWorkspace(currentWorkspace, win)
  end
  showWorkspace(currentWorkspace, win)
end

-- remove window from workspace
--- @param workspace workspace
--- @param win hs.window
--- @return hs.window | nil the window to focus, nil if no window to focus
local function removeWindowFromWorkspace(workspace, win)
  local layout = workspace.layout
  if layout.main and layout.main == win then
    if #layout.others > 0 then
      popOthersToMain(layout)
    else
      layout.main = nil
    end
    return layout.main
  else
    log.i('try to remove from others')
    local index = hs.fnutils.indexOf(layout.others, win)
    if index then
      log.i('found in others, removing')
      table.remove(layout.others, index)
      if 1 <= index and index <= #layout.others then
        return layout.others[index]
      else
        return layout.main
      end
    end
  end
end

-- find which workspace a window belongs to
-- return the workspace and the index in others (0 if main, -1 if not found)
--- @param win hs.window
--- @return workspace|nil
local function findWindowInWorkspaces(win)
  for _, workspace in pairs(workspaces) do
    local layout = workspace.layout
    if layout.main and layout.main == win then
      return workspace
    end
    local index = hs.fnutils.indexOf(layout.others, win)
    if index then
      return workspace
    end
  end
  return nil
end

--- @param win hs.window
local function onWindowDestroyed(win)
  log.i(string.format('window destroyed: \'%s\' (id=%d)', win:title(), win:id()))
  if not currentWorkspace then return end
  local workspace = findWindowInWorkspaces(win)
  if not workspace then return end
  local toFocus = removeWindowFromWorkspace(workspace, win)
  if workspace == currentWorkspace then
    showWorkspace(currentWorkspace, toFocus)
  end
end

--- @param win hs.window
local function onWindowMoved(win)
  if not isManagable(win) then return end
  log.i(string.format('window moved: \'%s\' (id=%d)', win:title(), win:id()))
  if not currentWorkspace then return end
  local workspace = findWindowInWorkspaces(win)
  if not workspace then return end
  if workspace == currentWorkspace then
    showWorkspace(currentWorkspace, false)
  end
end

--- @param win hs.window
local function onWindowFocused(win)
  if not isManagable(win) then return end
  log.i(string.format('window focused: \'%s\' (id=%d)', win:title(), win:id()))
  local index = findWindowInCurrentWorkspace(win)
  if index ~= -1 then return end
  local workspace = findWindowInWorkspaces(win)
  if not workspace then return end
  switchToWorkspace(workspace.name, win)
end

-- send current focused window to another workspace
--- @param name string
local function sendToWorkspace(name)
  log.i('try to send window to workspace ' .. name)
  local win = hs.window.focusedWindow()
  if not win then return end

  if currentWorkspace and currentWorkspace.name == name then return end

  local workspace = workspaces[name]
  if not workspace then
    log.i('workspace not found, creating new one')
    workspace = createWorkspace({ win }, name)
  else
    log.i('adding window to existing workspace')
    addWindowToWorkspace(workspace, win)
  end
  log.i('after adding, workspace is: ' .. workspaceString(workspace))

  hideWindow(win)

  if currentWorkspace then
    local toFocus = removeWindowFromWorkspace(currentWorkspace, win)
    showWorkspace(currentWorkspace, toFocus)
  end
end

-- enlarge current focused window
local function toggleEnlargeWindow()
  if not currentWorkspace then return end
  local win = hs.window.focusedWindow()
  if not win then return end
  local layout = currentWorkspace.layout
  if layout.tempLarge and layout.tempLarge == win then
    layout.tempLarge = nil
  else
    layout.tempLarge = win
  end
  showWorkspace(currentWorkspace, win)
end

local directionLeft <const> = 1
local directionRight <const> = 2
local directionUp <const> = 3
local directionDown <const> = 4

-- focus window in a direction
--- @param direction number
local function focus(direction)
  if not currentWorkspace then return end
  local win = hs.window.focusedWindow()
  if not win then return end
  local layout = currentWorkspace.layout
  local index = findWindowInCurrentWorkspace(win)

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

local function move(direction)
  if not currentWorkspace then return end
  local win = hs.window.focusedWindow()
  if not win then return end
  local layout = currentWorkspace.layout
  local index = findWindowInCurrentWorkspace(win)

  if index == -1 then return end

  if direction == directionLeft then
    if index == 0 and #layout.others > 0 then
      local oldFocus = layout.main
      local newMain = layout.others[1]
      layout.others[1] = layout.main
      layout.main = newMain
      showWorkspace(currentWorkspace, oldFocus)
    end
  elseif direction == directionRight then
    if index > 0 then
      local newMain = layout.others[index]
      layout.others[index] = layout.main
      layout.main = newMain
      showWorkspace(currentWorkspace, newMain)
    end
  elseif direction == directionDown then
    if index > 0 and index < #layout.others then
      win = layout.others[index]
      layout.others[index] = layout.others[index + 1]
      layout.others[index + 1] = win
      showWorkspace(currentWorkspace, win)
    end
  elseif direction == directionUp then
    if index > 1 then
      win = layout.others[index]
      layout.others[index] = layout.others[index - 1]
      layout.others[index - 1] = win
      showWorkspace(currentWorkspace, win)
    end
  end
end

local function closeWindow()
  local win = hs.window.focusedWindow()
  if win then
    win:close()
  end
end

local switchfilter = wf.new(function(win)
  local index = findWindowInCurrentWorkspace(win)
  if index == -1 then
    return hs.fnutils.contains(floatingWindows, win)
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
local function toggleFloatWindow()
  if not currentWorkspace then return end
  local win = hs.window.focusedWindow()
  if not win then return end

  local index = hs.fnutils.indexOf(floatingWindows, win)

  if index then
    -- already floating, make it managed
    table.remove(floatingWindows, index)
    addWindowToWorkspace(currentWorkspace, win)
    showWorkspace(currentWorkspace, win)
  else
    -- make it floating
    floatingWindows[#floatingWindows + 1] = win
    removeWindowFromWorkspace(currentWorkspace, win)
    showWorkspace(currentWorkspace, false)
  end
end

-- create key bindings for a workspace
--- @param name string
local function workspaceHotkeys(name)
  if name:len() ~= 1 then
    error('workspace name must be a single character')
  end

  bind({ 'option' }, name, function()
    switchToWorkspace(name)
  end)

  bind({ 'option', 'shift' }, name, function()
    sendToWorkspace(name)
  end)
end

function M.init()
  for _, k in pairs({ 'U', 'I', 'O', 'P', '7', '8', '9', '0' }) do
    workspaceHotkeys(k)
  end

  bind({ 'option' }, 'tab', function() switch:next() end)
  bind({ 'option', 'shift' }, 'tab', function() switch:previous() end)
  bind({ 'option' }, 'W', closeWindow)
  bind({ 'option' }, 'space', toggleFloatWindow)
  bind({ 'option' }, 'E', toggleEnlargeWindow)
  bind({ 'option' }, 'H', function() focus(directionLeft) end)
  bind({ 'option' }, 'L', function() focus(directionRight) end)
  bind({ 'option' }, 'J', function() focus(directionDown) end)
  bind({ 'option' }, 'K', function() focus(directionUp) end)
  bind({ 'option', 'shift' }, 'H', function() move(directionLeft) end)
  bind({ 'option', 'shift' }, 'L', function() move(directionRight) end)
  bind({ 'option', 'shift' }, 'J', function() move(directionDown) end)
  bind({ 'option', 'shift' }, 'K', function() move(directionUp) end)

  filter:subscribe(
    {
      [wf.windowCreated] = onWindowCreated,
      [wf.windowDestroyed] = onWindowDestroyed,
      [wf.windowMoved] = onWindowMoved,
      [wf.windowFocused] = onWindowFocused
    }
  )
  local windows = hs.window.allWindows()
  currentWorkspace = createWorkspace(windows, 'U')
  showWorkspace(currentWorkspace)
end

return M
