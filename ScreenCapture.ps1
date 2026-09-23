Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

try { [System.Windows.Forms.Application]::SetUnhandledExceptionMode([System.Windows.Forms.UnhandledExceptionMode]::CatchException) } catch {}
try { [System.Windows.Forms.Application]::add_ThreadException({ param($s,$e) }) } catch {}

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

# ── AI Answer Engine ─────────────────────────────────────────────────────────
# Load keys from keys.txt next to the script. Format: groq:<key> or openrouter:<key>
$script:aiKeys = @()
$keysFile = Join-Path $PSScriptRoot 'keys.txt'
if (Test-Path $keysFile) {
    Get-Content $keysFile | Where-Object { $_ -notmatch '^\s*#' -and $_.Trim() -ne '' } | ForEach-Object {
        $parts = $_.Trim() -split ':', 2
        if ($parts.Count -eq 2) {
            $script:aiKeys += [PSCustomObject]@{ Provider = $parts[0].Trim().ToLower(); Key = $parts[1].Trim() }
        }
    }
}
$script:aiKeyIndex  = 0
$script:aiLabel     = $null   # floating answer label form
$script:aiTimer     = $null   # auto-hide timer
$script:aiHandle    = $null   # async handle
$script:aiPs        = $null   # PowerShell instance
$script:aiRs        = $null   # Runspace instance
$script:aiPollTimer = $null   # WinForms polling timer
$script:latestOCRText = ""     # stores last captured question text
$script:tabs        = @{}     # tabKey -> @{ Wv = $wv; Url = $url; Btn = $btn }
$script:activeTab   = "Gem"   # currently active tab key

function Invoke-AIAnswer {
    param([string]$QuestionText)
    if ($script:aiKeys.Count -eq 0) { return }

    $prompt = "You are a student taking a multiple-choice exam. Read the question and all options carefully. Reply with ONLY: the answer letter (A, B, C, or D) followed by a dash and a reason of at most 7 words. Example: 'B - Quicksort is not stable'. No extra text."

    # Try each key in rotation, skip on rate limit or error
    $tried = 0
    while ($tried -lt $script:aiKeys.Count) {
        $entry = $script:aiKeys[$script:aiKeyIndex % $script:aiKeys.Count]
        $script:aiKeyIndex++
        $tried++
        try {
            $body = @{
                model    = if ($entry.Provider -eq 'groq') { 'llama-3.1-70b-versatile' } else { 'meta-llama/llama-3.1-70b-instruct:free' }
                messages = @(
                    @{ role = 'system'; content = $prompt }
                    @{ role = 'user';   content = $QuestionText }
                )
                max_tokens  = 40
                temperature = 0.1
            } | ConvertTo-Json -Depth 5

            $url = if ($entry.Provider -eq 'groq') {
                'https://api.groq.com/openai/v1/chat/completions'
            } else {
                'https://openrouter.ai/api/v1/chat/completions'
            }

            $headers = @{
                'Authorization' = "Bearer $($entry.Key)"
                'Content-Type'  = 'application/json'
            }
            if ($entry.Provider -eq 'openrouter') {
                $headers['HTTP-Referer'] = 'https://github.com/Evangelion-eva/PSIT-OAS-Launcher-Modded-'
                $headers['X-Title'] = 'PSIT OAS'
            }

            $resp = Invoke-RestMethod -Uri $url -Method POST -Headers $headers -Body $body -TimeoutSec 12 -ErrorAction Stop
            $answer = $resp.choices[0].message.content.Trim()
            return $answer
        } catch {
            # 429 = rate limit, try next key; anything else also try next
            continue
        }
    }
    return $null
}

