param([string]$PreviewDirectory)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase,System.Windows.Forms,System.Drawing
$script:appDir=Split-Path $PSScriptRoot -Parent
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $script:appDir 'runtime\chat-panel.ps1'),[Text.Encoding]::UTF8)))
function Assert-ChatBehavior($Condition,[string]$Message){if(!$Condition){throw $Message}}
function Assert-Mode($Expected,[long]$Now,[long]$Foreground=11,[bool]$Own=$false,[bool]$HostFocus=$true,[bool]$Root=$true,[bool]$Interacting=$false,[string]$Role='full'){
  $actual=Resolve-WidgetChatMode $Now $Foreground $Own $HostFocus $Root $Interacting $Role
  if($actual-ne $Expected){throw "At $Now expected $Expected, got $actual"}
}
# A task shows a small badge and collapses without any foreground change/click.
Assert-Mode hidden 1000
$script:chatHasTasks=$true;$script:chatTaskKey='task1';Assert-Mode status 2000
Assert-Mode status 4999
Assert-Mode compact 5000
$script:chatTaskKey='task1:approval';Assert-Mode status 7000
Assert-Mode status 8000 33 $true $false
Assert-Mode status 10999
Assert-Mode compact 11000
# Full-to-side repeats the badge; waiting-to-peek does not reset its deadline.
Assert-Mode status 12000 22 $false $false $false $false waiting
Assert-Mode status 13000 22 $false $false $false $false peek
Assert-Mode compact 15000 22 $false $false $false $false peek
Assert-Mode status 16000
Assert-Mode compact 19000
$script:chatState.dismissed=$script:chatTaskKey;Assert-Mode compact 19500
$script:chatTaskKey='task2';Assert-Mode status 20000
# Manual input retains focus across task updates; only its blur setting acts.
$script:chatState.mode='expanded';$script:chatState.manual=$true;$script:chatState.focus=11
$script:chatTaskKey='task2:question';Assert-Mode expanded 21000 33 $true $false
Assert-Mode expanded 26000 33 $true $false
Assert-Mode expanded 27000 44 $false $false $false $false waiting
Assert-Mode expanded 29999 44 $false $false $false $false peek
Assert-Mode compact 30000 44 $false $false $false $false peek
Assert-ChatBehavior (!$script:chatState.manual) 'Blurred composer did not return to automatic behavior'
$script:chatHasTasks=$false;$script:chatTaskKey='';Assert-Mode compact 31000 44 $false $false $false $false peek
Assert-Mode compact 32999 44 $false $false $false $false peek
Assert-Mode hidden 33000 44 $false $false $false $false peek
Initialize-WidgetChatBehavior
$script:chatHasTasks=$true;$script:chatTaskKey='side-start';Assert-Mode status 1000 22 $false $false $false $false peek
Assert-Mode compact 4000 22 $false $false $false $false peek
Initialize-WidgetChatBehavior
$script:chatHasTasks=$true;$script:chatTaskKey='hover';Assert-Mode status 1000
Assert-Mode status 3000 11 $false $true $true $true
Assert-Mode status 5999
Assert-Mode compact 6000
Initialize-WidgetChatBehavior
$script:chatHasTasks=$true;$script:chatTaskKey='switches';$script:chatAutoCollapse=$false
Assert-Mode status 1000
Assert-Mode status 30000
$script:chatAutoCollapse=$true;$script:chatAutoCollapseDelaySeconds=0;Assert-Mode compact 30001
$script:chatTaskOnly=$false;Assert-Mode hidden 31000
$script:chatState.mode='expanded';$script:chatState.manual=$true;$script:chatState.focus=11;$script:chatHasTasks=$false
Assert-Mode expanded 100000 33 $true $false
$script:chatCollapseOnBlur=$false;Assert-Mode expanded 110000 22 $false $false
$script:chatCollapseOnBlur=$true;$script:chatBlurDelaySeconds=0;Assert-Mode compact 110001 22 $false $false
Read-WidgetChatSettings ([PSCustomObject]@{chatTaskOnly=$true;chatBlurDelaySeconds=7;chatIdleDelaySeconds=4;chatAutoCollapse=$false;chatAutoCollapseDelaySeconds=9;chatDotsMotion=$false;chatAttentionBubble=$false})
$saved=Get-WidgetChatSettings;Initialize-WidgetChatBehavior;Read-WidgetChatSettings ($saved|ConvertTo-Json|ConvertFrom-Json)
Assert-ChatBehavior ($script:chatTaskOnly -and $script:chatBlurDelaySeconds-eq 7 -and $script:chatIdleDelaySeconds-eq 4 -and !$script:chatAutoCollapse -and $script:chatAutoCollapseDelaySeconds-eq 9 -and !$script:chatDotsMotion -and !$script:chatAttentionBubble) 'Settings JSON roundtrip failed'
foreach($invalid in @('NaN','Infinity','-Infinity','invalid',-1,61)){
  Initialize-WidgetChatBehavior;Read-WidgetChatSettings ([PSCustomObject]@{chatAutoCollapseDelaySeconds=$invalid;chatBlurDelaySeconds=$invalid;chatIdleDelaySeconds=$invalid;chatTaskOnly='false';chatAutoCollapse='false'})
  Assert-ChatBehavior ($script:chatBlurDelaySeconds-eq 3 -and $script:chatIdleDelaySeconds-eq 2 -and $script:chatAutoCollapseDelaySeconds-eq 3 -and $script:chatTaskOnly -and $script:chatAutoCollapse) 'Invalid settings replaced defaults'
}
# Native positioning is recorded, never applied. WPF HWNDs stay off screen.
Add-Type -TypeDefinition @'
using System;
public static class GptWidgetNative {
 public struct Rect { public int Left,Top,Right,Bottom; }
 public static Rect WidgetFrame,PeekFrame;
 public static int LastX,LastY;
 public static uint NativeDpi=96;
 public static IntPtr LastAfter;
 public static uint LastFlags;
 public static Rect Frame(IntPtr h){return h.ToInt64()==2 ? PeekFrame : WidgetFrame;}
 public static uint GetDpiForWindow(IntPtr h){return NativeDpi;}
 public static bool SetWindowPos(IntPtr h,IntPtr after,int x,int y,int w,int height,uint flags){LastX=x;LastY=y;LastAfter=after;LastFlags=flags;return true;}
 public static IntPtr GetForegroundWindow(){return new IntPtr(11);}
 public static IntPtr GetAncestor(IntPtr h,uint flags){return h;}
}
'@
Initialize-WidgetChatBehavior
$script:window=[Windows.Window]::new();$script:window.Width=350;$script:window.Height=350;$script:window.Left=-20000;$script:window.Top=-20000;$script:window.ShowActivated=$false;$script:window.ShowInTaskbar=$false
$script:ui=@{ChatButton=[Windows.Controls.Button]::new()}
$script:widgetHandle=[IntPtr]1;$script:peekHandle=[IntPtr]2
$script:peekWindow=[Windows.Window]::new();$script:peekWindow.Width=140;$script:peekWindow.Height=140;$script:peekWindow.Left=-20000;$script:peekWindow.Top=-20000;$script:peekWindow.ShowActivated=$false;$script:peekWindow.ShowInTaskbar=$false
Initialize-WidgetChatPanel;$script:chatPanel.Left=-20000;$script:chatPanel.Top=-20000
# This fixture covers layout/state; snapshot and lazy list integration is tested separately.
function Update-WidgetChats {}
$area=[Windows.Forms.Screen]::PrimaryScreen.WorkingArea
$full=[GptWidgetNative+Rect]::new();$full.Left=$area.Left+500;$full.Top=$area.Top+200;$full.Right=$full.Left+200;$full.Bottom=$full.Top+200;[GptWidgetNative]::WidgetFrame=$full
$side=[GptWidgetNative+Rect]::new();$side.Right=$area.Right;$side.Left=$side.Right-140;$side.Top=$area.Top+200;$side.Bottom=$side.Top+140;[GptWidgetNative]::PeekFrame=$side
try{
  $script:window.Show();$script:chatHasTasks=$true;$script:chatTaskKey='live';$script:chatState.key='live';$script:chatState.role='side'
  Set-WidgetChatMode status
  Assert-ChatBehavior ($script:chatPanel.IsVisible -and [Math]::Abs($script:chatPanel.Width-180)-lt 1 -and [Math]::Abs($script:chatPanel.Height-34)-lt 1 -and $script:chatUi.ChatStatus.Visibility-eq 'Visible' -and $script:chatUi.ChatExpanded.Visibility-eq 'Collapsed') 'Task status is not a small visible badge'
  Assert-ChatBehavior ($script:ui.ChatButton.Visibility-eq 'Collapsed') 'Original static label duplicates the badge'
  Assert-ChatBehavior ([GptWidgetNative]::LastX+180-le $full.Left) 'Badge overlaps original character'
  Set-WidgetChatMode compact
  Assert-ChatBehavior ([Math]::Abs($script:chatPanel.Width-72)-lt 1 -and $script:chatUi.ChatCompact.Visibility-eq 'Visible' -and $script:chatUi.ChatStatus.Visibility-eq 'Collapsed') 'Dots did not replace status text'
  Assert-ChatBehavior (![Windows.SystemParameters]::ClientAreaAnimation -or $script:chatUi.ChatDot1.RenderTransform.HasAnimatedProperties) 'Dots did not start native animation'
  $script:chatDotsMotion=$false;Set-WidgetChatDotAnimation
  Assert-ChatBehavior (!$script:chatUi.ChatDot1.RenderTransform.HasAnimatedProperties) 'Motion switch did not stop animation'
  $script:chatDotsMotion=$true;Set-WidgetChatDotAnimation;Set-WidgetChatMode status
  Assert-ChatBehavior (!$script:chatUi.ChatDot1.RenderTransform.HasAnimatedProperties) 'Leaving compact mode did not stop animation'
  $script:window.Hide();$script:peekWindow.Show();Set-WidgetChatMode status
  Assert-ChatBehavior ([GptWidgetNative]::LastX+180-le $side.Left -and $script:chatPanel.Owner-eq $null -and !$script:chatPanel.ShowActivated) 'Side status must be independent and avoid the side character'
  # Only the background compact indicator moves onto the character. A 140px
  # side avatar stays physically fixed while WPF display scaling varies.
  $compactBackground=$script:chatUi.ChatCompact.Background.ToString()
  foreach($nativeDpi in @(96,120,144,192)){
    [GptWidgetNative]::NativeDpi=[uint32]$nativeDpi;$dpiScale=$nativeDpi/96.0
    foreach($edge in @('left','right')){
      $overlayFrame=[GptWidgetNative+Rect]::new()
      $overlayFrame.Left=if($edge-eq 'left'){$area.Left}else{$area.Right-140}
      $overlayFrame.Right=$overlayFrame.Left+140;$overlayFrame.Top=$area.Top+200;$overlayFrame.Bottom=$overlayFrame.Top+140
      [GptWidgetNative]::PeekFrame=$overlayFrame
      Set-WidgetChatMode compact
      $dotWidth=[int]($script:chatPanel.Width*$dpiScale);$dotHeight=[int]($script:chatPanel.Height*$dpiScale)
      $dotX=[GptWidgetNative]::LastX;$dotY=[GptWidgetNative]::LastY
      Assert-ChatBehavior ($dotX-ge $overlayFrame.Left -and $dotX+$dotWidth-le $overlayFrame.Right -and $dotY-ge $overlayFrame.Top -and $dotY+$dotHeight-le $overlayFrame.Bottom) "$edge compact at $nativeDpi DPI escapes the avatar"
      Assert-ChatBehavior ([Math]::Abs(($dotX+$dotWidth/2)-($overlayFrame.Left+70))-le 1) "$edge compact at $nativeDpi DPI is not centered on the avatar"
      Assert-ChatBehavior ($dotY-ge $overlayFrame.Top+140*0.55 -and $dotY+$dotHeight/2-ge $overlayFrame.Top+140*0.70) "$edge compact at $nativeDpi DPI is not over the lower chest"
      Assert-ChatBehavior ($dotWidth-le 128 -and $dotHeight-le 34 -and [Math]::Abs($script:chatPanel.Width/$script:chatPanel.Height-2.4)-lt 0.08) "$edge compact at $nativeDpi DPI did not shrink proportionally inside the chest"
      if($nativeDpi-eq 96){Assert-ChatBehavior ([Math]::Abs($script:chatPanel.Width-72)-lt 1 -and [Math]::Abs($script:chatPanel.Height-30)-lt 1) 'Normal-DPI overlay did not preserve the 72x30 DIP size'}
      Assert-ChatBehavior ([GptWidgetNative]::LastAfter-eq [IntPtr](-1) -and [GptWidgetNative]::LastFlags-eq 0x11 -and !$script:chatPanel.ShowActivated -and $null-eq $script:chatPanel.Owner) 'Chest dots must stay above the actor without activating or inheriting a Codex owner'
      Assert-ChatBehavior ($script:chatUi.ChatCompact.Background.ToString()-eq $compactBackground -and (![Windows.SystemParameters]::ClientAreaAnimation -or $script:chatUi.ChatDot1.RenderTransform.HasAnimatedProperties)) 'Overlay placement changed the compact style or stopped dot motion'
      $dotCanvas=$script:chatUi.ChatDot1.Parent
      Assert-ChatBehavior ($dotCanvas.Parent-is [Windows.Controls.Viewbox] -and $dotCanvas.Parent.Stretch-eq 'Uniform' -and $dotCanvas.Parent.StretchDirection-eq 'DownOnly') 'Compact dots need a Viewbox when physical avatar width caps their DIP width'
      foreach($adjacentMode in @('status','expanded')){
        Set-WidgetChatMode $adjacentMode
        $adjacentWidth=[int]($script:chatPanel.Width*$dpiScale);$adjacentX=[GptWidgetNative]::LastX
        $expectedWidth=if($adjacentMode-eq 'status'){180}else{390}
        Assert-ChatBehavior ([Math]::Abs($script:chatPanel.Width-$expectedWidth)-lt 1) 'The compact cap leaked into status/composer width'
        Assert-ChatBehavior ($adjacentX+$adjacentWidth-le $overlayFrame.Left -or $adjacentX-ge $overlayFrame.Right) "$edge $adjacentMode at $nativeDpi DPI should remain beside the avatar"
        Assert-ChatBehavior ([GptWidgetNative]::LastAfter-eq [IntPtr]::Zero -and [GptWidgetNative]::LastFlags-eq 0x15) 'Adjacent status/composer Z order changed'
      }
    }
  }
  # The high-DPI side cap must not leak into foreground or other panel modes.
  Set-WidgetChatMode compact
  $script:peekWindow.Hide();$script:window.Show();Set-WidgetChatMode compact
  Assert-ChatBehavior ([Math]::Abs($script:chatPanel.Width-72)-lt 1 -and [Math]::Abs($script:chatPanel.Height-30)-lt 1) 'Returning foreground did not restore the original 72x30 DIP compact size'
  Assert-ChatBehavior ([GptWidgetNative]::LastX+[int]($script:chatPanel.Width*2)-le $full.Left) 'Foreground compact placement changed to an avatar overlay'
  Assert-ChatBehavior ([GptWidgetNative]::LastAfter-eq [IntPtr]::Zero -and [GptWidgetNative]::LastFlags-eq 0x15) 'Foreground compact Z order changed'
  Assert-ChatBehavior ($script:chatUi.ChatCompact.Background.ToString()-eq $compactBackground -and $script:chatUi.ChatCompact.Padding-eq [Windows.Thickness]::new(0)) 'Foreground compact styling changed'
  [GptWidgetNative]::NativeDpi=96;[GptWidgetNative]::PeekFrame=$side
  $script:window.Hide();$script:peekWindow.Show();Set-WidgetChatMode status
  $script:chatUi.ChatPrompt.Text='老大未发送的草稿';$script:chatState.manual=$true;Set-WidgetChatMode expanded;Hide-WidgetChatPanel
  Assert-ChatBehavior ($script:chatPanel.IsVisible -and $script:chatState.mode-eq 'compact' -and $script:chatUi.ChatPrompt.Text-eq '老大未发送的草稿') 'Closing active composer hid status or lost draft'
  Assert-Mode compact 1000 22 $false $false $false $false peek
  $script:chatTaskKey='live:approval';Assert-Mode status 2000 22 $false $false $false $false peek
  $script:chatClicks=0;function Open-WidgetChatPanel {$script:chatClicks++}
  foreach($name in @('ChatStatus','ChatCompact')){$script:chatUi[$name].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))}
  Assert-ChatBehavior ($script:chatClicks-eq 2) 'Status and dots must open chat on click'
  $script:chatHasTasks=$false;Hide-WidgetChatPanel
  Assert-ChatBehavior (!$script:chatPanel.IsVisible -and !$script:chatUi.ChatDot1.RenderTransform.HasAnimatedProperties) 'Last-task hide did not hide/stop indicator'
  $script:chatTaskOnly=$false;Update-WidgetChatButtonVisibility
  Assert-ChatBehavior ($script:ui.ChatButton.Visibility-eq 'Visible') 'Manual mode lost original chat entry'
  if($PreviewDirectory){
    $null=New-Item -ItemType Directory -Path $PreviewDirectory -Force
    $script:chatDotsMotion=$false;$content=$script:chatPanel.Content
    foreach($preview in @(@{Width=180;Height=34;Status=$true;Name='GPT-niang-v4-状态文字.png'},@{Width=72;Height=30;Status=$false;Name='GPT-niang-三点收起.png'})){
      Set-WidgetChatMode $(if($preview.Status){'status'}else{'compact'})
      $script:chatUi.ChatExpanded.Visibility='Collapsed';$script:chatUi.ChatStatus.Visibility=if($preview.Status){'Visible'}else{'Collapsed'};$script:chatUi.ChatCompact.Visibility=if($preview.Status){'Collapsed'}else{'Visible'}
      $content.Measure([Windows.Size]::new($preview.Width,$preview.Height));$content.Arrange([Windows.Rect]::new(0,0,$preview.Width,$preview.Height));$content.UpdateLayout()
      $render=[Windows.Media.Imaging.RenderTargetBitmap]::new($preview.Width,$preview.Height,96,96,[Windows.Media.PixelFormats]::Pbgra32);$render.Render($content)
      $encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($render));$stream=[IO.File]::Create((Join-Path $PreviewDirectory $preview.Name));try{$encoder.Save($stream)}finally{$stream.Dispose()}
    }
  }
}finally{$script:runtimeClosed=$true;$script:chatPanel.Close();$script:window.Close();$script:peekWindow.Close()}
Write-Output 'PASS: status-to-dots lifecycle, side overlay at 96/120/144/192 DPI on both edges, unchanged foreground/status/composer placement, manual draft, switches and native animation'
