# Tests the public API through API Management: key check and rate limit (Task 3).
# Run from the project folder:  powershell -ExecutionPolicy Bypass -File tests\test-apim.ps1
# You'll be asked for the Student App subscription key (APIM > Subscriptions > Student App > Show keys).

$gateway = "https://apim-feemgmt-kaif.azure-api.net/fees"
$secureKey = Read-Host "Paste the Student App primary key" -AsSecureString
$key = [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secureKey))
$headers = @{ "Ocp-Apim-Subscription-Key" = $key }

function StatusOf([scriptblock]$call) {
    try { & $call | Out-Null; return 200 } catch { return $_.Exception.Response.StatusCode.value__ }
}

Write-Host "`n=== 1. Student 1002 with a valid key (expect 200, Overdue) ===" -ForegroundColor Cyan
try {
    Invoke-RestMethod "$gateway/students/1002/fee" -Headers $headers | ConvertTo-Json
} catch {
    Write-Host "HTTP $($_.Exception.Response.StatusCode.value__)" -ForegroundColor Yellow
}

Write-Host "`n=== 2. No key (expect 401) ===" -ForegroundColor Cyan
"HTTP " + (StatusOf { Invoke-RestMethod "$gateway/students/1002/fee" })

Write-Host "`n=== 3. Wrong key (expect 401) ===" -ForegroundColor Cyan
"HTTP " + (StatusOf { Invoke-RestMethod "$gateway/students/1002/fee" -Headers @{ "Ocp-Apim-Subscription-Key" = "not-a-real-key" } })

Write-Host "`n=== 4. Rate limit: 15 quick calls (expect 429 once the 10-per-minute limit is hit) ===" -ForegroundColor Cyan
foreach ($i in 1..15) {
    $status = StatusOf { Invoke-RestMethod "$gateway/students/1001/fee" -Headers $headers }
    $color = if ($status -eq 429) { "Yellow" } else { "Green" }
    Write-Host ("call {0,2}: HTTP {1}" -f $i, $status) -ForegroundColor $color
}
Write-Host "`nThe limit resets 60 seconds after the first call." -ForegroundColor Gray
