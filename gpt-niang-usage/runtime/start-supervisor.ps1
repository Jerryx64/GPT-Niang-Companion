param([switch]$Manual)
$ErrorActionPreference='Stop'
$appDir=Split-Path $PSScriptRoot -Parent
. (Join-Path $PSScriptRoot 'supervisor-task.ps1')
try{
  $info=Get-WidgetSupervisorInfo $appDir
  $installed=Get-WidgetSupervisorTask $info
  if(!$Manual -and (!$installed -or [string]$installed.State-eq 'Disabled')){return}
  if($installed -and [string]$installed.State-eq 'Disabled'){
    & (Join-Path $PSScriptRoot 'supervisor.ps1') -Once
  }elseif($installed){
    if($Manual){Start-WidgetSupervisorTask $appDir}
    else{Start-ScheduledTask -TaskName $info.TaskName -TaskPath $info.TaskPath -ErrorAction Stop}
  }else{Register-WidgetSupervisorTask $appDir|Out-Null}
  [IO.File]::WriteAllText((Join-Path $info.DataDir 'refresh.flag'),([DateTime]::UtcNow.ToString('o')+' '+[Guid]::NewGuid().ToString('N')))
  Remove-Item -LiteralPath (Join-Path $info.DataDir 'supervisor-start-error.txt') -ErrorAction SilentlyContinue
}catch{
  try{$configuration=Get-Content -LiteralPath (Join-Path $appDir 'installation.json') -Raw -Encoding UTF8|ConvertFrom-Json;[IO.File]::WriteAllText((Join-Path $configuration.dataDir 'supervisor-start-error.txt'),$_.Exception.ToString())}catch{}
  throw
}