function Show-AIAnswer {
    param([string]$Answer)
    if (-not $Answer) { return }

    if ($script:aiTimer) { try { $script:aiTimer.Stop(); $script:aiTimer.Dispose() } catch {}; $script:aiTimer = $null }
    if ($script:aiLabel) { try { $script:aiLabel.Close(); $script:aiLabel.Dispose() } catch {}; $script:aiLabel = $null }

        # Clean markdown and formatting (preserve math asterisks)
    $cleanRaw = $Answer.Replace('**', '').Replace('`', '').Trim()
    $lines = ($cleanRaw -split "`r?`n") | ForEach-Object { $_.Trim() } | Where-Object { $_ -ne '' }

    $displayText = ""

    # Priority 1: Check for explicit "correct (answer|option) is X" or "Ans: X"
    foreach ($line in $lines) {
        if ($line -match '(?i)(?:correct\s+(?:option|answer|choice)\s+(?:is\s*)?[:\-]?\s*|^Ans(?:wer)?\s*[:\-]\s*)([A-D]\s*[\)\.\:\-]?\s*\(?[^
]+)') {
            $displayText = "Ans: " + $matches[1].Trim().TrimEnd('.')
            break
        }
    }

    # Priority 2: Line starting with option letter, e.g. "B (O(N log N)...)" or "C (Diamond)"
    if (-not $displayText) {
        foreach ($line in $lines) {
            if ($line -match '^([A-D]\s*[\)\.\:\-]\s*.+)$' -or $line -match '^([A-D]\s*\([^
]+\))$') {
                $displayText = "Ans: " + $matches[1].Trim().TrimEnd('.')
                break
            }
        }
    }

    # Priority 3: Standalone 'X (Option Text)' anywhere in line
    if (-not $displayText) {
        foreach ($line in $lines) {
            if ($line -match '\b([A-D]\s*\([^
]+\))') {
                $displayText = "Ans: " + $matches[1].Trim().TrimEnd('.')
                break
            }
        }
    }

    # Priority 4: Line starting with an option letter like "B" or "B. Something"
    if (-not $displayText) {
        foreach ($line in $lines) {
            if ($line -match '^[A-D]\b') {
                $displayText = "Ans: " + $line.TrimEnd('.')
                break
            }
        }
    }

    # Priority 4: Flexible fallback - if no standard option letter found, preserve full answer without cropping!
    if (-not $displayText) {
        $filteredLines = @()
        $skipPhrases = @('here is', 'the correct', 'based on', 'i think', 'sure', 'hello', 'question:')
        foreach ($line in $lines) {
            $lower = $line.ToLower()
            $skip = $false
            if ($lines.Count -gt 1) {
                foreach ($sp in $skipPhrases) {
                    if ($lower.StartsWith($sp)) { $skip = $true; break }
                }
            }
            if (-not $skip) { $filteredLines += $line }
        }
        $fullText = ($filteredLines -join " ").Trim()
        if (-not $fullText) { $fullText = $cleanRaw }
        $displayText = if ($fullText -match '^(Ans\s*[:\-])') { $fullText } else { "Ans: $fullText" }
    }

    $scr = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds

    # Normal regular text - clean, natural, not bold
    $font = New-Object System.Drawing.Font('Segoe UI', 10.5, [System.Drawing.FontStyle]::Regular)

    # Flexible container sizing with WordBreak - expands dynamically for long answers without cropping
    $maxW = [Math]::Min(720, [int]($scr.Width * 0.65))
    $flags = [System.Windows.Forms.TextFormatFlags]::WordBreak -bor [System.Windows.Forms.TextFormatFlags]::LeftAndRightPadding
    $size = [System.Windows.Forms.TextRenderer]::MeasureText($displayText, $font, (New-Object System.Drawing.Size($maxW, 0)), $flags)

    $ansW = [Math]::Min($maxW, [int]($size.Width + 16))
    $ansH = [int]($size.Height + 8)

    # Dynamic positioning for any screen resolution
    $ansX = [Math]::Max(36, [int]($scr.Width * 0.03))
    $ansY = [Math]::Max(360, [int]($scr.Height * 0.57))
    # Prevent overflowing off screen bottom
    if ($ansY + $ansH -gt ($scr.Height - 35)) {
        $ansY = [Math]::Max(50, [int]($scr.Height - $ansH - 45))
    }

    $af = New-Object System.Windows.Forms.Form
    $af.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
    $af.BackColor       = [System.Drawing.Color]::White
    $af.TransparencyKey = [System.Drawing.Color]::White
    $af.TopMost         = $true
    $af.ShowInTaskbar   = $false
    $af.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
    $af.Width           = $ansW
    $af.Height          = $ansH
    $af.Location        = New-Object System.Drawing.Point($ansX, $ansY)

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text        = $displayText
    $lbl.Dock        = [System.Windows.Forms.DockStyle]::Fill
    $lbl.Font        = $font
    $lbl.ForeColor   = [System.Drawing.Color]::FromArgb(25, 25, 25)
    $lbl.BackColor   = [System.Drawing.Color]::White
    $lbl.TextAlign   = [System.Drawing.ContentAlignment]::TopLeft
    $lbl.Padding     = New-Object System.Windows.Forms.Padding(4, 2, 4, 2)
    $lbl.BorderStyle = [System.Windows.Forms.BorderStyle]::None
    $lbl.Cursor      = [System.Windows.Forms.Cursors]::Hand

    # Click on the text to dismiss it immediately
    $dismissAction = {
        if ($script:aiTimer) { try { $script:aiTimer.Stop(); $script:aiTimer.Dispose() } catch {}; $script:aiTimer = $null }
        if ($script:aiLabel) { try { $script:aiLabel.Close(); $script:aiLabel.Dispose() } catch {}; $script:aiLabel = $null }
    }
    $af.Add_Click($dismissAction)
    $af.Add_MouseDown($dismissAction)
    $lbl.Add_Click($dismissAction)
    $lbl.Add_MouseDown($dismissAction)

    $af.Controls.Add($lbl)

    $af.Show()
    # WS_EX_TOOLWINDOW (0x80) + WS_EX_NOACTIVATE (0x08000000 = Never steal focus from browser)
    $ex = [OV]::GetWindowLong($af.Handle, [OV]::GWL_EXSTYLE)
    [OV]::SetWindowLong($af.Handle, [OV]::GWL_EXSTYLE, $ex -bor [OV]::WS_EX_TOOLWINDOW -bor 0x08000000) | Out-Null
    [OV]::SetWindowPos($af.Handle, [OV]::HWND_TOPMOST, 0, 0, 0, 0, ([OV]::SWP_NOMOVE -bor [OV]::SWP_NOSIZE)) | Out-Null
    $script:aiLabel = $af

    # Auto-hide after 35 seconds (next question press replaces it sooner)
    $t = New-Object System.Windows.Forms.Timer
    $t.Interval = 35000
    $t.Add_Tick({
        param($sender, $args)
        $sender.Stop(); $sender.Dispose()
        if ($script:aiLabel) {
            try { $script:aiLabel.Close(); $script:aiLabel.Dispose() } catch {}
            $script:aiLabel = $null
        }
    })
    $t.Start()
    $script:aiTimer = $t
}

# ── Layout constants ──────────────────────────────────────────────────────────
$CAP_SIZE = 16; $BRW_SIZE = 16; $OCR_SIZE = 16; $GAP = 5
$TOTAL_W  = $CAP_SIZE + $GAP + $BRW_SIZE + $GAP + $OCR_SIZE
$screen   = [System.Windows.Forms.Screen]::PrimaryScreen.Bounds
$script:bVisible = $false
$BW_W = 420; $BW_H = 460

# ── Browser window ────────────────────────────────────────────────────────────
$bForm = New-Object System.Windows.Forms.Form
$bForm.FormBorderStyle = [System.Windows.Forms.FormBorderStyle]::None
$bForm.Size            = New-Object System.Drawing.Size($BW_W, $BW_H)
$bForm.MinimumSize     = New-Object System.Drawing.Size(260, 220)
$bForm.TopMost         = $true
$bForm.ShowInTaskbar   = $false
$bForm.StartPosition   = [System.Windows.Forms.FormStartPosition]::Manual
$bForm.BackColor       = [System.Drawing.Color]::FromArgb(24, 24, 34)
$bForm.Location        = New-Object System.Drawing.Point(
    [int](($screen.Width - $BW_W) / 2),
    [int]($screen.Height - $BW_H - $TOTAL_W - 62)
)
$script:isQuitting = $false
$bForm.Add_FormClosing({
    param($s,$e)
    if ($script:isQuitting) { return }
    $e.Cancel = $true
    $bForm.Hide()
    $script:bVisible = $false
})

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
$grn = [System.Drawing.Color]::FromArgb(24,128,56)
$pur = [System.Drawing.Color]::FromArgb(110,50,180)

