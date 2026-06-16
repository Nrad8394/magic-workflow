# =============================================================================
# Magic Workflow — bootstrap (Windows / PowerShell)
# Mirrors setup.sh. Requires Docker Desktop (WSL2) + OpenSSL (Git for Windows).
# For the smoothest experience, run setup.sh inside WSL instead.
# =============================================================================
$ErrorActionPreference = "Stop"
Set-Location $PSScriptRoot

function New-Secret {
    $b = New-Object 'System.Byte[]' 32
    [System.Security.Cryptography.RandomNumberGenerator]::Create().GetBytes($b)
    return (([Convert]::ToBase64String($b)) -replace '[^A-Za-z0-9]', '').Substring(0,32)
}

Write-Host "==> Magic Workflow setup in $PSScriptRoot"

if (-not (Test-Path .env)) {
    Copy-Item .env.example .env
    $content = Get-Content .env -Raw
    $keys = @(
        'POSTGRES_SUPER_PASSWORD','NEXTCLOUD_DB_PASSWORD','MATTERMOST_DB_PASSWORD',
        'KEYCLOAK_DB_PASSWORD','REDIS_PASSWORD','MINIO_ROOT_PASSWORD','S3_SECRET_KEY',
        'KEYCLOAK_ADMIN_PASSWORD','OIDC_NEXTCLOUD_SECRET','OIDC_MATTERMOST_SECRET',
        'NEXTCLOUD_ADMIN_PASSWORD','COLLABORA_PASSWORD','GRAFANA_ADMIN_PASSWORD'
    )
    foreach ($k in $keys) {
        $content = $content -replace "(?m)^$k=.*", "$k=$(New-Secret)"
    }
    Set-Content -Path .env -Value $content -NoNewline
    Write-Host "==> Created .env with strong random secrets"
} else {
    Write-Host "==> .env exists, leaving secrets untouched"
}

# Derive hostnames from BASE_DOMAIN
$base = ((Select-String -Path .env -Pattern '^BASE_DOMAIN=' | Select-Object -First 1).Line -split '=',2)[1].Trim()
if (-not $base) { $base = 'magic.test' }
$content = Get-Content .env -Raw
$map = @{ 'NEXTCLOUD_HOST'='cloud'; 'MATTERMOST_HOST'='chat'; 'COLLABORA_HOST'='office';
          'KEYCLOAK_HOST'='id'; 'GRAFANA_HOST'='grafana'; 'HOMER_HOST'='dash'; 'MINIO_CONSOLE_HOST'='s3' }
foreach ($k in $map.Keys) { $content = $content -replace "(?m)^$k=.*", "$k=$($map[$k]).$base" }
Set-Content -Path .env -Value $content -NoNewline
Write-Host "==> Hostnames derived from BASE_DOMAIN=$base"

# OpenSSL (cert + realm render need it; envsubst not native on Windows)
$openssl = (Get-Command openssl -ErrorAction SilentlyContinue).Source
if (-not $openssl -and (Test-Path "C:\Program Files\Git\usr\bin\openssl.exe")) {
    $openssl = "C:\Program Files\Git\usr\bin\openssl.exe"
}

# Render Keycloak realm (simple .NET token replacement; no envsubst needed)
function Get-Env($k) { ((Select-String -Path .env -Pattern "^$k=" | Select-Object -First 1).Line -split '=',2)[1].Trim() }
$realm = Get-Content scripts\keycloak-realm.json.template -Raw
foreach ($k in @('KEYCLOAK_REALM','NEXTCLOUD_HOST','MATTERMOST_HOST','OIDC_NEXTCLOUD_SECRET','OIDC_MATTERMOST_SECRET')) {
    $realm = $realm -replace [regex]::Escape('${' + $k + '}'), (Get-Env $k)
}
New-Item -ItemType Directory -Force -Path config\keycloak | Out-Null
Set-Content -Path config\keycloak\magicworkflow-realm.json -Value $realm -NoNewline
Write-Host "==> Rendered config\keycloak\magicworkflow-realm.json"

# Self-signed wildcard cert
New-Item -ItemType Directory -Force -Path config\proxy\tls | Out-Null
if ($openssl -and -not (Test-Path config\proxy\tls\fullchain.pem)) {
    & $openssl req -x509 -nodes -newkey rsa:2048 -days 825 `
        -keyout config\proxy\tls\privkey.pem -out config\proxy\tls\fullchain.pem `
        -subj "/CN=*.$base" -addext "subjectAltName=DNS:*.$base,DNS:$base,DNS:localhost"
    Write-Host "==> Generated self-signed wildcard cert for *.$base"
} elseif (-not $openssl) {
    Write-Warning "openssl not found — run setup.sh in WSL to generate the TLS cert + realm."
}

Write-Host ""
Write-Host "==> Done. Add to your hosts file (C:\Windows\System32\drivers\etc\hosts):"
Write-Host "    127.0.0.1  cloud.$base chat.$base office.$base id.$base grafana.$base dash.$base s3.$base"
Write-Host ""
Write-Host "    Then:  make up   (or docker compose up -d) ;  make urls"
