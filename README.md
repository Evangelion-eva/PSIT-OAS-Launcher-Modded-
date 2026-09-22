# PSIT OAS Launcher (Modded)

So PSIT built an assessment browser to lock down your screen and make you suffer. Naturally, someone had to build an overlay so you don't actually have to remember what a red-black tree does at 9 AM on a Monday.

This is a modded setup for PSIT OAS. It wraps the original exam client with a stealth background overlay so you get an actual multi-tab browser, instant screenshot copying, local OCR text extraction, and an automated point-to-point AI answering engine without tripping any wire or showing up in the taskbar.

---

## What is this?

When you run this launcher, it launches the real PSIT OAS app so the invigilator sees what they expect to see. At the same time, it quietly spins up three tiny dots sitting in the corner of your screen.

They look like dead pixels or random UI dust unless you know what they are.

### The Three Dots

- **Blue Dot (<kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>P</kbd>): Screen grabber**
  Click it or hit the shortcut: the overlay vanishes for 180ms, snaps your entire screen, copies it straight to your clipboard, and reappears. Paste it wherever you want.

- **Green Dot (<kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>B</kbd>): Multi-Tab Stealth Browser**
  Opens a floating WebView2 window right over the exam window with persistent tabs and session history:
  - **Gem**: Google Gemini
  - **Ael**: Aelius AI (no sign-up, images & PDFs)
  - **Ima**: Ima Studio (direct image chat)
  - **Pix**: PixPal (chat + image reasoning)
  - **Jolly**: JollyAI (unlimited chat without account)
  - **Duck**: Duck.ai
  - **Yia**: Yiaho AI
  - **`+Q` Button**: Pastes the latest OCR-captured question directly into the active AI chat prompt box.
  - **`+Link` Button**: Pastes the current web link straight into chat.
  - Edge-resizable from all sides, draggable title bar, full zoom controls, and instant tab switching with chat history preserved.

- **Orange Dot (<kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>T</kbd>): Offline OCR + AI Auto-Solver**
  Extracts on-screen question text using Windows 10/11 native OCR (100% offline, zero lag, zero process footprint). It copies the question to your clipboard and immediately fires a background AI runspace to solve the question:
  - Rotates between Groq (`qwen/qwen3.8-27b`) and OpenRouter (`free`) keys.
  - Renders a clean, point-to-point answer (e.g. `Ans: C (Diamond)`) below the question options.
  - Pure black text keyed transparently — no background box, no chromatic halo, and doesn't steal focus.
  - **Click-to-dismiss**: Click directly on the answer text at any time to make it disappear instantly.

### Getting Rid of the Evidence

- **Right-click any dot** -> hit **"Quit Overlay"**. Everything evaporates instantly.
- Or hit <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>Q</kbd>.
- If you close or Alt+F4 the actual PSITOAS app, the overlay detects it and self-destructs automatically.

---

## AI Setup & Key Rotation (`keys.txt`)

The installer comes pre-bundled with working keys, but if you are running from source or want to use your own:

1. Duplicate `keys.txt.example` to `keys.txt`:
   ```txt
   # PSIT OAS AI Keys — one per line
   # Format:  groq:<key>   or   openrouter:<key>
   # Add as many keys as you want — they rotate automatically on rate limit.
   groq:gsk_your_groq_key_here
   openrouter:sk-or-v1-your_openrouter_key_here
   ```
2. Any number of Groq and OpenRouter keys can be added. If one hits a rate limit or returns an error, the engine seamlessly rotates to the next key.

---

## Local Testing Harness

An offline test page is included to test OCR, the browser, and answer overlays without needing an active exam:
- Open `test_page.html` in any browser.
- Run `Launch.bat` or `Launch.exe`.
- Hit <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>T</kbd> on any question to test OCR extraction and instant AI answering.

---

## Installation

Download `psit oas setup.msi` (or `PSIT OAS SETUP (Modded).msi`) and run it:

- **Per-User ("Only Me") Installation**: Dumps itself into your user profile (`AppData\Local\Programs\PSIT Online Assessment System\PSIT OAS SETUP`).
- **Zero Admin / UAC Required**: Lab PCs and non-admin Windows profiles throw Error 1925 when standard installers touch `C:\Program Files`. This bypasses UAC completely.
- Just click Next through the wizard. It puts a "PSIT OAS Launcher" shortcut on your desktop. Run that.

---

## Hotkeys Cheat Sheet

| Shortcut | Action |
| :--- | :--- |
| <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>B</kbd> | Toggle multi-tab stealth browser |
| <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>T</kbd> | OCR screen text & show AI answer |
| <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>P</kbd> | Stealth screenshot to clipboard |
| <kbd>Ctrl</kbd> + <kbd>Shift</kbd> + <kbd>Q</kbd> | Panic kill (evaporates overlay and browser) |

---

## Disclaimer

This is purely for academic research, reverse engineering curiosity, and checking out how Windows API hooks interact with locked down desktop software. If you use this in an actual lab and an external invigilator catches you staring at ChatGPT on a 300px floating window, you never saw this repo and I do not know you.
