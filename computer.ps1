param([string]$ArgsB64)

$ErrorActionPreference = 'Stop'
try { [Console]::OutputEncoding = [Text.Encoding]::UTF8 } catch { }

function Write-Json($value) {
  Write-Output ($value | ConvertTo-Json -Compress -Depth 6)
}

try {
  $request = [Text.Encoding]::UTF8.GetString([Convert]::FromBase64String($ArgsB64)) | ConvertFrom-Json

  Add-Type -AssemblyName System.Drawing
  Add-Type -AssemblyName System.Windows.Forms
  Add-Type -TypeDefinition @'
using System;
using System.Runtime.InteropServices;

public static class CU
{
    [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
    [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
    [DllImport("user32.dll")] public static extern void mouse_event(uint flags, int dx, int dy, uint data, IntPtr extra);
    [DllImport("user32.dll")] public static extern void keybd_event(byte key, byte scan, uint flags, IntPtr extra);
    [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr window);
    [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr window, int command);
    [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr window, out RECT rect);

    [StructLayout(LayoutKind.Sequential)]
    public struct RECT { public int Left; public int Top; public int Right; public int Bottom; }
}
'@
  [CU]::SetProcessDPIAware() | Out-Null

  $VK = @{
    ctrl = 0x11; control = 0x11; shift = 0x10; alt = 0x12; win = 0x5B
    esc = 0x1B; escape = 0x1B; enter = 0x0D; return = 0x0D; tab = 0x09; space = 0x20
    backspace = 0x08; delete = 0x2E; del = 0x2E
    up = 0x26; down = 0x28; left = 0x25; right = 0x27
    home = 0x24; end = 0x23; pageup = 0x21; pagedown = 0x22
    f1 = 0x70; f2 = 0x71; f3 = 0x72; f4 = 0x73; f5 = 0x74; f6 = 0x75
    f7 = 0x76; f8 = 0x77; f9 = 0x78; f10 = 0x79; f11 = 0x7A; f12 = 0x7B
    '0' = 0x30; '1' = 0x31; '2' = 0x32; '3' = 0x33; '4' = 0x34
    '5' = 0x35; '6' = 0x36; '7' = 0x37; '8' = 0x38; '9' = 0x39
    a = 0x41; b = 0x42; c = 0x43; d = 0x44; e = 0x45; f = 0x46; g = 0x47
    h = 0x48; i = 0x49; j = 0x4A; k = 0x4B; l = 0x4C; m = 0x4D; n = 0x4E
    o = 0x4F; p = 0x50; q = 0x51; r = 0x52; s = 0x53; t = 0x54; u = 0x55
    v = 0x56; w = 0x57; x = 0x58; y = 0x59; z = 0x5A
  }

  function Send-Combo([string]$combo) {
    $parts = $combo.ToLower().Split('+') | Where-Object { $_ -ne '' }
    $codes = @()
    foreach ($part in $parts) {
      $name = $part.Trim()
      if (-not $VK.ContainsKey($name)) { throw "unknown key '$name'" }
      $codes += [byte]$VK[$name]
    }
    foreach ($code in $codes) { [CU]::keybd_event($code, 0, 0, [IntPtr]::Zero) }
    [Array]::Reverse($codes)
    foreach ($code in $codes) { [CU]::keybd_event($code, 0, 2, [IntPtr]::Zero) }
  }

  function Get-WindowList {
    $list = @()
    foreach ($process in Get-Process | Where-Object { $_.MainWindowHandle -ne [IntPtr]::Zero -and $_.MainWindowTitle }) {
      $rect = New-Object CU+RECT
      [void][CU]::GetWindowRect($process.MainWindowHandle, [ref]$rect)
      $list += @{
        handle = [int64]$process.MainWindowHandle
        pid    = $process.Id
        name   = $process.ProcessName
        title  = $process.MainWindowTitle
        x      = $rect.Left
        y      = $rect.Top
        width  = $rect.Right - $rect.Left
        height = $rect.Bottom - $rect.Top
      }
    }
    return $list
  }

  function Find-Window([string]$needle) {
    $list = Get-WindowList
    $match = $list | Where-Object {
      $_.title.ToLower().Contains($needle) -or $_.name.ToLower().Contains($needle)
    } | Select-Object -First 1
    return $match
  }

  $action = [string]$request.action

  switch ($action) {
    'windows' {
      $list = Get-WindowList
      Write-Json @{ ok = $true; summary = "Found $($list.Count) visible windows."; windows = $list }
    }

    'screenshot' {
      $screen = [System.Windows.Forms.SystemInformation]::VirtualScreen
      $bitmap = New-Object System.Drawing.Bitmap($screen.Width, $screen.Height)
      $graphics = [System.Drawing.Graphics]::FromImage($bitmap)
      try {
        $graphics.CopyFromScreen($screen.Left, $screen.Top, 0, 0, $bitmap.Size)
      } finally {
        $graphics.Dispose()
      }
      $stamp = [DateTime]::Now.ToString('yyyyMMdd-HHmmss-fff')
      $path = Join-Path ([string]$request.dir) "shot-$stamp.png"
      $bitmap.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
      $bitmap.Dispose()
      Write-Json @{
        ok = $true
        summary = "Captured the desktop at $($screen.Width)x$($screen.Height); read the PNG with read_image."
        path = $path
        width = $screen.Width
        height = $screen.Height
      }
    }

    'focus' {
      $needle = [string]$request.window
      if ([string]::IsNullOrWhiteSpace($needle)) { throw 'focus needs `window`' }
      $match = Find-Window $needle.ToLower()
      if ($null -eq $match) { throw "no visible window matching '$needle'" }
      $handle = [IntPtr]$match.handle
      [void][CU]::ShowWindow($handle, 9)
      [void][CU]::SetForegroundWindow($handle)
      Write-Json @{ ok = $true; summary = "Focused '$($match.title)'." }
    }

    'move' {
      if ($null -eq $request.x -or $null -eq $request.y) { throw 'move needs `x` and `y`' }
      [void][CU]::SetCursorPos([int]$request.x, [int]$request.y)
      Write-Json @{ ok = $true; summary = "Cursor moved to $($request.x),$($request.y)." }
    }

    'click' {
      if ($null -eq $request.x -or $null -eq $request.y) { throw 'click needs `x` and `y`' }
      $right = ([string]$request.button) -eq 'right'
      $down = if ($right) { 0x0008 } else { 0x0002 }
      $up = if ($right) { 0x0010 } else { 0x0004 }
      [void][CU]::SetCursorPos([int]$request.x, [int]$request.y)
      Start-Sleep -Milliseconds 40
      $times = if ($request.double) { 2 } else { 1 }
      for ($i = 0; $i -lt $times; $i++) {
        [CU]::mouse_event($down, 0, 0, 0, [IntPtr]::Zero)
        [CU]::mouse_event($up, 0, 0, 0, [IntPtr]::Zero)
        if ($times -gt 1) { Start-Sleep -Milliseconds 60 }
      }
      $label = if ($right) { 'Right-clicked' } else { 'Clicked' }
      Write-Json @{ ok = $true; summary = "$label $($request.x),$($request.y)." }
    }

    'drag' {
      if ($null -eq $request.x -or $null -eq $request.y -or $null -eq $request.toX -or $null -eq $request.toY) {
        throw 'drag needs `x`, `y`, `toX` and `toY`'
      }
      $startX = [int]$request.x; $startY = [int]$request.y
      $endX = [int]$request.toX; $endY = [int]$request.toY
      [void][CU]::SetCursorPos($startX, $startY)
      Start-Sleep -Milliseconds 40
      [CU]::mouse_event(0x0002, 0, 0, 0, [IntPtr]::Zero)
      for ($step = 1; $step -le 12; $step++) {
        $ratio = $step / 12.0
        [void][CU]::SetCursorPos([int]($startX + ($endX - $startX) * $ratio), [int]($startY + ($endY - $startY) * $ratio))
        Start-Sleep -Milliseconds 16
      }
      [CU]::mouse_event(0x0004, 0, 0, 0, [IntPtr]::Zero)
      Write-Json @{ ok = $true; summary = "Dragged $startX,$startY -> $endX,$endY." }
    }

    'type' {
      $text = [string]$request.text
      if ([string]::IsNullOrEmpty($text)) { throw 'type needs `text`' }
      Set-Clipboard -Value $text
      Start-Sleep -Milliseconds 60
      Send-Combo 'ctrl+v'
      Write-Json @{ ok = $true; summary = "Typed $($text.Length) characters into the focused window." }
    }

    'key' {
      $combo = [string]$request.keys
      if ([string]::IsNullOrWhiteSpace($combo)) { throw 'key needs `keys`, e.g. ctrl+s' }
      Send-Combo $combo
      Write-Json @{ ok = $true; summary = "Pressed $combo." }
    }

    default {
      throw "unknown action '$action'"
    }
  }
} catch {
  Write-Json @{ ok = $false; error = $_.Exception.Message }
}
