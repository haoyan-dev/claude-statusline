#Requires -Version 7.0
Set-StrictMode -Off
$ErrorActionPreference = 'SilentlyContinue'
$OutputEncoding = [System.Text.Encoding]::UTF8
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8

$inputData = [Console]::In.ReadToEnd()

if ([string]::IsNullOrWhiteSpace($inputData)) {
    [Console]::Write("Claude")
    exit 0
}

# ── Colors ──────────────────────────────────────────────
$ESC     = [char]27
$blue    = "$ESC[38;2;0;153;255m"
$orange  = "$ESC[38;2;255;176;85m"
$green   = "$ESC[38;2;0;175;80m"
$cyan    = "$ESC[38;2;86;182;194m"
$red     = "$ESC[38;2;255;85;85m"
$yellow  = "$ESC[38;2;230;200;0m"
$white   = "$ESC[38;2;220;220;220m"
$magenta = "$ESC[38;2;180;140;255m"
$dim     = "$ESC[2m"
$reset   = "$ESC[0m"

$sep = " $dim│$reset "

# ── Helpers ─────────────────────────────────────────────
function Get-ColorForPct {
    param([int]$pct)
    if     ($pct -ge 90) { return $red }
    elseif ($pct -ge 70) { return $yellow }
    elseif ($pct -ge 50) { return $orange }
    else                 { return $green }
}

function Build-Bar {
    param([int]$pct, [int]$width)
    if ($pct -lt 0)   { $pct = 0 }
    if ($pct -gt 100) { $pct = 100 }
    $filled   = [Math]::Floor($pct * $width / 100)
    $empty    = $width - $filled
    $barColor = Get-ColorForPct $pct
    return "${barColor}$('●' * $filled)${dim}$('○' * $empty)${reset}"
}

function Format-EpochTime {
    param([string]$epoch, [string]$style = "date")
    if ([string]::IsNullOrEmpty($epoch) -or $epoch -eq "null" -or $epoch -eq "0") { return "" }
    try {
        $dt = [DateTimeOffset]::FromUnixTimeSeconds([long]$epoch).LocalDateTime
        switch ($style) {
            "time" {
                return $dt.ToString("h:mmtt").ToLower() -replace '\.'
            }
            "datetime" {
                return ($dt.ToString("MMM") + " " + $dt.Day + ", " + $dt.ToString("h:mmtt")).ToLower() -replace '\.'
            }
            default {
                return ($dt.ToString("MMM") + " " + $dt.Day).ToLower()
            }
        }
    } catch { return "" }
}

function ConvertTo-EpochFromIso {
    param([string]$isoStr)
    if ([string]::IsNullOrEmpty($isoStr) -or $isoStr -eq "null") { return $null }
    $asLong = 0L
    if ([long]::TryParse($isoStr, [ref]$asLong)) { return $asLong }
    try {
        return [DateTimeOffset]::Parse($isoStr).ToUnixTimeSeconds()
    } catch { return $null }
}

function Invoke-JqRaw {
    param([string]$json, [string]$filter)
    $result = ($json | & jq -r $filter 2>$null)
    if ($LASTEXITCODE -ne 0 -or $null -eq $result) { return "" }
    if ($result -eq "null") { return "" }
    return ($result -join "`n")
}

# ── Extract JSON data ───────────────────────────────────
$model_name   = Invoke-JqRaw $inputData '.model.display_name // "Claude"'
if ([string]::IsNullOrEmpty($model_name)) { $model_name = "Claude" }

[long]$size         = 200000
[long]$input_tokens = 0
[long]$cache_create = 0
[long]$cache_read   = 0

$sz = Invoke-JqRaw $inputData '.context_window.context_window_size // 200000'
if (-not [string]::IsNullOrEmpty($sz)) { $size = [long]$sz }
if ($size -eq 0) { $size = 200000 }

$it = Invoke-JqRaw $inputData '.context_window.current_usage.input_tokens // 0'
if (-not [string]::IsNullOrEmpty($it)) { $input_tokens = [long]$it }

$cc = Invoke-JqRaw $inputData '.context_window.current_usage.cache_creation_input_tokens // 0'
if (-not [string]::IsNullOrEmpty($cc)) { $cache_create = [long]$cc }

