# Analyze raw bytes in the corrupted lines
$filePath = 'C:\Users\gamparo\Documents\advanced_fibonacci_pro_v7\mt5\portafolio_manager\Symbol_Engine.mq5'
$bytes = [System.IO.File]::ReadAllBytes($filePath)
$utf8NoBOM = New-Object System.Text.UTF8Encoding($false)
$content = $utf8NoBOM.GetString($bytes)
$lines = $content -split "`n"

# Print hex bytes around the emoji in specific lines
$lineNums = @(905, 942, 964, 977, 992, 1011, 1033, 1054, 1068, 1081, 1219, 1239, 1265, 1354, 1369, 1436, 1459, 2347, 2424)
foreach ($ln in $lineNums) {
    $line = $lines[$ln - 1]
    $lineBytes = $utf8NoBOM.GetBytes($line)
    # Find position of first non-ASCII byte
    $firstNonAscii = -1
    for ($i = 0; $i -lt $lineBytes.Length; $i++) {
        if ($lineBytes[$i] -gt 127) { $firstNonAscii = $i; break }
    }
    if ($firstNonAscii -ge 0) {
        $start = [Math]::Max(0, $firstNonAscii - 5)
        $end = [Math]::Min($lineBytes.Length - 1, $firstNonAscii + 20)
        $hexSlice = ($lineBytes[$start..$end] | ForEach-Object { $_.ToString('X2') }) -join ' '
        # Also show the chars
        $charSlice = $line.Substring([Math]::Max(0,$firstNonAscii-2), [Math]::Min(30, $line.Length - [Math]::Max(0,$firstNonAscii-2)))
        Write-Host "L$ln [nonAscii@$firstNonAscii]: hex=$hexSlice | char=[$charSlice]"
    }
}
