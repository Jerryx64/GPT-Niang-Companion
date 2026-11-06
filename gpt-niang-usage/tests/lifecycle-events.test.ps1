$ErrorActionPreference='Stop'
$app=Split-Path $PSScriptRoot -Parent
$source=[IO.File]::ReadAllText((Join-Path $app 'widget.ps1'),[Text.Encoding]::UTF8)
$ast=[Management.Automation.Language.Parser]::ParseInput($source,[ref]$null,[ref]$null)
$native=$ast.Find({param($node)$node-is [Management.Automation.Language.CommandAst] -and $node.GetCommandName()-eq 'Add-Type' -and $node.Extent.Text.Contains('public static class GptWidgetNative')},$true)
. ([scriptblock]::Create($native.Extent.Text))
$script:events=[System.Collections.Generic.List[System.UInt32]]::new()
$callback=[GptWidgetNative]::FilterLifecycle([GptWidgetNative+WinEventProc]{
  param($hook,$ev,$window,$objectId,$childId,$threadId,$time)
  $script:events.Add($ev)
})
[GptWidgetNative]::ObservedHost=[IntPtr]2468
# Irrelevant traffic must never enter PowerShell, even on a busy desktop.
for($i=0;$i-lt 10000;$i++){
  $callback.Invoke([IntPtr]::Zero,0x8000,[IntPtr]1357,0,0,1,0)
}
if($script:events.Count-ne 0){throw 'Unrelated OS events entered the script callback.'}
foreach($eventId in @(16,23,0x8000,0x8001,0x8002,0x8003)){
  $callback.Invoke([IntPtr]::Zero,$eventId,[IntPtr]2468,0,0,1,0)
}
if($script:events.Count-ne 6){throw 'Host lifecycle events were lost.'}
$callback.Invoke([IntPtr]::Zero,3,[IntPtr]1357,0,0,1,0)
if($script:events.Count-ne 7){throw 'Foreground changes were lost.'}
$callback.Invoke([IntPtr]::Zero,0x8000,[IntPtr]2468,-4,0,1,0)
$callback.Invoke([IntPtr]::Zero,0x8000,[IntPtr]2468,0,1,1,0)
$callback.Invoke([IntPtr]::Zero,0x800B,[IntPtr]2468,0,0,1,0)
if($script:events.Count-ne 7){throw 'Child/accessibility/unregistered events entered the script callback.'}
[GptWidgetNative]::ObservedHost=[IntPtr]9876
$callback.Invoke([IntPtr]::Zero,0x8001,[IntPtr]2468,0,0,1,0)
$callback.Invoke([IntPtr]::Zero,0x8002,[IntPtr]9876,0,0,1,0)
if($script:events.Count-ne 8){throw 'Changed host was not tracked.'}
[GptWidgetNative]::ObservedHost=[IntPtr]::Zero
$callback.Invoke([IntPtr]::Zero,0x8000,[IntPtr]::Zero,0,0,1,0)
if($script:events.Count-ne 8){throw 'An empty HWND became a host.'}
'PASS: 10,000 irrelevant events suppressed; foreground, host lifecycle and host switching preserved.'
Add-Type -Path (Join-Path $app 'runtime\resource-job.cs')
[GptNiangResourceJob]::Enter(('Local\GPTNiangPressureTest-'+[Guid]::NewGuid().ToString('N')),384MB,448MB)
Add-Type @'
using System;
using System.Diagnostics;
using System.Runtime.CompilerServices;
public static class PressureFixture {
 [MethodImpl(MethodImplOptions.NoInlining)]
 public static WeakReference Allocate(){
   long current;using(var p=Process.GetCurrentProcess()){current=p.PrivateMemorySize64;}
   var bytes=new byte[Math.Max(16*1024*1024,280*1024*1024-current)];
   for(int i=0;i<bytes.Length;i+=4096)bytes[i]=1;
   return new WeakReference(bytes);
 }
}
'@
[GC]::Collect()
[GptWidgetMemory]::Check(0)
if([GptWidgetMemory]::Collections-ne 0){throw 'Low memory caused unnecessary full collection.'}
$garbage=[PressureFixture]::Allocate()
[GptWidgetMemory]::Check(6000)
if([GptWidgetMemory]::Collections-ne 1 -or $garbage.IsAlive){throw 'Memory pressure did not reclaim unreachable data.'}
[GptWidgetMemory]::Check(7000)
if([GptWidgetMemory]::Collections-ne 1){throw 'Memory reclamation cooldown was ignored.'}
'PASS: low memory skips GC; pressure reclaims temporary data; collection cooldown is bounded.'