$cr = Invoke-JqRaw $inputData '.context_window.current_usage.cache_read_input_tokens // 0'
if (-not [string]::IsNullOrEmpty($cr)) { $cache_read = [long]$cr }

$current  = $input_tokens + $cache_create + $cache_read
$pct_used = if ($size -gt 0) { [int][Math]::Floor($current * 100 / $size) } else { 0 }

$effort        = "default"
$settings_path = Join-Path $env:USERPROFILE ".claude\settings.json"
if (Test-Path $settings_path) {
    $eff = Get-Content $settings_path -Raw 2>$null | & jq -r '.effortLevel // "default"' 2>$null
    if (-not [string]::IsNullOrEmpty($eff) -and $eff -ne "null") { $effort = $eff }
}

# ── LINE 1: Model │ Context % │ Directory (branch) │ Session │ Effort ──
$cwd = Invoke-JqRaw $inputData '.cwd // ""'
if ([string]::IsNullOrEmpty($cwd) -or $cwd -eq "null") { $cwd = (Get-Location).Path }
$dirname = Split-Path $cwd -Leaf

$git_branch = ""
$git_dirty  = ""
$isGit = & git -C "$cwd" rev-parse --is-inside-work-tree 2>$null
if ($LASTEXITCODE -eq 0) {
    $git_branch = (& git -C "$cwd" symbolic-ref --short HEAD 2>$null)
    $porcelain  = (& git -C "$cwd" --no-optional-locks status --porcelain 2>$null)
    if (-not [string]::IsNullOrEmpty($porcelain)) { $git_dirty = "*" }
}

$session_duration = ""
$session_start    = Invoke-JqRaw $inputData '.session.start_time // empty'
if (-not [string]::IsNullOrEmpty($session_start) -and $session_start -ne "null") {
    $start_epoch = ConvertTo-EpochFromIso $session_start
    if ($null -ne $start_epoch) {
        $now_epoch = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
        $elapsed   = $now_epoch - $start_epoch
        if ($elapsed -ge 3600) {
            $session_duration = "$([Math]::Floor($elapsed / 3600))h$([Math]::Floor(($elapsed % 3600) / 60))m"
        } elseif ($elapsed -ge 60) {
            $session_duration = "$([Math]::Floor($elapsed / 60))m"
        } else {
            $session_duration = "${elapsed}s"
        }
    }
}

$skip_perms = ""
try {
    $parentPid = (Get-CimInstance Win32_Process -Filter "ProcessId = $PID" -ErrorAction Stop).ParentProcessId
    $parentCmd = (Get-CimInstance Win32_Process -Filter "ProcessId = $parentPid" -ErrorAction Stop).CommandLine
    if ($parentCmd -like "*--dangerously-skip-permissions*") { $skip_perms = "⚡  " }
} catch {}

$pct_color = Get-ColorForPct $pct_used
$line1  = "${blue}${model_name}${reset}"
$line1 += $sep
$line1 += "✍️ ${pct_color}${pct_used}%${reset}"
$line1 += $sep
$line1 += "${skip_perms}${cyan}${dirname}${reset}"
if (-not [string]::IsNullOrEmpty($git_branch)) {
    $line1 += " ${green}(${git_branch}${red}${git_dirty}${green})${reset}"
}
if (-not [string]::IsNullOrEmpty($session_duration)) {
    $line1 += $sep
    $line1 += "${dim}⏱ ${reset}${white}${session_duration}${reset}"
}
$line1 += $sep
switch ($effort) {
    "high"   { $line1 += "${magenta}● ${effort}${reset}" }
    "medium" { $line1 += "${dim}◑ ${effort}${reset}" }
    "low"    { $line1 += "${dim}◔ ${effort}${reset}" }
    default  { $line1 += "${dim}◑ ${effort}${reset}" }
}

# ── Rate limits from stdin (primary) ───────────────────
$has_stdin_rates     = $false
$five_hour_pct       = ""
$five_hour_reset_str = ""
$seven_day_pct       = ""
$seven_day_reset_str = ""

