$ErrorActionPreference='Stop'
$app=Split-Path $PSScriptRoot -Parent
. (Join-Path $app 'runtime\native-supervisor.ps1')
. (Join-Path $app 'runtime\update-helper.ps1') -FunctionsOnly
$testDir=Join-Path ([IO.Path]::GetTempPath()) ('gpt-native-build-'+[Guid]::NewGuid().ToString('N'))
try{
  $exe=Build-WidgetNativeSupervisor $app $testDir
  $before=[IO.File]::GetLastWriteTimeUtc($exe)
  $again=Build-WidgetNativeSupervisor $app $testDir
  if($again-ne $exe -or [IO.File]::GetLastWriteTimeUtc($exe)-ne $before){throw 'Unchanged native source recompiled.'}
  $p=Start-Process -FilePath $exe -ArgumentList '--self-test' -WindowStyle Hidden -PassThru -RedirectStandardOutput (Join-Path $testDir 'out.txt') -RedirectStandardError (Join-Path $testDir 'error.txt')
  $null=$p.Handle
  try{if(!$p.WaitForExit(15000)){throw 'Native supervisor self-test timed out.'};if($p.ExitCode-ne 0){throw ([IO.File]::ReadAllText((Join-Path $testDir 'error.txt')))}}
  finally{if(!$p.HasExited){$p.Kill()};$p.Dispose()}
  Get-Content -LiteralPath (Join-Path $testDir 'out.txt')
  $now=[DateTime]::UtcNow
  $journal=[pscustomobject]@{appDir=$app;dataDir=$testDir}
  $status=[pscustomobject]@{processStartedAt=$now.ToString('o')}
  $identity=[pscustomobject]@{Name='GPTNiangSupervisor.exe';ExecutablePath=$exe;CreationDate=$now;CommandLine=('"'+$exe+'" "'+$app+'" "'+$testDir+'"')}
  if(!(Test-WidgetSupervisorHealthIdentity $identity $journal $status)){throw 'Native upgrade health rejected matching process.'}
  $identity.CreationDate=$now.AddMinutes(1)
  if(Test-WidgetSupervisorHealthIdentity $identity $journal $status){throw 'Native upgrade health accepted reused PID.'}
  $identity.CreationDate=$now;$identity.ExecutablePath=Join-Path $testDir 'foreign.exe'
  if(Test-WidgetSupervisorHealthIdentity $identity $journal $status){throw 'Native upgrade health accepted foreign binary.'}
  'PASS: native compiler cache and executable self-test'
}finally{
  $full=[IO.Path]::GetFullPath($testDir);$prefix=[IO.Path]::GetFullPath([IO.Path]::GetTempPath()).TrimEnd('\')+'\'
  if(!$full.StartsWith($prefix,[StringComparison]::OrdinalIgnoreCase) -or [IO.Path]::GetFileName($full)-notlike 'gpt-native-build-*'){throw 'Unsafe test cleanup path.'}
  if(Test-Path -LiteralPath $full){Remove-Item -LiteralPath $full -Recurse -Force}
}
