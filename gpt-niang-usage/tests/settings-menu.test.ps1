param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$appDir=Split-Path $TestRoot -Parent
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $appDir 'runtime\ui-settings.ps1'),[Text.Encoding]::UTF8)))
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $appDir 'runtime\chat-panel.ps1'),[Text.Encoding]::UTF8)))
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $appDir 'runtime\role-peek.ps1'),[Text.Encoding]::UTF8)))
function Assert-Equal($actual,$expected,[string]$message){if($actual-ne $expected){throw "$message : expected '$expected', got '$actual'"}}
function Save-Settings {}
function Update-WidgetChats {}
function Tick-WidgetChatBehavior {}
function Tick-Widget {}
function Set-WidgetFollowHost([bool]$Follow){$script:followHost=$Follow}
function Set-WidgetMenuBounds {}
function Position-WidgetMenuToHost {}
function Set-Appearance {}
function Set-WidgetAudioVolume {}
function Stop-WidgetAudio {}
. (Join-Path $appDir 'runtime\supervisor-task.ps1')
. (Join-Path $appDir 'runtime\update-common.ps1')
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $appDir 'runtime\update-ui.ps1'),[Text.Encoding]::UTF8)))
$script:dataDir=Join-Path ([IO.Path]::GetTempPath()) ('gpt-niang-menu-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $script:dataDir
$script:config=@{version='1.3.2'}
Initialize-WidgetUpdater
$script:window=New-Object Windows.Window
$script:collapsed=$true;$script:bubbleMode='quota';$script:followHost=$true;$script:desktopTopmost=$true
$script:scale=1.0;$script:soundOn=$true;$script:soundVolume=0.9;$script:bubbleTapAdvance=$false;$script:hideMenu=$false
$script:colorMode='mixed';$script:colorChance=0.5;$script:colorTextChance=3;$script:colorPaused=$false
try{
  Initialize-WidgetSettingsMenu
  $expected=@('查看额度','聊天与运行情况','聊天显示与收起','换一句台词','刷新额度','编辑我的语录','显示与位置','外观设置','声音与点击','更新','退出 GPT 娘')
  $actual=@($script:context.Items|Where-Object{$_.Header-is [string]}|ForEach-Object{$_.Header})
  Assert-Equal ($actual-join '|') ($expected-join '|') 'Menu entries and removed title block'
  Assert-Equal $script:settingsMenuUi.ChatTaskOnly.IsChecked $true 'Task-only display defaults on'
  Assert-Equal $script:settingsMenuUi.ChatBlurDelay.Value 3 'Focus collapse defaults to three seconds'
  Assert-Equal $script:settingsMenuUi.ChatIdleDelay.Value 2 'Completion hide defaults to two seconds'
  Assert-Equal $script:settingsMenuUi.ChatAutoCollapse.IsChecked $true 'Status defaults to compact without a click'
  Assert-Equal $script:settingsMenuUi.ChatAutoCollapseDelay.Value 3 'Status remains readable for three seconds'
  $script:settingsMenuUi.ChatAutoCollapseDelay.Value=6
  Assert-Equal $script:chatAutoCollapseDelaySeconds 6 'Status delay is configurable independently of focus'
  $script:settingsMenuUi.ChatAutoCollapse.IsChecked=$false;$script:settingsMenuUi.ChatAutoCollapse.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent));Update-WidgetSettingsMenu
  Assert-Equal $script:settingsMenuUi.ChatAutoCollapseDelay.IsEnabled $false 'Disabling automatic compact disables its delay slider'
  Assert-Equal $script:settingsMenuUi.PeekTransition.IsChecked $true 'Pose transition is enabled by default'
  Assert-Equal $script:settingsMenuUi.Peek.IsChecked $true 'Side pose defaults on'
  Assert-Equal $script:settingsMenuUi.PeekDelay.Value 3 'Side pose delay defaults to three seconds'
  Assert-Equal $script:settingsMenuUi.PeekRight.IsChecked $true 'Side pose defaults to the right edge'
  Assert-Equal $script:settingsMenuUi.PeekLeft.IsChecked $false 'Only one side is selected'
  $script:settingsMenuUi.PeekDelay.Value=8
  Assert-Equal $script:rolePeekDelaySeconds 8 'Side pose delay slider updates behavior'
  Assert-Equal $script:settingsMenuUi.PeekDelayText.Text '8 秒' 'Side pose delay label is clear'
  $script:settingsMenuUi.PeekLeft.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
  Assert-Equal $script:rolePeekSide 'left' 'Left edge control updates pose preference'
  Assert-Equal $script:settingsMenuUi.PeekLeft.IsChecked $true 'Left edge control reflects selection'
  Assert-Equal $script:settingsMenuUi.PeekRight.IsChecked $false 'Right edge clears when left is selected'
  $script:settingsMenuUi.PeekRight.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
  Assert-Equal $script:rolePeekSide 'right' 'Right edge control updates pose preference'
  $script:settingsMenuUi.Peek.IsChecked=$false;$script:settingsMenuUi.Peek.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
  Assert-Equal $script:rolePeekEnabled $false 'Side pose switch updates behavior'
  Assert-Equal $script:settingsMenuUi.PeekDelay.IsEnabled $false 'Disabled side pose disables its delay slider'
  Assert-Equal $script:settingsMenuUi.PeekLeft.IsEnabled $false 'Disabled side pose disables edge controls'
  $script:settingsMenuUi.Peek.IsChecked=$true;$script:settingsMenuUi.Peek.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
  Assert-Equal $script:settingsMenuUi.PeekDelay.IsEnabled $true 'Reenabled side pose enables its delay slider'
  Assert-Equal $script:settingsMenuUi.PeekDelay.Value 8 'Toggling the pose preserves its delay'
  $script:settingsMenuUi.ChatBlurDelay.Value=7
  Assert-Equal $script:chatBlurDelaySeconds 7 'Focus delay slider updates behavior'
  Assert-Equal $script:settingsMenuUi.ChatBlurDelayText.Text '7 秒' 'Focus delay label is clear'
  $script:settingsMenuUi.ChatIdleDelay.Value=4
  Assert-Equal $script:chatIdleDelaySeconds 4 'Completion delay slider updates behavior'
  $script:settingsMenuUi.ChatBlur.IsChecked=$false;$script:settingsMenuUi.ChatBlur.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent));Update-WidgetSettingsMenu
  Assert-Equal $script:chatCollapseOnBlur $false 'Focus collapse switch updates behavior'
  Assert-Equal $script:settingsMenuUi.ChatBlurDelay.IsEnabled $false 'Disabled collapse disables its delay slider'
  Assert-Equal $script:settingsMenuUi.UpdateVersion.Header '当前版本：1.3.2' 'Update menu shows actual version'
  Assert-Equal $script:settingsMenuUi.AutoUpdate.IsChecked $true 'Automatic updates are on initially'
  $script:settingsMenuUi.AutoUpdate.IsChecked=$false
  $script:settingsMenuUi.AutoUpdate.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
  Assert-Equal (Read-WidgetUpdateJson (Join-Path $script:dataDir 'update-preferences.json')).automatic $false 'Menu toggle persists separately'
  Assert-Equal $script:settingsMenuUi.Topmost.Visibility Collapsed 'Window mode hides topmost'
  Assert-Equal $script:settingsMenuUi.TopmostDivider.Visibility Collapsed 'Window mode hides its divider'
  foreach($name in @('Follow','Desktop','Topmost','Hide','Sound','Tap','Peek','PeekLeft','PeekRight')){
    Assert-Equal $script:settingsMenuUi[$name].StaysOpenOnClick $true 'All settings retain menu interaction'
    Assert-Equal $script:settingsMenuUi[$name].Style $script:settingsMenuResources['SettingsItem'] 'Rows share the same style'
  }
  $script:settingsMenuUi.Desktop.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
  Assert-Equal $script:followHost $false 'Desktop row selects desktop mode'
  Assert-Equal $script:settingsMenuUi.Follow.IsChecked $false 'Modes are mutually exclusive'
  Assert-Equal $script:settingsMenuUi.Desktop.IsChecked $true 'Selected desktop indicator'
  Assert-Equal $script:settingsMenuUi.Topmost.Visibility Visible 'Desktop mode exposes topmost'
  Assert-Equal $script:settingsMenuUi.Topmost.IsChecked $true 'Remembered desktop preference'
  $script:settingsMenuUi.Follow.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
  Assert-Equal $script:followHost $true 'Window row selects window mode'
  Assert-Equal $script:settingsMenuUi.Desktop.IsChecked $false 'Desktop indicator clears'
  Assert-Equal $script:settingsMenuUi.Topmost.Visibility Collapsed 'Topmost disappears immediately'
  Assert-Equal $script:desktopTopmost $true 'Switching modes retains desktop preference'
  $script:settingsMenuUi.SizeButtons[2].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
  Assert-Equal $script:scale 1.4 'Preset updates actual size'
  Assert-Equal $script:sizeSlider.Value 1.4 'Preset and slider stay synchronized'
  $script:settingsMenuUi.Sound.IsChecked=$false
  $script:settingsMenuUi.Sound.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.MenuItem]::ClickEvent))
  Assert-Equal $script:settingsMenuUi.Volume.IsEnabled $false 'Muted sound disables volume control'
  Write-Output 'PASS: menu modes, side pose settings, conditional topmost, shared row styling, presets and sound controls'
}finally{
  $script:window.Close()
  Assert-WidgetUpdateChildPath $script:dataDir ([IO.Path]::GetTempPath())
  Remove-Item -LiteralPath $script:dataDir -Recurse -Force
}
