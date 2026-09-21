Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

Add-Type @"
using System;
using System.Runtime.InteropServices;
public class OV {
    [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr a, int x, int y, int cx, int cy, uint f);
    [DllImport("user32.dll")] public static extern int  GetWindowLong(IntPtr h, int n);
    [DllImport("user32.dll")] public static extern int  SetWindowLong(IntPtr h, int n, int v);
    public const int  GWL_EXSTYLE      = -20;
    public const int  WS_EX_TOOLWINDOW = 0x00000080;
    public const int  WS_EX_APPWINDOW  = 0x00040000;
    public const uint SWP_NOMOVE       = 0x0002;
    public const uint SWP_NOSIZE       = 0x0001;
    public const uint SWP_FRAMECHANGED = 0x0020;
    [DllImport("user32.dll")] public static extern bool ReleaseCapture();
    [DllImport("user32.dll")] public static extern IntPtr SendMessage(IntPtr h, int msg, IntPtr wp, IntPtr lp);
    public const int  WM_NCLBUTTONDOWN = 0x00A1;
    public const int  HTCAPTION        = 2;
    public static readonly IntPtr HWND_TOPMOST = new IntPtr(-1);
}
"@

try {
Add-Type @"
using System;
using System.Windows.Forms;
using System.Drawing;
public class ResizableNW : NativeWindow {
    const int WM_NCHITTEST=0x84,HTLEFT=10,HTRIGHT=11,HTTOP=12,HTTOPLEFT=13,HTTOPRIGHT=14,HTBOTTOM=15,HTBOTTOMLEFT=16,HTBOTTOMRIGHT=17,HTCLIENT=1;
    Form _f; int _g;
    public ResizableNW(Form f,int grip=6){_f=f;_g=grip;AssignHandle(f.Handle);}
    protected override void WndProc(ref Message m){
        base.WndProc(ref m);
        if(m.Msg==WM_NCHITTEST&&(int)m.Result==HTCLIENT){
            int lp=m.LParam.ToInt32();
            var p=_f.PointToClient(new Point(lp&0xFFFF,lp>>16));
            int x=p.X,y=p.Y,w=_f.Width,h=_f.Height,g=_g;
            if(x<g&&y<g)m.Result=(IntPtr)HTTOPLEFT;
            else if(x>w-g&&y<g)m.Result=(IntPtr)HTTOPRIGHT;
            else if(x<g&&y>h-g)m.Result=(IntPtr)HTBOTTOMLEFT;
            else if(x>w-g&&y>h-g)m.Result=(IntPtr)HTBOTTOMRIGHT;
            else if(x<g)m.Result=(IntPtr)HTLEFT;
            else if(x>w-g)m.Result=(IntPtr)HTRIGHT;
            else if(y<g)m.Result=(IntPtr)HTTOP;
            else if(y>h-g)m.Result=(IntPtr)HTBOTTOM;
        }
    }
}
"@ -ReferencedAssemblies "System.Windows.Forms","System.Drawing" -ErrorAction Stop
} catch { }

try {
Add-Type @"
using System;
using System.Windows.Forms;
using System.Runtime.InteropServices;
public class HotkeyNW : NativeWindow {
    const int WM_HOTKEY=0x0312;
    public static int LastKey=0;
    [DllImport("user32.dll")] public static extern bool RegisterHotKey(IntPtr h,int id,uint mod,uint vk);
    [DllImport("user32.dll")] public static extern bool UnregisterHotKey(IntPtr h,int id);
    public const uint CTRL=2,SHIFT=4,ALT=1;
    public HotkeyNW(IntPtr h){AssignHandle(h);}
    protected override void WndProc(ref Message m){
        if(m.Msg==WM_HOTKEY) LastKey=m.WParam.ToInt32();
        base.WndProc(ref m);
    }
}
"@ -ReferencedAssemblies "System.Windows.Forms" -ErrorAction Stop
} catch { }

# ── Download WebView2 SDK DLLs from NuGet (one-time, ~500KB) ─────────────────
$sdk = "$PSScriptRoot\wv2sdk"
$core = "$sdk\Microsoft.Web.WebView2.Core.dll"
$wf   = "$sdk\Microsoft.Web.WebView2.WinForms.dll"
$ldr  = "$sdk\WebView2Loader.dll"