$tBack = MakeTBtn "<"    3  22 $dk
$tFwd  = MakeTBtn ">"   27  22 $dk
$tRld  = MakeTBtn "R"   51  22 $dk

$tURL  = New-Object System.Windows.Forms.TextBox
$tURL.Location=New-Object System.Drawing.Point(75,7); $tURL.Size=New-Object System.Drawing.Size(155,20)
$tURL.BackColor=[System.Drawing.Color]::FromArgb(46,46,64); $tURL.ForeColor=[System.Drawing.Color]::White
$tURL.BorderStyle=[System.Windows.Forms.BorderStyle]::FixedSingle
$tURL.Font=New-Object System.Drawing.Font("Segoe UI",8); $tURL.Text="https://gemini.google.com"

$tGo      = MakeTBtn "Go"   232 24 $bl
$tAddQ    = MakeTBtn "+Q"   258 26 $grn
$tAddLink = MakeTBtn "+Link" 286 42 $pur
$tZin     = MakeTBtn "+"    330 20 $dk
$zoomLbl  = New-Object System.Windows.Forms.Label
$zoomLbl.Text = "100%"
$zoomLbl.Location = New-Object System.Drawing.Point(352, 8)
$zoomLbl.Size     = New-Object System.Drawing.Size(26, 18)
$zoomLbl.ForeColor = [System.Drawing.Color]::FromArgb(180,180,210)
$zoomLbl.Font     = New-Object System.Drawing.Font("Segoe UI",6,[System.Drawing.FontStyle]::Bold)
$zoomLbl.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$tZout    = MakeTBtn "-"    380 20 $dk

$tbTip = New-Object System.Windows.Forms.ToolTip
$tbTip.SetToolTip($tAddQ, "Paste OCR Question text into Chat")
$tbTip.SetToolTip($tAddLink, "Paste current URL into Chat")

$tb.Controls.AddRange(@($tBack,$tFwd,$tRld,$tURL,$tGo,$tAddQ,$tAddLink,$tZin,$zoomLbl,$tZout))

# ── Drag handle (title bar area) ──────────────────────────────────────────────
$dragLbl = New-Object System.Windows.Forms.Label
$dragLbl.Text="  Browser (Tabs)"; $dragLbl.Size=New-Object System.Drawing.Size(0,26)
$dragLbl.Dock=[System.Windows.Forms.DockStyle]::Fill
$dragLbl.ForeColor=[System.Drawing.Color]::FromArgb(160,160,190)
$dragLbl.Font=New-Object System.Drawing.Font("Segoe UI",8,[System.Drawing.FontStyle]::Bold)
$dragLbl.TextAlign=[System.Drawing.ContentAlignment]::MiddleLeft
$dragLbl.SendToBack()

$closeBtn = MakeTBtn "X" 0 0 $rd
$closeBtn.Size=New-Object System.Drawing.Size(28,26); $closeBtn.Location=New-Object System.Drawing.Point(([int]$BW_W-28),0)
$closeBtn.FlatAppearance.BorderSize=0; $closeBtn.Dock=[System.Windows.Forms.DockStyle]::None

$minBtn = MakeTBtn "-" 0 0 ([System.Drawing.Color]::FromArgb(60,60,80))
$minBtn.Size=New-Object System.Drawing.Size(28,26); $minBtn.Location=New-Object System.Drawing.Point(([int]$BW_W-56),0)
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
        $nw=[Math]::Max(260,$bForm.Width+$n.X-$script:rPt.X)
        $nh=[Math]::Max(220,$bForm.Height+$n.Y-$script:rPt.Y)
        $bForm.Size=New-Object System.Drawing.Size($nw,$nh)
        $closeBtn.Location=New-Object System.Drawing.Point($bForm.Width-28,0)
        $minBtn.Location=New-Object System.Drawing.Point($bForm.Width-56,0)
        $script:rPt=$n
    }
})
$grip.Add_MouseUp({ $script:rDrag=$false })

# ── WebView2 Multi-Tab Host Panel ─────────────────────────────────────────────
$wvHost = New-Object System.Windows.Forms.Panel
$wvHost.Dock = [System.Windows.Forms.DockStyle]::Fill

$script:tabs = @{}
$script:activeTab = ""

$script:wvEnvProps = New-Object Microsoft.Web.WebView2.WinForms.CoreWebView2CreationProperties
$script:wvEnvProps.UserDataFolder = "$env:TEMP\OAS_WV2"

function Get-ActiveWv {
    if ($script:tabs -and $script:tabs.ContainsKey($script:activeTab)) {
        return $script:tabs[$script:activeTab].Wv
    }
    return $null
}

# ── AI Shortcuts Tabs Bar ─────────────────────────────────────────────────────
$aiBar = New-Object System.Windows.Forms.Panel
$aiBar.Dock      = [System.Windows.Forms.DockStyle]::Top
$aiBar.Height    = 28
$aiBar.BackColor = [System.Drawing.Color]::FromArgb(20, 20, 32)
$aiTip = New-Object System.Windows.Forms.ToolTip

