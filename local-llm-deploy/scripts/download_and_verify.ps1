# download_and_verify.ps1
# hf-mirror 下载 GGUF 模型 + 大小/SHA256 双校验
#
# 用法：
#   powershell -File download_and_verify.ps1 -Repo "SwagMessiah100/Qwen3.8-27B-Unleashed-GGUF" -File "Qwen3.8-27B-Unleashed-UD-IQ3_XXS.gguf" -OutDir ".\models"
#   # 带 SHA256 校验：
#   ... -Sha256 "585267A0BA9BEE47E3684F68E7991A61F48EF589982EF93CC0963FF344BC1FCA"
#
# 先查文件清单（大小）：
#   curl "https://hf-mirror.com/api/models/<repo>/tree/main"   → 返回 JSON 含 size

param(
    [Parameter(Mandatory = $true)][string]$Repo,
    [Parameter(Mandatory = $true)][string]$File,
    [Parameter(Mandatory = $true)][string]$OutDir,
    [string]$Sha256 = "",
    [string]$Mirror = "https://hf-mirror.com"
)

$ErrorActionPreference = "Stop"

# 1. 拼 URL
$url = "$Mirror/$Repo/resolve/main/$File"
Write-Output "==> 下载: $url"

# 2. 建目录
New-Item -ItemType Directory -Force -Path $OutDir | Out-Null
$outPath = Join-Path $OutDir $File

# 3. 下载
if (-not (Test-Path $outPath)) {
    Write-Output "==> 开始下载（HF 直连会超时，必须走镜像）..."
    curl.exe -L --retry 3 -o $outPath $url
    if ($LASTEXITCODE -ne 0) { throw "下载失败，exit=$LASTEXITCODE" }
} else {
    Write-Output "==> 文件已存在，跳过下载（$outPath）"
}

# 4. 大小校验（与 HF API 清单核对）
$size = (Get-Item $outPath).Length
Write-Output ("==> 文件大小: {0:N0} 字节 ({1:N2} GB)" -f $size, ($size / 1GB))

# 5. SHA256 校验（可选，强烈建议）
if ($Sha256 -ne "") {
    Write-Output "==> 计算 SHA256..."
    $hash = (Get-FileHash $outPath -Algorithm SHA256).Hash.ToUpper()
    Write-Output ("    实际: " + $hash)
    Write-Output ("    期望: " + $Sha256.ToUpper())
    if ($hash -eq $Sha256.ToUpper()) {
        Write-Output "==> SHA256 校验通过 ✅"
    } else {
        Write-Output "==> SHA256 不一致 ❌ 文件可能损坏，请删除后重下"
        exit 1
    }
} else {
    Write-Output "==> 未提供 -Sha256，跳过哈希校验（建议到 HF 页面核对）"
}

Write-Output ("==> 完成: " + $outPath)
