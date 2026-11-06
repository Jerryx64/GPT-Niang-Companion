param([string]$PreviewDirectory,[string]$SnapshotFile)
$ErrorActionPreference='Stop'
Add-Type -AssemblyName PresentationFramework,PresentationCore,WindowsBase
$script:appDir=Split-Path $PSScriptRoot -Parent
. ([ScriptBlock]::Create([IO.File]::ReadAllText((Join-Path $script:appDir 'runtime\chat-panel.ps1'),[Text.Encoding]::UTF8)))
# Layout placement is covered by chat-behavior; keep this interaction window
# off screen, including when a successful handoff returns to active-task dots.
function Position-WidgetChatPanel {}
function Assert-Chat($Condition,[string]$Message){if(!$Condition){throw $Message}}
$text='你好 & RT-DETR / "论文" + 中文? #'
$uri=Get-WidgetNewChatUri $text
Assert-Chat ([Uri]::UnescapeDataString($uri.Substring('codex://new?prompt='.Length))-eq $text) 'Prompt URI roundtrip failed'
Assert-Chat ((Get-WidgetNewChatUri '')-eq 'codex://threads/new') 'Empty prompt must open a blank composer'
$rejected=$false;try{Get-WidgetThreadUri 'invalid/../thread'|Out-Null}catch{$rejected=$true};Assert-Chat $rejected 'Invalid thread ID was accepted'
$rejected=$false;try{Get-WidgetNewChatUri ('a'*2001)|Out-Null}catch{$rejected=$true};Assert-Chat $rejected 'Overlong prompt was accepted'
$script:dataDir=Join-Path ([IO.Path]::GetTempPath()) ('niang-panel-test-'+[Guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $script:dataDir
try{
  $script:window=[Windows.Markup.XamlReader]::Parse([IO.File]::ReadAllText((Join-Path $script:appDir 'widget.xaml'),[Text.Encoding]::UTF8))
  [Windows.Interop.WindowInteropHelper]::new($script:window).EnsureHandle()|Out-Null
  $script:ui=@{ChatButton=$script:window.FindName('ChatButton')}
  Initialize-WidgetChatPanel
  $script:chatPanel.Left=-20000;$script:chatPanel.Top=-20000
  $now=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds()
  $snapshot=@{ok=$true;at=$now;threads=@(
    @{id='01a1440b-750d-7e73-9e6e-e36944aba5f0';title='聊天功能测试';state='running';lastAt=$now},
    @{id='01a13996-3080-76f3-b2ba-c452ee580753';title='需要输入的聊天';state='waiting';lastAt=$now},
    @{id='01a13e61-79dd-7580-a260-cc2b49d202a0';title='已完成的聊天';state='completed';lastAt=$now}
  )}
  $file=Join-Path $script:dataDir 'chat-activity.json'
  [IO.File]::WriteAllText($file,($snapshot|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false))
  Set-WidgetChatMode expanded
  Update-WidgetChats
  Assert-Chat ($script:chatUi.ChatList.Children.Count-eq 3) 'Chat rows were not populated'
  Assert-Chat ($script:ui.ChatButton.Content-eq '老大，有个问题问你') 'Needs input must take priority'
  Assert-Chat ($script:chatUi.ChatStatusText.Text-eq '老大，有个问题问你') 'Small badge must show the current attention state'
  Assert-Chat ($script:ui.ChatButton.Visibility-eq 'Collapsed') 'Automatic status must not leave duplicate original-pose text'
  function Start-Process {param([string]$FilePath,[string]$ErrorAction)$script:lastOpenedUri=$FilePath;if($script:failOpen){throw '测试启动失败'}}
  $script:chatUi.ChatPrompt.Text=$text
  $script:chatUi.ContinueChat.RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
  Assert-Chat ($script:lastOpenedUri-eq $uri) 'Quick chat did not open its encoded URI'
  Assert-Chat ($script:chatUi.ChatPrompt.Text-eq '') 'Prompt was not cleared after successful handoff'
  Assert-Chat ($script:chatState.mode-eq 'compact' -and $script:chatPanel.IsVisible) 'Successful handoff must retain the active task dots'
  Set-WidgetChatMode expanded
  $script:chatUi.ChatList.Children[0].RaiseEvent([Windows.RoutedEventArgs]::new([Windows.Controls.Button]::ClickEvent))
  Assert-Chat ($script:lastOpenedUri-eq 'codex://threads/01a1440b-750d-7e73-9e6e-e36944aba5f0') 'Existing chat did not open the selected ID'
  $script:failOpen=$true;$script:chatUi.ChatPrompt.Text='保留未发送内容';Open-WidgetQuickChat
  Assert-Chat ($script:chatUi.ChatPrompt.Text-eq '保留未发送内容') 'Failed handoff lost the draft'
  $snapshot.threads[1].waitingKind='approval';$snapshot.threads[1].attentionId='approval-2';$script:chatStamp=0
  [IO.File]::WriteAllText($file,($snapshot|ConvertTo-Json -Depth 6),[Text.UTF8Encoding]::new($false));Update-WidgetChats
  Assert-Chat ($script:chatUi.ChatStatusText.Text-eq '老大，等你授权') 'Approval state did not reach the side/full status badge'
  $snapshot.at=$now-30000;[IO.File]::WriteAllText($file,($snapshot|ConvertTo-Json -Depth 6));$script:chatStamp=0;Update-WidgetChats
  Assert-Chat ($script:ui.ChatButton.Content-eq '老大，状态待确认') 'Stale snapshots must not claim a live status'
  if($PreviewDirectory){
    $null=New-Item -ItemType Directory -Path $PreviewDirectory -Force
    if($SnapshotFile){Copy-Item -LiteralPath $SnapshotFile -Destination $file -Force}else{$snapshot.at=[DateTimeOffset]::UtcNow.ToUnixTimeMilliseconds();[IO.File]::WriteAllText($file,($snapshot|ConvertTo-Json -Depth 6))}
    $script:chatStamp=0;Update-WidgetChats;$script:chatUi.ChatFeedback.Text='';$script:chatUi.ChatPrompt.Clear()
    $script:chatUi.ChatExpanded.Visibility='Visible';$script:chatUi.ChatStatus.Visibility='Collapsed';$script:chatUi.ChatCompact.Visibility='Collapsed'
    Set-WidgetChatMode expanded
    $content=$script:chatPanel.Content;$size=[Windows.Size]::new(390,550)
    $content.Measure($size);$content.Arrange([Windows.Rect]::new(0,0,390,550));$content.UpdateLayout()
    Assert-Chat ($script:chatUi.ChatPrompt.ActualHeight-ge 70) 'Composer was clipped'
    $render=[Windows.Media.Imaging.RenderTargetBitmap]::new(390,550,96,96,[Windows.Media.PixelFormats]::Pbgra32)
    $render.Render($content);$encoder=[Windows.Media.Imaging.PngBitmapEncoder]::new();$encoder.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($render))
    $stream=[IO.File]::Create((Join-Path $PreviewDirectory 'GPT-niang-聊天面板.png'));try{$encoder.Save($stream)}finally{$stream.Dispose()}
  }
  Write-Output 'PASS: chat panel, encoded handoff, selected chat, draft preservation, stale status and layout'
}finally{
  $script:runtimeClosed=$true;if($script:chatPanel){$script:chatPanel.Close()}
  $script:window.Close()
  if([IO.Path]::GetFullPath($script:dataDir).StartsWith([IO.Path]::GetTempPath(),[StringComparison]::OrdinalIgnoreCase)){Remove-Item -LiteralPath $script:dataDir -Recurse -Force}
}
