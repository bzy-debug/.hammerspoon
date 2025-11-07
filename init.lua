-- checkout https://github.com/Hammerspoon/hammerspoon/issues/3712 and patch hammerspoon first

hs.loadSpoon('EmmyLua')
hs.loadSpoon('LeftRightHotkey')
hs.loadSpoon('BingDaily')

spoon.BingDaily.uhd_resolution = true

local http = require('hs.http')
local json = require('hs.json')

---@return string hostname
local function getLocalHostName()
  --- @type string
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

local wifiServiceName = 'Wi-Fi'
local proxyHost = '127.0.0.1'
local proxyPort = '7890'
local mihomoConfigUrl = 'http://127.0.0.1:9090/configs'

---@param enabled boolean
---@return boolean
local function setTunMode(enabled)
  local body = json.encode({ tun = { enable = enabled } })
  local status = http.doRequest(mihomoConfigUrl, 'PATCH', body)
  if status and status >= 200 and status < 300 then
    return true
  end
  quickAlert('Failed to update Mihomo TUN mode', 0.6)
  return false
end

local function enableProxy(service)
  hs.execute(string.format('networksetup -setwebproxy %q %s %s', service, proxyHost, proxyPort))
  hs.execute(string.format('networksetup -setsecurewebproxy %q %s %s', service, proxyHost, proxyPort))
  hs.execute(string.format('networksetup -setwebproxystate %q on', service))
  hs.execute(string.format('networksetup -setsecurewebproxystate %q on', service))
  local tunOk = setTunMode(true)
  local suffix = tunOk and ' (TUN on)' or ' (TUN failed)'
  quickAlert(string.format('Proxy enabled: %s:%s%s', proxyHost, proxyPort, suffix), 0.6)
end

local function disableProxy(service)
  hs.execute(string.format('networksetup -setwebproxystate %q off', service))
  hs.execute(string.format('networksetup -setsecurewebproxystate %q off', service))
  local tunOk = setTunMode(false)
  local suffix = tunOk and ' (TUN off)' or ' (TUN failed)'
  quickAlert('Proxy disabled' .. suffix, 0.6)
end

---@param service string
---@return boolean
local function isWebProxyEnabled(service)
  local output = hs.execute(string.format('networksetup -getwebproxy %q', service)) or ''
  local enabled = output:match('Enabled:%s+(%w+)')
  return enabled == 'Yes'
end

local function toggleWifiProxy()
  local enabled = isWebProxyEnabled(wifiServiceName)
  if enabled then
    disableProxy(wifiServiceName)
  else
    enableProxy(wifiServiceName)
  end
end

local bind = hs.hotkey.bind

bind({ 'option' }, 'R', function()
  hs.reload()
end)

bind({ 'option' }, 'C', function()
  hs.openConsole()
end)

bind({ 'option' }, 'M', function()
  hs.urlevent.openURL('https://metacubex.github.io/metacubexd/')
end)

bind({ 'option' }, 'N', function()
  toggleWifiProxy()
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
  'com.apple.Passwords',
  'com.apple.FollowUpUI',
  'com.apple.LocalAuthentication.UIAgent',
  'com.apple.reminders',
  'com.xunlei.Thunder',
  'com.west2online.ClashXPro',
  'io.mpv',
  'com.apple.ScreenContinuity',
  'com.apple.mail'
}


if hostName == "bzy-mbp-home" then
  -- load home config

  wm.appWorkspace = {
    ['org.gnu.Emacs'] = '7',
  }


  helloMsg = 'Home Config loaded'
elseif hostName == "bzy-mbp-16-office" then
  wm.appWorkspace = {
    ['com.apple.Music'] = '7',
    ['com.tencent.WeWorkMac'] = '8',
    ['org.gnu.Emacs'] = '9',
  }

  helloMsg = 'Office Config loaded'
end

-- wm:init()

quickAlert(helloMsg)
