function Initialize-WidgetRoleBehavior {
  $script:rolePeekEnabled=$true;$script:rolePeekDelaySeconds=3.0;$script:rolePeekSide='right';$script:roleTransitionEnabled=$true
  $script:roleState=@{mode='hidden';blurAt=$null}
  $script:peekRenderedMode='hidden';$script:fullRoleBounds=$null;$script:peekTransition=$null
  $script:fullRoleAnchor=$null;$script:rolePeekPosition=$null;$script:peekDrag=$null
}
function Read-WidgetRoleSettings($Settings) {
  if($Settings.rolePeekEnabled-is [bool]){$script:rolePeekEnabled=$Settings.rolePeekEnabled}
  if($Settings.roleTransitionEnabled-is [bool]){$script:roleTransitionEnabled=$Settings.roleTransitionEnabled}
  if($null-ne $Settings.rolePeekDelaySeconds){try{$seconds=[double]$Settings.rolePeekDelaySeconds;if(![double]::IsNaN($seconds) -and $seconds-ge 0 -and $seconds-le 60){$script:rolePeekDelaySeconds=$seconds}}catch{}}
  if($Settings.rolePeekSide-in @('left','right')){$script:rolePeekSide=[string]$Settings.rolePeekSide}
  if($Settings.rolePeekPosition){
    try{
      $position=@{}
      foreach($name in @('X','Y','OriginX','OriginY','OriginWidth','OriginHeight')){
        $value=$Settings.rolePeekPosition.$name
        if($null-eq $value -and $name-like 'Origin*'){$position[$name]=$null;continue}
        if($null-eq $value){throw 'Missing position'}
        $number=[double]$value;if([double]::IsNaN($number) -or [double]::IsInfinity($number)){throw 'Invalid position'}
        $position[$name]=$number
      }
      if($null-ne $position.OriginWidth -and ($position.OriginWidth-le 0 -or $position.OriginHeight-le 0)){throw 'Invalid origin'}
      $script:rolePeekPosition=$position
    }catch{}
  }
}
function Get-WidgetRoleSettings {
  return @{rolePeekEnabled=$script:rolePeekEnabled;rolePeekDelaySeconds=$script:rolePeekDelaySeconds;rolePeekSide=$script:rolePeekSide;roleTransitionEnabled=$script:roleTransitionEnabled;rolePeekPosition=$script:rolePeekPosition}
}
function Resolve-WidgetRoleMode([long]$Now,[bool]$HostFocused,[bool]$OwnFocused,[bool]$HostExists,[bool]$Interacting=$false) {
  if(!$script:rolePeekEnabled){$script:roleState.mode='legacy';$script:roleState.blurAt=$null;return 'legacy'}
  if(!$HostExists){$script:roleState.mode='hidden';$script:roleState.blurAt=$null;return 'hidden'}
  if($HostFocused){$script:roleState.mode='full';$script:roleState.blurAt=$null;return 'full'}
  if($OwnFocused -or $Interacting){return $script:roleState.mode}
  if($null-eq $script:roleState.blurAt){$script:roleState.blurAt=$Now}
  $script:roleState.mode=if($Now-$script:roleState.blurAt-ge $script:rolePeekDelaySeconds*1000){'peek'}else{'waiting'}
  return $script:roleState.mode
}
function Initialize-WidgetPeekWindow {
  $script:peekWindow=[Windows.Markup.XamlReader]::Parse(@'
<Window xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" Title="GPT 娘 · 侧边陪伴" Width="140" Height="140" WindowStyle="None" ResizeMode="NoResize" AllowsTransparency="True" Background="Transparent" ShowActivated="False" ShowInTaskbar="False" Topmost="True">
 <Grid x:Name="PeekStage" Background="Transparent" Cursor="Hand" ToolTip="老大，我在这里陪你 · 点击聊天，右键设置">
  <Image x:Name="OriginalGirl" Stretch="Uniform" Opacity="0" RenderTransformOrigin="0.5,0.5" IsHitTestVisible="False"/>
  <Image x:Name="PeekGirl" Stretch="Uniform" RenderTransformOrigin="0.5,0.5" IsHitTestVisible="False"/>
 </Grid>
</Window>
'@)
  $script:peekImage=$script:peekWindow.FindName('PeekGirl')
  $script:peekOriginalImage=$script:peekWindow.FindName('OriginalGirl');$script:peekStage=$script:peekWindow.FindName('PeekStage')
  if($script:ui.Girl){$script:peekOriginalImage.Source=$script:ui.Girl.Source}
  $image=[Windows.Media.Imaging.BitmapImage]::new();$image.BeginInit();$image.CacheOption='OnLoad';$image.UriSource=[Uri](Join-Path $script:appDir 'assets\gpt-niang-side-peek-b2.png');$image.EndInit();$image.Freeze()
  $script:peekImage.Source=$image
  $converted=[Windows.Media.Imaging.FormatConvertedBitmap]::new($image,[Windows.Media.PixelFormats]::Bgra32,$null,0)
  $script:peekStride=$image.PixelWidth*4;$script:peekPixels=New-Object byte[] ($script:peekStride*$image.PixelHeight);$converted.CopyPixels($script:peekPixels,$script:peekStride,0)
  $script:peekHandle=[Windows.Interop.WindowInteropHelper]::new($script:peekWindow).EnsureHandle()
  $extended=[GptWidgetNative]::GetWindowLongPtr($script:peekHandle,-20).ToInt64()
  [GptWidgetNative]::SetWindowLongPtr($script:peekHandle,-20,[IntPtr]($extended-bor 0x08000000-bor 0x80))|Out-Null
  $script:peekMessageHook=[Windows.Interop.HwndSourceHook]{param($hwnd,$msg,$w,$l,[ref]$handled)
    if($msg-eq 0x21){$handled.Value=$true;return [IntPtr]3}
    if($msg-eq 0x84 -and !$script:peekDrag){
      $packed=$l.ToInt64();$x=[int]($packed-band 65535);$y=[int](($packed-shr 16)-band 65535)
      if($x-ge 32768){$x-=65536};if($y-ge 32768){$y-=65536}
      $hit=$false
      if($script:peekImage.Opacity-gt 0.05){$hit=Test-WidgetPeekHit ($script:peekImage.PointFromScreen([Windows.Point]::new($x,$y)))}
      if(!$hit -and $script:peekOriginalImage.Opacity-gt 0.05){$hit=Test-WidgetImageHit ($script:peekOriginalImage.PointFromScreen([Windows.Point]::new($x,$y))) $script:peekOriginalImage $script:alphaPixels $script:alphaStride}
      if(!$hit){$handled.Value=$true;return [IntPtr](-1)}
    }
    return [IntPtr]::Zero
  }
  [Windows.Interop.HwndSource]::FromHwnd($script:peekHandle).AddHook($script:peekMessageHook)
  $script:peekStage.Add_MouseLeftButtonDown({param($sender,$event)
    $cursor=[GptWidgetNative+Point]::new();[GptWidgetNative]::GetCursorPos([ref]$cursor)|Out-Null
    Start-WidgetPeekDrag $cursor.X $cursor.Y $sender;$event.Handled=$true
  })
  $script:peekStage.Add_MouseMove({param($sender,$event)
    if(!$script:peekDrag){return}
    $cursor=[GptWidgetNative+Point]::new();[GptWidgetNative]::GetCursorPos([ref]$cursor)|Out-Null
    Move-WidgetPeekDrag $cursor.X $cursor.Y;$event.Handled=$true
  })
  $script:peekStage.Add_MouseLeftButtonUp({param($sender,$event)Complete-WidgetPeekDrag;$event.Handled=$true})
  $script:peekStage.Add_LostMouseCapture({if($script:peekDrag){Complete-WidgetPeekDrag $false}})
  $script:peekStage.Add_MouseRightButtonUp({param($sender,$event)Open-WidgetMenu;$event.Handled=$true})
  $script:peekWindow.Add_Closing({param($sender,$event)if(!$script:runtimeClosed){$event.Cancel=$true;$sender.Hide()}})
}
function Test-WidgetPeekHit([Windows.Point]$Point) {
  return Test-WidgetImageHit $Point $script:peekImage $script:peekPixels $script:peekStride
}
function Test-WidgetImageHit([Windows.Point]$Point,$Control,[byte[]]$Pixels,[int]$Stride) {
  $image=$Control.Source;$width=$Control.ActualWidth;$height=$Control.ActualHeight
  if(!$image -or !$Pixels){return $false}
  if($width-le 0 -or $height-le 0 -or $Point.X-lt 0 -or $Point.Y-lt 0 -or $Point.X-ge $width -or $Point.Y-ge $height){return $false}
  $x=[int][Math]::Floor($Point.X/$width*$image.PixelWidth);$y=[int][Math]::Floor($Point.Y/$height*$image.PixelHeight)
  return $Pixels[$y*$Stride+$x*4+3]-ge 16
}
function Save-WidgetFullRoleBounds {
  if(!$script:window.IsVisible -or !$script:ui.Girl.IsVisible){return}
  $girl=$script:ui.Girl
  $points=@($girl.PointToScreen([Windows.Point]::new(0,0)),$girl.PointToScreen([Windows.Point]::new($girl.ActualWidth,0)),$girl.PointToScreen([Windows.Point]::new(0,$girl.ActualHeight)),$girl.PointToScreen([Windows.Point]::new($girl.ActualWidth,$girl.ActualHeight)))
  $left=($points.X|Measure-Object -Minimum).Minimum;$top=($points.Y|Measure-Object -Minimum).Minimum
  $width=($points.X|Measure-Object -Maximum).Maximum-$left;$height=($points.Y|Measure-Object -Maximum).Maximum-$top
  if($width-ge 1 -and $height-ge 1){$script:fullRoleBounds=@{X=$left;Y=$top;Width=$width;Height=$height;Facing=$script:ui.FacingScale.ScaleX}}
  $nativeFrame=[GptWidgetNative]::Frame($script:widgetHandle)
  $script:fullRoleAnchor=@{X=$nativeFrame.Left;Y=$nativeFrame.Top;Width=$nativeFrame.Right-$nativeFrame.Left;Height=$nativeFrame.Bottom-$nativeFrame.Top}
}
function Get-WidgetRoleArea([double]$X,[double]$Y) {
  return [Windows.Forms.Screen]::FromPoint([Drawing.Point]::new([int]$X,[int]$Y)).WorkingArea
}
function Get-WidgetPeekPlacement($Area,$Bounds,$Position,[string]$Side='right') {
  $centerX=if($Bounds){$Bounds.X+$Bounds.Width/2}else{($Area.Left+$Area.Right)/2}
  $centerY=if($Bounds){$Bounds.Y+$Bounds.Height/2}else{($Area.Top+$Area.Bottom)/2}
  if($Position){$x=$Position.X;$y=$Position.Y;$centerX=$x+70}
  else{
    if($Bounds){$Side=if($centerX-lt ($Area.Left+$Area.Right)/2){'left'}else{'right'}}
    $x=if($Side-eq 'left'){$Area.Left}else{$Area.Right-140};$y=$centerY-70
  }
  if($Position){$Side=if($centerX-lt ($Area.Left+$Area.Right)/2){'left'}else{'right'}}
  return @{X=[Math]::Max($Area.Left,[Math]::Min($Area.Right-140,$x));Y=[Math]::Max($Area.Top,[Math]::Min($Area.Bottom-140,$y));Width=140;Height=140;Side=$Side}
}
function Test-WidgetPeekOrigin($Position,$Origin) {
  if(!$Position -or !$Origin -or $null-eq $Position.OriginWidth){return $true}
  foreach($name in @('X','Y','Width','Height')){if([Math]::Abs($Position[('Origin'+$name)]-$Origin[$name])-gt 2){return $false}}
  return $true
}
function Get-WidgetRoleOrigin {
  if($script:fullRoleAnchor){return $script:fullRoleAnchor};return $script:fullRoleBounds
}
function Get-WidgetPeekTarget {
  $origin=Get-WidgetRoleOrigin
  if($script:rolePeekPosition -and !(Test-WidgetPeekOrigin $script:rolePeekPosition $origin)){$script:rolePeekPosition=$null;Save-Settings}
  if($script:rolePeekPosition -and $origin -and $null-eq $script:rolePeekPosition.OriginWidth){
    foreach($name in @('X','Y','Width','Height')){$script:rolePeekPosition[('Origin'+$name)]=$origin[$name]};Save-Settings
  }
  if($script:rolePeekPosition){$x=$script:rolePeekPosition.X+70;$y=$script:rolePeekPosition.Y+70}
  elseif($script:fullRoleBounds){$x=$script:fullRoleBounds.X+$script:fullRoleBounds.Width/2;$y=$script:fullRoleBounds.Y+$script:fullRoleBounds.Height/2}
  else{$area=[Windows.Forms.Screen]::FromHandle($script:hostHandle).WorkingArea;$x=($area.Left+$area.Right)/2;$y=($area.Top+$area.Bottom)/2}
  $area=Get-WidgetRoleArea $x $y
  $target=Get-WidgetPeekPlacement $area $script:fullRoleBounds $script:rolePeekPosition $script:rolePeekSide
  $script:rolePeekSide=$target.Side;return $target
}
function Get-WidgetPeekFrame {
  $rect=[GptWidgetNative]::Frame($script:peekHandle)
  return @{X=$rect.Left;Y=$rect.Top;Width=$rect.Right-$rect.Left;Height=$rect.Bottom-$rect.Top}
}
function Set-WidgetPeekPosition($Frame) {
  $origin=Get-WidgetRoleOrigin
  $script:rolePeekPosition=@{X=$Frame.X+($Frame.Width-140)/2;Y=$Frame.Y+($Frame.Height-140)/2;OriginX=$origin.X;OriginY=$origin.Y;OriginWidth=$origin.Width;OriginHeight=$origin.Height}
  $target=Get-WidgetPeekTarget
  $script:rolePeekPosition.X=$target.X;$script:rolePeekPosition.Y=$target.Y
}
function Set-WidgetPeekSide([string]$Side) {
  Stop-WidgetPeekTransition
  $script:rolePeekSide=$Side
  if($script:peekWindow -and $script:peekWindow.IsVisible){$bounds=Get-WidgetPeekFrame}else{$bounds=$script:fullRoleBounds}
  if($bounds){
    $area=Get-WidgetRoleArea ($bounds.X+$bounds.Width/2) ($bounds.Y+$bounds.Height/2)
    $x=if($Side-eq 'left'){$area.Left}else{$area.Right-140}
    Set-WidgetPeekPosition @{X=$x;Y=$bounds.Y+($bounds.Height-140)/2;Width=140;Height=140}
  }else{$script:rolePeekPosition=$null}
  Save-Settings;Update-WidgetSettingsMenu;Tick-Widget
}
function Start-WidgetPeekDrag([double]$X,[double]$Y,$Control) {
  $script:peekDrag=@{X=$X;Y=$Y;Frame=(Get-WidgetPeekFrame);Moved=$false;Control=$Control;Rendered=$script:peekRenderedMode}
  Stop-WidgetPeekTransition
  if($Control){$Control.CaptureMouse()|Out-Null}
}
function Get-WidgetPeekDragFrame($Area,$Frame,[double]$Dx,[double]$Dy) {
  return @{X=[Math]::Max($Area.Left,[Math]::Min($Area.Right-$Frame.Width,$Frame.X+$Dx));Y=[Math]::Max($Area.Top,[Math]::Min($Area.Bottom-$Frame.Height,$Frame.Y+$Dy));Width=$Frame.Width;Height=$Frame.Height}
}
function Move-WidgetPeekDrag([double]$X,[double]$Y) {
  if(!$script:peekDrag){return}
  $dx=$X-$script:peekDrag.X;$dy=$Y-$script:peekDrag.Y
  if(!$script:peekDrag.Moved -and $dx*$dx+$dy*$dy-lt 9){return}
  $script:peekDrag.Moved=$true
  Set-WidgetRoleFrame (Get-WidgetPeekDragFrame (Get-WidgetRoleArea $X $Y) $script:peekDrag.Frame $dx $dy)
  Position-WidgetChatPanel
}
function Complete-WidgetPeekDrag([bool]$OpenChat=$true) {
  if(!$script:peekDrag){return}
  $drag=$script:peekDrag;$script:peekDrag=$null
  if($drag.Moved){Set-WidgetPeekPosition (Get-WidgetPeekFrame);Save-Settings}
  if($drag.Control){$drag.Control.ReleaseMouseCapture()}
  if($drag.Moved -and $script:roleState.mode-eq 'peek'){Set-WidgetPeekMode 'peek'}
  if(!$drag.Moved -and $OpenChat){Open-WidgetChatPanel}
}
function Set-WidgetRoleFrame($Frame) {
  $dpi=[GptWidgetNative]::GetDpiForWindow($script:peekHandle)/96.0;if($dpi-le 0){$dpi=1}
  $script:peekWindow.Width=$Frame.Width/$dpi;$script:peekWindow.Height=$Frame.Height/$dpi
  Set-WidgetDesktopLayer $script:peekHandle $true
  [GptWidgetNative]::SetWindowPos($script:peekHandle,[IntPtr]::Zero,[int]$Frame.X,[int]$Frame.Y,[int]$Frame.Width,[int]$Frame.Height,0x14)|Out-Null
  $script:peekWindow.UpdateLayout()
  if(!$script:peekWindow.IsVisible){$script:peekWindow.Show()}
}
function Stop-WidgetPeekTransition {
  if($script:peekTransitionTimer){$script:peekTransitionTimer.Stop()}
  $script:peekTransition=$null
}
function Tick-WidgetPeekTransition {
  if(!$script:peekTransition){return}
  $state=$script:peekTransition;$elapsed=([DateTime]::UtcNow-$state.Started).TotalMilliseconds
  $fraction=[Math]::Min(1.0,[Math]::Max(0.0,$elapsed/300.0));$ease=1-[Math]::Pow(1-$fraction,3)
  $frame=@{};foreach($name in @('X','Y','Width','Height')){$frame[$name]=$state.From[$name]+($state.To[$name]-$state.From[$name])*$ease}
  Set-WidgetRoleFrame $frame
  $script:peekOriginalImage.Opacity=$state.OriginalFrom*(1-$ease);$script:peekImage.Opacity=$state.PeekFrom+(1-$state.PeekFrom)*$ease
  Position-WidgetChatPanel
  if($fraction-ge 1){Stop-WidgetPeekTransition;$script:peekRenderedMode='peek'}
}
function Set-WidgetPeekMode([string]$Mode) {
  if($Mode-notin @('waiting','peek')){
    if($script:peekDrag){Complete-WidgetPeekDrag $false}
    Stop-WidgetPeekTransition
    if($script:peekWindow -and $script:peekWindow.IsVisible){$script:peekWindow.Hide()}
    $script:peekRenderedMode='hidden';return
  }
  if(!$script:peekWindow){Initialize-WidgetPeekWindow}
  if($script:peekDrag){return}
  $target=Get-WidgetPeekTarget
  $script:peekImage.RenderTransform=[Windows.Media.ScaleTransform]::new($(if($script:rolePeekSide-eq 'left'){-1}else{1}),1)
  if($Mode-eq 'waiting'){
    if($script:peekRenderedMode-ne 'waiting'){
      Stop-WidgetPeekTransition
      $hasOriginal=$script:fullRoleBounds -and $script:peekOriginalImage.Source
      $script:peekOriginalImage.Opacity=$(if($hasOriginal){1}else{0});$script:peekImage.Opacity=$(if($hasOriginal){0}else{1})
      if($hasOriginal){$script:peekOriginalImage.RenderTransform=[Windows.Media.ScaleTransform]::new($script:fullRoleBounds.Facing,1);Set-WidgetRoleFrame $script:fullRoleBounds}else{Set-WidgetRoleFrame $target}
      $script:peekRenderedMode='waiting'
    }
    return
  }
  if($script:peekTransition){return}
  if($script:peekRenderedMode-in @('waiting','transition') -and $script:peekOriginalImage.Opacity-gt 0 -and $script:roleTransitionEnabled -and [Windows.SystemParameters]::ClientAreaAnimation){
    $script:peekTransition=@{From=(Get-WidgetPeekFrame);To=$target;Started=[DateTime]::UtcNow;OriginalFrom=$script:peekOriginalImage.Opacity;PeekFrom=$script:peekImage.Opacity};$script:peekRenderedMode='transition'
    if(!$script:peekTransitionTimer){$script:peekTransitionTimer=[Windows.Threading.DispatcherTimer]::new();$script:peekTransitionTimer.Interval=[TimeSpan]::FromMilliseconds(20);$script:peekTransitionTimer.Add_Tick({Tick-WidgetPeekTransition})}
    $script:peekTransitionTimer.Start();Tick-WidgetPeekTransition;return
  }
  Set-WidgetRoleFrame $target;$script:peekOriginalImage.Opacity=0;$script:peekImage.Opacity=1;$script:peekRenderedMode='peek'
  if($script:context -and $script:context.IsOpen){Set-WidgetMenuBounds;Position-WidgetMenuToHost}
}
function Get-WidgetMenuAnchor {
  if($script:peekWindow -and $script:peekWindow.IsVisible -and !$script:window.IsVisible){
    $dpi=[GptWidgetNative]::GetDpiForWindow($script:peekHandle)/96.0;if($dpi-le 0){$dpi=1}
    return @{Target=$script:peekStage;Frame=[Windows.Forms.Screen]::FromHandle($script:peekHandle).WorkingArea;Dpi=$dpi;Side=$script:rolePeekSide}
  }
  return @{Target=$script:ui.MenuButton;Frame=(Get-WidgetPlacementFrame);Dpi=(Get-WidgetPlacementDpi);Side=$script:side}
}
Initialize-WidgetRoleBehavior
