# Fix encoding script for Symbol_Engine.mq5
$filePath = 'C:\Users\gamparo\Documents\advanced_fibonacci_pro_v7\mt5\portafolio_manager\Symbol_Engine.mq5'
$bytes = [System.IO.File]::ReadAllBytes($filePath)
$utf8NoBOM = New-Object System.Text.UTF8Encoding($false)
$content = $utf8NoBOM.GetString($bytes)

Write-Host "File loaded, length: $($content.Length)"

# Perform all replacements - replace corrupted emoji sequences with ASCII equivalents
# The corrupted sequences are UTF-8 re-encoded Latin-1 mojibake

# Line 905, 977, 2347: corrupted "warning" emoji (⚠️ -> âš ï¸)
$content = $content.Replace("`u{00e2}`u{009a}`u{00a0}`u{00ef}`u{00b8}`u{008f} DOMINANCE FILTER:", "[WARN] DOMINANCE FILTER:")
$content = $content.Replace("`u{00e2}`u{009a}`u{00a0}`u{00ef}`u{00b8}`u{008f} CORRELATION BLOCK:", "[WARN] CORRELATION BLOCK:")
$content = $content.Replace("`u{00e2}`u{009a}`u{00a0}`u{00ef}`u{00b8}`u{008f} Spread too wide:", "[WARN] Spread too wide:")

# Line 992: corrupted "no entry" / block emoji (🚫 -> ðŸš«)
$content = $content.Replace("`u{00f0}`u{009f}`u{009a}`u{00ab} BLOCKED:", "[BLOCK] BLOCKED:")

# Line 1436: corrupted "check mark" emoji (✅ -> âœ…)
$content = $content.Replace("`u{00e2}`u{009c}`u{0085} TRADE OPENED", "[OK] TRADE OPENED")

# Line 1459: corrupted "rocket" emoji (🚀 -> ðŸš€)
$content = $content.Replace("`u{00f0}`u{009f}`u{009a}`u{0080} TRADE OPENED:", "[INFO] TRADE OPENED:")

# Line 2424: corrupted arrow (→ -> â†')
$content = $content.Replace("`u{00e2}`u{0086}`u{0092}", "->")

Write-Host "Replacements done. Verifying..."

# Check if any non-ASCII remain in string literals
$remaining = [regex]::Matches($content, '"[^"]*[^\x00-\x7F][^"]*"')
Write-Host "Remaining non-ASCII string literals: $($remaining.Count)"
foreach ($m in $remaining) {
    $lineNum = ($content.Substring(0, $m.Index) -split "`n").Count
    $preview = $m.Value
    if ($preview.Length -gt 100) { $preview = $preview.Substring(0, 100) }
    Write-Host "  Line $lineNum : $preview"
}

# Write back with UTF-8 BOM (as original)
$utf8WithBOM = New-Object System.Text.UTF8Encoding($true)
$outBytes = $utf8WithBOM.GetBytes($content)
[System.IO.File]::WriteAllBytes($filePath, $outBytes)
Write-Host "File saved successfully."
