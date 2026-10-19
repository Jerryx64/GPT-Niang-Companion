param([string]$TestRoot=$PSScriptRoot)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:appDir=Split-Path $TestRoot -Parent
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $script:appDir 'runtime\role-peek.ps1'),[Text.Encoding]::UTF8)))
function Assert-Equal($Actual,$Expected,[string]$Message){if($Actual-ne $Expected){throw "$Message : expected '$Expected', got '$Actual'"}}
function Assert-Role([string]$Expected,[long]$Now,[bool]$HostFocus=$false,[bool]$OwnFocus=$false,[bool]$HostExists=$true,[bool]$Interacting=$false){Assert-Equal (Resolve-WidgetRoleMode $Now $HostFocus $OwnFocus $HostExists $Interacting) $Expected "Role at $Now"}

# A quick app switch cancels the first deadline rather than reusing it later.
Assert-Role full 1000 $true
Assert-Role waiting 2000
Assert-Role waiting 3999
Assert-Role full 4000 $true
Assert-Equal $script:roleState.blurAt $null 'Returning to Codex clears the deadline'
Assert-Role waiting 4500
Assert-Role waiting 7499
Assert-Role peek 7500
Assert-Role peek 8000 $false $true
Assert-Role peek 9000 $false $false $true $true
Assert-Role full 10000 $true
Assert-Role full 11000 $false $true
Assert-Role full 12000 $false $false $true $true
Assert-Equal $script:roleState.blurAt $null 'Our chat and menu do not start an external app deadline'

# Host destruction clears pending transitions, and a new host starts cleanly.
Assert-Role waiting 13000
Assert-Role hidden 14000 $false $false $false
Assert-Equal $script:roleState.blurAt $null 'A missing host clears the deadline'
Assert-Role waiting 15000
Assert-Role waiting 17999
Assert-Role peek 18000
Assert-Role hidden 19000 $false $true $false

Initialize-WidgetRoleBehavior
Read-WidgetRoleSettings ([PSCustomObject]@{rolePeekDelaySeconds=7})
Assert-Role full 1000 $true
Assert-Role waiting 2000
Assert-Role waiting 8999
Assert-Role peek 9000
$script:rolePeekDelaySeconds=0
Assert-Role full 10000 $true
Assert-Role peek 10001
$script:rolePeekEnabled=$false
Assert-Role legacy 11000
Assert-Equal $script:roleState.blurAt $null 'Disabling the feature clears the deadline'
$script:rolePeekEnabled=$true
Assert-Role full 12000 $true

# Only typed booleans, bounded durations and supported sides replace defaults.
Read-WidgetRoleSettings ([PSCustomObject]@{rolePeekEnabled=$false;rolePeekDelaySeconds=8;rolePeekSide='left'})
$saved=Get-WidgetRoleSettings
Initialize-WidgetRoleBehavior
Read-WidgetRoleSettings ($saved|ConvertTo-Json|ConvertFrom-Json)
Assert-Equal $script:rolePeekEnabled $false 'Enabled preference survives JSON roundtrip'
Assert-Equal $script:rolePeekDelaySeconds 8 'Delay survives JSON roundtrip'
Assert-Equal $script:rolePeekSide 'left' 'Side survives JSON roundtrip'
foreach($invalid in @('NaN','Infinity','-Infinity','invalid',-1,61)){
  Initialize-WidgetRoleBehavior
  Read-WidgetRoleSettings ([PSCustomObject]@{rolePeekDelaySeconds=$invalid})
  Assert-Equal $script:rolePeekDelaySeconds 3 "Invalid duration $invalid preserves the default"
}
foreach($invalid in @('false',0,1,$null)){
  Initialize-WidgetRoleBehavior
  Read-WidgetRoleSettings ([PSCustomObject]@{rolePeekEnabled=$invalid})
  Assert-Equal $script:rolePeekEnabled $true 'Untyped boolean preserves the default'
}
foreach($invalid in @('center',1,$null)){
  Initialize-WidgetRoleBehavior
  Read-WidgetRoleSettings ([PSCustomObject]@{rolePeekSide=$invalid})
  Assert-Equal $script:rolePeekSide 'right' 'Unsupported side preserves the default'
}

