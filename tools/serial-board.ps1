# serial-board.ps1
#
# Drive the board's Linux shell through the debug UART (on-board CH9102,
# 115200 baud, 8 data bits, no parity, 1 stop bit, no flow control).
#
#   .\tools\serial-board.ps1 'uname -m'
#       Run one shell line on the board. Prints only that line's output and
#       exits with the board-side exit status of the last command in the line.
#
#   .\tools\serial-board.ps1 -Upload .\hello -Destination /tmp/lab/hello
#       Copy one local file to the board. The file is gzipped and cut into
#       blocks; each block travels as base64 text in its own heredoc, and the
#       board appends it only after its sha256 matches. A block that arrives
#       damaged is sent again. At the end the whole file is compared once more.
#
#   .\tools\serial-board.ps1 -Download /tmp/lab/run.log -To .\run.log
#       Copy one board file back: gzip | base64 on the board -> decode here ->
#       compare sha256 of both sides.
#
# Why blocks and resends: the board's UART drops bytes now and then when the
# CPU does not empty its receive FIFO in time (the kernel counts these as "oe"
# in /proc/tty/driver/IMX-uart). Pacing cannot prevent that, only detection can.
#
# -CorruptBlock N is a test hook: the first attempt of block N (counting from 0)
# is sent with one character changed, so the resend path can be seen working.
#
# A COM port can be held by one program at a time: close PuTTY / MobaXterm
# before running this script, and run it again after they are closed.

[CmdletBinding(DefaultParameterSetName = 'Command')]
param(
    [Parameter(Mandatory, Position = 0, ParameterSetName = 'Command')]
    [string]$Command,

    [Parameter(ParameterSetName = 'Command')]
    [int]$TimeoutSec = 60,

    [Parameter(Mandatory, ParameterSetName = 'Upload')]
    [string]$Upload,

    [Parameter(Mandatory, ParameterSetName = 'Upload')]
    [ValidatePattern('^/tmp/[A-Za-z0-9_./-]+$')]
    [string]$Destination,

    [Parameter(ParameterSetName = 'Upload')]
    [int]$CorruptBlock = -1,

    [Parameter(Mandatory, ParameterSetName = 'Download')]
    [ValidatePattern('^/[A-Za-z0-9_./-]+$')]
    [string]$Download,

    [Parameter(Mandatory, ParameterSetName = 'Download')]
    [string]$To,

    [string]$Port = 'COM8'
)

$ErrorActionPreference = 'Stop'
Add-Type -AssemblyName System.IO.Compression

if ($PSCmdlet.ParameterSetName -eq 'Command' -and $Command -match '[^\x00-\x7F]') {
    # The board's bash has no UTF-8 locale and runs readline with convert-meta
    # on, so every byte >= 0x80 is taken as Meta+key (M-d kills a word, ...) and
    # the line bash finally sees is silently rewritten. Output in UTF-8 is fine.
    throw 'Non-ASCII text in -Command is mangled by the board''s readline. Use printf octal escapes instead.'
}

