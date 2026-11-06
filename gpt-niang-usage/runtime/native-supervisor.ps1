function Build-WidgetNativeSupervisor([string]$AppDir,[string]$DataDir) {
  $sources=@('resource-job.cs','supervisor-host.cs','supervisor-main.cs')|ForEach-Object{Join-Path $AppDir ('runtime\'+$_)}
  $sha=[Security.Cryptography.SHA256]::Create()
  try{
    $text=($sources|ForEach-Object{[IO.File]::ReadAllText($_,[Text.Encoding]::UTF8)}) -join "`n"
    $fingerprint=[BitConverter]::ToString($sha.ComputeHash([Text.Encoding]::UTF8.GetBytes($text))).Replace('-','')
  }finally{$sha.Dispose()}
  $directory=Join-Path $DataDir 'native'
  $exe=Join-Path $directory 'GPTNiangSupervisor.exe'
  $stamp=Join-Path $directory 'supervisor-build.txt'
  if((Test-Path -LiteralPath $exe) -and (Test-Path -LiteralPath $stamp) -and [IO.File]::ReadAllText($stamp)-eq $fingerprint){return $exe}
  $null=New-Item -ItemType Directory -Path $directory -Force
  $compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
  if(!(Test-Path -LiteralPath $compiler)){$compiler=Join-Path $env:WINDIR 'Microsoft.NET\Framework\v4.0.30319\csc.exe'}
  $temp=Join-Path $directory ('build-'+[Guid]::NewGuid().ToString('N')+'.exe')
  try{
    $arguments=@('/nologo','/target:winexe','/optimize+','/reference:System.Web.Extensions.dll','/reference:System.Management.dll',('/out:'+$temp))+$sources
    $output=& $compiler @arguments 2>&1
    if($LASTEXITCODE-ne 0 -or !(Test-Path -LiteralPath $temp)){throw ('Native supervisor compilation failed: '+($output -join "`n"))}
    if([IO.File]::Exists($exe)){[IO.File]::Replace($temp,$exe,[System.Management.Automation.Language.NullString]::Value)}else{[IO.File]::Move($temp,$exe)}
    [IO.File]::WriteAllText($stamp,$fingerprint)
  }finally{if([IO.File]::Exists($temp)){[IO.File]::Delete($temp)}}
  return $exe
}
