param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:appDir=Split-Path $TestRoot -Parent
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $script:appDir 'runtime\role-peek.ps1'),[Text.Encoding]::UTF8)))
function Assert-Drag($Condition,[string]$Message){if(!$Condition){throw $Message}}
function Assert-Frame($Actual,$Expected,[string]$Message){foreach($name in @('X','Y','Width','Height')){Assert-Drag ([Math]::Abs($Actual[$name]-$Expected[$name])-lt 0.001) "$Message ($name): expected $($Expected[$name]), got $($Actual[$name])"}}
$primary=@{Left=0;Top=0;Right=1920;Bottom=1040}
$left=@{Left=-1920;Top=0;Right=0;Bottom=1080}
$upper=@{Left=0;Top=-1440;Right=2560;Bottom=0}
$cases=@(
  @{Name='primary right';Area=$primary;Bounds=@{X=1760;Y=700;Width=160;Height=180};X=1780;Y=720;Side='right'},
  @{Name='primary left';Area=$primary;Bounds=@{X=100;Y=200;Width=180;Height=180};X=0;Y=220;Side='left'},
  @{Name='negative monitor left';Area=$left;Bounds=@{X=-1780;Y=700;Width=180;Height=180};X=-1920;Y=720;Side='left'},
  @{Name='negative monitor right';Area=$left;Bounds=@{X=-200;Y=250;Width=180;Height=180};X=-140;Y=270;Side='right'},
  @{Name='vertical monitor';Area=$upper;Bounds=@{X=1900;Y=-1300;Width=180;Height=180};X=2420;Y=-1280;Side='right'},
  @{Name='top clamp';Area=$primary;Bounds=@{X=100;Y=-70;Width=180;Height=180};X=0;Y=0;Side='left'},
  @{Name='bottom clamp';Area=$primary;Bounds=@{X=1700;Y=1000;Width=180;Height=180};X=1780;Y=900;Side='right'}
)
foreach($case in $cases){
  $actual=Get-WidgetPeekPlacement $case.Area $case.Bounds $null left
  Assert-Frame $actual @{X=$case.X;Y=$case.Y;Width=140;Height=140} $case.Name
  Assert-Drag ($actual.Side-eq $case.Side) "$($case.Name) chose the wrong nearest edge"
}
$free=Get-WidgetPeekPlacement $left $cases[0].Bounds @{X=-1600;Y=600} right
Assert-Frame $free @{X=-1600;Y=600;Width=140;Height=140} 'A free position must not snap back to an edge'
$clamped=Get-WidgetPeekPlacement $left $null @{X=-5000;Y=5000} right
Assert-Frame $clamped @{X=-1920;Y=940;Width=140;Height=140} 'Free positions clamp to their monitor work area'
$dragged=Get-WidgetPeekDragFrame $left @{X=-900;Y=500;Width=180;Height=180} -2000 2000
Assert-Frame $dragged @{X=-1920;Y=900;Width=180;Height=180} 'Dragging a waiting clone preserves its size while clamping'

