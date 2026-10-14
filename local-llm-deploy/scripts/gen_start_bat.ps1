# gen_start_bat.ps1
# 生成 llama-server 启动 bat（Windows）
#
# 用法：
#   powershell -File gen_start_bat.ps1 -ModelPath "models\Qwen3.8-27B-Unleashed-UD-IQ3_XXS.gguf" -OutFile ".\启动-IQ3XXS.bat"
#   # 无思考快速版：-NoReasoning
#   # 多模态：-Mmproj "models\mmproj-Unleashed-f16.gguf"
#   # 自定义：-Port 8085 -Context 102400 -FitTarget 1024
#
# 说明：
#   - 生成的 bat 为 GBK + CRLF（Windows 双击不乱码、命令不错乱）
#   - 含"已在运行则拒绝启动"防重复检测（第二实例必 OOM）
#   - bat 与 llama-server.exe 同目录运行时，模型路径为相对路径

param(
    [Parameter(Mandatory = $true)][string]$ModelPath,
    [string]$OutFile = "启动.bat",
    [int]$Port = 8085,
    [int]$Context = 102400,
    [string]$Mmproj = "",
    [switch]$NoReasoning,
    [int]$FitTarget = 0
)

$ErrorActionPreference = "Stop"

# ---- 命令主体（每行一个片段，最后一行不加续行符）----
$cmd = @()
$cmd += "llama-server.exe -m $ModelPath"
$cmd += "  --host 127.0.0.1 --port $Port"
$cmd += "  -c $Context"
$cmd += "  --cache-type-k q4_0 --cache-type-v q4_0"
$cmd += "  --jinja"
if ($Mmproj) { $cmd += "  --mmproj $Mmproj --no-mmproj-offload" }
if ($NoReasoning) { $cmd += "  --no-reasoning-preserve" }
$cmd += "  --spec-type draft-mtp --spec-draft-n-max 2"
if ($FitTarget -gt 0) { $cmd += "  --fit-target $FitTarget" }
for ($i = 0; $i -lt $cmd.Count - 1; $i++) { $cmd[$i] += " ^" }

# ---- 头部与防重复检测 ----
$head = @()
$head += "@echo off"
$head += "chcp 65001 >nul"
$head += "title llama-server - $ModelPath"
$head += "echo ================================================"
$head += "echo   $ModelPath"
$head += ("echo   Context: {0} tokens" -f $Context)
if ($NoReasoning) { $head += "echo   Thinking: OFF (fast)" } else { $head += "echo   Thinking: ON" }
if ($Mmproj) { $head += "echo   Vision: $Mmproj" }
$head += "echo ================================================"
$head += ""
$head += "REM 防重复启动：已在运行则退出（避免第二实例 OOM）"
$head += 'tasklist /FI "IMAGENAME eq llama-server.exe" 2>nul | find /I "llama-server.exe" >nul'
$head += "if %errorlevel%==0 ("
$head += "  echo  [提示] llama-server 已经在运行中，无需重复启动！"
$head += "  echo  如需切换版本：先 taskkill /IM llama-server.exe /F 再启动"
$head += "  pause"
$head += "  exit /b 0"
$head += ")"
$head += ""
$head += "echo 启动中... 看到 'listening on' 即成功"
$head += ""

$full = (($head -join "`r`n") + ($cmd -join "`r`n") + "`r`npause`r`n")

# ---- 写为 GBK + CRLF ----
$gbk = [Text.Encoding]::GetEncoding(936)
$target = if ([IO.Path]::IsPathRooted($OutFile)) { $OutFile } else { Join-Path (Get-Location).Path $OutFile }
[IO.File]::WriteAllText($target, $full, $gbk)
Write-Output ("==> 已生成: " + $target)