# Create only an unshown HWND. Native calls are stubbed so this test cannot
# raise, reposition or activate any app on the user's desktop.
Add-Type -TypeDefinition @'
using System;
public static class GptWidgetNative {
 public struct Rect {public int Left,Top,Right,Bottom;}
 public static long ExtendedStyle;
 public static Rect Frame(IntPtr hwnd){return new Rect {Left=0,Top=0,Right=140,Bottom=140};}
 public static IntPtr GetWindowLongPtr(IntPtr hwnd,int index){return new IntPtr(ExtendedStyle);}
 public static IntPtr SetWindowLongPtr(IntPtr hwnd,int index,IntPtr value){ExtendedStyle=value.ToInt64();return IntPtr.Zero;}
}
'@
$script:chatClicks=0;$script:menuClicks=0;$script:runtimeClosed=$false
function Open-WidgetChatPanel {$script:chatClicks++}
function Open-WidgetMenu {$script:menuClicks++}
try{
  Initialize-WidgetPeekWindow
  # EnsureHandle may round a DIP to the nearest physical pixel at monitor DPI.
  # Set-WidgetPeekMode later enforces the exact 140 physical pixel HWND frame.
  Assert-Equal ([Math]::Abs($script:peekWindow.Width-140)-lt 1) $true 'Initial width requests the approved size'
  Assert-Equal ([Math]::Abs($script:peekWindow.Height-140)-lt 1) $true 'Initial height requests the approved size'
  Assert-Equal $script:peekWindow.Owner $null 'Peek window has no Codex owner'
  Assert-Equal $script:peekWindow.ShowActivated $false 'Showing the pose does not request activation'
  Assert-Equal $script:peekWindow.ShowInTaskbar $false 'Pose has no taskbar entry'
  Assert-Equal $script:peekWindow.Topmost $true 'Pose can accompany external apps'
  Assert-Equal $script:peekWindow.IsVisible $false 'The test never shows the pose'
  Assert-Equal ($script:peekHandle-ne [IntPtr]::Zero) $true 'Window initialization creates a usable HWND'
  Assert-Equal (([GptWidgetNative]::ExtendedStyle-band 0x08000080)-eq 0x08000080) $true 'No-activate and tool-window styles are requested'
  Assert-Equal ($script:peekImage.Source.PixelWidth-gt 0) $true 'Approved B2 asset loads'
  Assert-Equal $script:peekImage.Source.IsFrozen $true 'Image decoding finishes before use'
  $script:peekImage.Measure([Windows.Size]::new(140,140));$script:peekImage.Arrange([Windows.Rect]::new(0,0,140,140));$script:peekImage.UpdateLayout()
  Assert-Equal $script:peekImage.ActualWidth 140 'The isolated image lays out at 140'
  Assert-Equal $script:peekImage.ActualHeight 140 'The isolated image height lays out at 140'
  $render=[Windows.Media.Imaging.RenderTargetBitmap]::new(140,140,96,96,[Windows.Media.PixelFormats]::Pbgra32);$render.Render($script:peekImage)
  Assert-Equal $render.PixelWidth 140 'Offscreen preview is exactly 140 pixels wide'
  Assert-Equal $render.PixelHeight 140 'Offscreen preview is exactly 140 pixels high'
  $transparent=$null;$opaque=$null;$image=$script:peekImage.Source
  for($y=0;$y-lt 140 -and (!$transparent -or !$opaque);$y++){
    for($x=0;$x-lt 140 -and (!$transparent -or !$opaque);$x++){
      $px=[int][Math]::Floor(($x+0.5)/140*$image.PixelWidth);$py=[int][Math]::Floor(($y+0.5)/140*$image.PixelHeight)
      $alpha=$script:peekPixels[$py*$script:peekStride+$px*4+3]
      if($alpha-eq 0 -and !$transparent){$transparent=[Windows.Point]::new($x+0.5,$y+0.5)}
      if($alpha-ge 240 -and !$opaque){$opaque=[Windows.Point]::new($x+0.5,$y+0.5)}
    }
  }
  Assert-Equal ($null-ne $transparent -and $null-ne $opaque) $true 'The asset contains both transparent and visible pixels'
  Assert-Equal (Test-WidgetPeekHit $transparent) $false 'Transparent art pixels pass through'
  Assert-Equal (Test-WidgetPeekHit $opaque) $true 'Visible art remains clickable'
  foreach($point in @([Windows.Point]::new(-1,0),[Windows.Point]::new(0,-1),[Windows.Point]::new(140,0),[Windows.Point]::new(0,140))){Assert-Equal (Test-WidgetPeekHit $point) $false 'Out-of-bounds points pass through'}
  $left=[Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0,[Windows.Input.MouseButton]::Left);$left.RoutedEvent=[Windows.UIElement]::MouseLeftButtonUpEvent
  Start-WidgetPeekDrag 20 20 $null
  $script:peekStage.RaiseEvent($left)
  Assert-Equal $script:chatClicks 1 'Left click opens the existing chat panel'
  Start-WidgetPeekDrag 20 20 $null
  $lost=[Windows.Input.MouseEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0);$lost.RoutedEvent=[Windows.Input.Mouse]::LostMouseCaptureEvent
  $script:peekStage.RaiseEvent($lost)
  Assert-Equal ($null-eq $script:peekDrag) $true 'Lost mouse capture cleans up the pending gesture'
  Assert-Equal $script:chatClicks 1 'Lost mouse capture must not become a chat click'
  $right=[Windows.Input.MouseButtonEventArgs]::new([Windows.Input.Mouse]::PrimaryDevice,0,[Windows.Input.MouseButton]::Right);$right.RoutedEvent=[Windows.UIElement]::MouseRightButtonUpEvent
  $script:peekStage.RaiseEvent($right)
  Assert-Equal $script:menuClicks 1 'Right click opens existing settings'
  Assert-Equal $script:peekWindow.IsVisible $false 'Interaction tests never show the pose'
}finally{$script:runtimeClosed=$true;if($script:peekWindow){$script:peekWindow.Close()}}
Write-Output 'PASS: role delay cancellation, own focus, host lifecycle, preferences, B2 image, inactive 140 px window, alpha hit testing and clicks'
