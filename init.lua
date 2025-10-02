-- checkout https://github.com/Hammerspoon/hammerspoon/issues/3712 and patch hammerspoon first

hs.loadSpoon('EmmyLua')
hs.loadSpoon('LeftRightHotkey')
hs.loadSpoon('BingDaily')

-- hs.logger.defaultLogLevel = 'debug'

spoon.BingDaily.uhd_resolution = true

local bind = hs.hotkey.bind

bind({ 'option' }, 'R', function()
  hs.reload()
end)

bind({ 'option' }, 'C', function()
  hs.openConsole()
end)

-- print all running application bundleID
bind({ 'option' }, 'A', function()
  local applications = hs.application.runningApplications()
  for _, app in ipairs(applications) do
    print(app:name(), app:bundleID())
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

local wm = require('wm')

wm.margin = 5

wm.floatWindows = {
  'Picture-in-Picture'
}

wm.floatApps = {
  'com.apple.systempreferences',
  'com.apple.SystemProfiler',
}

wm.appWorkspace = {
  ['org.gnu.Emacs'] = '7',
}

wm.workspaces = { 'U', 'I', 'O', 'P', '7', '8', '9', '0' }

wm:init()

hs.alert.show('Config loaded', hs.alert.defaultStyle, hs.screen.mainScreen(), 0.3)
