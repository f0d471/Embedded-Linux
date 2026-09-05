# Windows PowerShell / PowerShell 7; run after logging into the board shell.
[CmdletBinding(DefaultParameterSetName = 'Command')]
param(
    [string]$Port = 'COM8',
    [Parameter(Mandatory, ParameterSetName = 'Command')][string]$Command,
    [Parameter(Mandatory, ParameterSetName = 'Upload')][string]$Upload,
    [Parameter(Mandatory, ParameterSetName = 'Upload')]
    [ValidatePattern('^/tmp/[a-zA-Z0-9_./-]+$')][string]$Destination
)
$ErrorActionPreference = 'Stop'
$serial = [System.IO.Ports.SerialPort]::new($Port, 115200, [System.IO.Ports.Parity]::None, 8, [System.IO.Ports.StopBits]::One)
$serial.Handshake = [System.IO.Ports.Handshake]::None
$serial.DtrEnable = $false
$serial.RtsEnable = $false
$serial.WriteTimeout = 10000
$echoDisabled = $false
function Invoke-BoardCommand([string]$Text, [int]$TimeoutSeconds = 15) {
    $marker = '__DONE_' + [Guid]::NewGuid().ToString('N') + '__'
    $line = $Text + '; printf ''\n' + $marker + ':%s\n'' "$?"'
    $serial.Write($line + "`r")
    $received = [System.Text.StringBuilder]::new()
    $timer = [Diagnostics.Stopwatch]::StartNew()
    while ($timer.Elapsed.TotalSeconds -lt $TimeoutSeconds) {
        Start-Sleep -Milliseconds 100
        [void]$received.Append($serial.ReadExisting())
        $match = [regex]::Match($received.ToString(), '\r?\n' + $marker + ':(\d+)\r?\n')
        if ($match.Success) {
            $result = $received.ToString()
            Write-Output $result
            if ([int]$match.Groups[1].Value -ne 0) { throw 'Board command failed; see output above.' }
            return
        }
    }
    Write-Output $received.ToString()
    throw 'Timed out. Confirm that the board is at its Linux shell prompt.'
}
try {
    $serial.Open()
    $serial.Write("`r")
    Start-Sleep -Milliseconds 500
    $prompt = $serial.ReadExisting()
    if ($prompt -notmatch '\[root@100ask:[^\r\n]*\]#') {
        throw ('Expected an idle root shell. Log in with a serial terminal first. Received: ' + $prompt)
    }
    if ($PSCmdlet.ParameterSetName -eq 'Command') {
        Invoke-BoardCommand $Command
    } else {
        if ($Destination.Split('/') -contains '..') { throw 'Parent path segments are not allowed.' }
        $localFile = (Resolve-Path -LiteralPath $Upload).Path
        $payload = [Convert]::ToBase64String([IO.File]::ReadAllBytes($localFile))
        $expectedHash = (Get-FileHash -LiteralPath $localFile -Algorithm SHA256).Hash.ToLowerInvariant()
        $parent = $Destination.Substring(0, $Destination.LastIndexOf('/'))
        Invoke-BoardCommand ("mkdir -p '$parent' && command -v base64 && command -v sha256sum && stty -echo")
        $echoDisabled = $true
        $end = '__UPLOAD_' + [Guid]::NewGuid().ToString('N') + '__'
        $serial.Write("base64 -d > '$Destination' <<'$end'`r")
        Start-Sleep -Milliseconds 200
        # Pace below 115200 baud to avoid overrunning the UART input queue.
        for ($offset = 0; $offset -lt $payload.Length; $offset += 768) {
            $count = [Math]::Min(768, $payload.Length - $offset)
            $serial.Write($payload.Substring($offset, $count) + "`r")
            Start-Sleep -Milliseconds 90
            [void]$serial.ReadExisting()
        }
        $serial.Write($end + "`r")
        Start-Sleep -Milliseconds 500
        [void]$serial.ReadExisting()
        Invoke-BoardCommand ("printf '%s  %s\n' '$expectedHash' '$Destination' | sha256sum -c -")
        Invoke-BoardCommand 'stty echo'
        $echoDisabled = $false
    }
} finally {
    if ($serial.IsOpen) {
        if ($echoDisabled) {
            $serial.Write(([char]3).ToString())
            Start-Sleep -Milliseconds 100
            $serial.Write("stty echo`r")
            Start-Sleep -Milliseconds 200
        }
        $serial.Close()
    }
    $serial.Dispose()
}
