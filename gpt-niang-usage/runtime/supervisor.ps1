param([switch]$CheckOnly)
$ErrorActionPreference='Stop'
. (Join-Path $PSScriptRoot 'supervisor-task.ps1')
$appDir=Split-Path $PSScriptRoot -Parent
$info=Get-WidgetSupervisorInfo $appDir
if($CheckOnly){
  if(!('GptWidgetSupervisorNative' -as [type])){Add-Type -Path (Join-Path $PSScriptRoot 'supervisor-host.cs')}
  return [pscustomobject]@{ok=$true;info=$info;hosts=@([GptWidgetSupervisorNative]::Hosts())}
}
. (Join-Path $PSScriptRoot 'native-supervisor.ps1')
$executable=Build-WidgetNativeSupervisor $info.AppDir $info.DataDir
# Do not keep this PowerShell launcher resident beside the native watchdog.
$process=Start-Process -FilePath $executable -ArgumentList @(('"'+$info.AppDir+'"'),('"'+$info.DataDir+'"')) -WindowStyle Hidden -PassThru
$process.Dispose()