# Serial line parameters. Both ends must agree on every one of them.
$serial = [System.IO.Ports.SerialPort]::new(
    $Port, 115200, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$serial.Handshake = [System.IO.Ports.Handshake]::None  # RTS/CTS are not wired to the SoC
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$serial.Encoding = [System.Text.Encoding]::UTF8
$serial.WriteTimeout = 10000

$blockBytes = 30000  # gzip bytes per block: 40000 base64 chars, about 4 s on the wire
$lineChars = 3072    # base64 chars per heredoc line, below the 4095-byte tty line limit

$script:buf = [System.Text.StringBuilder]::new()
$script:echoOff = $false

function Get-Clean([string]$Text) {
    # Drop ANSI color codes from the prompt and normalize tty CRLF to LF.
    return ($Text -replace '\x1b\[[0-9;?]*[A-Za-z]', '') -replace '\r\n?', "`n"
}

function Read-Until([string]$Pattern, [double]$Seconds) {
    $timer = [Diagnostics.Stopwatch]::StartNew()
    $fresh = $true
    while ($timer.Elapsed.TotalSeconds -lt $Seconds) {
        if ($fresh) {
            $m = [regex]::Match((Get-Clean $script:buf.ToString()), $Pattern, 'Singleline')
            if ($m.Success) { return $m }
        }
        Start-Sleep -Milliseconds 20
        $chunk = $serial.ReadExisting()
        $fresh = [bool]$chunk
        if ($fresh) { [void]$script:buf.Append($chunk) }
    }
    return $null
}

function Send-Line([string]$Text) {
    # The tty turns CR into LF on input (ICRNL), exactly like pressing Enter.
    $serial.Write($Text + "`r")
}

function Reset-Line {
    # Ctrl+C: bash abandons whatever it was reading (a half-received heredoc or
    # a garbled command line) and prints a fresh prompt.
    $serial.Write([string][char]3)
    [void](Read-Until '#\s*$' 5)
    [void]$script:buf.Clear()
}

function Enter-Shell {
    [void]$script:buf.Clear()
    Send-Line ''
    $m = Read-Until '(login:\s*$)|(#\s*$)' 3
    if ($m -and $m.Groups[1].Success) {
        Send-Line 'root'
        $m = Read-Until '(Password:\s*$)|(#\s*$)' 5
        if ($m -and $m.Groups[1].Success) {
            Send-Line ''
            $m = Read-Until '#\s*$' 5
        }
    }
    if (-not $m) {
        throw ("No idle root shell on $Port. Is a program still running in the " +
               "foreground? Received:`n" + (Get-Clean $script:buf.ToString()))
    }
    [void]$script:buf.Clear()
    Send-Line 'stty -echo'
    $script:echoOff = $true
    if (-not (Read-Until '#\s*$' 5)) { throw 'Board did not return to the prompt after stty -echo.' }
}

function Invoke-Board([string]$Line, [double]$Seconds) {
    $tag = [Guid]::NewGuid().ToString('N').Substring(0, 12)
    [void]$script:buf.Clear()
    # printf assembles each marker at run time, so the command text itself never
    # matches the pattern even if echo were on. $Line sits alone inside { ... }
    # on its own input line, so a trailing comment or '&' cannot swallow the END
    # marker, and bash reads the whole group before running any of it: the only
    # prompt it prints in between is the "> " before BEGIN, outside the capture.
    Send-Line ("printf '\n%s_%s\n' BEGIN $tag; { " + $Line)
    Send-Line ("}; printf '\n%s_%s:%s\n' END $tag " + '"$?"')
    $m = Read-Until ("\nBEGIN_$tag\n(.*?)\nEND_${tag}:(\d+)\n") $Seconds
    if (-not $m) {
        throw ("Timed out after $Seconds s. Received:`n" + (Get-Clean $script:buf.ToString()))
    }
    [void](Read-Until '#\s*$' 2)
    $out = $m.Groups[1].Value
    if ($out.EndsWith("`n")) { $out = $out.Substring(0, $out.Length - 1) }
    return [pscustomobject]@{ Output = $out; Status = [int]$m.Groups[2].Value }
}

function Get-BoardHash([string]$Path) {
    $r = Invoke-Board "sha256sum '$Path'" 60
    if ($r.Status -ne 0) { throw "sha256sum failed on the board: $($r.Output)" }
    return ($r.Output -split '\s+')[0]
}

function Send-Block([string]$Text, [string]$Path) {
    # One heredoc per block, decoded into $Path. Lock-step flow control: bash
    # prints its continuation prompt "> " after reading each heredoc line, so
    # the next line goes out only after that prompt comes back. If a dropped
    # byte breaks the framing itself (a lost CR merges two lines, a damaged
    # terminator never ends the heredoc), the expected prompt never arrives;
    # give up on this attempt and let the caller resend.
    $end = 'EOF_' + [Guid]::NewGuid().ToString('N').Substring(0, 12)
    [void]$script:buf.Clear()
    Send-Line ("base64 -d > '$Path' 2>/dev/null <<'$end'")
    for ($off = 0; $off -lt $Text.Length; $off += $lineChars) {
        if (-not (Read-Until '> $' 3)) { Reset-Line; return $false }
        [void]$script:buf.Clear()
        Send-Line $Text.Substring($off, [Math]::Min($lineChars, $Text.Length - $off))
    }
    if (-not (Read-Until '> $' 3)) { Reset-Line; return $false }
    [void]$script:buf.Clear()
    Send-Line $end
    if (-not (Read-Until '#\s*$' 10)) { Reset-Line; return $false }
    return $true
}

$exitCode = 0
try {
    try {
        $serial.Open()
    } catch [System.UnauthorizedAccessException] {
        throw "$Port is held by another program (close PuTTY / MobaXterm first)."
    } catch {
        $present = [System.IO.Ports.SerialPort]::GetPortNames() -join ', '
        throw "Cannot open $Port. Ports present now: $present"
    }

    Enter-Shell

    if ($PSCmdlet.ParameterSetName -eq 'Command') {
        $r = Invoke-Board $Command $TimeoutSec
        if ($r.Output.Length -gt 0) { Write-Output $r.Output }
        $exitCode = $r.Status

    } elseif ($PSCmdlet.ParameterSetName -eq 'Upload') {
        $local = (Resolve-Path -LiteralPath $Upload).Path
        $bytes = [IO.File]::ReadAllBytes($local)
        $ms = [IO.MemoryStream]::new()
        $gz = [IO.Compression.GZipStream]::new($ms, [IO.Compression.CompressionLevel]::Optimal)
        $gz.Write($bytes, 0, $bytes.Length)
        $gz.Dispose()
        $gzBytes = $ms.ToArray()
        $hash = (Get-FileHash -LiteralPath $local -Algorithm SHA256).Hash.ToLowerInvariant()
        $sha = [Security.Cryptography.SHA256]::Create()

        $parent = $Destination.Substring(0, $Destination.LastIndexOf('/'))
        $part = "$Destination.part"
        $gzPath = "$Destination.gz"
        $r = Invoke-Board ("mkdir -p '$parent' && rm -f '$part' '$gzPath' && " +
                           "command -v base64 >/dev/null && command -v gzip >/dev/null") 10
        if ($r.Status -ne 0) { throw "Board side is missing $parent, base64 or gzip." }

        $timer = [Diagnostics.Stopwatch]::StartNew()
        $blocks = [int][Math]::Ceiling($gzBytes.Length / $blockBytes)
        $resent = 0
        for ($i = 0; $i -lt $blocks; $i++) {
            $off = $i * $blockBytes
            $len = [Math]::Min($blockBytes, $gzBytes.Length - $off)
            $b64 = [Convert]::ToBase64String($gzBytes, $off, $len)
            $want = ([BitConverter]::ToString($sha.ComputeHash($gzBytes, $off, $len)) -replace '-', '').ToLowerInvariant()
            # Append the block only if what the board decoded hashes the same.
            $check = '[ "$(sha256sum < ''{0}'' | cut -c1-64)" = {1} ] && cat ''{0}'' >> ''{2}''' -f $part, $want, $gzPath
            for ($attempt = 1; ; $attempt++) {
                if ($attempt -gt 5) { throw "Block $($i + 1)/$blocks failed 5 times in a row." }
                $text = $b64
                if ($i -eq $CorruptBlock -and $attempt -eq 1) {
                    $text = $(if ($b64[0] -eq 'A') { 'B' } else { 'A' }) + $b64.Substring(1)
                }
                $ok = $false
                if (Send-Block $text $part) {
                    try { $ok = (Invoke-Board $check 30).Status -eq 0 } catch { Reset-Line }
                }
                if ($ok) { break }
                $resent++
                Write-Warning "block $($i + 1)/$blocks arrived damaged (attempt $attempt), sending it again"
            }
            $pct = [int](100 * ($i + 1) / $blocks)
            Write-Progress -Activity "Upload $Destination" -Status "$pct %" -PercentComplete $pct
        }
        Write-Progress -Activity "Upload $Destination" -Completed
        $r = Invoke-Board "gzip -dc '$gzPath' > '$Destination' && rm -f '$part' '$gzPath'" 60
        if ($r.Status -ne 0) { throw "Board could not unpack $gzPath : $($r.Output)" }
        $seconds = $timer.Elapsed.TotalSeconds

        $boardHash = Get-BoardHash $Destination
        $line = '{0} -> {1}: {2} bytes, gzip {3}, {4} blocks, {5} resent, {6:N1} s' -f `
            (Split-Path -Leaf $local), $Destination, $bytes.Length, $gzBytes.Length, $blocks, $resent, $seconds
        if ($boardHash -eq $hash) {
            Write-Output "$line, sha256 OK"
        } else {
            Write-Output "$line, sha256 MISMATCH"
            Write-Output "  local $hash"
            Write-Output "  board $boardHash"
            $exitCode = 1
        }

    } else {
        $timer = [Diagnostics.Stopwatch]::StartNew()
        $r = Invoke-Board "gzip -c '$Download' | base64" 600
        if ($r.Status -ne 0) { throw "Cannot read $Download on the board: $($r.Output)" }
        $gzBytes = [Convert]::FromBase64String(($r.Output -replace '\s', ''))
        $in = [IO.Compression.GZipStream]::new(
            [IO.MemoryStream]::new($gzBytes), [IO.Compression.CompressionMode]::Decompress)
        $ms = [IO.MemoryStream]::new()
        $in.CopyTo($ms)
        $in.Dispose()
        $bytes = $ms.ToArray()
        $seconds = $timer.Elapsed.TotalSeconds

        $localPath = [IO.Path]::GetFullPath((Join-Path (Get-Location) $To))
        [IO.File]::WriteAllBytes($localPath, $bytes)
        $hash = (Get-FileHash -LiteralPath $localPath -Algorithm SHA256).Hash.ToLowerInvariant()
        $boardHash = Get-BoardHash $Download
        $line = '{0} -> {1}: {2} bytes, gzip {3}, {4:N1} s' -f `
            $Download, (Split-Path -Leaf $localPath), $bytes.Length, $gzBytes.Length, $seconds
        if ($boardHash -eq $hash) {
            Write-Output "$line, sha256 OK"
        } else {
            Write-Output "$line, sha256 MISMATCH"
            $exitCode = 1
        }
    }
} finally {
    if ($serial.IsOpen) {
        if ($script:echoOff) {
            # Ctrl+C first in case an upload was interrupted halfway through a
            # heredoc; on an idle prompt it only prints a new prompt.
            $serial.Write([string][char]3)
            Start-Sleep -Milliseconds 300
            Send-Line 'stty echo'
            Start-Sleep -Milliseconds 300
        }
        $serial.Close()
    }
    $serial.Dispose()
}
exit $exitCode
