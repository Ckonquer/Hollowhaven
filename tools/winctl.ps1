<#
  winctl.ps1 - drive a running game window with real OS-level input (SendInput) and capture it.
  Only intended for Hollowhaven playtesting on the developer's machine.
  Usage examples:
    winctl.ps1 -Pid 1234 -Action focus
    winctl.ps1 -Pid 1234 -Action key -Key D -Ms 1500         (hold key D for 1500 ms)
    winctl.ps1 -Pid 1234 -Action tap -Key E
    winctl.ps1 -Pid 1234 -Action seq -Seq "W:800,E:80,wait:500,LMB:100,mouse:200:0"
    winctl.ps1 -Pid 1234 -Action click -X 640 -Y 360      (client coords)
    winctl.ps1 -Pid 1234 -Action mouse -Dx 200 -Dy 0
    winctl.ps1 -Pid 1234 -Action shot -Out C:\path\shot.png
#>
param(
  [int]$ProcId,
  [string]$Action = "focus",
  [string]$Key = "",
  [int]$Ms = 100,
  [int]$X = 0, [int]$Y = 0, [int]$Dx = 0, [int]$Dy = 0,
  [string]$Out = "",
  [string]$Seq = ""
)
$ErrorActionPreference = "Stop"
if (-not ("HH.Win" -as [type])) {
Add-Type -ReferencedAssemblies System.Drawing -TypeDefinition @"
using System; using System.Runtime.InteropServices; using System.Drawing; using System.Drawing.Imaging;
namespace HH {
public static class Win {
  [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
  [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; }
  [StructLayout(LayoutKind.Sequential)] struct MOUSEINPUT { public int dx, dy; public uint mouseData, dwFlags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Sequential)] struct KEYBDINPUT { public ushort wVk, wScan; public uint dwFlags, time; public IntPtr extra; }
  [StructLayout(LayoutKind.Explicit)] struct UNION { [FieldOffset(0)] public MOUSEINPUT mi; [FieldOffset(0)] public KEYBDINPUT ki; }
  [StructLayout(LayoutKind.Sequential)] struct INPUT { public uint type; public UNION u; }
  [DllImport("user32.dll")] static extern uint SendInput(uint n, INPUT[] inputs, int size);
  [DllImport("user32.dll")] public static extern bool SetForegroundWindow(IntPtr h);
  [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);
  [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
  [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
  [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
  [DllImport("user32.dll")] public static extern bool SetCursorPos(int x, int y);
  [DllImport("user32.dll")] public static extern uint MapVirtualKey(uint code, uint type);
  [DllImport("user32.dll")] public static extern void keybd_event(byte vk, byte scan, uint flags, UIntPtr extra);
  [DllImport("user32.dll")] public static extern uint GetWindowThreadProcessId(IntPtr h, out uint pid);
  [DllImport("kernel32.dll")] public static extern uint GetCurrentThreadId();
  [DllImport("user32.dll")] public static extern bool AttachThreadInput(uint a, uint b, bool attach);
  [DllImport("user32.dll")] public static extern bool BringWindowToTop(IntPtr h);
  public static void Focus(IntPtr h) {
    IntPtr fg = GetForegroundWindow(); uint p; uint fgThread = GetWindowThreadProcessId(fg, out p); uint me = GetCurrentThreadId();
    keybd_event(0x12, 0, 0, UIntPtr.Zero); keybd_event(0x12, 0, 2, UIntPtr.Zero); // ALT tap unlocks SetForegroundWindow
    AttachThreadInput(me, fgThread, true); ShowWindow(h, 9); BringWindowToTop(h); SetForegroundWindow(h); AttachThreadInput(me, fgThread, false);
  }
  static void Send(INPUT i) { SendInput(1, new INPUT[]{ i }, Marshal.SizeOf(typeof(INPUT))); }
  public static void Key(ushort vk, bool up) {
    ushort sc = (ushort)MapVirtualKey(vk, 0); uint fl = 0x0008; if (up) fl |= 0x0002;
    if (vk == 0x25 || vk == 0x26 || vk == 0x27 || vk == 0x28) fl |= 0x0001; // extended arrows
    INPUT i = new INPUT(); i.type = 1; i.u.ki.wVk = vk; i.u.ki.wScan = sc; i.u.ki.dwFlags = fl; Send(i);
  }
  public static void MouseMove(int dx, int dy) { INPUT i = new INPUT(); i.type = 0; i.u.mi.dx = dx; i.u.mi.dy = dy; i.u.mi.dwFlags = 0x0001; Send(i); }
  public static void MouseButton(int btn, bool up) {
    uint f = btn == 1 ? (up ? 0x0004u : 0x0002u) : (up ? 0x0010u : 0x0008u);
    INPUT i = new INPUT(); i.type = 0; i.u.mi.dwFlags = f; Send(i);
  }
  public static void Wheel(int delta) { INPUT i = new INPUT(); i.type = 0; i.u.mi.dwFlags = 0x0800; i.u.mi.mouseData = (uint)delta; Send(i); }
  public static RECT ClientScreenRect(IntPtr h) { RECT r; GetClientRect(h, out r); POINT p = new POINT(); ClientToScreen(h, ref p); RECT o = new RECT(); o.L = p.X; o.T = p.Y; o.R = p.X + r.R; o.B = p.Y + r.B; return o; }
  public static void Shot(IntPtr h, string path) {
    RECT r = ClientScreenRect(h); int w = r.R - r.L, hh = r.B - r.T;
    using (Bitmap b = new Bitmap(w, hh)) { using (Graphics g = Graphics.FromImage(b)) { g.CopyFromScreen(r.L, r.T, 0, 0, new Size(w, hh)); } b.Save(path, ImageFormat.Png); }
  }
}}
"@
}
$vk = @{ "A"=0x41;"B"=0x42;"C"=0x43;"D"=0x44;"E"=0x45;"F"=0x46;"G"=0x47;"H"=0x48;"I"=0x49;"J"=0x4A;"K"=0x4B;"L"=0x4C;"M"=0x4D;"N"=0x4E;"O"=0x4F;"P"=0x50;"Q"=0x51;"R"=0x52;"S"=0x53;"T"=0x54;"U"=0x55;"V"=0x56;"W"=0x57;"X"=0x58;"Y"=0x59;"Z"=0x5A;
  "0"=0x30;"1"=0x31;"2"=0x32;"3"=0x33;"4"=0x34;"5"=0x35;"6"=0x36;"7"=0x37;"8"=0x38;"9"=0x39;
  "SPACE"=0x20;"ENTER"=0x0D;"ESC"=0x1B;"TAB"=0x09;"SHIFT"=0xA0;"CTRL"=0xA2;"ALT"=0xA4;"BACKSPACE"=0x08;
  "LEFT"=0x25;"UP"=0x26;"RIGHT"=0x27;"DOWN"=0x28;"F1"=0x70;"F2"=0x71;"F3"=0x72;"F5"=0x74;"F9"=0x78;"F10"=0x79;"F11"=0x7A;"F12"=0x7B }
$proc = Get-Process -Id $ProcId
$h = $proc.MainWindowHandle
if ($h -eq [IntPtr]::Zero) { throw "Process $ProcId has no main window" }
function Hold([string]$k, [int]$ms) {
  $k = $k.ToUpper()
  if ($k -eq "LMB" -or $k -eq "RMB") { $b = if ($k -eq "LMB") {1} else {2}; [HH.Win]::MouseButton($b,$false); Start-Sleep -Milliseconds $ms; [HH.Win]::MouseButton($b,$true); return }
  $keys = $k.Split("+") | ForEach-Object { [uint16]$vk[$_] }
  foreach ($c in $keys) { [HH.Win]::Key($c, $false) }
  Start-Sleep -Milliseconds $ms
  [array]::Reverse($keys); foreach ($c in $keys) { [HH.Win]::Key($c, $true) }
}
switch ($Action) {
  "focus" { [HH.Win]::Focus($h); Start-Sleep -Milliseconds 250; "focused=$([HH.Win]::GetForegroundWindow() -eq $h)" }
  "key"   { [HH.Win]::Focus($h); Start-Sleep -Milliseconds 150; Hold $Key $Ms; "held $Key $Ms ms" }
  "tap"   { [HH.Win]::Focus($h); Start-Sleep -Milliseconds 150; Hold $Key 70; "tapped $Key" }
  "mouse" { [HH.Win]::Focus($h); [HH.Win]::MouseMove($Dx, $Dy); "moved $Dx,$Dy" }
  "wheel" { [HH.Win]::Focus($h); [HH.Win]::Wheel($Dy); "wheel $Dy" }
  "click" { [HH.Win]::Focus($h); Start-Sleep -Milliseconds 150; $r = [HH.Win]::ClientScreenRect($h); [HH.Win]::SetCursorPos($r.L + $X, $r.T + $Y); Start-Sleep -Milliseconds 80; [HH.Win]::MouseButton(1,$false); Start-Sleep -Milliseconds 60; [HH.Win]::MouseButton(1,$true); "clicked $X,$Y" }
  "shot"  { [HH.Win]::Shot($h, $Out); "saved $Out" }
  "rect"  { $r = [HH.Win]::ClientScreenRect($h); "client rect L=$($r.L) T=$($r.T) R=$($r.R) B=$($r.B)" }
  "seq"   {
    [HH.Win]::Focus($h); Start-Sleep -Milliseconds 150
    foreach ($step in $Seq.Split(",")) {
      $p = $step.Split(":")
      switch ($p[0].ToLower()) {
        "wait"  { Start-Sleep -Milliseconds ([int]$p[1]) }
        "mouse" { [HH.Win]::MouseMove([int]$p[1], [int]$p[2]) }
        "wheel" { [HH.Win]::Wheel([int]$p[1]) }
        "click" { $r = [HH.Win]::ClientScreenRect($h); [HH.Win]::SetCursorPos($r.L + [int]$p[1], $r.T + [int]$p[2]); Start-Sleep -Milliseconds 60; [HH.Win]::MouseButton(1,$false); Start-Sleep -Milliseconds 60; [HH.Win]::MouseButton(1,$true) }
        "shot"  { [HH.Win]::Shot($h, $p[1] + ":" + $p[2]) }
        default { Hold $p[0] ([int]$p[1]) }
      }
    }
    "seq done"
  }
}
