function Get-WidgetNewChatUri([string]$Prompt) {
  $text=$Prompt.Trim()
  if($text.Length-gt 2000){throw '请将内容控制在 2000 字以内'}
  if(!$text){return 'codex://threads/new'}
  return 'codex://new?prompt='+[Uri]::EscapeDataString($text)
}
function Get-WidgetThreadUri([string]$Id) {
  if($Id-notmatch '^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$'){throw '聊天标识无效'}
  return 'codex://threads/'+$Id
}
function Initialize-WidgetChatPanel {
  $script:chatPanel=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $script:appDir 'chat-panel.xaml'),[Text.Encoding]::UTF8))
  $script:chatUi=@{}
  foreach($name in @('ChatExpanded','ChatStatus','ChatStatusText','ChatCompact','ChatDot1','ChatDot2','ChatDot3','ChatGreeting','CloseChatPanel','ChatPrompt','ContinueChat','ChatFeedback','ChatSummary','ChatScroll','ChatList','ChatFooter')){$script:chatUi[$name]=$script:chatPanel.FindName($name)}
  $script:chatPanel.Add_Closing({param($sender,$event)if(!$script:runtimeClosed){$event.Cancel=$true;Hide-WidgetChatPanel}})
  $script:chatUi.CloseChatPanel.Add_Click({Hide-WidgetChatPanel})
  $script:chatUi.ChatCompact.Add_Click({Open-WidgetChatPanel})
  $script:chatUi.ChatStatus.Add_Click({Open-WidgetChatPanel})
  $script:chatUi.ContinueChat.Add_Click({Open-WidgetQuickChat})
  $script:chatUi.ChatPrompt.Add_PreviewKeyDown({param($sender,$event)
    if($event.Key-eq [Windows.Input.Key]::Return -and !([Windows.Input.Keyboard]::Modifiers-band [Windows.Input.ModifierKeys]::Shift)){
      Open-WidgetQuickChat;$event.Handled=$true
    }
  })
  $script:chatPanel.Add_KeyDown({param($sender,$event)if($event.Key-eq [Windows.Input.Key]::Escape){Hide-WidgetChatPanel;$event.Handled=$true}})
}
function Open-WidgetQuickChat {
  try{
    $uri=Get-WidgetNewChatUri ([string]$script:chatUi.ChatPrompt.Text)
    Start-Process -FilePath $uri -ErrorAction Stop
    $script:chatUi.ChatPrompt.Clear();$script:chatUi.ChatFeedback.Text='';Hide-WidgetChatPanel
  }catch{$script:chatUi.ChatFeedback.Text='无法打开 Codex：'+$_.Exception.Message}
}
function Open-WidgetThread([string]$Id) {
  try{Start-Process -FilePath (Get-WidgetThreadUri $Id) -ErrorAction Stop;Hide-WidgetChatPanel}
  catch{$script:chatUi.ChatFeedback.Text='无法打开聊天：'+$_.Exception.Message}
}
function Position-WidgetChatPanel {
  if(!$script:chatPanel -or !$script:chatPanel.IsVisible){return}
  $small=$script:chatState.mode-in @('status','compact')
  $frame=[GptWidgetNative]::Frame($script:widgetHandle)
  $peekAnchor=$script:peekWindow -and $script:peekWindow.IsVisible -and !$script:window.IsVisible
  if($peekAnchor){$frame=[GptWidgetNative]::Frame($script:peekHandle)}
  elseif($small -and $script:window.IsVisible -and $script:fullRoleBounds -and $script:fullRoleBounds.Width-gt 0){
    $bounds=$script:fullRoleBounds;$frame=@{Left=$bounds.X;Top=$bounds.Y;Right=$bounds.X+$bounds.Width;Bottom=$bounds.Y+$bounds.Height}
  }
  elseif($small -and $script:window.IsVisible -and $script:ui.Girl -and $script:ui.Girl.ActualWidth-gt 0){
    # The full window includes transparent space for the quota bubble. Anchor
    # the small badge beside the visible character instead of that empty area.
    $girl=$script:ui.Girl
    $corners=@($girl.PointToScreen([Windows.Point]::new(0,0)),$girl.PointToScreen([Windows.Point]::new($girl.ActualWidth,$girl.ActualHeight)))
    $frame=@{Left=($corners.X|Measure-Object -Minimum).Minimum;Right=($corners.X|Measure-Object -Maximum).Maximum;Top=($corners.Y|Measure-Object -Minimum).Minimum;Bottom=($corners.Y|Measure-Object -Maximum).Maximum}
  }
  $area=[Windows.Forms.Screen]::FromPoint([Drawing.Point]::new($frame.Left,$frame.Top)).WorkingArea
  $handle=[Windows.Interop.WindowInteropHelper]::new($script:chatPanel).EnsureHandle()
  $dpi=[GptWidgetNative]::GetDpiForWindow($handle)/96.0;if($dpi-le 0){$dpi=1}
  $chestDots=$peekAnchor -and $script:chatState.mode-eq 'compact'
  if($script:chatState.mode-eq 'compact'){
    $dotScale=1.0
    if($chestDots){$dotScale=[Math]::Min(1.0,[Math]::Min(($frame.Right-$frame.Left-12)/(72*$dpi),($frame.Bottom-$frame.Top)*0.24/(30*$dpi)))}
    $script:chatPanel.Width=72*$dotScale
  }
  $script:chatPanel.Height=if($script:chatState.mode-eq 'compact'){30}elseif($script:chatState.mode-eq 'status'){34}else{[Math]::Min(550,($area.Height-24)/$dpi)}
  if($chestDots){$script:chatPanel.Height=30*$dotScale}
  $width=[int]($script:chatPanel.Width*$dpi);$height=[int]($script:chatPanel.Height*$dpi)
  $x=$frame.Left-$width-10
  if($x-lt $area.Left){$x=$frame.Right+10}
  $x=[int][Math]::Max($area.Left,[Math]::Min($area.Right-$width,$x))
  $desiredY=if($small){$frame.Top+($frame.Bottom-$frame.Top)*0.30-$height/2}else{$frame.Bottom-$height}
  $y=[int][Math]::Max($area.Top,[Math]::Min($area.Bottom-$height,$desiredY))
  if($chestDots){
    $x=[int][Math]::Round(($frame.Left+$frame.Right-$width)/2)
    $y=[int]($frame.Bottom-$height-4)
  }
  if($small -and !$script:window.IsVisible -and !$peekAnchor){$x=$area.Right-$width-12;$y=$area.Bottom-$height-12}
  $after=if($chestDots){[IntPtr](-1)}else{[IntPtr]::Zero}
  $flags=if($chestDots){0x11}else{0x15}
  [GptWidgetNative]::SetWindowPos($handle,$after,$x,$y,0,0,$flags)|Out-Null
}
function Open-WidgetChatPanel {
  if($script:chatPanel -and $script:chatPanel.IsVisible -and $script:chatState.mode-eq 'expanded'){Hide-WidgetChatPanel;return}
  $script:context.IsOpen=$false
  $script:chatState.manual=$true;$script:chatState.dismissed=$null;$script:chatState.blurAt=$null
  $script:chatState.focus=([GptWidgetNative]::GetAncestor([GptWidgetNative]::GetForegroundWindow(),2)).ToInt64()
  Update-WidgetChats
  Set-WidgetChatMode 'expanded'
  $script:chatPanel.Activate()|Out-Null;$script:chatUi.ChatPrompt.Focus()|Out-Null
}
function Update-WidgetChats {
  $file=Join-Path $script:dataDir 'chat-activity.json'
  try{
    $stamp=[IO.File]::GetLastWriteTimeUtc($file).Ticks
    if($stamp-ne $script:chatStamp){$script:chatSnapshot=Get-Content -LiteralPath $file -Raw -Encoding UTF8|ConvertFrom-Json;$script:chatStamp=$stamp}
  }catch{$script:chatSnapshot=$null;$script:chatStamp=0}
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $fresh=$script:chatSnapshot -and $script:chatSnapshot.ok -and $now-[long]$script:chatSnapshot.at-ge 0 -and $now-[long]$script:chatSnapshot.at-lt 15000
  $threads=@($script:chatSnapshot.threads|Where-Object{$null-ne $_})
  $running=@($threads|Where-Object{$_.state-eq 'running'}).Count
  $waiting=@($threads|Where-Object{$_.state-eq 'waiting'}).Count
  $failed=@($threads|Where-Object{$_.state-eq 'failed'}).Count
  $approval=@($threads|Where-Object{$_.state-eq 'waiting' -and $_.waitingKind-eq 'approval'}).Count
  $question=$waiting-$approval
  if($fresh){
    $active=@($threads|Where-Object{$_.state-in @('running','waiting','failed')})
    $script:chatHasTasks=$active.Count-gt 0
    $script:chatTaskKey=($active|Sort-Object id|ForEach-Object{$_.id+':'+$_.startedAt+':'+$_.state+':'+$_.waitingKind+':'+$_.attentionId})-join ';'
    $latest=$threads|Sort-Object lastAt -Descending|Select-Object -First 1
    $script:chatPrimary=if($approval){'approval'}elseif($question){'question'}elseif($failed){'failed'}elseif($running){'running'}elseif($latest.state-in @('completed','interrupted') -and $now-[long]$latest.lastAt-lt 60000){[string]$latest.state}else{'idle'}
  }
  $greetings=@{approval='老大，等你授权';question='老大，有个问题问你';failed='老大，这里卡住了';running='老大，我正在忙';completed='老大，忙完啦';interrupted='老大，任务已中断';idle='老大，随时喊我'}
  $greeting=if(!$fresh){'老大，状态待确认'}else{$greetings[$script:chatPrimary]}
  $summary=if(!$fresh){'状态待确认'}elseif($waiting){"$waiting 待输入"}elseif($failed){"$failed 异常"}elseif($running){"$running 运行中"}else{'最近聊天'}
  $color=if(!$fresh){'#9786A5'}elseif($waiting){'#AE7C29'}elseif($failed){'#B8544A'}elseif($running){'#6D9277'}else{'#79659A'}
  if($script:ui.ChatButton){
    $script:ui.ChatButton.Content=$greeting
    Update-WidgetChatButtonVisibility
    $script:ui.ChatButton.ToolTip=if($fresh){"$($threads.Count) 个本机聊天 · $running 运行中 · $approval 待授权 · $question 待回答`n点击输入新聊天或查看进度"}else{'点击打开聊天面板；当前运行状态尚未确认'}
    $script:ui.ChatButton.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString($color)
  }
  if($script:peekImage){$script:peekImage.ToolTip=$greeting+' · 点击聊天，右键设置'}
  if($script:peekStage){$script:peekStage.ToolTip=$greeting+' · 点击聊天，右键设置'}
  $attentionKey=if($fresh -and $script:chatPrimary-in @('approval','question','failed')){$script:chatTaskKey}else{''}
  if($attentionKey -and $attentionKey-ne $script:chatLastNoticeKey -and $script:chatAttentionBubble -and $script:window.IsVisible){Show-WidgetChatNotice $greeting}
  $script:chatLastNoticeKey=$attentionKey
  if(!$script:chatPanel){return}
  $script:chatUi.ChatGreeting.Text=$greeting
  $script:chatUi.ChatStatusText.Text=$greeting
  $script:chatUi.ChatStatusText.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString($color)
  $script:chatUi.ChatStatus.ToolTip=$greeting+' · 点击输入聊天或查看进度'
  $script:chatUi.ChatCompact.ToolTip=$greeting+' · 点击展开'
  $dotColor=if($approval -or $question){'#AE7C29'}elseif($failed){'#B8544A'}else{'#9B86C1'}
  foreach($name in @('ChatDot1','ChatDot2','ChatDot3')){$script:chatUi[$name].Fill=[Windows.Media.BrushConverter]::new().ConvertFromString($dotColor)}
  $script:chatUi.ChatSummary.Text=if(!$fresh){'状态待确认'}elseif($waiting){"$approval 待授权 · $question 待回答"}else{"$running 运行中"}
  $script:chatUi.ChatFooter.Text=if($fresh){'每 3 秒更新 · '+[DateTimeOffset]::FromUnixTimeMilliseconds([long]$script:chatSnapshot.at).ToLocalTime().ToString('HH:mm:ss')+' 更新'}elseif($script:chatSnapshot.error){$script:chatSnapshot.error}else{'等待更新；可直接打开聊天确认进度'}
  if($script:chatState.mode-ne 'expanded'){return}
  $signature=([string]$fresh)+(($threads|ForEach-Object{$_.id+'|'+$_.title+'|'+$_.state+'|'+$_.waitingKind+'|'+[Math]::Floor([double]$_.lastAt/60000)})-join ';')
  if($signature-eq $script:chatSignature){return};$script:chatSignature=$signature
  $scroll=$script:chatUi.ChatScroll.VerticalOffset;$script:chatUi.ChatList.Children.Clear()
  if(!$threads.Count){
    $empty=[Windows.Controls.TextBlock]::new();$empty.Text='这里会显示你的本机 Codex 聊天';$empty.TextWrapping='Wrap';$empty.Foreground=[Windows.Media.Brushes]::Gray;$empty.Margin=[Windows.Thickness]::new(0,18,0,0)
    $script:chatUi.ChatList.Children.Add($empty)|Out-Null;return
  }
  $labels=@{running='运行中';waiting='等待输入';completed='已完成';interrupted='已中断';failed='异常';uncertain='运行待确认';unknown='状态未知'}
  $colors=@{running='#6D9277';waiting='#AE7C29';completed='#8D78AA';interrupted='#9786A5';failed='#B8544A';uncertain='#9786A5';unknown='#9786A5'}
  foreach($thread in $threads){
    $state=if($fresh -and $labels.ContainsKey([string]$thread.state)){[string]$thread.state}else{'unknown'}
    $button=[Windows.Controls.Button]::new();$button.Tag=$thread.id;$button.Margin=[Windows.Thickness]::new(0,0,2,6);$button.Padding=[Windows.Thickness]::new(10,9,10,9);$button.HorizontalContentAlignment='Stretch';$button.Background=[Windows.Media.BrushConverter]::new().ConvertFromString('#F6F1FA');$button.ToolTip=$thread.title
    $grid=[Windows.Controls.Grid]::new();$grid.RowDefinitions.Add([Windows.Controls.RowDefinition]::new());$grid.RowDefinitions.Add([Windows.Controls.RowDefinition]::new())
    $title=[Windows.Controls.TextBlock]::new();$title.Text=[string]$thread.title;$title.FontSize=12.5;$title.TextTrimming='CharacterEllipsis';$title.TextWrapping='NoWrap';$title.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString('#57416E');$grid.Children.Add($title)|Out-Null
    $detail=[Windows.Controls.TextBlock]::new();$detail.FontSize=10.5;$detail.Margin=[Windows.Thickness]::new(0,5,0,0);$detail.Foreground=[Windows.Media.BrushConverter]::new().ConvertFromString($colors[$state]);$detail.Text=if($state-eq 'waiting'){if($thread.waitingKind-eq 'approval'){'老大，等你授权'}else{'老大，等你回答'}}else{$labels[$state]}
    if($thread.lastAt){$detail.Text+=' · '+[DateTimeOffset]::FromUnixTimeMilliseconds([long]$thread.lastAt).ToLocalTime().ToString('MM-dd HH:mm')}
    [Windows.Controls.Grid]::SetRow($detail,1);$grid.Children.Add($detail)|Out-Null;$button.Content=$grid
    $button.Add_Click({param($sender,$event)Open-WidgetThread ([string]$sender.Tag);$event.Handled=$true})
    $script:chatUi.ChatList.Children.Add($button)|Out-Null
  }
  $script:chatUi.ChatScroll.ScrollToVerticalOffset($scroll)
}

