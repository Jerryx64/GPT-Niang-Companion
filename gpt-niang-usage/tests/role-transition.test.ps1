$ErrorActionPreference='Stop'
$sourceApp=Split-Path $PSScriptRoot -Parent
$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('gpt-niang-transition-'+[Guid]::NewGuid().ToString('N'))
$taskApp=Join-Path $fixtureRoot 'app'
$fixtureData=Join-Path $fixtureRoot 'state'
$null=New-Item -ItemType Directory -Path $taskApp,$fixtureData -Force
try{
Copy-Item -LiteralPath (Join-Path $sourceApp 'runtime'),(Join-Path $sourceApp 'assets') -Destination $taskApp -Recurse
foreach($name in @('widget.ps1','widget.xaml','chat-panel.xaml')){Copy-Item -LiteralPath (Join-Path $sourceApp $name) -Destination $taskApp}
@{dataDir=$fixtureData;version='1.3.4';nodePath=(Get-Command node.exe).Source}|ConvertTo-Json|Set-Content -LiteralPath (Join-Path $taskApp 'installation.json') -Encoding UTF8
# Load the real WPF/native implementation without starting a worker or event loop.
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $taskApp 'widget.ps1'),[Text.Encoding]::UTF8))) -AppDir $taskApp -CheckOnly | Out-Null
function Assert-Transition($Condition,[string]$Message){if(!$Condition){throw $Message}}
$script:widgetHandle=[Windows.Interop.WindowInteropHelper]::new($script:window).EnsureHandle()
$script:hostHandle=$script:widgetHandle;$script:runtimeClosed=$false
$script:window.Opacity=0;$script:window.ShowActivated=$false
try{
  $script:window.Show();$script:window.UpdateLayout();Save-WidgetFullRoleBounds
  Assert-Transition ($script:fullRoleBounds -and $script:fullRoleBounds.Width-gt 0) 'Real transformed character bounds were not cached'
  Initialize-WidgetPeekWindow;$script:peekWindow.Opacity=0
  Set-WidgetPeekMode waiting
  Assert-Transition ($script:peekWindow.IsVisible -and $script:window.IsVisible) 'The independent clone must show before hiding the original window'
  Assert-Transition ($script:peekOriginalImage.Opacity-eq 1 -and $script:peekImage.Opacity-eq 0) 'Waiting must keep the original silhouette visible'
  $script:window.Hide()
  Assert-Transition $script:peekWindow.IsVisible 'Minimizing/hiding the original must not leave a blank delay'
  $script:roleTransitionEnabled=$true
  Set-WidgetPeekMode peek
  if([Windows.SystemParameters]::ClientAreaAnimation){
    Assert-Transition ([bool]$script:peekTransition) 'A single native transition should start after the delay'
    $script:peekTransition.Started=[DateTime]::UtcNow.AddMilliseconds(-120);Tick-WidgetPeekTransition
    Assert-Transition ($script:peekOriginalImage.Opacity-gt 0 -and $script:peekImage.Opacity-gt 0) 'Both poses must overlap during the crossfade'
    Assert-Transition ([Math]::Abs($script:peekOriginalImage.Opacity+$script:peekImage.Opacity-1)-lt 0.001) 'Transition opacity must never introduce a blank frame'
    $script:peekTransition.Started=[DateTime]::UtcNow.AddMilliseconds(-500);Tick-WidgetPeekTransition
  }
  $frame=[GptWidgetNative]::Frame($script:peekHandle)
  Assert-Transition (($frame.Right-$frame.Left)-eq 140 -and ($frame.Bottom-$frame.Top)-eq 140) 'The final native pose must be exactly 140 physical pixels'
  Assert-Transition (!$script:peekTransition -and $script:peekRenderedMode-eq 'peek') 'Transition must finish once, not restart each tick'
  Set-WidgetPeekMode peek
  Assert-Transition (!$script:peekTransition) 'Stable peek must not restart the animation'
  Set-WidgetPeekMode waiting;Set-WidgetPeekMode peek
  $script:window.Show();Set-WidgetPeekMode full
  Assert-Transition ($script:window.IsVisible -and !$script:peekWindow.IsVisible) 'Returning to Codex must show the original before removing the clone'
  Assert-Transition (!$script:peekTransition -and (!$script:peekTransitionTimer -or !$script:peekTransitionTimer.IsEnabled)) 'Quick return must cancel pending animation'
  Set-WidgetPeekMode waiting;$script:roleTransitionEnabled=$false;Set-WidgetPeekMode peek
  Assert-Transition ($script:peekWindow.IsVisible -and !$script:peekTransition -and $script:peekImage.Opacity-eq 1) 'Disabling motion must preserve gapless handoff'
  # Exercise the real physical GetWindowRect/SetWindowPos path on this fully
  # transparent test window. Control=null avoids mouse capture and user input.
  $script:window.Hide()
  $before=Get-WidgetPeekFrame
  $centerX=$before.X+$before.Width/2;$centerY=$before.Y+$before.Height/2
  $area=Get-WidgetRoleArea $centerX $centerY
  $dx=if($centerX-lt ($area.Left+$area.Right)/2){100}else{-100}
  $dy=if($centerY-lt ($area.Top+$area.Bottom)/2){40}else{-40}
  $expected=Get-WidgetPeekDragFrame $area $before $dx $dy
  Start-WidgetPeekDrag $centerX $centerY $null
  Move-WidgetPeekDrag ($centerX+$dx) ($centerY+$dy)
  $moved=Get-WidgetPeekFrame
  foreach($name in @('X','Y','Width','Height')){Assert-Transition ([Math]::Abs($moved[$name]-$expected[$name])-le 1) "Native drag did not apply expected physical $name"}
  Complete-WidgetPeekDrag $false
  Assert-Transition ($null-eq $script:peekDrag -and [Math]::Abs(($script:rolePeekPosition.X+70)-($moved.X+$moved.Width/2))-le 1 -and [Math]::Abs(($script:rolePeekPosition.Y+70)-($moved.Y+$moved.Height/2))-le 1) 'Native drag release must preserve the dragged center without a chat click'
  Set-WidgetPeekMode peek
  $held=Get-WidgetPeekFrame
  foreach($name in @('X','Y','Width','Height')){Assert-Transition ([Math]::Abs($held[$name]-$moved[$name])-le 1) "Stable peek reset native dragged $name"}
  $persisted=Get-Content -LiteralPath (Join-Path $script:dataDir 'settings.json') -Raw -Encoding UTF8|ConvertFrom-Json
  Assert-Transition ($persisted.rolePeekPosition -and [Math]::Abs($persisted.rolePeekPosition.X-$moved.X)-le 1 -and [Math]::Abs($persisted.rolePeekPosition.Y-$moved.Y)-le 1) 'Native dragged position did not persist to JSON settings'
  $script:rolePeekPosition=$null;Read-WidgetRoleSettings $persisted;Set-WidgetPeekMode peek
  $restored=Get-WidgetPeekFrame
  foreach($name in @('X','Y','Width','Height')){Assert-Transition ([Math]::Abs($restored[$name]-$held[$name])-le 1) "JSON reload reset native dragged $name"}
  Assert-Transition ($script:peekWindow.Opacity-eq 0 -and !$script:peekWindow.ShowActivated) 'Native drag regression must remain transparent and non-activating'
  Write-Output 'PASS: real WPF clone handoff, overlap, 140 px endpoint, cancellation, native physical drag and persisted JSON handoff'
}finally{Stop-WidgetPeekTransition;$script:runtimeClosed=$true;if($script:peekWindow){$script:peekWindow.Close()};$script:window.Close()}
}finally{
  $resolvedFixture=[IO.Path]::GetFullPath($fixtureRoot)
  $tempParent=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
  if($resolvedFixture.StartsWith($tempParent,[StringComparison]::OrdinalIgnoreCase) -and (Split-Path $resolvedFixture -Leaf)-like 'gpt-niang-transition-*'){
    Remove-Item -LiteralPath $resolvedFixture -Recurse -Force
  }
}