$script:aiList = @(
    @{L="Gem";   C=[System.Drawing.Color]::FromArgb(66,103,212);  U="https://gemini.google.com";                                        T="Google Gemini"},
    @{L="Ael";   C=[System.Drawing.Color]::FromArgb(90,40,180);   U="https://aeliusai.com/";                                            T="Aelius AI (Images & PDFs)"},
    @{L="Ima";   C=[System.Drawing.Color]::FromArgb(210,70,50);   U="https://imastudio.com/chat-with-image";                           T="Ima Studio (Chat with Image)"},
    @{L="Pix";   C=[System.Drawing.Color]::FromArgb(40,160,180);  U="https://pixpal.chat/";                                             T="PixPal (Chat & Images)"},
    @{L="Jolly"; C=[System.Drawing.Color]::FromArgb(220,130,20);  U="https://jollyai.online/models/ai-chatbot-unlimited-messages.php"; T="JollyAI (Unlimited Chat)"},
    @{L="Duck";  C=[System.Drawing.Color]::FromArgb(222,88,51);   U="https://duck.ai/";                                                T="Duck.ai"},
    @{L="Yia";   C=[System.Drawing.Color]::FromArgb(50,140,90);   U="https://www.yiaho.com/en/";                                        T="Yiaho AI"}
)

function Switch-BrowserTab($tabKey, $tabUrl) {
    if (-not $script:tabs.ContainsKey($tabKey)) {
        $newWv = New-Object Microsoft.Web.WebView2.WinForms.WebView2
        $newWv.Dock = [System.Windows.Forms.DockStyle]::Fill
        $newWv.CreationProperties = $script:wvEnvProps
        $newWv.Tag = @{ Key = $tabKey; Url = $tabUrl }
        $newWv.Add_CoreWebView2InitializationCompleted({
            param($s,$e)
            if ($e.IsSuccess) {
                $tag = $s.Tag
                $s.CoreWebView2.Settings.AreDefaultContextMenusEnabled  = $true
                $s.CoreWebView2.Settings.IsStatusBarEnabled             = $false
                $s.CoreWebView2.Settings.IsZoomControlEnabled           = $true
                if ($tag -and $tag.Url) {
                    $s.CoreWebView2.Navigate($tag.Url)
                }
            }
        })
        $newWv.Add_NavigationCompleted({
            param($s,$e)
            if ($s.Tag -and $script:activeTab -eq $s.Tag.Key -and $s.Source) {
                $tURL.Text = $s.Source.AbsoluteUri
            }
        })
        $wvHost.Controls.Add($newWv)
        $newWv.EnsureCoreWebView2Async($null) | Out-Null
        $script:tabs[$tabKey] = @{ Wv = $newWv; Url = $tabUrl; Key = $tabKey }
    }

    $script:activeTab = $tabKey

    foreach ($k in $script:tabs.Keys) {
        $entry = $script:tabs[$k]
        if ($k -eq $tabKey) {
            $entry.Wv.Visible = $true
            $entry.Wv.BringToFront()
            if ($entry.Wv.Source) {
                $tURL.Text = $entry.Wv.Source.AbsoluteUri
            } elseif ($entry.Url) {
                $tURL.Text = $entry.Url
            }
        } else {
            $entry.Wv.Visible = $false
        }
    }

    # Update tab button borders to reflect active tab
    foreach ($ctl in $aiBar.Controls) {
        if ($ctl.Tag -and $ctl.Tag.Key -eq $tabKey) {
            $ctl.FlatAppearance.BorderColor = [System.Drawing.Color]::White
            $ctl.FlatAppearance.BorderSize  = 2
        } else {
            $ctl.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(55,55,75)
            $ctl.FlatAppearance.BorderSize  = 1
        }
    }
}

$ax = 4
foreach ($ai in $script:aiList) {
    $ab = New-Object System.Windows.Forms.Button
    $ab.Text     = $ai.L
    $ab.Size     = New-Object System.Drawing.Size(46, 22)
    $ab.Location = New-Object System.Drawing.Point($ax, 3)
    $ab.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $ab.FlatAppearance.BorderSize  = 1
    $ab.FlatAppearance.BorderColor = [System.Drawing.Color]::FromArgb(55,55,75)
    $ab.BackColor = $ai.C
    $ab.ForeColor = [System.Drawing.Color]::White
    $ab.Font      = New-Object System.Drawing.Font("Segoe UI", 7.5, [System.Drawing.FontStyle]::Bold)
    $ab.Cursor    = [System.Windows.Forms.Cursors]::Hand
    $ab.Tag       = @{ Key = $ai.L; Url = $ai.U }
    $aiTip.SetToolTip($ab, $ai.T)
    $ab.Add_Click({
        param($s,$e)
        if ($s.Tag) {
            Switch-BrowserTab $s.Tag.Key $s.Tag.Url
        }
    })
    $aiBar.Controls.Add($ab)
    $ax += 48
}

# ── Toolbar Actions for Active Tab ────────────────────────────────────────────
$tBack.Add_Click({ $w = Get-ActiveWv; if($w -and $w.CoreWebView2){ $w.CoreWebView2.GoBack() } })
$tFwd.Add_Click({  $w = Get-ActiveWv; if($w -and $w.CoreWebView2){ $w.CoreWebView2.GoForward() } })
$tRld.Add_Click({  $w = Get-ActiveWv; if($w -and $w.CoreWebView2){ $w.CoreWebView2.Reload() } })
$tGo.Add_Click({
    $w = Get-ActiveWv
    $raw = $tURL.Text.Trim()
    if ($raw -match '^https?://') { $url = $raw }
    elseif ($raw -match '^(localhost|[a-zA-Z0-9][a-zA-Z0-9\-]*(\.[a-zA-Z]{2,})+)(:[0-9]+)?(/.*)?$') { $url = "https://$raw" }
    else { $url = "https://www.google.com/search?q=" + [Uri]::EscapeDataString($raw) }
    if ($w -and $w.CoreWebView2) { $w.CoreWebView2.Navigate($url) }
})

$tURL.Add_KeyDown({
    param($s,$e)
    if ($e.Control -and $e.KeyCode -eq [System.Windows.Forms.Keys]::A) {
        $tURL.SelectAll(); $e.Handled=$true; $e.SuppressKeyPress=$true
    } elseif ($e.KeyCode -eq [System.Windows.Forms.Keys]::Return) {
        $tGo.PerformClick(); $e.Handled=$true; $e.SuppressKeyPress=$true
    }
})