function Initialize-WidgetChatBehavior {
  $script:chatTaskOnly=$true;$script:chatCollapseOnBlur=$true;$script:chatDotsMotion=$true;$script:chatAttentionBubble=$true
  $script:chatAutoCollapse=$true;$script:chatAutoCollapseDelaySeconds=3.0
  $script:chatBlurDelaySeconds=3.0;$script:chatIdleDelaySeconds=2.0
  $script:chatHasTasks=$false;$script:chatTaskKey='';$script:chatPrimary='idle'
  $script:chatState=@{mode='hidden';manual=$false;dismissed=$null;key='';idleAt=$null;blurAt=$null;statusAt=$null;focus=0;role=''}
  $script:chatRenderedMode='hidden';$script:chatDotsAnimated=$false
}
function Read-WidgetChatSettings($Settings) {
  foreach($name in @('chatTaskOnly','chatCollapseOnBlur','chatDotsMotion','chatAttentionBubble','chatAutoCollapse')){if($Settings.$name-is [bool]){Set-Variable -Scope Script -Name $name -Value $Settings.$name}}
  foreach($name in @('chatBlurDelaySeconds','chatIdleDelaySeconds','chatAutoCollapseDelaySeconds')){
    if($null-ne $Settings.$name){try{$seconds=[double]$Settings.$name;if(![double]::IsNaN($seconds) -and $seconds-ge 0 -and $seconds-le 60){Set-Variable -Scope Script -Name $name -Value $seconds}}catch{}}
  }
}
function Get-WidgetChatSettings {
  return @{chatTaskOnly=$script:chatTaskOnly;chatCollapseOnBlur=$script:chatCollapseOnBlur;chatDotsMotion=$script:chatDotsMotion;chatAttentionBubble=$script:chatAttentionBubble;chatBlurDelaySeconds=$script:chatBlurDelaySeconds;chatIdleDelaySeconds=$script:chatIdleDelaySeconds;chatAutoCollapse=$script:chatAutoCollapse;chatAutoCollapseDelaySeconds=$script:chatAutoCollapseDelaySeconds}
}
function Resolve-WidgetChatMode([long]$Now,[long]$Foreground,[bool]$OwnedFocus,[bool]$HostFocus,[bool]$RootVisible,[bool]$Interacting=$false,[string]$Role='') {
  $state=$script:chatState;$changed=$script:chatTaskKey-ne $state.key
  if($changed){$state.key=$script:chatTaskKey;$state.dismissed=$null}
  $roleGroup=if($Role-in @('waiting','peek','side')){'side'}elseif($Role-in @('full','legacy')){'full'}elseif($RootVisible){'full'}else{'side'}
  $roleChanged=$state.role -and $state.role-ne $roleGroup;$state.role=$roleGroup
  if($roleChanged){$state.dismissed=$null}
  if($script:chatHasTasks){$state.idleAt=$null}else{if($null-eq $state.idleAt){$state.idleAt=$Now}}
  if($script:chatTaskOnly -and $script:chatHasTasks -and !$state.manual){
    if($state.mode-eq 'hidden' -or $state.mode-eq 'expanded' -or $changed -or $roleChanged -or ($state.mode-eq 'compact' -and !$script:chatAutoCollapse -and $state.dismissed-ne $state.key)){
      $state.mode='status';$state.statusAt=$Now;$state.focus=$Foreground;$state.blurAt=$null
    }
    if($state.mode-eq 'status'){
      if($null-eq $state.statusAt -or $OwnedFocus -or $Interacting){$state.statusAt=$Now}
      if($script:chatAutoCollapse -and $Now-[long]$state.statusAt-ge $script:chatAutoCollapseDelaySeconds*1000){$state.mode='compact'}
    }
  }
  if(!$script:chatTaskOnly -and !$state.manual -and $state.mode-in @('status','compact')){$state.mode='hidden'}
  if($script:chatTaskOnly -and !$script:chatHasTasks -and !$state.manual -and $Now-[long]$state.idleAt-ge $script:chatIdleDelaySeconds*1000){$state.mode='hidden'}
  if($state.mode-eq 'expanded' -and $script:chatCollapseOnBlur){
    if($OwnedFocus -or $Interacting){$state.focus=$Foreground;$state.blurAt=$null}
    elseif($Foreground-ne $state.focus -or (!$RootVisible -and !$state.manual)){
      if($null-eq $state.blurAt){$state.blurAt=$Now}
      if($Now-[long]$state.blurAt-ge $script:chatBlurDelaySeconds*1000){$state.mode='compact';$state.manual=$false}
    }else{$state.blurAt=$null}
  }else{$state.blurAt=$null}
  return $state.mode
}
function Update-WidgetChatButtonVisibility {
  if(!$script:ui.ChatButton){return}
  # Status text and dots live beside both character poses. Keep the old entry
  # point only for manual mode, so the original pose cannot leave duplicate text.
  $script:ui.ChatButton.Visibility=if($script:chatState.mode-ne 'hidden' -or $script:chatTaskOnly){'Collapsed'}else{'Visible'}
}
function Set-WidgetChatDotAnimation {
  if(!$script:chatPanel){return}
  $animate=$script:chatState.mode-eq 'compact' -and $script:chatDotsMotion -and [Windows.SystemParameters]::ClientAreaAnimation
  if($animate-eq $script:chatDotsAnimated){return};$script:chatDotsAnimated=$animate
  $index=0
  foreach($name in @('ChatDot1','ChatDot2','ChatDot3')){
    $dot=$script:chatUi[$name];$dot.RenderTransform.BeginAnimation([Windows.Media.TranslateTransform]::YProperty,$null);$dot.RenderTransform.Y=0;$dot.BeginAnimation([Windows.UIElement]::OpacityProperty,$null);$dot.Opacity=1
    if($animate){
      $motion=[Windows.Media.Animation.DoubleAnimation]::new(0,-4,[Windows.Duration]::new([TimeSpan]::FromMilliseconds(360)));$motion.AutoReverse=$true;$motion.RepeatBehavior=[Windows.Media.Animation.RepeatBehavior]::Forever;$motion.BeginTime=[TimeSpan]::FromMilliseconds($index*180)
      $dot.RenderTransform.BeginAnimation([Windows.Media.TranslateTransform]::YProperty,$motion)
      $fade=[Windows.Media.Animation.DoubleAnimation]::new(0.35,1,[Windows.Duration]::new([TimeSpan]::FromMilliseconds(360)));$fade.AutoReverse=$true;$fade.RepeatBehavior=[Windows.Media.Animation.RepeatBehavior]::Forever;$fade.BeginTime=$motion.BeginTime
      $dot.BeginAnimation([Windows.UIElement]::OpacityProperty,$fade)
    }
    $index++
  }
}
function Set-WidgetChatMode([string]$Mode) {
  $script:chatState.mode=$Mode
  if($Mode-ne 'expanded' -and $script:chatRenderedMode-eq 'expanded' -and $script:chatPanel){
    $script:chatUi.ChatList.Children.Clear();$script:chatSignature=$null
  }
  Update-WidgetChatButtonVisibility
  if($Mode-eq 'hidden'){
    if($script:chatPanel){$script:chatPanel.Hide();Set-WidgetChatDotAnimation};$script:chatRenderedMode='hidden';return
  }
  if(!$script:chatPanel){Initialize-WidgetChatPanel;Update-WidgetChats}
  if($script:chatRenderedMode-ne $Mode -or !$script:chatPanel.IsVisible){
    $expanded=$Mode-eq 'expanded'
    if($expanded){Update-WidgetChats}
    $script:chatUi.ChatExpanded.Visibility=if($expanded){'Visible'}else{'Collapsed'}
    $script:chatUi.ChatStatus.Visibility=if($Mode-eq 'status'){'Visible'}else{'Collapsed'}
    $script:chatUi.ChatCompact.Visibility=if($Mode-eq 'compact'){'Visible'}else{'Collapsed'}
    $script:chatPanel.Width=if($expanded){390}elseif($Mode-eq 'status'){180}else{72};$script:chatPanel.Height=if($expanded){550}elseif($Mode-eq 'status'){34}else{30}
    # The tiny indicator is independent of the Codex owner, so minimizing Codex does not hide an active task.
    $script:chatPanel.Owner=if($expanded -and $script:window.IsVisible){$script:window}else{$null}
    $script:chatPanel.Topmost=!$expanded -or !$script:window.IsActive
    $script:chatPanel.Show();Position-WidgetChatPanel;$script:chatRenderedMode=$Mode
  }
  $script:chatPanel.Owner=if($Mode-eq 'expanded' -and $script:window.IsVisible){$script:window}else{$null}
  Position-WidgetChatPanel
  Set-WidgetChatDotAnimation
}
function Hide-WidgetChatPanel {
  $script:chatState.manual=$false;$script:chatState.dismissed=$script:chatState.key;$script:chatState.blurAt=$null
  Set-WidgetChatMode $(if($script:chatHasTasks -and $script:chatTaskOnly){'compact'}else{'hidden'})
}
function Tick-WidgetChatBehavior([long]$Now=0) {
  if(!$script:widgetHandle){return};if(!$Now){$Now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()}
  $foreground=[GptWidgetNative]::GetAncestor([GptWidgetNative]::GetForegroundWindow(),2)
  $own=[GptWidgetNative]::ProcessId($foreground)-eq $PID
  $hostFocused=[GptWidgetNative]::ForegroundHost($foreground)-ne [IntPtr]::Zero
  $interacting=($script:chatPanel -and $script:chatPanel.IsMouseOver) -or ($script:context -and $script:context.IsOpen)
  $role=if($script:roleState){[string]$script:roleState.mode}else{''}
  $mode=Resolve-WidgetChatMode $Now $foreground.ToInt64() $own $hostFocused $script:window.IsVisible $interacting $role
  Set-WidgetChatMode $mode
}
function Show-WidgetChatNotice([string]$Text) {
  if(!(Get-Command Show-Quota -ErrorAction SilentlyContinue)){return}
  if(!$script:collapsed -and $script:bubbleMode-ne 'activity'){return}
  Show-Quota;$script:bubbleMode='activity';$script:ui.QuoteText.Text=$Text;Fit-QuoteText;$script:ui.QuoteText.Tag=$Text;Apply-Scene;Restart-SceneTtl
}
Initialize-WidgetChatBehavior
