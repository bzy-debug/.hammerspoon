hs.loadSpoon('EmmyLua')
hs.loadSpoon('LeftRightHotkey')
hs.loadSpoon('BingDaily')

spoon.BingDaily.uhd_resolution = true

local http = hs.http
local json = hs.json
local aerospace = require('aerospace')

aerospace:init()

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
  aerospace.reload_config()
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

spoon.LeftRightHotkey:bind({ 'rShift' }, 'f', function()
  hs.execute("open -n '/Applications/Firefox.app' --args -P 'default'", true)
end)

spoon.LeftRightHotkey:bind({ 'rShift' }, 'a', function()
  hs.execute("open -n '/Applications/Firefox.app' --args -P 'anonymous'", true)
end)

spoon.LeftRightHotkey:start()

-- Mihomo Traffic Monitor
local trafficMenubar = hs.menubar.new(true, 'hs.mihomo.trafficMenubar')
local trafficTask = nil


local function formatBytes(bytes)
  if bytes < 1024 then
    return string.format("%5.0fB", bytes)
  elseif bytes < 1024 * 1024 then
    return string.format("%5.1fK", bytes / 1024)
  elseif bytes < 1024 * 1024 * 1024 then
    return string.format("%5.1fM", bytes / (1024 * 1024))
  else
    return string.format("%5.1fG", bytes / (1024 * 1024 * 1024))
  end
end

---@param up number kilobits per second
---@param down number kilobits per second
---@return hs.styledtext | string
local function formatTraffic(up, down)
  local content = string.format("⬆️%s ⬇️%s", formatBytes(up), formatBytes(down))
  return hs.styledtext.new(content, {
    font = { name = "Sarasa Term SC Nerd" }
  }) or content
end

local function startTrafficMonitor()
  if trafficTask then
    trafficTask:terminate()
  end

  trafficTask = hs.task.new("/usr/bin/curl", function(exitCode, stdout, stderr)
    -- Task terminated
    if exitCode ~= 0 and trafficMenubar then
      trafficMenubar:setTitle("⚠️ Error")
    end
  end, function(task, stdout, stderr)
    if stdout and stdout ~= "" and trafficMenubar then
      local success, data = pcall(json.decode, stdout)
      if success and data and data.up and data.down then
        local title = formatTraffic(data.up, data.down)
        trafficMenubar:setTitle(title)
      end
    end
    return true
  end, { "--no-buffer", "http://127.0.0.1:9090/traffic" })

  trafficTask:start()
end

if trafficMenubar then
  trafficMenubar:setTitle("Loading...")
  trafficMenubar:setMenu({
    { title = "Restart Monitor", fn = startTrafficMonitor },
    { title = "-" },
    {
      title = "Open Mihomo Dashboard",
      fn = function()
        hs.urlevent.openURL('https://metacubex.github.io/metacubexd/')
      end
    }
  })

  startTrafficMonitor()
end

local helloMsg = 'Config loaded'

if hostName == "bzy-mbp-home" then
  helloMsg = 'Home Config loaded'
elseif hostName == "bzy-mbp-16-office" then
  helloMsg = 'Office Config loaded'
end

quickAlert(helloMsg)
