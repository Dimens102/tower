param([ValidateSet('Run','Install','Remove')][string]$Mode='Run')
$ErrorActionPreference='Stop'
$identity=[Security.Principal.WindowsIdentity]::GetCurrent()
$target=('{0}|{1}' -f $env:COMPUTERNAME,$identity.Name).ToLowerInvariant()
$taskName='Tower Script Worker - '+$identity.User.Value
$root=Join-Path $env:APPDATA 'Tower'
$clientPath=Join-Path $root 'client.json'
if($Mode -eq 'Remove'){
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
    exit
}
if($Mode -eq 'Install'){
    $stable=Join-Path $env:ProgramFiles 'Tower Control\Tower-Script-Worker.ps1'
    if(-not (Test-Path -LiteralPath $stable)){throw 'Run Install-Tower-Control.cmd first.'}
    $action=New-ScheduledTaskAction -Execute "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -Argument "-NoProfile -WindowStyle Hidden -ExecutionPolicy Bypass -File `"$stable`"" -WorkingDirectory (Split-Path $stable)
    $trigger=New-ScheduledTaskTrigger -AtLogOn -User $identity.Name
    $principal=New-ScheduledTaskPrincipal -UserId $identity.Name -LogonType Interactive -RunLevel Highest
    $settings=New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -MultipleInstances IgnoreNew -ExecutionTimeLimit ([TimeSpan]::Zero) -RestartCount 3 -RestartInterval (New-TimeSpan -Minutes 1)
    Stop-ScheduledTask -TaskName $taskName -ErrorAction SilentlyContinue
    Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
    Start-ScheduledTask -TaskName $taskName
    exit
}
[Net.WebRequest]::DefaultWebProxy=New-Object Net.WebProxy
New-Item -ItemType Directory -Path $root -Force | Out-Null
$workerLog=Join-Path $root 'script-worker.log'
$pendingResult=$null
$workerIsElevated=(New-Object Security.Principal.WindowsPrincipal($identity)).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
function Invoke-WorkerPost([string]$path,$body){
    Invoke-RestMethod -Uri (([string]$workerConfig.server).TrimEnd('/')+$path) -Method Post -Headers @{Authorization="Bearer $($workerConfig.token)"} -ContentType 'application/json' -Body ($body|ConvertTo-Json -Depth 20 -Compress) -TimeoutSec 10
}
while($true){
    try{
        $workerConfig=Get-Content -LiteralPath $clientPath -Raw | ConvertFrom-Json
        if($null -ne $pendingResult){[void](Invoke-WorkerPost '/api/v1/control/windows-jobs/complete' $pendingResult);$pendingResult=$null}
        $response=Invoke-WorkerPost '/api/v1/control/windows-jobs/claim' @{target=$target}
        if($null -ne $response.job){
            $job=$response.job
            $jobFolder=Join-Path $root ('script-job-'+[guid]::NewGuid().ToString('N'))
            New-Item -ItemType Directory -Path $jobFolder | Out-Null
            $inputPath=Join-Path $jobFolder 'run.ps1'
            $bodyPath=Join-Path $jobFolder 'body.ps1'
            $exitPath=Join-Path $jobFolder 'exit-code.txt'
            $outputPath=Join-Path $jobFolder 'output.txt'
            $errorPath=Join-Path $jobFolder 'error.txt'
            $ok=$false;$message='Script could not start'
            try{
                $windowMode=if([string]$job.window_mode -eq 'hidden'){'hidden'}else{'visible'}
                if(-not $workerIsElevated){throw 'The Windows worker is an older limited-privilege installation. Use Settings > Install / Repair to replace it.'}
                [IO.File]::WriteAllText($bodyPath,('$ErrorActionPreference = ''Stop''' + "`r`n" + [string]$job.body),(New-Object Text.UTF8Encoding($true)))
                $escapedBodyPath=$bodyPath.Replace("'","''")
                $escapedExitPath=$exitPath.Replace("'","''")
                $runner=@"
`$ErrorActionPreference = 'Stop'
`$towerExitCode = 1
try {
    & '$escapedBodyPath'
    `$towerExitCode = if (`$null -ne `$LASTEXITCODE) {[int]`$LASTEXITCODE} else {0}
}
catch {
    `$_ | Out-String | Write-Error
    `$towerExitCode = 1
}
finally {
    [IO.File]::WriteAllText('$escapedExitPath',[string]`$towerExitCode,(New-Object Text.UTF8Encoding(`$false)))
}
exit `$towerExitCode
"@
                [IO.File]::WriteAllText($inputPath,$runner,(New-Object Text.UTF8Encoding($true)))
                $process=Start-Process -FilePath "$env:SystemRoot\System32\WindowsPowerShell\v1.0\powershell.exe" -ArgumentList @('-NoProfile','-ExecutionPolicy','Bypass','-File',('"{0}"' -f $inputPath)) -WindowStyle $(if($windowMode -eq 'hidden'){'Hidden'}else{'Normal'}) -WorkingDirectory $env:USERPROFILE -RedirectStandardOutput $outputPath -RedirectStandardError $errorPath -PassThru
                $deadline=[DateTime]::UtcNow.AddSeconds([int]$job.timeout_seconds)
                $tooMuchOutput=$false
                while(-not $process.HasExited -and [DateTime]::UtcNow -lt $deadline){
                    $size=0;foreach($file in @($outputPath,$errorPath)){if(Test-Path -LiteralPath $file){$size+=(Get-Item -LiteralPath $file).Length}}
                    if($size -gt 1048576){$tooMuchOutput=$true;break}
                    Start-Sleep -Milliseconds 100;$process.Refresh()
                }
                if(-not $process.HasExited){$process.Kill();$process.WaitForExit();$message=if($tooMuchOutput){'Output limit exceeded'}else{'Script timed out'}}
                else{
                    $process.WaitForExit()
                    $reportedExit=$null
                    if(Test-Path -LiteralPath $exitPath){$exitText=(Get-Content -LiteralPath $exitPath -Raw).Trim();$parsedExit=0;if([int]::TryParse($exitText,[ref]$parsedExit)){$reportedExit=$parsedExit}}
                    if($null -eq $reportedExit){try{$process.Refresh();if($null -ne $process.ExitCode){$reportedExit=[int]$process.ExitCode}}catch{}}
                    if($null -eq $reportedExit){$reportedExit=1;$message='Script finished without reporting an exit code'}
                    else{$ok=$reportedExit -eq 0;$message=if($ok){"Script completed ($windowMode, elevated)"}else{"Script failed (exit $reportedExit, $windowMode, elevated)"}}
                }
                foreach($file in @($outputPath,$errorPath)){
                    if(Test-Path -LiteralPath $file){$reader=[IO.File]::OpenText($file);try{$buffer=New-Object char[] 1800;$length=$reader.Read($buffer,0,$buffer.Length);if($length){$message+="`r`n"+(New-Object string($buffer,0,$length))}}finally{$reader.Dispose()}}
                }
            }catch{$message=[string]$_.Exception.Message}
            finally{Remove-Item -LiteralPath $jobFolder -Recurse -Force -ErrorAction SilentlyContinue}
            $pendingResult=@{id=[string]$job.id;target=$target;ok=$ok;message=$message}
        }
    }catch{
        # Never execute a claimed job twice. Only its completion report is retried.
        if(Test-Path $workerLog){if((Get-Item $workerLog).Length -gt 1048576){Move-Item $workerLog "$workerLog.old" -Force}}
        Add-Content -LiteralPath $workerLog -Value "$(Get-Date -Format s) $($_.Exception.Message)"
        if($null -ne $pendingResult -and $_.Exception.Response.StatusCode -eq 400){$pendingResult=$null}
    }
    Start-Sleep -Seconds 2
}