$tZin.Add_Click({  $w = Get-ActiveWv; if($w -and $w.CoreWebView2){ $w.ZoomFactor=[Math]::Min(3.0,$w.ZoomFactor+0.25); $zoomLbl.Text=[int]($w.ZoomFactor*100)+"%" } })
$tZout.Add_Click({ $w = Get-ActiveWv; if($w -and $w.CoreWebView2){ $w.ZoomFactor=[Math]::Max(0.25,$w.ZoomFactor-0.25); $zoomLbl.Text=[int]($w.ZoomFactor*100)+"%" } })

# Paste OCR Question directly into active chat box
$tAddQ.Add_Click({
    $w = Get-ActiveWv
    if ($w -and $w.CoreWebView2 -and $script:latestOCRText) {
        [System.Windows.Forms.Clipboard]::SetText($script:latestOCRText)
        $qEsc = $script:latestOCRText.Replace('\', '\\').Replace('"', '\"').Replace("`r", '').Replace("`n", '\n')
        $js = @"
(function() {
    let t = "$qEsc";
    let el = document.activeElement;
    if (!el || el === document.body || el.tagName === 'IFRAME') {
        el = document.querySelector('textarea, div[contenteditable="true"], input[type="text"], [role="textbox"]');
    }
    if (el) {
        el.focus();
        if (el.isContentEditable) {
            el.innerText = (el.innerText ? el.innerText + ' ' : '') + t;
        } else {
            el.value = (el.value ? el.value + ' ' : '') + t;
        }
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
    }
})();
"@
        $w.CoreWebView2.ExecuteScriptAsync($js) | Out-Null
        (New-Object System.Windows.Forms.ToolTip).Show("Question pasted into chat!", $tAddQ, 0, -26, 1600)
    } elseif (-not $script:latestOCRText) {
        (New-Object System.Windows.Forms.ToolTip).Show("No OCR question captured yet", $tAddQ, 0, -26, 1600)
    }
})

# Paste URL directly into active chat box
$tAddLink.Add_Click({
    $w = Get-ActiveWv
    if ($w -and $w.CoreWebView2) {
        $u = $w.CoreWebView2.Source
        if ($u) {
            [System.Windows.Forms.Clipboard]::SetText($u)
            $uEsc = $u.Replace('\', '\\').Replace('"', '\"')
            $js = @"
(function() {
    let t = "$uEsc";
    let el = document.activeElement;
    if (!el || el === document.body || el.tagName === 'IFRAME') {
        el = document.querySelector('textarea, div[contenteditable="true"], input[type="text"], [role="textbox"]');
    }
    if (el) {
        el.focus();
        if (el.isContentEditable) {
            el.innerText = (el.innerText ? el.innerText + ' ' : '') + t;
        } else {
            el.value = (el.value ? el.value + ' ' : '') + t;
        }
        el.dispatchEvent(new Event('input', { bubbles: true }));
        el.dispatchEvent(new Event('change', { bubbles: true }));
    }
})();
"@
            $w.CoreWebView2.ExecuteScriptAsync($js) | Out-Null
            (New-Object System.Windows.Forms.ToolTip).Show("URL pasted into chat!", $tAddLink, 0, -26, 1600)
        }
    }
})

# Drag title bar
foreach ($ctl in @($titleBar,$dragLbl)) {
    $ctl.Add_MouseDown({
        param($s,$e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            [OV]::ReleaseCapture() | Out-Null
            [OV]::SendMessage($bForm.Handle, [OV]::WM_NCLBUTTONDOWN, ([IntPtr]([OV]::HTCAPTION)), [IntPtr]::Zero) | Out-Null
        }
    })
}

# ── Left / Right edge resize panels ───────────────────────────────────────────
$rRight = New-Object System.Windows.Forms.Panel
$rRight.Width=5; $rRight.Dock=[System.Windows.Forms.DockStyle]::Right
$rRight.BackColor=[System.Drawing.Color]::FromArgb(24,24,34)
$rRight.Cursor=[System.Windows.Forms.Cursors]::SizeWE
$script:rrDrag=$false; $script:rrPt=[System.Drawing.Point]::Empty
$rRight.Add_MouseDown({ $script:rrDrag=$true; $script:rrPt=[System.Windows.Forms.Cursor]::Position })
$rRight.Add_MouseMove({
    if($script:rrDrag){
        $n=[System.Windows.Forms.Cursor]::Position
        $nw=[Math]::Max(260,$bForm.Width+$n.X-$script:rrPt.X)
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
        $nw=[Math]::Max(260,$script:rlW-$delta)
        $bForm.Left=$script:rlLeft+($script:rlW-$nw)
        $bForm.Width=$nw
        $closeBtn.Location=New-Object System.Drawing.Point($bForm.Width-28,0)
        $minBtn.Location=New-Object System.Drawing.Point($bForm.Width-56,0)
        $script:rlPt=$n
    }
})
$rLeft.Add_MouseUp({ $script:rlDrag=$false })

# Assemble browser form
$bForm.Controls.Add($wvHost)    # multi-tab host fill
$bForm.Controls.Add($grip)      # bottom strip
$bForm.Controls.Add($rRight)    # right resize edge
$bForm.Controls.Add($rLeft)     # left resize edge
$bForm.Controls.Add($aiBar)     # AI shortcuts tab row
$bForm.Controls.Add($tb)        # toolbar
$bForm.Controls.Add($titleBar)  # title bar (top)

$bForm.Add_Shown({
    Switch-BrowserTab "Gem" "https://gemini.google.com"
    try { $null = New-Object ResizableNW($bForm, 6) } catch { }
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

# Hover tooltips for the three circles
$hoverTip = New-Object System.Windows.Forms.ToolTip
$hoverTip.InitialDelay = 400
$hoverTip.ReshowDelay = 200

$btnCap=MakeCircle 0 $CAP_SIZE ([System.Drawing.Color]::FromArgb(255,80,145,255)) ([System.Drawing.Color]::FromArgb(255,20,65,210))
$hoverTip.SetToolTip($btnCap, "Screenshot -> Clipboard (Ctrl+Shift+P)")
$script:ssTimer = $null
$btnCap.Add_Click({
    if ($script:suppressClick) { $script:suppressClick = $false; return }
    try {
        $bar.Hide()
        if ($script:ssTimer) { try { $script:ssTimer.Stop(); $script:ssTimer.Dispose() } catch {} }
        $script:ssTimer = New-Object System.Windows.Forms.Timer
        $script:ssTimer.Interval = 180
        $script:ssTimer.Add_Tick({
            param($sender, $args)
            try { $sender.Stop(); $sender.Dispose() } catch {}
            $script:ssTimer = $null
            try {
                $bmp = New-Object System.Drawing.Bitmap($screen.Width, $screen.Height)
                $gfx = [System.Drawing.Graphics]::FromImage($bmp)
                $gfx.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
                $gfx.Dispose()
                [System.Windows.Forms.Clipboard]::SetDataObject($bmp, $true)
                $bmp.Dispose()
                $bar.Show()
                [OV]::SetWindowPos($bar.Handle, [OV]::HWND_TOPMOST, 0, 0, 0, 0, ([OV]::SWP_NOMOVE -bor [OV]::SWP_NOSIZE)) | Out-Null
                (New-Object System.Windows.Forms.ToolTip).Show("Screenshot copied!", $btnCap, 0, -24, 1500)
            } catch {
                $bar.Show()
            }
        })
        $script:ssTimer.Start()
    } catch {
        $bar.Show()
    }
})

$btnBrw=MakeCircle ($CAP_SIZE+$GAP) $BRW_SIZE ([System.Drawing.Color]::FromArgb(255,60,180,100)) ([System.Drawing.Color]::FromArgb(255,20,120,55))
$hoverTip.SetToolTip($btnBrw, "Toggle Browser (Ctrl+Shift+B)")
$btnBrw.Add_Click({
    if ($script:suppressClick) { $script:suppressClick = $false; return }
    try {
        if ($script:bVisible -and $bForm.Visible -and $bForm.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized) {
            $bForm.Hide()
            $script:bVisible = $false
        } else {
            if ($bForm.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) {
                $bForm.WindowState = [System.Windows.Forms.FormWindowState]::Normal
            }
            if (!$bForm.Visible) {
                $bForm.Show()
                $w = Get-ActiveWv
                if ($w) { $w.EnsureCoreWebView2Async($null) | Out-Null }
                else { Switch-BrowserTab "Gem" "https://gemini.google.com" }
            }
            $bForm.BringToFront()
            [OV]::SetWindowPos($bForm.Handle, [OV]::HWND_TOPMOST, 0, 0, 0, 0, ([OV]::SWP_NOMOVE -bor [OV]::SWP_NOSIZE)) | Out-Null
            $ex = [OV]::GetWindowLong($bForm.Handle, [OV]::GWL_EXSTYLE)
            [OV]::SetWindowLong($bForm.Handle, [OV]::GWL_EXSTYLE, ($ex -bor [OV]::WS_EX_TOOLWINDOW) -band (-bnot [OV]::WS_EX_APPWINDOW)) | Out-Null
            $script:bVisible = $true
        }
    } catch {}
})

# ── OCR button — isolated subprocess, all vars $script: so timer tick can see them ──
$btnOCR = MakeCircle ($CAP_SIZE+$GAP+$BRW_SIZE+$GAP) $OCR_SIZE ([System.Drawing.Color]::FromArgb(255,230,130,20)) ([System.Drawing.Color]::FromArgb(255,160,70,5))
$hoverTip.SetToolTip($btnOCR, "Extract Screen Text -> Clipboard (Ctrl+Shift+T)")
$script:ocrBusy   = $false
$script:ocrDelayT = $null
$script:ocrImgTmp = [IO.Path]::Combine($env:TEMP, "oas_img_$PID.png")
$script:ocrResTmp = [IO.Path]::Combine($env:TEMP, "oas_res_$PID.txt")
$script:ocrWrkTmp = [IO.Path]::Combine($env:TEMP, "oas_wkr_$PID.ps1")
$script:ocrPollN  = 0
$script:ocrTimer  = New-Object System.Windows.Forms.Timer
$script:ocrTimer.Interval = 400
$script:ocrTimer.Add_Tick({
    param($sender, $args)
    try {
        $script:ocrPollN++
        if (Test-Path $script:ocrResTmp) {
            $sender.Stop()
            $txt = (Get-Content $script:ocrResTmp -Raw -Encoding UTF8 -ErrorAction SilentlyContinue) + ""
            Remove-Item $script:ocrResTmp, $script:ocrImgTmp, $script:ocrWrkTmp -Force -EA SilentlyContinue
            $btnOCR.BackColor = [System.Drawing.Color]::Magenta
            $btnOCR.Refresh()
            $script:ocrBusy = $false
            $txt = $txt.Trim()
            if ($txt -and -not $txt.StartsWith("ERR:")) {
                $script:latestOCRText = $txt
                [System.Windows.Forms.Clipboard]::SetText($txt)
                (New-Object System.Windows.Forms.ToolTip).Show("Text copied - asking AI...", $btnOCR, 0, -28, 2200)
                # Fire AI answer in a background runspace so UI stays responsive (PS5 compatible)
                if ($script:aiKeys.Count -gt 0) {
                    $capturedTxt  = $txt
                    $capturedKeys = $script:aiKeys
                    $capturedIdx  = $script:aiKeyIndex
                    $rs = [System.Management.Automation.Runspaces.RunspaceFactory]::CreateRunspace()
                    $rs.ApartmentState = 'STA'
                    $rs.ThreadOptions  = 'ReuseThread'
                    $rs.Open()
                    $rs.SessionStateProxy.SetVariable('capturedTxt', $capturedTxt)
                    $rs.SessionStateProxy.SetVariable('aiKeys',      $capturedKeys)
                    $rs.SessionStateProxy.SetVariable('aiKeyIndex',  $capturedIdx)
                    $ps = [System.Management.Automation.PowerShell]::Create()
                    $ps.Runspace = $rs
                    $ps.AddScript({
                        function Invoke-AIAnswerLocal {
                            param([string]$Q)
                            $prompt = "You are an automated multiple-choice exam solver. Carefully read the question and options provided. Determine the single correct option. Your entire output MUST strictly be ONLY the option letter and its exact text formatted as: X (Option Text). Example: 'B (RAM)' or 'C (Diamond)'. Do NOT include any explanations, markdown, quotes, prefixes, or conversational text. Output exactly this format on one line."
                            $idx = $aiKeyIndex; $tried = 0
                            while ($tried -lt $aiKeys.Count) {
                                $entry = $aiKeys[$idx % $aiKeys.Count]; $idx++; $tried++
                                try {
                                    $modelName = if ($entry.Provider -eq 'groq') { 'qwen/qwen3.8-27b' } else { 'openrouter/free' }
                                    $body = @{
                                        model       = $modelName
                                        messages    = @(@{ role='system'; content=$prompt },@{ role='user'; content=$Q })
                                        max_tokens  = 250
                                        temperature = 0.1
                                    } | ConvertTo-Json -Depth 5
                                    $url = if ($entry.Provider -eq 'groq') { 'https://api.groq.com/openai/v1/chat/completions' } else { 'https://openrouter.ai/api/v1/chat/completions' }
                                    $hdrs = @{ 'Authorization'="Bearer $($entry.Key)"; 'Content-Type'='application/json' }
                                    if ($entry.Provider -eq 'openrouter') { $hdrs['HTTP-Referer']='https://github.com/Evangelion-eva/PSIT-OAS-Launcher-Modded-'; $hdrs['X-Title']='PSIT OAS' }
                                    $resp = Invoke-RestMethod -Uri $url -Method POST -Headers $hdrs -Body $body -TimeoutSec 10 -ErrorAction Stop
                                    $rawAns = $null
                                    if ($resp -and $resp.choices -and $resp.choices.Count -gt 0) {
                                        $msg = $resp.choices[0].message
                                        if ($msg.content) {
                                            $rawAns = [string]$msg.content
                                        } elseif ($msg.reasoning) {
                                            $rawAns = [string]$msg.reasoning
                                        }
                                    }
                                    if ($rawAns) {
                                        return $rawAns.Trim()
                                    }
                                } catch { continue }
                            }
                            return $null
                        }
                        Invoke-AIAnswerLocal -Q $capturedTxt
                    }) | Out-Null
                    $script:aiRs = $rs
                    $script:aiPs = $ps
                    $script:aiHandle = $ps.BeginInvoke()
                    if ($script:aiPollTimer) {
                        try { $script:aiPollTimer.Stop(); $script:aiPollTimer.Dispose() } catch {}
                        $script:aiPollTimer = $null
                    }
                    $script:aiPollTimer = New-Object System.Windows.Forms.Timer
                    $script:aiPollTimer.Interval = 60
                    $script:aiPollTimer.Add_Tick({
                        param($snd, $ev)
                        try {
                            if ($script:aiHandle -and $script:aiHandle.IsCompleted) {
                                $snd.Stop(); $snd.Dispose()
                                $script:aiPollTimer = $null
                                $result = $script:aiPs.EndInvoke($script:aiHandle)
                                $ans = $result | Select-Object -Last 1
                                if ($ans) {
                                    Show-AIAnswer -Answer ([string]$ans)
                                }
                                try { $script:aiPs.Dispose() } catch {}
                                try { $script:aiRs.Close(); $script:aiRs.Dispose() } catch {}
                                $script:aiHandle = $null
                                $script:aiPs     = $null
                                $script:aiRs     = $null
                            }
                        } catch {
                            try { $snd.Stop(); $snd.Dispose() } catch {}
                            $script:aiPollTimer = $null
                        }
                    })
                    $script:aiPollTimer.Start()
                    $script:aiKeyIndex = ($capturedIdx + 1) % [Math]::Max(1, $script:aiKeys.Count)
                }
            } else {
                (New-Object System.Windows.Forms.ToolTip).Show("No text found", $btnOCR, 0, -28, 1800)
            }
        } elseif ($script:ocrPollN -gt 40) {
            $sender.Stop()
            Remove-Item $script:ocrResTmp, $script:ocrImgTmp, $script:ocrWrkTmp -Force -EA SilentlyContinue
            $btnOCR.BackColor = [System.Drawing.Color]::Magenta
            $btnOCR.Refresh()
            $script:ocrBusy = $false
            (New-Object System.Windows.Forms.ToolTip).Show("OCR timed out", $btnOCR, 0, -28, 2000)
        }
    } catch {
        try { $sender.Stop() } catch {}
        $script:ocrBusy = $false
        $btnOCR.BackColor = [System.Drawing.Color]::Magenta
    }
})

$btnOCR.Add_Click({
    if ($script:suppressClick) { $script:suppressClick = $false; return }
    try {
        if ($script:ocrBusy) { return }
        $script:ocrBusy = $true
        $script:ocrPollN = 0
        $btnOCR.BackColor = [System.Drawing.Color]::FromArgb(255,180,90,5)
        $btnOCR.Refresh()
        $bar.Hide()
        if ($script:ocrDelayT) { try { $script:ocrDelayT.Stop(); $script:ocrDelayT.Dispose() } catch {} }
        $script:ocrDelayT = New-Object System.Windows.Forms.Timer
        $script:ocrDelayT.Interval = 180
        $script:ocrDelayT.Add_Tick({
            param($sender, $args)
            try { $sender.Stop(); $sender.Dispose() } catch {}
            $script:ocrDelayT = $null
            try {
                $bmp = New-Object System.Drawing.Bitmap($screen.Width, $screen.Height)
                $gfx = [System.Drawing.Graphics]::FromImage($bmp)
                $gfx.CopyFromScreen(0, 0, 0, 0, $bmp.Size)
                $gfx.Dispose()
                $bmp.Save($script:ocrImgTmp, [System.Drawing.Imaging.ImageFormat]::Png)
                $bmp.Dispose()
                $bar.Show()
                [OV]::SetWindowPos($bar.Handle, [OV]::HWND_TOPMOST, 0, 0, 0, 0, ([OV]::SWP_NOMOVE -bor [OV]::SWP_NOSIZE)) | Out-Null
                Remove-Item $script:ocrResTmp -Force -EA SilentlyContinue
                
                # Build the worker script with explicit paths
                $ip = $script:ocrImgTmp
                $rp = $script:ocrResTmp
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
                $bar.Show()
                $script:ocrBusy = $false
                $btnOCR.BackColor = [System.Drawing.Color]::Magenta
            }
        })
        $script:ocrDelayT.Start()
    } catch {
        $script:ocrBusy = $false
        $bar.Show()
        $btnOCR.BackColor = [System.Drawing.Color]::Magenta
    }
})

# ── Drag (threshold prevents accidental click trigger on drag) ───────────────
$script:drag          = $false
$script:dragging      = $false
$script:suppressClick = $false
$script:dPt           = [System.Drawing.Point]::Empty

foreach ($b in @($btnCap, $btnBrw, $btnOCR)) {
    $b.Add_MouseDown({
        param($s, $e)
        if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Left) {
            $script:drag = $true
            $script:dragging = $false
            $script:suppressClick = $false
            $script:dPt = [System.Windows.Forms.Cursor]::Position
        }
    })
    $b.Add_MouseMove({
        param($s, $e)
        if ($script:drag) {
            $n = [System.Windows.Forms.Cursor]::Position
            $dx = $n.X - $script:dPt.X
            $dy = $n.Y - $script:dPt.Y
            if ([Math]::Abs($dx) + [Math]::Abs($dy) -gt 3) {
                $script:dragging = $true
                $script:suppressClick = $true
                $bar.Left += $dx
                $bar.Top += $dy
                $script:dPt = $n
            }
        }
    })
    $b.Add_MouseUp({
        param($s, $e)
        $script:drag = $false
        $script:dragging = $false
    })
}

# ── Right-click -> Quit (also Ctrl+Shift+Q hotkey registered below) ───────────
function Quit-OverlayApp {
    $script:isQuitting = $true
    try { [HotkeyNW]::UnregisterHotKey($bar.Handle,1) | Out-Null } catch {}
    try { [HotkeyNW]::UnregisterHotKey($bar.Handle,2) | Out-Null } catch {}
    try { [HotkeyNW]::UnregisterHotKey($bar.Handle,3) | Out-Null } catch {}
    try { [HotkeyNW]::UnregisterHotKey($bar.Handle,4) | Out-Null } catch {}
    try { if ($bar) { $bar.Hide(); $bar.Close(); $bar.Dispose() } } catch {}
    try { if ($bForm) { $bForm.Hide(); $bForm.Close(); $bForm.Dispose() } } catch {}
    try { [System.Windows.Forms.Application]::Exit() } catch {}
    try { [System.Environment]::Exit(0) } catch {}
    try { Stop-Process -Id $PID -Force } catch {}
}

$ctxMenu = New-Object System.Windows.Forms.ContextMenuStrip
$quitItem = New-Object System.Windows.Forms.ToolStripMenuItem("Quit Overlay")
$quitItem.ForeColor = [System.Drawing.Color]::FromArgb(255,80,80)
$quitItem.Add_Click({ Quit-OverlayApp })
$ctxMenu.Items.Add($quitItem) | Out-Null
foreach ($b in @($btnCap,$btnBrw,$btnOCR,$bar)) { $b.ContextMenuStrip=$ctxMenu }

$bar.Controls.Add($btnCap);$bar.Controls.Add($btnBrw);$bar.Controls.Add($btnOCR)
$bar.Region=New-Object System.Drawing.Region((New-Object System.Drawing.Rectangle(0,0,$TOTAL_W,$CAP_SIZE)))

$bar.Add_Shown({
    $ex=[OV]::GetWindowLong($bar.Handle,[OV]::GWL_EXSTYLE)
    [OV]::SetWindowLong($bar.Handle,[OV]::GWL_EXSTYLE,$ex -bor [OV]::WS_EX_TOOLWINDOW) | Out-Null
    [OV]::SetWindowPos($bar.Handle,[OV]::HWND_TOPMOST,0,0,0,0,([OV]::SWP_NOMOVE -bor [OV]::SWP_NOSIZE)) | Out-Null
    # Register global hotkeys: Ctrl+Shift+B=browser, Ctrl+Shift+P=screenshot, Ctrl+Shift+T=OCR text, Ctrl+Shift+Q=quit
    try {
        $script:hkw = New-Object HotkeyNW($bar.Handle)
        [HotkeyNW]::RegisterHotKey($bar.Handle,1,([HotkeyNW]::CTRL -bor [HotkeyNW]::SHIFT),0x42) | Out-Null  # B
        [HotkeyNW]::RegisterHotKey($bar.Handle,2,([HotkeyNW]::CTRL -bor [HotkeyNW]::SHIFT),0x50) | Out-Null  # P
        [HotkeyNW]::RegisterHotKey($bar.Handle,3,([HotkeyNW]::CTRL -bor [HotkeyNW]::SHIFT),0x54) | Out-Null  # T
        [HotkeyNW]::RegisterHotKey($bar.Handle,4,([HotkeyNW]::CTRL -bor [HotkeyNW]::SHIFT),0x51) | Out-Null  # Q
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
                4 { Quit-OverlayApp }          # Ctrl+Shift+Q → Quit Overlay
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
        Quit-OverlayApp
    }
})
$watchTimer.Start()

[System.Windows.Forms.Application]::Run($bar)
