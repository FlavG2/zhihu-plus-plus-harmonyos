# build_hap.ps1
# 按当天日期注入版本号（versionName=0.2.YYMMDD / versionCode=YYMMDD）后，
# 用 DevEco hvigor CLI 构建未签名 HAP。
# 用法：在 PowerShell 中执行  .\build_hap.ps1

$ErrorActionPreference = 'Stop'

# ---- 环境（与历史构建命令一致）----
$env:PATH = "D:\DevEco Studio\jbr\bin;" + $env:PATH
$env:DEVECO_SDK_HOME = "D:\DevEco Studio\sdk"
Remove-Item Env:NODE_OPTIONS -ErrorAction SilentlyContinue

$proj = "E:\DevelopMent\ZhiHu Clone\zhihu-plus-plus-harmonyos"

# ---- 当天日期版本号 ----
$date = (Get-Date).ToString("yyMMdd")
$versionName = "0.2.$date"
$versionCode = [int]$date

# ---- 注入 AppScope/app.json5（整条替换，避免反向引用歧义）----
$appJson5 = Join-Path $proj "AppScope\app.json5"
$content = [System.IO.File]::ReadAllText($appJson5)
$content = [regex]::Replace($content, '"versionName": "[^"]*"', '"versionName": "' + $versionName + '"')
$content = [regex]::Replace($content, '"versionCode": \d+', '"versionCode": ' + $versionCode)
[System.IO.File]::WriteAllText($appJson5, $content, [System.Text.UTF8Encoding]::new($false))
Write-Host "app.json5 -> versionName=$versionName versionCode=$versionCode"

# ---- 注入 BuildInfo.ts（About 页运行时读取失败时的回退值）----
$buildInfo = Join-Path $proj "entry\src\main\ets\generated\BuildInfo.ts"
$bcontent = [System.IO.File]::ReadAllText($buildInfo)
$bcontent = [regex]::Replace($bcontent, "export const APP_VERSION_NAME: string = '[^']*'", "export const APP_VERSION_NAME: string = '" + $versionName + "'")
[System.IO.File]::WriteAllText($buildInfo, $bcontent, [System.Text.UTF8Encoding]::new($false))
Write-Host "BuildInfo.ts -> APP_VERSION_NAME=$versionName"

# ---- 构建未签名 HAP（日志写到工程内 build_hap.log）----
# 用 cmd /c "cd /d 工程目录 && node ..." 强制子进程在正确目录运行（规避部分环境下
# Set-Location 对原生子进程不生效的问题），输出经管道落盘。
$buildLog = Join-Path $proj "build_hap.log"
$nodeExe = "D:\DevEco Studio\tools\node\node.exe"
$hvigorJs = "D:\DevEco Studio\tools\hvigor\bin\hvigorw.js"
$cmd = "cd /d `"$proj`" && `"$nodeExe`" `"$hvigorJs`" assembleHap --mode module -p product=default --no-daemon"
cmd /c $cmd 2>&1 | Out-String -Width 4096 | ForEach-Object {
  [System.IO.File]::WriteAllText($buildLog, $_, [System.Text.UTF8Encoding]::new($false))
}
Write-Host "hvigor 日志已写入 $buildLog"
