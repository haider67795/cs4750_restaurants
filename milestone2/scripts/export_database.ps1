param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
$exportDir = Join-Path $root 'exports'
New-Item -ItemType Directory -Path $exportDir -Force | Out-Null
$dump = 'C:\Program Files\MySQL\MySQL Server 26.10\bin\mysqldump.exe'
if (-not (Test-Path -LiteralPath $dump)) { throw "MySQL dump tool not found: $dump" }
$stamp = Get-Date -Format 'yyyyMMdd_HHmmss'
$output = Join-Path $exportDir "restaurants_$stamp.sql"
Write-Host 'Enter your database password when prompted.'
& $dump -h 35.245.147.165 -u root -p --ssl-mode=REQUIRED --single-transaction --hex-blob --set-gtid-purged=OFF --no-tablespaces --column-statistics=0 --triggers --routines --databases restaurants "--result-file=$output"
if ($LASTEXITCODE -ne 0) { throw "Export failed. Do not submit the partial file: $output" }
Write-Host "Export saved to $output"