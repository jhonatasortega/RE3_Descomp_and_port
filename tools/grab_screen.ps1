<#
grab_screen.ps1 — captura de tela p/ identificar animacoes do RE3 (GOG PC) rodando.

Uso:
  # 1) listar titulos de janelas visiveis (achar a janela do jogo)
  powershell -ExecutionPolicy Bypass -File tools/grab_screen.ps1 -List

  # 2) capturar a janela do jogo (por trecho do titulo). Burst de N quadros.
  powershell -ExecutionPolicy Bypass -File tools/grab_screen.ps1 -Title "BIOHAZARD" -Out capturas/walk -Count 5 -Interval 140

  # 3) capturar a tela primaria inteira (fallback)
  powershell -ExecutionPolicy Bypass -File tools/grab_screen.ps1 -Out capturas/full -Count 1

Saida: PNGs <Out>_00.png, <Out>_01.png ... na pasta indicada (cria se preciso).
#>
param(
  [switch]$List,
  [string]$Title = "",
  [string]$Out = "capturas/shot",
  [int]$Count = 1,
  [int]$Interval = 150
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
using System.Text;
public class Win32 {
  [DllImport("user32.dll")] public static extern bool GetWindowRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
  [DllImport("user32.dll")] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
  [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc cb, IntPtr p);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  public delegate bool EnumProc(IntPtr h, IntPtr p);
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int Left, Top, Right, Bottom; }
}
"@

function Get-VisibleWindows {
  $list = New-Object System.Collections.ArrayList
  $cb = [Win32+EnumProc]{
    param($h, $p)
    if ([Win32]::IsWindowVisible($h)) {
      $sb = New-Object System.Text.StringBuilder 512
      [void][Win32]::GetWindowText($h, $sb, 512)
      $t = $sb.ToString()
      if ($t.Trim().Length -gt 0) {
        $r = New-Object Win32+RECT
        [void][Win32]::GetWindowRect($h, [ref]$r)
        $w = $r.Right - $r.Left; $hh = $r.Bottom - $r.Top
        if ($w -gt 100 -and $hh -gt 100) {
          [void]$list.Add([pscustomobject]@{ H=$h; Title=$t; X=$r.Left; Y=$r.Top; W=$w; Hh=$hh })
        }
      }
    }
    return $true
  }
  [void][Win32]::EnumWindows($cb, [IntPtr]::Zero)
  return $list
}

if ($List) {
  Get-VisibleWindows | ForEach-Object {
    "{0,5} x{1,-5} @({2},{3})  {4}" -f $_.W, $_.Hh, $_.X, $_.Y, $_.Title
  }
  exit 0
}

# resolve regiao de captura
$rx = 0; $ry = 0
$rw = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Width
$rh = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds.Height
$targetH = [IntPtr]::Zero
if ($Title -ne "") {
  $win = Get-VisibleWindows | Where-Object { $_.Title -match [regex]::Escape($Title) } | Select-Object -First 1
  if ($win) {
    $targetH = $win.H
    [void][Win32]::SetForegroundWindow($win.H); Start-Sleep -Milliseconds 250
    # re-le o rect (pode ter mudado ao focar)
    $r = New-Object Win32+RECT; [void][Win32]::GetWindowRect($win.H, [ref]$r)
    $rx = $r.Left; $ry = $r.Top; $rw = $r.Right - $r.Left; $rh = $r.Bottom - $r.Top
    "janela: '$($win.Title)'  regiao ${rw}x${rh} @($rx,$ry)"
  } else {
    "AVISO: nenhuma janela casou '$Title' -> capturando tela inteira"
  }
}

$dir = Split-Path -Parent $Out
if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Force -Path $dir | Out-Null }

for ($i = 0; $i -lt $Count; $i++) {
  $bmp = New-Object System.Drawing.Bitmap $rw, $rh
  $g = [System.Drawing.Graphics]::FromImage($bmp)
  $g.CopyFromScreen($rx, $ry, 0, 0, (New-Object System.Drawing.Size $rw, $rh))
  $path = "{0}_{1:D2}.png" -f $Out, $i
  $bmp.Save($path, [System.Drawing.Imaging.ImageFormat]::Png)
  $g.Dispose(); $bmp.Dispose()
  "salvo $path"
  if ($i -lt $Count - 1) { Start-Sleep -Milliseconds $Interval }
}
