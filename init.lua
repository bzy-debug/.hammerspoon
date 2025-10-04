-- checkout https://github.com/Hammerspoon/hammerspoon/issues/3712 and patch hammerspoon first

hs.loadSpoon('EmmyLua')
hs.loadSpoon('LeftRightHotkey')
hs.loadSpoon('BingDaily')

-- hs.logger.defaultLogLevel = 'debug'

spoon.BingDaily.uhd_resolution = true

---@return string hostname
local function getLocalHostName()
  --- @type string
  ---@diagnostic disable-next-line: assign-type-mismatch
  local output = hs.execute('scutil --get LocalHostName')
  output = output:gsub('%s+', '')
  return output
end

local hostName = getLocalHostName()

---@param msg string
---@param time number|nil
---@return nil
local function quickAlert(msg, time)
  time = time or 0.3
  hs.alert.show(msg, hs.alert.defaultStyle, hs.screen.mainScreen(), time)
end

local bind = hs.hotkey.bind

bind({ 'option' }, 'R', function()
  hs.reload()
end)

bind({ 'option' }, 'C', function()
  hs.openConsole()
end)

-- print all running application bundleID
bind({ 'option' }, 'A', function()
  local win = hs.window.focusedWindow()
  if not win then return end
  local app = win:application()
  if not app then return end
  local bundleID = app:bundleID()
  local title = win:title()
  local content = string.format('%s - %s', bundleID, title)
  if hs.pasteboard.setContents(content) then
    quickAlert(content, 0.5)
  else
    quickAlert('failed to set clipboard', 0.5)
  end
end)

spoon.LeftRightHotkey:bind({ 'rShift' }, 't', function()
  local script = [[
tell application "iTerm"
  create window with default profile
  activate
end tell
]]
  hs.osascript.applescript(script)
end)

spoon.LeftRightHotkey:bind({ 'rShift' }, 'c', function()
  hs.execute('c --new-window', true)
end)

spoon.LeftRightHotkey:bind({ 'rShift' }, 'z', function()
  hs.execute("open -n '/Applications/Zen.app'", true)
end)

spoon.LeftRightHotkey:start()

hs.window.animationDuration = 0

local helloMsg = 'Config loaded'

local wm = require('wm')

wm.margin = 5

wm.workspaces = { 'U', 'I', 'O', 'P', '7', '8', '9', '0' }

wm.floatWindows = {
  'Picture-in-Picture',
}

wm.floatApps = {
  'com.apple.systempreferences',
  'com.apple.SystemProfiler',
  'com.xunlei.Thunder',
  'io.mpv'
}


if hostName == "bzy-mbp-home" then
  -- load home config

  wm.appWorkspace = {
    ['org.gnu.Emacs'] = '7',
  }


  helloMsg = 'Home Config loaded'
end

wm:init()

quickAlert(helloMsg)
