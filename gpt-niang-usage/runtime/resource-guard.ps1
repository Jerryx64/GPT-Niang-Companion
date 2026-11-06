# One shared Windows job for the widget, supervisor and all their descendants.
# These are committed-memory limits, not a working-set trimming hint.
if(!('GptNiangResourceJob' -as [type])){
Add-Type -Path (Join-Path $PSScriptRoot 'resource-job.cs')
}
function Enter-WidgetResourceBudget {
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  [GptNiangResourceJob]::Enter(('Local\GPTNiangResources-'+$sid),384MB,448MB)
}
function Open-WidgetInstanceMutex {
  $sid=[Security.Principal.WindowsIdentity]::GetCurrent().User.Value
  $mutex=[Threading.Mutex]::new($false,('Local\GPTNiangUsage-'+$sid))
  $owned=$false
  try{$owned=$mutex.WaitOne(0)}catch [Threading.AbandonedMutexException]{$owned=$true}
  if(!$owned){$mutex.Dispose();return $null}
  return $mutex
}
function Test-WidgetLaunchBudget([string]$DataDir,[DateTime]$Now=[DateTime]::UtcNow) {
  $file=Join-Path $DataDir 'supervisor-launches.json'
  $recent=@()
  if(Test-Path -LiteralPath $file){
    $saved=Get-Content -LiteralPath $file -Raw -Encoding UTF8|ConvertFrom-Json
    $recent=@($saved|ForEach-Object{([DateTime]$_).ToUniversalTime()}|Where-Object{$_-gt $Now.AddMinutes(-10)})
  }
  if($recent.Count-ge 3){
    [IO.File]::WriteAllText((Join-Path $DataDir 'resource-block.flag'),'Stopped after 3 launches within 10 minutes. Use the launcher to resume.')
    return $false
  }
  $recent+=@($Now)
  [IO.File]::WriteAllText($file,(ConvertTo-Json -InputObject @($recent|ForEach-Object{$_.ToUniversalTime().ToString('o')})))
  return $true
}
