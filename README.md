# PSIT OAS Launcher (Modded)

So PSIT built an assessment browser to lock down your screen and make you suffer. Naturally, someone had to build an overlay so you don't actually have to remember what a red-black tree does at 9 AM on a Monday.

This is a modded setup for PSIT OAS. It wraps the original exam client with a stealth background overlay so you get an actual browser, instant screenshot copying, and local OCR without tripping any wire or showing up in the taskbar.

## What is this?

When you run this launcher, it launches the real PSIT OAS app so the invigilator sees what they expect to see. At the same time, it quietly spins up three tiny dots sitting in the corner of your screen. 

They look like dead pixels or random UI dust unless you know what they are.

### The Three Dots

- Blue Dot (Ctrl + Shift + P): Screen grabber. You click it (or hit the shortcut), the overlay vanishes for 180ms, snaps your entire screen, copies it straight to your clipboard, and reappears. Paste it wherever you want.
- Green Dot (Ctrl + Shift + B): Mini stealth browser. Opens a floating WebView2 window right over the exam window. Comes with quick buttons for Gemini, ChatGPT, Claude, Perplexity, Copilot, DeepSeek, and Meta AI so you don't waste time typing URLs. Resize it from the edges, drag it around, close it whenever someone walks by.
- Orange Dot (Ctrl + Shift + T): Local OCR text extractor. Runs Windows native OCR engine directly on your screen in an isolated hidden background thread. Rips all the text off the current question and puts it straight into your clipboard. No external internet calls, no lag, completely offline.

### Getting Rid of the Evidence

- Right-click any dot -> hit "Quit Overlay". Everything evaporates instantly.
- Or hit Ctrl + Shift + Q.
- If you close or Alt+F4 the actual PSITOAS app, the overlay detects it and self-destructs immediately.

## Installation

Download the MSI from the releases page and run it.

Important notes on the installer:
- It is patched for "Only Me" (per-user) installation. It dumps itself into your user profile (AppData\Local\Programs).
- Why? Because lab PCs and non-admin Windows profiles throw Error 1925 when installers try to touch Program Files. This bypasses UAC completely. You do not need admin rights.
- Just click Next through the wizard. It puts a "PSIT OAS Launcher" shortcut on your desktop. Run that.

## Hotkeys Cheat Sheet

- Ctrl + Shift + B -> Toggle stealth browser
- Ctrl + Shift + P -> Screenshot to clipboard
- Ctrl + Shift + T -> Extract screen text to clipboard (OCR)
- Ctrl + Shift + Q -> Panic button (kills overlay and browser immediately)

## Disclaimer

This is purely for academic research, reverse engineering curiosity, and checking out how Windows API hooks interact with locked down desktop software. If you use this in an actual lab and an external invigilator catches you staring at ChatGPT on a 300px floating window, you never saw this repo and I do not know you.