if (!(Test-Path $core) -or !(Test-Path $wf) -or !(Test-Path $ldr)) {
    New-Item -ItemType Directory -Force $sdk | Out-Null
    Write-Host "Downloading WebView2 SDK..." -ForegroundColor Cyan
    $zip = "$sdk\wv2.zip"
    Invoke-WebRequest "https://www.nuget.org/api/v2/package/Microsoft.Web.WebView2/1.0.2792.45" `
        -OutFile $zip -UseBasicParsing
    Expand-Archive $zip -DestinationPath "$sdk\pkg" -Force
    Copy-Item "$sdk\pkg\lib\net462\Microsoft.Web.WebView2.Core.dll"     $sdk -Force
    Copy-Item "$sdk\pkg\lib\net462\Microsoft.Web.WebView2.WinForms.dll" $sdk -Force
    $arch = if ([IntPtr]::Size -eq 8) { "x64" } else { "x86" }
    Copy-Item "$sdk\pkg\build\native\$arch\WebView2Loader.dll"          $sdk -Force
    Remove-Item "$sdk\pkg" -Recurse -Force
    Remove-Item $zip -Force
    Write-Host "WebView2 SDK ready." -ForegroundColor Green
}

try { Add-Type -Path $core -ErrorAction Stop } catch { }
try { Add-Type -Path $wf  -ErrorAction Stop } catch { }

# ── Layout constants ──────────────────────────────────────────────────────────
$CAP_SIZE = 16; $BRW_SIZE = 16; $OCR_SIZE = 16; $GAP = 5
$TOTAL_W  = $CAP_SIZE + $GAP + $BRW_SIZE + $GAP + $OCR_SIZE
$screen   = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$script:bVisible = $false
$BW_W = 360; $BW_H = 420

# ── Browser window ────────────────────────────────────────────────────────────
$bForm = New-Object System.Windows.Forms.Form
$bForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$bForm.Size            = New-Object System.Drawing.Size($BW_W, $BW_H)
$bForm.MinimumSize     = New-Object System.Drawing.Size(240, 200)
$bForm.TopMost         = $true
$bForm.ShowInTaskbar   = $false
$bForm.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
$bForm.BackColor       = [System.Drawing.Color]::FromArgb(24, 24, 34)
$bForm.Location        = New-Object System.Drawing.Point(
    [int](($screen.Width - $BW_W) / 2),
    [int]($screen.Height - $BW_H - $TOTAL_W - 62)
)
$bForm.Add_FormClosing({ param($s,$e); $e.Cancel=$true; $bForm.Hide(); $script:bVisible=$false })

# ── Toolbar ───────────────────────────────────────────────────────────────────
$tb = New-Object System.Windows.Forms.Panel
$tb.Dock      = [System.Windows.Forms.DockStyle]::Top
$tb.Height    = 34
$tb.BackColor = [System.Drawing.Color]::FromArgb(32, 32, 46)

function MakeTBtn($txt,$x,$w,$bg) {
    $b=New-Object System.Windows.Forms.Button
    $b.Text=$txt; $b.Location=New-Object System.Drawing.Point($x,4)
    $b.Size=New-Object System.Drawing.Size($w,26); $b.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat
    $b.FlatAppearance.BorderColor=[System.Drawing.Color]::FromArgb(55,55,75)
    $b.FlatAppearance.BorderSize=1; $b.BackColor=$bg
    $b.ForeColor=[System.Drawing.Color]::White
    $b.Font=New-Object System.Drawing.Font("Segoe UI",8,[System.Drawing.FontStyle]::Bold)
    $b.Cursor=[System.Windows.Forms.Cursors]::Hand; return $b
}
$dk  = [System.Drawing.Color]::FromArgb(48,48,66)
$bl  = [System.Drawing.Color]::FromArgb(35,90,210)
$rd  = [System.Drawing.Color]::FromArgb(180,40,40)

$tBack = MakeTBtn "<"   4  24 $dk
$tFwd  = MakeTBtn ">"   30 24 $dk
$tRld  = MakeTBtn "R"   56 24 $dk

$tURL  = New-Object System.Windows.Forms.TextBox
$tURL.Location=New-Object System.Drawing.Point(82,7); $tURL.Size=New-Object System.Drawing.Size(168,20)
$tURL.BackColor=[System.Drawing.Color]::FromArgb(46,46,64); $tURL.ForeColor=[System.Drawing.Color]::White
$tURL.BorderStyle=[System.Windows.Forms.BorderStyle]::FixedSingle
$tURL.Font=New-Object System.Drawing.Font("Segoe UI",8); $tURL.Text="https://www.google.com"

$tGo   = MakeTBtn "Go"  253 26 $bl
$tZin  = MakeTBtn "+"   281 24 $dk
$tZout = MakeTBtn "-"   336 24 $dk

# Zoom level label between Z+ and Z-
$zoomLbl = New-Object System.Windows.Forms.Label
$zoomLbl.Text = "100%"
$zoomLbl.Location = New-Object System.Drawing.Point(307, 8)
$zoomLbl.Size     = New-Object System.Drawing.Size(27, 18)
$zoomLbl.ForeColor = [System.Drawing.Color]::FromArgb(180,180,210)
$zoomLbl.Font     = New-Object System.Drawing.Font("Segoe UI",6.5,[System.Drawing.FontStyle]::Bold)
$zoomLbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter

$tb.Controls.AddRange(@($tBack,$tFwd,$tRld,$tURL,$tGo,$tZin,$zoomLbl,$tZout))

# ── Drag handle (title bar area) ──────────────────────────────────────────────
$dragLbl = New-Object System.Windows.Forms.Label
$dragLbl.Text=" Browser"; $dragLbl.Size=New-Object System.Drawing.Size(0,34)
$dragLbl.Dock=[System.Windows.Forms.DockStyle]::Fill
$dragLbl.ForeColor=[System.Drawing.Color]::FromArgb(160,160,190)
$dragLbl.Font=New-Object System.Drawing.Font("Segoe UI",8)
$dragLbl.TextAlign=[System.Drawing.ContentAlignment]::MiddleLeft
$dragLbl.SendToBack()

$closeBtn = MakeTBtn "X" 0 0 $rd
$closeBtn.Size=New-Object System.Drawing.Size(28,34); $closeBtn.Location=New-Object System.Drawing.Point(([int]$BW_W-28),0)
$closeBtn.FlatAppearance.BorderSize=0; $closeBtn.Dock=[System.Windows.Forms.DockStyle]::None

$minBtn = MakeTBtn "-" 0 0 ([System.Drawing.Color]::FromArgb(60,60,80))
$minBtn.Size=New-Object System.Drawing.Size(28,34); $minBtn.Location=New-Object System.Drawing.Point(([int]$BW_W-56),0)
$minBtn.FlatAppearance.BorderSize=0; $minBtn.Dock=[System.Windows.Forms.DockStyle]::None

$titleBar = New-Object System.Windows.Forms.Panel
$titleBar.Dock=[System.Windows.Forms.DockStyle]::Top; $titleBar.Height=26
$titleBar.BackColor=[System.Drawing.Color]::FromArgb(22,22,32)
$titleBar.Controls.Add($dragLbl); $titleBar.Controls.Add($minBtn); $titleBar.Controls.Add($closeBtn)
$closeBtn.Location=New-Object System.Drawing.Point(([int]$BW_W-28),0)
$closeBtn.Size=New-Object System.Drawing.Size(28,26)
$minBtn.Location=New-Object System.Drawing.Point(([int]$BW_W-56),0)
$minBtn.Size=New-Object System.Drawing.Size(28,26)
$closeBtn.Add_Click({ $bForm.Hide(); $script:bVisible=$false })
$minBtn.Add_Click({ $bForm.WindowState=[System.Windows.Forms.FormWindowState]::Minimized })

# ── Resize grip ───────────────────────────────────────────────────────────────
$grip = New-Object System.Windows.Forms.Label
$grip.Dock=[System.Windows.Forms.DockStyle]::Bottom; $grip.Height=6
$grip.BackColor=[System.Drawing.Color]::FromArgb(40,40,58)
$grip.Cursor=[System.Windows.Forms.Cursors]::SizeNWSE
$script:rDrag=$false; $script:rPt=[System.Drawing.Point]::Empty
$grip.Add_MouseDown({ param($s,$e); $script:rDrag=$true; $script:rPt=[System.Windows.Forms.Cursor]::Position })
$grip.Add_MouseMove({
    param($s,$e)
    if ($script:rDrag) {
        $n=[System.Windows.Forms.Cursor]::Position
        $nw=[Math]::Max(240,$bForm.Width+$n.X-$script:rPt.X)
        $nh=[Math]::Max(200,$bForm.Height+$n.Y-$script:rPt.Y)
        $bForm.Size=New-Object System.Drawing.Size($nw,$nh)
        $closeBtn.Location=New-Object System.Drawing.Point($bForm.Width-28,0)
        $script:rPt=$n
    }
})
$grip.Add_MouseUp({ $script:rDrag=$false })

# ── WebView2 control ──────────────────────────────────────────────────────────
$wv = New-Object Microsoft.Web.WebView2.WinForms.WebView2
$wv.Dock = [System.Windows.Forms.DockStyle]::Fill
$wv.CreationProperties = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
$wv.CreationProperties.UserDataFolder = "$env:TEMP\OAS_WV2"

$wv.Add_CoreWebView2InitializationCompleted({
    param($s,$e)
    if ($e.IsSuccess) {
        $wv.CoreWebView2.Settings.AreDefaultContextMenusEnabled  = $true
        $wv.CoreWebView2.Settings.IsStatusBarEnabled             = $false
        $wv.CoreWebView2.Settings.IsZoomControlEnabled           = $true
        $wv.CoreWebView2.Navigate("https://www.google.com")
        # Update URL bar on navigation
        $wv.CoreWebView2.add_NavigationCompleted({
            param($src,$ev)
            $tURL.Text = $wv.CoreWebView2.Source
        })
    }
})

# Toolbar actions
$tBack.Add_Click({ if($wv.CoreWebView2){ $wv.CoreWebView2.GoBack() } })
$tFwd.Add_Click({  if($wv.CoreWebView2){ $wv.CoreWebView2.GoForward() } })
$tRld.Add_Click({  if($wv.CoreWebView2){ $wv.CoreWebView2.Reload() } })
$tGo.Add_Click({
    $raw = $tURL.Text.Trim()
    if ($raw -match '^https?://') {
        $url = $raw
    } elseif ($raw -match '^(localhost|[a-zA-Z0-9][a-zA-Z0-9\-]*(\.[a-zA-Z]{2,})+)(:[0-9]+)?(/.*)?$') {
        $url = "https://$raw"
    } else {
        $url = "https://www.google.com/search?q=" + [Uri]::EscapeDataString($raw)
    }
    if ($wv.CoreWebView2) { $wv.CoreWebView2.Navigate($url) }
})
$tURL.Add_KeyDown({
    param($s,$e)
    if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::A) {
        $tURL.SelectAll(); $e.Handled=$true; $e.SuppressKeyPress=$true
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Return) {
        $tGo.PerformClick(); $e.Handled=$true; $e.SuppressKeyPress=$true
    }
})
$tZin.Add_Click({  if($wv.CoreWebView2){ $wv.ZoomFactor=[Math]::Min(3.0,$wv.ZoomFactor+0.25); $zoomLbl.Text=[int]($wv.ZoomFactor*100)+"%" } })
$tZout.Add_Click({ if($wv.CoreWebView2){ $wv.ZoomFactor=[Math]::Max(0.25,$wv.ZoomFactor-0.25); $zoomLbl.Text=[int]($wv.ZoomFactor*100)+"%" } })

# Drag title bar — native OS drag via WM_NCLBUTTONDOWN/HTCAPTION (works even with WebView2)
foreach ($ctl in @($titleBar,$dragLbl)) {
    $ctl.Add_MouseDown({
        param($s,$e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            [OV]::ReleaseCapture() | Out-Null
            [OV]::SendMessage($bForm.Handle, [OV]::WM_NCLBUTTONDOWN, ([IntPtr]([OV]::HTCAPTION)), [IntPtr]::Zero) | Out-Null
        }
    })
}

# ── AI Shortcuts bar ────────────────────────────────────────────────────────
$aiBar = New-Object System.Windows.Forms.Panel
$aiBar.Dock      = [System.Windows.Forms.DockStyle]::Top
$aiBar.Height    = 28
$aiBar.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 32)
$aiTip = New-Object System.Windows.Forms.ToolTip
$aiList = @(
    @{L="Gem"; C=[System.Drawing.Color]::FromArgb(66,103,212);  U="https://gemini.google.com";       T="Google Gemini"},
    @{L="GPT"; C=[System.Drawing.Color]::FromArgb(16,163,127);  U="https://chatgpt.com";             T="ChatGPT"},
    @{L="Cld"; C=[System.Drawing.Color]::FromArgb(200,100,40);  U="https://claude.ai";               T="Claude (Anthropic)"},
    @{L="Pplx";C=[System.Drawing.Color]::FromArgb(24,140,145);  U="https://www.perplexity.ai";      T="Perplexity AI"},
    @{L="Co";  C=[System.Drawing.Color]::FromArgb(0,114,198);   U="https://copilot.microsoft.com";  T="Microsoft Copilot"},
    @{L="DS";  C=[System.Drawing.Color]::FromArgb(14,118,188);  U="https://chat.deepseek.com";      T="DeepSeek"},
    @{L="Meta";C=[System.Drawing.Color]::FromArgb(24,119,242);  U="https://www.meta.ai";            T="Meta AI"}
)
$ax = 4
foreach ($ai in $aiList) {
    $ab = New-Object System.Windows.Forms.Button
    $ab.Text     = $ai.L
    $ab.Size     = New-Object System.Drawing.Size(44, 22)
    $ab.Location = New-Object System.Drawing.Point($ax, 3)
    $ab.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $ab.FlatAppearance.BorderSize  = 1
    $ab.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(55,55,75)
    $ab.BackColor = $ai.C
    $ab.ForeColor = [System.Drawing.Color]::White
    $ab.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
    $ab.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $ab.Tag       = $ai.U
    $aiTip.SetToolTip($ab, $ai.T)
    $ab.Add_Click({ param($s,$e); if ($wv.CoreWebView2) { $wv.CoreWebView2.Navigate($s.Tag) } })
    $aiBar.Controls.Add($ab)
    $ax += 46
}

# ── Left / Right edge resize panels (sit above WebView2 so they receive mouse) ────
$rRight = New-Object System.Windows.Forms.Panel
$rRight.Width=5; $rRight.Dock=[System.Windows.Forms.DockStyle]::Right
$rRight.BackColor=[System.Drawing.Color]::FromArgb(24,24,34)
$rRight.Cursor=[System.Windows.Forms.Cursors]::SizeWE
$script:rrDrag=$false; $script:rrPt=[System.Drawing.Point]::Empty
$rRight.Add_MouseDown({ $script:rrDrag=$true; $script:rrPt=[System.Windows.Forms.Cursor]::Position })
$rRight.Add_MouseMove({
    if($script:rrDrag){
        $n=[System.Windows.Forms.Cursor]::Position
        $nw=[Math]::Max(240,$bForm.Width+$n.X-$script:rrPt.X)
        $bForm.Width=$nw
        $closeBtn.Location=New-Object System.Drawing.Point($bForm.Width-28,0)
        $minBtn.Location=New-Object System.Drawing.Point($bForm.Width-56,0)
        $script:rrPt=$n
    }
})
$rRight.Add_MouseUp({ $script:rrDrag=$false })

$rLeft = New-Object System.Windows.Forms.Panel
$rLeft.Width=5; $rLeft.Dock=[System.Windows.Forms.DockStyle]::Left
$rLeft.BackColor=[System.Drawing.Color]::FromArgb(24,24,34)
$rLeft.Cursor=[System.Windows.Forms.Cursors]::SizeWE
$script:rlDrag=$false; $script:rlPt=[System.Drawing.Point]::Empty; $script:rlLeft=0; $script:rlW=0
$rLeft.Add_MouseDown({ $script:rlDrag=$true; $script:rlPt=[System.Windows.Forms.Cursor]::Position; $script:rlLeft=$bForm.Left; $script:rlW=$bForm.Width })
$rLeft.Add_MouseMove({
    if($script:rlDrag){
        $n=[System.Windows.Forms.Cursor]::Position
        $delta=$n.X-$script:rlPt.X
        $nw=[Math]::Max(240,$script:rlW-$delta)
        $bForm.Left=$script:rlLeft+($script:rlW-$nw)
        $bForm.Width=$nw
        $closeBtn.Location=New-Object System.Drawing.Point($bForm.Width-28,0)
        $minBtn.Location=New-Object System.Drawing.Point($bForm.Width-56,0)
    }
})
$rLeft.Add_MouseUp({ $script:rlDrag=$false })

# Assemble browser form
$bForm.Controls.Add($wv)        # fill
$bForm.Controls.Add($grip)      # bottom strip
$bForm.Controls.Add($rRight)    # right resize edge
$bForm.Controls.Add($rLeft)     # left resize edge
$bForm.Controls.Add($aiBar)     # AI shortcuts row
$bForm.Controls.Add($tb)        # toolbar
$bForm.Controls.Add($titleBar)  # title bar (top)

$bForm.Add_Shown({
    $wv.EnsureCoreWebView2Async($null) | Out-Null
    try { $null = New-Object ResizableNW($bForm, 6) } catch { }   # all-edge resize
})

# ── Main overlay bar ──────────────────────────────────────────────────────────
$bar = New-Object System.Windows.Forms.Form
$bar.FormBorderStyle=[System.Windows.Forms.FormBorderStyle]::None
$bar.BackColor=[System.Drawing.Color]::Magenta; $bar.TransparencyKey=[System.Drawing.Color]::Magenta
$bar.TopMost=$true; $bar.ShowInTaskbar=$false
$bar.StartPosition=[System.Windows.Forms.FormStartPosition]::Manual
$bar.Size=New-Object System.Drawing.Size($TOTAL_W,$CAP_SIZE)
$bar.Location=New-Object System.Drawing.Point(20,[int]($screen.Height-$CAP_SIZE-52))

function MakeCircle($x,$sz,$c1,$c2) {
    $b=New-Object System.Windows.Forms.Button
    $b.Size=New-Object System.Drawing.Size($sz,$sz); $b.Location=New-Object System.Drawing.Point($x,0)
    $b.FlatStyle=[System.Windows.Forms.FlatStyle]::Flat; $b.FlatAppearance.BorderSize=0
    $b.BackColor=[System.Drawing.Color]::Magenta; $b.Text=""; $b.Cursor=[System.Windows.Forms.Cursors]::Hand
    $b.Tag=@{C1=$c1;C2=$c2;Sz=$sz}
    $b.Add_Paint({
        param($s,$e)
        $t=$s.Tag;$g=$e.Graphics;$sz=[int]$t.Sz;$s1=[int]($sz-1);$s2=[int]($sz-2)
        $g.SmoothingMode=[System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $sh=New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(45,0,0,0))
        $g.FillEllipse($sh,1,2,$s2,$s2);$sh.Dispose()
        $r=New-Object System.Drawing.Rectangle(0,0,$s1,$s1)
        $gr=New-Object System.Drawing.Drawing2D.LinearGradientBrush($r,$t.C1,$t.C2,[System.Drawing.Drawing2D.LinearGradientMode]::Vertical)
        $g.FillEllipse($gr,0,0,$s1,$s1);$gr.Dispose()
        $sh2=New-Object System.Drawing.SolidBrush([System.Drawing.Color]::FromArgb(50,255,255,255))
        $g.FillEllipse($sh2,3,2,[int]($sz*0.55),[int]($sz*0.32));$sh2.Dispose()
    })
    return $b
}

$btnCap=MakeCircle 0 $CAP_SIZE ([System.Drawing.Color]::FromArgb(255,80,145,255)) ([System.Drawing.Color]::FromArgb(255,20,65,210))
$btnCap.Add_Click({
    try {
        $bar.Hide()
        # Delay via timer so the bar visually disappears before screenshot
        $ssTimer = New-Object System.Windows.Forms.Timer; $ssTimer.Interval=160
        $ssTimer.Add_Tick({
            $ssTimer.Stop(); $ssTimer.Dispose()
            try {
                $bmp = New-Object System.Drawing.Bitmap($screen.Width,$screen.Height)
                $gfx = [System.Drawing.Graphics]::FromImage($bmp)
                $gfx.CopyFromScreen(0,0,0,0,$bmp.Size); $gfx.Dispose()
                [System.Windows.Forms.Clipboard]::SetDataObject($bmp,$true)
                $bmp.Dispose()
                $bar.Show()
                (New-Object System.Windows.Forms.ToolTip).Show("Screenshot copied!",$btnCap,0,-24,1400)
            } catch { $bar.Show() }
        })
        $ssTimer.Start()
    } catch { $bar.Show() }
})

$btnBrw=MakeCircle ($CAP_SIZE+$GAP) $BRW_SIZE ([System.Drawing.Color]::FromArgb(255,60,180,100)) ([System.Drawing.Color]::FromArgb(255,20,120,55))
$btnBrw.Add_Click({
    try {
        if ($script:bVisible) {
            $bForm.Hide(); $script:bVisible=$false
        } else {
            if (!$bForm.Visible) { $bForm.Show(); $wv.EnsureCoreWebView2Async($null) | Out-Null }
            $bForm.BringToFront()
            [OV]::SetWindowPos($bForm.Handle,[OV]::HWND_TOPMOST,0,0,0,0,([OV]::SWP_NOMOVE -bor [OV]::SWP_NOSIZE)) | Out-Null
            $ex=[OV]::GetWindowLong($bForm.Handle,[OV]::GWL_EXSTYLE)
            [OV]::SetWindowLong($bForm.Handle,[OV]::GWL_EXSTYLE,($ex -bor [OV]::WS_EX_TOOLWINDOW) -band (-bnot [OV]::WS_EX_APPWINDOW)) | Out-Null
            $script:bVisible=$true
        }
    } catch {}
})

# ── OCR button — isolated subprocess, all vars $script: so timer tick can see them ──
$btnOCR = MakeCircle ($CAP_SIZE+$GAP+$BRW_SIZE+$GAP) $OCR_SIZE ([System.Drawing.Color]::FromArgb(255,230,130,20)) ([System.Drawing.Color]::FromArgb(255,160,70,5))
$script:ocrBusy = $false
$script:ocrImgTmp = [IO.Path]::Combine($env:TEMP,"oas_img.png")
$script:ocrResTmp = [IO.Path]::Combine($env:TEMP,"oas_res.txt")
$script:ocrWrkTmp = [IO.Path]::Combine($env:TEMP,"oas_wkr.ps1")
$script:ocrPollN  = 0
$script:ocrTimer  = New-Object System.Windows.Forms.Timer
$script:ocrTimer.Interval = 600
$script:ocrTimer.Add_Tick({
    try {
        $script:ocrPollN++
        if (Test-Path $script:ocrResTmp) {
            $script:ocrTimer.Stop()
            $txt = (Get-Content $script:ocrResTmp -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) + ""
            Remove-Item $script:ocrResTmp,$script:ocrImgTmp,$script:ocrWrkTmp -Force -EA SilentlyContinue
            $btnOCR.BackColor=[System.Drawing.Color]::Magenta; $btnOCR.Refresh()
            $script:ocrBusy=$false
            $txt=$txt.Trim()
            if ($txt -and -not $txt.StartsWith("ERR:")) {
                [System.Windows.Forms.Clipboard]::SetText($txt)
                (New-Object System.Windows.Forms.ToolTip).Show("Text copied ($($txt.Length) chars)",$btnOCR,0,-28,2200)
            } else { (New-Object System.Windows.Forms.ToolTip).Show("No text found",$btnOCR,0,-28,1800) }
        } elseif ($script:ocrPollN -gt 35) {
            $script:ocrTimer.Stop()
            $btnOCR.BackColor=[System.Drawing.Color]::Magenta; $btnOCR.Refresh()
            $script:ocrBusy=$false
            (New-Object System.Windows.Forms.ToolTip).Show("OCR timed out",$btnOCR,0,-28,2000)
        }
    } catch { $script:ocrTimer.Stop(); $script:ocrBusy=$false; $btnOCR.BackColor=[System.Drawing.Color]::Magenta }
})

$btnOCR.Add_Click({
    try {
        if ($script:ocrBusy) { return }
        $script:ocrBusy=$true; $script:ocrPollN=0
        $btnOCR.BackColor=[System.Drawing.Color]::FromArgb(255,180,90,5); $btnOCR.Refresh()
        $bar.Hide()
        $ocrDelayT = New-Object System.Windows.Forms.Timer; $ocrDelayT.Interval=160
        $ocrDelayT.Add_Tick({
            $ocrDelayT.Stop(); $ocrDelayT.Dispose()
            try {
                $bmp = New-Object System.Drawing.Bitmap($screen.Width,$screen.Height)
                $gfx = [System.Drawing.Graphics]::FromImage($bmp)
                $gfx.CopyFromScreen(0,0,0,0,$bmp.Size); $gfx.Dispose()
                $bmp.Save($script:ocrImgTmp,[System.Drawing.Imaging.ImageFormat]::Png); $bmp.Dispose()
                $bar.Show()
                Remove-Item $script:ocrResTmp -Force -EA SilentlyContinue
                # Build the worker script (uses $script: paths baked-in as literals)
                $ip = $script:ocrImgTmp; $rp = $script:ocrResTmp
                @"
Add-Type -AssemblyName System.Runtime.WindowsRuntime -EA SilentlyContinue
try {
    `$at = ([System.WindowsRuntimeSystemExtensions].GetMethods() |
        Where-Object { `$_.Name -eq 'AsTask' -and `$_.IsGenericMethodDefinition -and `$_.GetParameters().Count -eq 1 }) |
        Select-Object -First 1
    function W(`$o,`$t){ `$m=`$at.MakeGenericMethod(`$t);`$n=`$m.Invoke(`$null,@(`$o));`$n.Wait()|Out-Null;`$n.Result }
    [void][Windows.Media.Ocr.OcrEngine,Windows.Foundation,ContentType=WindowsRuntime]
    [void][Windows.Storage.StorageFile,Windows.Storage,ContentType=WindowsRuntime]
    [void][Windows.Graphics.Imaging.BitmapDecoder,Windows.Foundation,ContentType=WindowsRuntime]
    `$e  = [Windows.Media.Ocr.OcrEngine]::TryCreateFromUserProfileLanguages()
    `$f  = W ([Windows.Storage.StorageFile]::GetFileFromPathAsync('$ip'))  ([Windows.Storage.StorageFile])
    `$s  = W (`$f.OpenAsync([Windows.Storage.FileAccessMode]::Read))       ([Windows.Storage.Streams.IRandomAccessStream])
    `$d  = W ([Windows.Graphics.Imaging.BitmapDecoder]::CreateAsync(`$s)) ([Windows.Graphics.Imaging.BitmapDecoder])
    `$sb = W (`$d.GetSoftwareBitmapAsync())                                ([Windows.Graphics.Imaging.SoftwareBitmap])
    `$r  = W (`$e.RecognizeAsync(`$sb))                                    ([Windows.Media.Ocr.OcrResult])
    `$s.Dispose(); `$r.Text | Out-File '$rp' -Encoding UTF8
} catch { "ERR:`$_" | Out-File '$rp' -Encoding UTF8 }
"@ | Out-File $script:ocrWrkTmp -Encoding UTF8 -Force
                Start-Process powershell.exe -WindowStyle Hidden -ArgumentList "-WindowStyle","Hidden","-ExecutionPolicy","Bypass","-File","`"$($script:ocrWrkTmp)`""
                $script:ocrTimer.Start()
            } catch {
                $bar.Show(); $script:ocrBusy=$false
                $btnOCR.BackColor=[System.Drawing.Color]::Magenta
            }
        })
        $ocrDelayT.Start()
    } catch { $script:ocrBusy=$false; $bar.Show(); $btnOCR.BackColor=[System.Drawing.Color]::Magenta }
})

# ── Drag (threshold prevents accidental drags on quick clicks) ───────────────
$script:drag=$false; $script:dragging=$false; $script:dPt=[System.Drawing.Point]::Empty
foreach ($b in @($btnCap,$btnBrw,$btnOCR)) {
    $b.Add_MouseDown({ param($s,$e)
        if($e.Button -eq [System.Windows.Forms.MouseButtons]::Left){
            $script:drag=$true; $script:dragging=$false; $script:dPt=[System.Windows.Forms.Cursor]::Position
        }
    })
    $b.Add_MouseMove({ param($s,$e)
        if($script:drag){
            $n=[System.Windows.Forms.Cursor]::Position
            if([Math]::Abs($n.X-$script:dPt.X)+[Math]::Abs($n.Y-$script:dPt.Y) -gt 4){ $script:dragging=$true }
            if($script:dragging){ $bar.Left+=$n.X-$script:dPt.X; $bar.Top+=$n.Y-$script:dPt.Y; $script:dPt=$n }
        }
    })
    $b.Add_MouseUp({ param($s,$e); $script:drag=$false })
}

# ── Right-click → Quit (also Ctrl+Shift+Q hotkey registered below) ───────────
$ctxMenu = New-Object System.Windows.Forms.ContextMenuStrip
$quitItem = New-Object System.Windows.Forms.ToolStripMenuItem("Quit Overlay")
$quitItem.ForeColor = [System.Drawing.Color]::FromArgb(255,80,80)
$quitItem.Add_Click({
    try { [HotkeyNW]::UnregisterHotKey($bar.Handle,1) | Out-Null } catch {}
    try { [HotkeyNW]::UnregisterHotKey($bar.Handle,2) | Out-Null } catch {}
    try { [HotkeyNW]::UnregisterHotKey($bar.Handle,3) | Out-Null } catch {}
    try { [HotkeyNW]::UnregisterHotKey($bar.Handle,4) | Out-Null } catch {}
    [System.Windows.Forms.Application]::Exit()
})
$ctxMenu.Items.Add($quitItem) | Out-Null
foreach ($b in @($btnCap,$btnBrw,$btnOCR)) { $b.ContextMenuStrip=$ctxMenu }

$bar.Controls.Add($btnCap);$bar.Controls.Add($btnBrw);$bar.Controls.Add($btnOCR)
$bar.Region=New-Object System.Drawing.Region((New-Object System.Drawing.Rectangle(0,0,$TOTAL_W,$CAP_SIZE)))

$bar.Add_Shown({
    $ex=[OV]::GetWindowLong($bar.Handle,[OV]::GWL_EXSTYLE)
    [OV]::SetWindowLong($bar.Handle,[OV]::GWL_EXSTYLE,$ex -bor [OV]::WS_EX_TOOLWINDOW) | Out-Null
    [OV]::SetWindowPos($bar.Handle,[OV]::HWND_TOPMOST,0,0,0,0,([OV]::SWP_NOMOVE -bor [OV]::SWP_NOSIZE)) | Out-Null
    # Register global hotkeys: Ctrl+Shift+B=browser, Ctrl+Shift+P=screenshot, Ctrl+Shift+T=OCR text
    try {
        $script:hkw = New-Object HotkeyNW($bar.Handle)
        [HotkeyNW]::RegisterHotKey($bar.Handle,1,([HotkeyNW]::CTRL -bor [HotkeyNW]::SHIFT),0x42) | Out-Null  # B
        [HotkeyNW]::RegisterHotKey($bar.Handle,2,([HotkeyNW]::CTRL -bor [HotkeyNW]::SHIFT),0x50) | Out-Null  # P
        [HotkeyNW]::RegisterHotKey($bar.Handle,3,([HotkeyNW]::CTRL -bor [HotkeyNW]::SHIFT),0x54) | Out-Null  # T
    } catch {}
})

# Hotkey polling timer (100ms) — wrapped in try/catch so a missing HotkeyNW type never crashes the app
$hkTimer = New-Object System.Windows.Forms.Timer
$hkTimer.Interval = 100
$hkTimer.Add_Tick({
    try {
        $k = [HotkeyNW]::LastKey
        if ($k -gt 0) {
            [HotkeyNW]::LastKey = 0
            switch ($k) {
                1 { $btnBrw.PerformClick() }   # Ctrl+Shift+B → toggle browser
                2 { $btnCap.PerformClick() }   # Ctrl+Shift+P → screenshot
                3 { $btnOCR.PerformClick() }   # Ctrl+Shift+T → OCR text
            }
        }
    } catch { $hkTimer.Stop() }   # stop timer if HotkeyNW type not available
})
try { $hkTimer.Start() } catch {}

# ── Auto-close when PSITOAS.exe exits (handles Alt+F4, task manager, any close) ───
$script:oasEverSeen = [bool](Get-Process -Name "PSITOAS" -ErrorAction SilentlyContinue)
$watchTimer = New-Object System.Windows.Forms.Timer
$watchTimer.Interval = 2000
$watchTimer.Add_Tick({
    $running = [bool](Get-Process -Name "PSITOAS" -ErrorAction SilentlyContinue)
    if ($running) { $script:oasEverSeen = $true }    # mark first sighting
    if ($script:oasEverSeen -and -not $running) {    # was seen, now gone
        $watchTimer.Stop()
        if ($bForm.Visible) { $bForm.Close() }
        [System.Windows.Forms.Application]::Exit()
    }
})
$watchTimer.Start()

# Suppress unhandled WinForms exceptions from crashing the process
[System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException)
[System.Windows.Forms.Application]::add_ThreadException({ param($s,$e) <# silently swallow #> })

[System.Windows.Forms.Application]::Run($bar)
