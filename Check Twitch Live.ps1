# Checks which streamers in "Twitch streamers.txt" are live and opens their streams
# in the default browser.

Write-Host "Welcome to THE FINALS stream dodger"
Write-Host "==================================="
Write-Host ""
Write-Host "Checking the following streamers:"
Write-Host ""

$listFile = Join-Path $PSScriptRoot 'Twitch streamers.txt'
if (-not (Test-Path $listFile)) {
    Write-Host "Could not find $listFile" -ForegroundColor Red
    exit 1
}

# Pull usernames out of each line (accepts full URLs or bare names; skips blanks and # comments)
$users = Get-Content $listFile |
    ForEach-Object { $_.Trim() } |
    Where-Object { $_ -and -not $_.StartsWith('#') } |
    ForEach-Object { ($_ -replace '^(https?://)?(www\.)?twitch\.tv/', '').Trim('/').ToLower() } |
    Where-Object { $_ -match '^[a-z0-9_]+$' } |
    Select-Object -Unique

if (-not $users) {
    Write-Host 'No streamers found in the list.' -ForegroundColor Yellow
    exit 0
}

# Twitch rejects requests that ask about too many users at once, so check them in
# groups of $batchSize (Twitch's public web client ID, no login needed)
$batchSize = 10
$results = @{}
for ($start = 0; $start -lt $users.Count; $start += $batchSize) {
    $end = [Math]::Min($start + $batchSize, $users.Count) - 1
    $fields = for ($i = $start; $i -le $end; $i++) {
        "u${i}: user(login: `"$($users[$i])`") { login stream { title game { name } viewersCount } }"
    }
    $body = @{ query = "query { $($fields -join ' ') }" } | ConvertTo-Json -Compress

    try {
        $resp = Invoke-RestMethod -Uri 'https://gql.twitch.tv/gql' -Method Post -Body $body `
            -ContentType 'application/json' -Headers @{ 'Client-Id' = 'kimne78kx3ncx6brgo4mv6wki5h1ko' }
    } catch {
        Write-Host "Failed to contact Twitch: $($_.Exception.Message)" -ForegroundColor Red
        exit 1
    }
    if ($resp.errors) {
        Write-Host "Twitch returned an error: $($resp.errors[0].message)" -ForegroundColor Red
        exit 1
    }
    for ($i = $start; $i -le $end; $i++) { $results[$i] = $resp.data."u$i" }
}

$live = 0
for ($i = 0; $i -lt $users.Count; $i++) {
    $u = $results[$i]
    if (-not $u) {
        Write-Host ("{0,-14} not found" -f $users[$i]) -ForegroundColor DarkGray
    } elseif ($u.stream) {
        $live++
        $game = if ($u.stream.game) { $u.stream.game.name } else { '?' }
        Write-Host ("{0,-14} LIVE  [{1}] {2} viewers - {3}" -f $users[$i], $game, $u.stream.viewersCount, $u.stream.title) -ForegroundColor Green
        Start-Process "https://www.twitch.tv/$($users[$i])"
    } else {
        Write-Host ("{0,-14} offline" -f $users[$i]) -ForegroundColor DarkGray
    }
}

Write-Host ""
Write-Host "$live of $($users.Count) streamers live."
Write-Host "Opening the $live active streams.."
Write-Host ""