$stdin_five_pct = Invoke-JqRaw $inputData '.rate_limits.five_hour.used_percentage // empty'
if (-not [string]::IsNullOrEmpty($stdin_five_pct)) {
    $has_stdin_rates     = $true
    $five_hour_pct       = [Math]::Round([double]$stdin_five_pct).ToString()
    $five_hour_reset_str = Invoke-JqRaw $inputData '.rate_limits.five_hour.resets_at // empty'
    $seven_day_raw       = Invoke-JqRaw $inputData '.rate_limits.seven_day.used_percentage // empty'
    if (-not [string]::IsNullOrEmpty($seven_day_raw)) {
        $seven_day_pct = [Math]::Round([double]$seven_day_raw).ToString()
    }
    $seven_day_reset_str = Invoke-JqRaw $inputData '.rate_limits.seven_day.resets_at // empty'
}

# ── Fallback: API call (cached) ────────────────────────
$cache_dir     = Join-Path $env:TEMP "claude"
$cache_file    = Join-Path $cache_dir "statusline-usage-cache.json"
$cache_max_age = 60

if (-not (Test-Path $cache_dir)) {
    New-Item -ItemType Directory -Path $cache_dir -Force | Out-Null
}

$usage_data    = ""
$extra_enabled = "false"

if (-not $has_stdin_rates) {
    $needs_refresh = $true

    if (Test-Path $cache_file) {
        $ageSeconds = ([DateTimeOffset]::UtcNow - (Get-Item $cache_file).LastWriteTimeUtc).TotalSeconds
        if ($ageSeconds -lt $cache_max_age) {
            $needs_refresh = $false
            $usage_data    = Get-Content $cache_file -Raw 2>$null
        }
    }

    if ($needs_refresh) {
        $token = ""
        if (-not [string]::IsNullOrEmpty($env:CLAUDE_CODE_OAUTH_TOKEN)) {
            $token = $env:CLAUDE_CODE_OAUTH_TOKEN
        }
        if ([string]::IsNullOrEmpty($token) -or $token -eq "null") {
            $creds_file = Join-Path $env:USERPROFILE ".claude\.credentials.json"
            if (Test-Path $creds_file) {
                $t = Get-Content $creds_file -Raw 2>$null | & jq -r '.claudeAiOauth.accessToken // empty' 2>$null
                if (-not [string]::IsNullOrEmpty($t) -and $t -ne "null") { $token = $t }
            }
        }

        if (-not [string]::IsNullOrEmpty($token) -and $token -ne "null") {
            try {
                $headers  = @{
                    "Accept"         = "application/json"
                    "Content-Type"   = "application/json"
                    "Authorization"  = "Bearer $token"
                    "anthropic-beta" = "oauth-2025-04-20"
                    "User-Agent"     = "claude-code/2.1.34"
                }
                $response = Invoke-RestMethod -Uri "https://api.anthropic.com/api/oauth/usage" `
                                              -Headers $headers `
                                              -TimeoutSec 5 `
                                              -ErrorAction Stop
                if ($null -ne $response.five_hour) {
                    $usage_data = $response | ConvertTo-Json -Depth 10
                    Set-Content -Path $cache_file -Value $usage_data -Encoding UTF8
                }
            } catch {}
        }

        if ([string]::IsNullOrEmpty($usage_data) -and (Test-Path $cache_file)) {
            $usage_data = Get-Content $cache_file -Raw 2>$null
        }
    }

    if (-not [string]::IsNullOrEmpty($usage_data)) {
        $null = $usage_data | & jq -e . 2>$null
        if ($LASTEXITCODE -eq 0) {
            $fh_raw = Invoke-JqRaw $usage_data '.five_hour.utilization // 0'
            $five_hour_pct       = [Math]::Round([double]$fh_raw).ToString()
            $five_hour_reset_str = Invoke-JqRaw $usage_data '.five_hour.resets_at // empty'

            $sd_raw = Invoke-JqRaw $usage_data '.seven_day.utilization // 0'
            $seven_day_pct       = [Math]::Round([double]$sd_raw).ToString()
            $seven_day_reset_str = Invoke-JqRaw $usage_data '.seven_day.resets_at // empty'

            $extra_enabled = Invoke-JqRaw $usage_data '.extra_usage.is_enabled // false'
        }
    }
} else {
    if (Test-Path $cache_file) {
        $cached = Get-Content $cache_file -Raw 2>$null
        if (-not [string]::IsNullOrEmpty($cached)) {
            $null = $cached | & jq -e . 2>$null
            if ($LASTEXITCODE -eq 0) {
                $extra_enabled = Invoke-JqRaw $cached '.extra_usage.is_enabled // false'
            }
        }
    }
}

# ── Rate limit lines ────────────────────────────────────
$rate_lines = ""
$bar_width  = 10

if (-not [string]::IsNullOrEmpty($five_hour_pct)) {
    $five_epoch     = ConvertTo-EpochFromIso $five_hour_reset_str
    $five_reset_fmt = if ($null -ne $five_epoch) { Format-EpochTime $five_epoch.ToString() "time" } else { "" }
    $five_bar       = Build-Bar ([int]$five_hour_pct) $bar_width
    $five_color     = Get-ColorForPct ([int]$five_hour_pct)
    $five_pct_fmt   = ([int]$five_hour_pct).ToString().PadLeft(3)

    $rate_lines += "${white}current${reset} ${five_bar} ${five_color}${five_pct_fmt}%${reset}"
    if (-not [string]::IsNullOrEmpty($five_reset_fmt)) {
        $rate_lines += " ${dim}⟳${reset} ${white}${five_reset_fmt}${reset}"
    }
}

if (-not [string]::IsNullOrEmpty($seven_day_pct)) {
    $seven_epoch     = ConvertTo-EpochFromIso $seven_day_reset_str
    $seven_reset_fmt = if ($null -ne $seven_epoch) { Format-EpochTime $seven_epoch.ToString() "datetime" } else { "" }
    $seven_bar       = Build-Bar ([int]$seven_day_pct) $bar_width
    $seven_color     = Get-ColorForPct ([int]$seven_day_pct)
    $seven_pct_fmt   = ([int]$seven_day_pct).ToString().PadLeft(3)

    if (-not [string]::IsNullOrEmpty($rate_lines)) { $rate_lines += "`n" }
    $rate_lines += "${white}weekly${reset}  ${seven_bar} ${seven_color}${seven_pct_fmt}%${reset}"
    if (-not [string]::IsNullOrEmpty($seven_reset_fmt)) {
        $rate_lines += " ${dim}⟳${reset} ${white}${seven_reset_fmt}${reset}"
    }
}

if ($extra_enabled -eq "true" -and -not [string]::IsNullOrEmpty($usage_data)) {
    $extra_pct_raw  = Invoke-JqRaw $usage_data '.extra_usage.utilization // 0'
    $extra_pct      = [int][Math]::Round([double]$extra_pct_raw)
    $extra_used_raw = Invoke-JqRaw $usage_data '.extra_usage.used_credits // 0'
    $extra_used     = [Math]::Round([double]$extra_used_raw / 100, 2).ToString("0.00")
    $extra_lim_raw  = Invoke-JqRaw $usage_data '.extra_usage.monthly_limit // 0'
    $extra_limit    = [Math]::Round([double]$extra_lim_raw / 100, 2).ToString("0.00")
    $extra_bar      = Build-Bar $extra_pct $bar_width
    $extra_color    = Get-ColorForPct $extra_pct

    $now        = [DateTime]::Now
    $nextMonth  = (New-Object DateTime($now.Year, $now.Month, 1)).AddMonths(1)
    $extra_reset = ($nextMonth.ToString("MMM") + " " + $nextMonth.Day.ToString()).ToLower()

    if (-not [string]::IsNullOrEmpty($rate_lines)) { $rate_lines += "`n" }
    $rate_lines += "${white}extra${reset}   ${extra_bar} ${extra_color}`$${extra_used}${dim}/${reset}${white}`$${extra_limit}${reset} ${dim}⟳${reset} ${white}${extra_reset}${reset}"
}

# ── Output ──────────────────────────────────────────────
[Console]::Write($line1)
if (-not [string]::IsNullOrEmpty($rate_lines)) {
    [Console]::Write("`n`n$rate_lines")
}

exit 0