# Native frame, settings and cursor effects are all simulated. No real window
# is shown, moved or focused, and no files in the user state are written.
Add-Type -TypeDefinition @'
using System;
public static class GptWidgetNative {
 public struct Rect { public int Left,Top,Right,Bottom; }
 public static Rect Current;
 public static Rect Frame(IntPtr h){return Current;}
}
'@
$script:saved=0;$script:chatClicks=0;$script:frameWrites=0;$script:chatFollows=0;$script:lastAreaPoint=$null
function Save-Settings {$script:saved++}
function Open-WidgetChatPanel {$script:chatClicks++}
function Position-WidgetChatPanel {$script:chatFollows++}
function Get-WidgetRoleArea([double]$X,[double]$Y){
  $script:lastAreaPoint=@{X=$X;Y=$Y}
  foreach($area in @($left,$primary,$upper)){if($X-ge $area.Left -and $X-lt $area.Right -and $Y-ge $area.Top -and $Y-lt $area.Bottom){return $area}}
  return $primary
}
function Set-WidgetRoleFrame($Frame){
  $native=[GptWidgetNative+Rect]::new();$native.Left=[int]$Frame.X;$native.Top=[int]$Frame.Y;$native.Right=$native.Left+[int]$Frame.Width;$native.Bottom=$native.Top+[int]$Frame.Height
  [GptWidgetNative]::Current=$native;$script:frameWrites++
}
$script:peekHandle=[IntPtr]1;$script:peekWindow=[Windows.Window]::new()
$script:peekImage=[Windows.Controls.Image]::new();$script:peekOriginalImage=[Windows.Controls.Image]::new()
$bitmap=[Windows.Media.Imaging.BitmapImage]::new();$bitmap.BeginInit();$bitmap.CacheOption='OnLoad';$bitmap.UriSource=[Uri](Join-Path $script:appDir 'assets\gpt-dragon-niang-bust.png');$bitmap.EndInit();$bitmap.Freeze();$script:peekOriginalImage.Source=$bitmap
$script:fullRoleBounds=@{X=100;Y=200;Width=180;Height=180;Facing=1}
$script:fullRoleAnchor=@{X=0;Y=100;Width=350;Height=350}
$control=[PSCustomObject]@{Captures=0;Releases=0}
$control|Add-Member ScriptMethod CaptureMouse {$this.Captures++;return $true}
$control|Add-Member ScriptMethod ReleaseMouseCapture {$this.Releases++}
try{
  $target=Get-WidgetPeekTarget
  Assert-Frame $target @{X=0;Y=220;Width=140;Height=140} 'Default target follows the large actor center'
  Assert-Drag ($script:lastAreaPoint.X-eq 190 -and $script:lastAreaPoint.Y-eq 290) 'Monitor selection must use the large visible actor center'
  $script:fullRoleBounds=@{X=-1780;Y=700;Width=180;Height=180;Facing=1}
  Assert-Frame (Get-WidgetPeekTarget) @{X=-1920;Y=720;Width=140;Height=140} 'Default projection must select the negative-coordinate monitor containing the large actor'
  $script:fullRoleBounds=@{X=100;Y=200;Width=180;Height=180;Facing=1}
  Set-WidgetPeekPosition @{X=-1600;Y=600;Width=180;Height=180}
  Assert-Frame (Get-WidgetPeekTarget) @{X=-1580;Y=620;Width=140;Height=140} 'A dragged waiting pose must keep its center at the 140px endpoint'
  Assert-Drag ($script:rolePeekSide-eq 'left') 'Cross-monitor free placement must update facing'
  $savedSettings=Get-WidgetRoleSettings
  $script:rolePeekPosition=$null
  Read-WidgetRoleSettings ($savedSettings|ConvertTo-Json -Depth 5|ConvertFrom-Json)
  Assert-Drag ($script:rolePeekPosition.X-eq -1580 -and $script:rolePeekPosition.OriginWidth-eq 350) 'Free position and origin did not survive JSON'
  $script:fullRoleBounds=@{X=105;Y=205;Width=190;Height=190;Facing=-1}
  Assert-Frame (Get-WidgetPeekTarget) @{X=-1580;Y=620;Width=140;Height=140} 'Press/mirror visual changes must not invalidate a stable native origin'
  $script:fullRoleAnchor.X=1
  Assert-Drag (Test-WidgetPeekOrigin $script:rolePeekPosition (Get-WidgetRoleOrigin)) 'One-pixel native rounding should retain the free position'
  $script:fullRoleAnchor.X=10;$savesBefore=$script:saved
  $target=Get-WidgetPeekTarget
  Assert-Drag ($null-eq $script:rolePeekPosition -and $script:saved-eq $savesBefore+1) 'Moving the large actor must clear and persist the old free-position basis'
  Assert-Frame $target @{X=0;Y=230;Width=140;Height=140} 'After the large actor moves, its edge/center projection takes precedence'
  Get-WidgetPeekTarget|Out-Null
  Assert-Drag ($script:saved-eq $savesBefore+1) 'An already cleared basis must not write settings repeatedly'
  foreach($name in @('Y','Width','Height')){
    $position=@{X=500;Y=400;OriginX=10;OriginY=100;OriginWidth=350;OriginHeight=350}
    $changed=@{X=10;Y=100;Width=350;Height=350};$changed[$name]+=10
    Assert-Drag (!(Test-WidgetPeekOrigin $position $changed)) "Changing origin $name must invalidate the override"
  }
  $script:rolePeekPosition=$null
  Set-WidgetRoleFrame @{X=500;Y=400;Width=180;Height=180}
  $script:peekRenderedMode='waiting';$script:peekOriginalImage.Opacity=1;$script:peekImage.Opacity=0
  Start-WidgetPeekDrag 550 450 $control
  $writes=$script:frameWrites
  Move-WidgetPeekDrag 552 450
  Assert-Drag (!$script:peekDrag.Moved -and $script:frameWrites-eq $writes) 'Sub-threshold mouse jitter must remain a click'
  Set-WidgetPeekMode peek
  Assert-Drag ($script:frameWrites-eq $writes -and $null-eq $script:peekTransition) 'An active drag must block automatic pose repositioning'
  Complete-WidgetPeekDrag
  Assert-Drag ($script:chatClicks-eq 1 -and $control.Captures-eq 1 -and $control.Releases-eq 1 -and $null-eq $script:peekDrag) 'A click must open chat once and release capture'
  Start-WidgetPeekDrag 550 450 $control
  Complete-WidgetPeekDrag $false
  Assert-Drag ($script:chatClicks-eq 1 -and $null-eq $script:peekDrag) 'Lost capture without movement must not open chat'

  # Pause a partially completed crossfade and resume from its actual dragged
  # frame and current opacities, rather than resetting to the old full pose.
  $script:peekRenderedMode='transition';$script:peekOriginalImage.Opacity=0.6;$script:peekImage.Opacity=0.4
  $script:peekTransition=@{Started=[DateTime]::UtcNow;From=$script:fullRoleBounds;To=@{X=0;Y=230;Width=140;Height=140};OriginalFrom=1;PeekFrom=0}
  $script:peekTransitionTimer=[Windows.Threading.DispatcherTimer]::new();$script:peekTransitionTimer.Start()
  Start-WidgetPeekDrag 550 450 $control
  Assert-Drag (!$script:peekTransition -and !$script:peekTransitionTimer.IsEnabled) 'Mouse-down must pause the running transition'
  $followBefore=$script:chatFollows
  Move-WidgetPeekDrag 570 465
  $moved=Get-WidgetPeekFrame
  Assert-Frame $moved @{X=520;Y=415;Width=180;Height=180} 'Actual drag must move from the captured physical frame'
  Assert-Drag ($script:peekDrag.Moved -and $script:chatFollows-eq $followBefore+1) 'A real drag must follow with the chat/dots anchor'
  $savesBefore=$script:saved;Complete-WidgetPeekDrag
  Assert-Drag ($script:chatClicks-eq 1 -and $script:saved-eq $savesBefore+1) 'Drag release must persist position without opening chat'
  Assert-Drag ($script:rolePeekPosition.X-eq 540 -and $script:rolePeekPosition.Y-eq 435) 'Dragged full-size center was not preserved'
  Set-WidgetPeekMode peek
  if([Windows.SystemParameters]::ClientAreaAnimation){
    Assert-Frame $script:peekTransition.From $moved 'Resumed animation must start at the dragged frame'
    Assert-Drag ($script:peekTransition.OriginalFrom-eq 0.6 -and $script:peekTransition.PeekFrom-eq 0.4) 'Resumed crossfade reset the current pose opacity'
    $script:peekTransition.Started=[DateTime]::UtcNow.AddMilliseconds(-500);Tick-WidgetPeekTransition
  }
  Assert-Frame (Get-WidgetPeekFrame) @{X=540;Y=435;Width=140;Height=140} 'Resumed animation must finish at the saved 140px endpoint'
  Set-WidgetPeekMode peek
  Assert-Drag (!$script:peekTransition) 'Stable dragged position must not restart transition on every tick'
  Start-WidgetPeekDrag 580 480 $control;Move-WidgetPeekDrag 590 480;Complete-WidgetPeekDrag $false
  Assert-Drag ($null-eq $script:peekDrag -and $script:chatClicks-eq 1) 'Lost capture after moving must persist and clean up without opening chat'
  Start-WidgetPeekDrag 590 480 $control;Set-WidgetPeekMode full
  Assert-Drag ($null-eq $script:peekDrag -and $script:chatClicks-eq 1) 'Returning to full mode must cancel capture without creating a chat click'
  Assert-Drag (!$script:peekWindow.IsVisible) 'The test must never show a real overlay'
  Write-Output 'PASS: nearest-edge/same-center projection, negative-coordinate monitors, free drag vs click, capture cleanup, persistence/basis invalidation, transition resume and 140px endpoint'
}finally{Stop-WidgetPeekTransition;$script:runtimeClosed=$true;$script:peekWindow.Close()}
