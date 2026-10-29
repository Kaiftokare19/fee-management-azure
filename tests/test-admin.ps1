# Tests the admin endpoints through API Management with Entra ID tokens (Task 4).
# Run from the project folder:  powershell -ExecutionPolicy Bypass -File tests\test-admin.ps1
# You'll be asked for the Admin Tool subscription key and both client apps' IDs and secrets.
# The only update rewrites student 1003's paid amount with the value it already has (20000),
# so no data changes, but a row is added to dbo.FeeAuditLog.

$gateway = "https://apim-feemgmt-kaif.azure-api.net/fees"
$tenant = "019be382-2033-4602-863e-2ff2afa0b0c4"
$apiClientId = "cca19e0b-0da0-41ea-8302-b3503e55bcb1"

function Read-Secret($prompt) {
    $secure = Read-Host $prompt -AsSecureString
    [Runtime.InteropServices.Marshal]::PtrToStringAuto([Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure))
}

function Get-Token($clientId, $clientSecret) {
    $body = @{
        grant_type    = "client_credentials"
        client_id     = $clientId
        client_secret = $clientSecret
        scope         = "api://$apiClientId/.default"
    }
    (Invoke-RestMethod -Method Post "https://login.microsoftonline.com/$tenant/oauth2/v2.0/token" -Body $body).access_token
}

function Show($label, [scriptblock]$call) {
    Write-Host "`n=== $label ===" -ForegroundColor Cyan
    try {
        & $call | ConvertTo-Json -Depth 5
    } catch {
        $resp = $_.Exception.Response
        $body = ""
        if ($resp) { $body = (New-Object System.IO.StreamReader($resp.GetResponseStream())).ReadToEnd() }
        Write-Host "HTTP $($resp.StatusCode.value__) $body" -ForegroundColor Yellow
    }
}

$adminKey = Read-Secret "Admin Tool subscription key"
$adminClientId = Read-Host "fee-admin-client Application (client) ID"
$adminSecret = Read-Secret "fee-admin-client secret Value"
$viewerClientId = Read-Host "fee-viewer-client Application (client) ID (press Enter to skip the viewer test)"
$viewerSecret = if ($viewerClientId) { Read-Secret "fee-viewer-client secret Value" } else { "" }

Write-Host "`nGetting tokens from Entra ID..." -ForegroundColor Gray
$adminToken = Get-Token $adminClientId $adminSecret
$viewerToken = if ($viewerClientId) { Get-Token $viewerClientId $viewerSecret } else { "" }
$adminToken | Set-Clipboard
Write-Host "Admin token copied to clipboard: paste it into https://jwt.ms to see the roles claim." -ForegroundColor Gray

$admin = @{ "Ocp-Apim-Subscription-Key" = $adminKey; Authorization = "Bearer $adminToken" }
$viewer = @{ "Ocp-Apim-Subscription-Key" = $adminKey; Authorization = "Bearer $viewerToken" }
$keyOnly = @{ "Ocp-Apim-Subscription-Key" = $adminKey }

Show "1. Admin token: list overdue students (expect 200, count 7)" {
    Invoke-RestMethod "$gateway/manage/students?status=Overdue" -Headers $admin
}
Show "2. Admin token: update 1003 with its current amount (expect 200, Partially Paid)" {
    Invoke-RestMethod -Method Put "$gateway/manage/students/1003/fee" -Headers $admin `
        -ContentType "application/json" -Body '{"paidAmount": 20000}'
}
Show "3. Admin token: pay more than the total (expect 400)" {
    Invoke-RestMethod -Method Put "$gateway/manage/students/1003/fee" -Headers $admin `
        -ContentType "application/json" -Body '{"paidAmount": 999999}'
}
if ($viewerToken) {
    Show "4. Viewer token, no Fee.Admin role (expect 401)" {
        Invoke-RestMethod -Method Put "$gateway/manage/students/1003/fee" -Headers $viewer `
            -ContentType "application/json" -Body '{"paidAmount": 20000}'
    }
} else {
    Write-Host "`n=== 4. Viewer token test skipped (no fee-viewer-client given) ===" -ForegroundColor DarkGray
}
Show "5. Key but no token (expect 401)" {
    Invoke-RestMethod "$gateway/manage/students?status=Overdue" -Headers $keyOnly
}
