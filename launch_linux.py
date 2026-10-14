#!/usr/bin/env python3
"""
PSIT OAS Launcher (Modded) — Linux Native Engine & Overlay
Provides stealth floating dots, targeted question cropping, local libtesseract OCR,
AI auto-solver with key rotation (keys.txt), and click-to-dismiss HUD on Linux.
"""

import os
import sys
import time
import json
import ctypes
import re
import threading
import urllib.request
import webbrowser
import tkinter as tk
from tkinter import messagebox
from PIL import Image, ImageGrab

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
KEYS_FILE = os.path.join(SCRIPT_DIR, "keys.txt")
TEST_PAGE = os.path.join(SCRIPT_DIR, "test_page.html")

# ── Load API Keys ────────────────────────────────────────────────────────────
ai_keys = []
if os.path.exists(KEYS_FILE):
    with open(KEYS_FILE, "r", encoding="utf-8") as f:
        for line in f:
            line = line.strip()
            if line and not line.startswith("#"):
                parts = line.split(":", 1)
                if len(parts) == 2:
                    ai_keys.append({"provider": parts[0].strip().lower(), "key": parts[1].strip()})

if not ai_keys and os.environ.get("OAS_AI_KEYS"):
    for entry in re.split(r"[;\r\n]+", os.environ.get("OAS_AI_KEYS", "")):
        entry = entry.strip()
        if entry and ":" in entry:
            parts = entry.split(":", 1)
            if len(parts) == 2:
                ai_keys.append({"provider": parts[0].strip().lower(), "key": parts[1].strip()})

key_index = 0
key_lock = threading.Lock()

def get_next_key():
    global key_index
    with key_lock:
        if not ai_keys:
            return None
        entry = ai_keys[key_index % len(ai_keys)]
        key_index += 1
        return entry

# ── Linux Tesseract OCR Engine via ctypes ────────────────────────────────────
class LinuxOCR:
    def __init__(self):
        self.available = False
        self.api = None
        self.tess = None
        # Common shared library locations on Linux
        candidates = [
            "/usr/lib64/libtesseract.so.5.5",
            "/usr/lib64/libtesseract.so.5",
            "/usr/lib64/libtesseract.so",
            "/usr/lib/x86_64-linux-gnu/libtesseract.so.5",
            "/usr/lib/libtesseract.so"
        ]
        for path in candidates:
            if os.path.exists(path):
                try:
                    self.tess = ctypes.cdll.LoadLibrary(path)
                    self.tess.TessBaseAPICreate.restype = ctypes.c_void_p
                    self.api = self.tess.TessBaseAPICreate()
                    self.tess.TessBaseAPIInit3.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_char_p]
                    self.tess.TessBaseAPIInit3.restype = ctypes.c_int
                    if self.tess.TessBaseAPIInit3(self.api, None, b"eng") == 0:
                        self.tess.TessBaseAPISetImage.argtypes = [ctypes.c_void_p, ctypes.c_char_p, ctypes.c_int, ctypes.c_int, ctypes.c_int, ctypes.c_int]
                        self.tess.TessBaseAPIGetUTF8Text.argtypes = [ctypes.c_void_p]
                        self.tess.TessBaseAPIGetUTF8Text.restype = ctypes.c_char_p
                        self.available = True
                        break
                except Exception:
                    continue

    def recognize(self, pil_image):
        if not self.available or not self.api:
            return ""
        try:
            rgb = pil_image.convert("RGB")
            raw_bytes = rgb.tobytes()
            self.tess.TessBaseAPISetImage(self.api, raw_bytes, rgb.width, rgb.height, 3, rgb.width * 3)
            res = self.tess.TessBaseAPIGetUTF8Text(self.api)
            if res:
                return res.decode("utf-8", errors="ignore").strip()
        except Exception as e:
            print(f"[OCR Error]: {e}")
        return ""

    def cleanup(self):
        if self.available and self.api and self.tess:
            try:
                self.tess.TessBaseAPIClear(self.api)
                self.tess.TessBaseAPIEnd(self.api)
                self.tess.TessBaseAPIDelete(self.api)
            except Exception:
                pass

ocr_engine = LinuxOCR()

# ── Targeted Question Bounds & Cleaning ──────────────────────────────────────
def get_question_crop_bbox(screen_w, screen_h):
    # Online exam layouts place question & options in upper-left quadrant.
    # Exclude top header bar (8.5%), bottom action buttons (10%), and right palette grid (26.5%).
    qx = int(screen_w * 0.015)
    qy = int(screen_h * 0.085)
    qw = int(screen_w * 0.735)
    qh = int(screen_h * 0.80)
    return (qx, qy, qx + qw, qy + qh)

def clean_ocr_text(raw):
    if not raw:
        return ""
    lines = [line.strip() for line in raw.splitlines() if line.strip()]
    filtered = []
    ignore_re = re.compile(
        r"^(Time\s*Remaining|Timer|Candidate|Assessment\s*&|Marking\s*Scheme|Question\s*Palette|Legend|Answered|Not\s*Answered|Not\s*Visited|Marked\s*for\s*Review|Clear\s*Response|Save\s*&\s*Next|Submit\s*(Exam|Test)?)",
        re.IGNORECASE
    )
    palette_nums = re.compile(r"^\d+(\s+\d+){2,}$")
    for line in lines:
        if ignore_re.match(line) or palette_nums.match(line):
            continue
        filtered.append(line)
    return "\n".join(filtered).strip()

def parse_ai_response(raw_text):
    if not raw_text:
        return ""
    clean = raw_text.replace("**", "").replace("`", "").strip()
    lines = [l.strip() for l in clean.splitlines() if l.strip()]

    # Priority 1: Explicit answer marker
    for line in reversed(lines):
        m = re.search(
            r'(?i)(?:^Ans(?:wer)?\s*[:\-]?\s*|(?:correct|final)\s+(?:option|answer|choice)\s+(?:is\s*)?[:\-]?\s*)'
            r'\[?([A-D])\]?'
            r'(?:\s*[:\.\-]\s*|\s*[\[\(]|\s+)'
            r'([^\]\)\r\n]*)',
            line
        )
        if m:
            letter = m.group(1).upper()
            content = m.group(2).strip().rstrip(']').strip()
            return f"Ans: {letter} [{content}]" if content else f"Ans: {letter}"

        m2 = re.search(
            r'(?i)(?:^Ans(?:wer)?\s*[:\-]?\s*|(?:correct|final)\s+(?:option|answer|choice)\s+(?:is\s*)?[:\-]?\s*)'
            r'\[?([A-D])\]?[\.\:\-]?$',
            line
        )
        if m2:
            return f"Ans: {m2.group(1).upper()}"

    # Priority 2: Only bottom 3 lines starting with option letter (avoids matching question text)
    start_idx = max(0, len(lines) - 3)
    for line in reversed(lines[start_idx:]):
        m3 = re.search(r'(?i)^\[?([A-D])\]?\s*(?:[:\.\-]\s*|[\[\(])\s*([^\]\)\r\n]+)[\]\)]?$', line)
        if m3:
            return f"Ans: {m3.group(1).upper()} [{m3.group(2).strip().rstrip(']').strip()}]"

    last_line = lines[-1] if lines else clean
    return last_line if last_line.startswith("Ans:") else f"Ans: {last_line}"

# ── AI Auto-Solver Execution ────────────────────────────────────────────────
def query_ai_solver(question_text):
    if not ai_keys or not question_text:
        return None

    prompt = (
        "You are an expert exam solver. Read the question and all options carefully. "
        "Reason step-by-step to determine the single correct option. "
        "On the VERY LAST LINE, output strictly in this exact format: "
        "Ans: [Letter] [Option Text]. Example: Ans: B [Third to the left]"
    )

    for _ in range(len(ai_keys)):
        entry = get_next_key()
        if not entry:
            break
        provider = entry["provider"]
        api_key = entry["key"]

        if provider == "gemini":
            gemini_models = ["gemini-flash-lite-latest", "gemini-flash-latest", "gemini-2.5-flash-lite", "gemini-3.8-flash"]
            for gm in gemini_models:
                url = f"https://generativelanguage.googleapis.com/v1beta/models/{gm}:generateContent?key={api_key}"
                body = {
                    "contents": [{"parts": [{"text": f"{prompt}\n\nQuestion & Options:\n{question_text}"}]}],
                    "generationConfig": {"maxOutputTokens": 2048, "temperature": 0.0}
                }
                headers = {"Content-Type": "application/json; charset=utf-8"}
                try:
                    req = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"), headers=headers)
                    with urllib.request.urlopen(req, timeout=12) as resp:
                        data = json.loads(resp.read().decode("utf-8"))
                        candidates = data.get("candidates", [])
                        if candidates and "parts" in candidates[0].get("content", {}):
                            raw_ans = candidates[0]["content"]["parts"][0].get("text", "")
                            if raw_ans:
                                return parse_ai_response(raw_ans)
                except Exception:
                    continue
            continue

        model = "llama-3.3-70b-versatile" if provider == "groq" else "openrouter/free"
        url = (
            "https://api.groq.com/openai/v1/chat/completions"
            if provider == "groq"
            else "https://openrouter.ai/api/v1/chat/completions"
        )

        body = {
            "model": model,
            "messages": [
                {"role": "system", "content": prompt},
                {"role": "user", "content": question_text}
            ],
            "max_tokens": 450,
            "temperature": 0.0
        }

        headers = {
            "Content-Type": "application/json; charset=utf-8",
            "Authorization": f"Bearer {api_key}"
        }
        if provider == "openrouter":
            headers["HTTP-Referer"] = "https://github.com/Evangelion-eva/PSIT-OAS-Launcher-Modded-"
            headers["X-Title"] = "PSIT OAS"

        try:
            req = urllib.request.Request(url, data=json.dumps(body).encode("utf-8"), headers=headers)
            with urllib.request.urlopen(req, timeout=12) as resp:
                data = json.loads(resp.read().decode("utf-8"))
                choice = data["choices"][0]["message"]
                raw_ans = choice.get("content") or choice.get("reasoning")
                if raw_ans:
                    return parse_ai_response(raw_ans)
        except Exception as e:
            continue
    return None

# ── GUI Overlay Application ──────────────────────────────────────────────────
class LinuxOverlayApp:
    def __init__(self):
        self.root = tk.Tk()
        self.root.title("PSIT OAS Overlay")
        self.root.overrideredirect(True)
        self.root.attributes("-topmost", True)
        self.root.config(bg="#181824")

        self.screen_w = self.root.winfo_screenwidth()
        self.screen_h = self.root.winfo_screenheight()

        # Overlay Dot Constants
        self.dot_size = 16
        self.gap = 8
        self.width = self.dot_size * 3 + self.gap * 4
        self.height = self.dot_size + 10

        # Position at bottom-left corner
        pos_x = 20
        pos_y = self.screen_h - self.height - 40
        self.root.geometry(f"{self.width}x{self.height}+{pos_x}+{pos_y}")

        # Drag tracking
        self.drag_x = 0
        self.drag_y = 0
        self.is_dragging = False

        # Canvas for the 3 stealth dots
        self.canvas = tk.Canvas(self.root, width=self.width, height=self.height, bg="#181824", highlightthickness=0)
        self.canvas.pack(fill=tk.BOTH, expand=True)

        # Draw 3 circular buttons
        # 1. Blue Dot (Capture Screen -> Clipboard)
        x1 = self.gap
        self.btn_blue = self.canvas.create_oval(x1, 5, x1 + self.dot_size, 5 + self.dot_size, fill="#2563eb", outline="#60a5fa", width=1)
        # 2. Green Dot (Stealth Browser)
        x2 = x1 + self.dot_size + self.gap
        self.btn_green = self.canvas.create_oval(x2, 5, x2 + self.dot_size, 5 + self.dot_size, fill="#16a34a", outline="#4ade80", width=1)
        # 3. Orange Dot (Question OCR + AI Solver)
        x3 = x2 + self.dot_size + self.gap
        self.btn_orange = self.canvas.create_oval(x3, 5, x3 + self.dot_size, 5 + self.dot_size, fill="#ea580c", outline="#fb923c", width=1)

        # Bindings
        self.canvas.tag_bind(self.btn_blue, "<Button-1>", lambda e: self.on_blue_click())
        self.canvas.tag_bind(self.btn_green, "<Button-1>", lambda e: self.on_green_click())
        self.canvas.tag_bind(self.btn_orange, "<Button-1>", lambda e: self.on_orange_click())

        # Dragging
        self.canvas.bind("<ButtonPress-1>", self.start_drag)
        self.canvas.bind("<B1-Motion>", self.do_drag)
        self.canvas.bind("<ButtonRelease-1>", self.stop_drag)
        self.canvas.bind("<Button-3>", self.show_context_menu)

        # Context Menu
        self.menu = tk.Menu(self.root, tearoff=0, bg="#20222e", fg="#ffffff", activebackground="#3b82f6")
        self.menu.add_command(label="Open Test Page (test_page.html)", command=self.open_test_page)
        self.menu.add_command(label="Toggle Gemini Chat", command=lambda: webbrowser.open("https://gemini.google.com"))
        self.menu.add_separator()
        self.menu.add_command(label="Quit Overlay", command=self.quit_app, foreground="#ef4444")

        # Answer HUD state
        self.hud_win = None
        self.hud_timer = None
        self.ocr_busy = False

        # Global hotkey simulation (when window active) & Tooltip
        self.tooltip = None
        self.canvas.bind("<Enter>", self.show_dots_tooltip)
        self.canvas.bind("<Leave>", self.hide_dots_tooltip)

    def show_dots_tooltip(self, event):
        x = self.root.winfo_x() + 10
        y = self.root.winfo_y() - 30
        self.tooltip = tk.Toplevel(self.root)
        self.tooltip.overrideredirect(True)
        self.tooltip.attributes("-topmost", True)
        self.tooltip.geometry(f"+{x}+{y}")
        lbl = tk.Label(self.tooltip, text="Blue: Snip | Green: Browser | Orange: OCR+AI Solve", bg="#1e202e", fg="#e2e8f0", font=("Segoe UI", 8), padx=6, pady=2)
        lbl.pack()

    def hide_dots_tooltip(self, event):
        if self.tooltip:
            try:
                self.tooltip.destroy()
            except Exception:
                pass
            self.tooltip = None

    def start_drag(self, event):
        self.drag_x = event.x
        self.drag_y = event.y
        self.is_dragging = False

    def do_drag(self, event):
        dx = event.x - self.drag_x
        dy = event.y - self.drag_y
        if abs(dx) + abs(dy) > 8:
            self.is_dragging = True
            new_x = self.root.winfo_x() + dx
            new_y = self.root.winfo_y() + dy
            self.root.geometry(f"+{new_x}+{new_y}")

    def stop_drag(self, event):
        self.is_dragging = False

    def show_context_menu(self, event):
        self.menu.post(event.x_root, event.y_root)

    def open_test_page(self):
        if os.path.exists(TEST_PAGE):
            webbrowser.open(f"file://{TEST_PAGE}")

    # ── Button 1: Blue Dot (Screenshot) ──────────────────────────────────────
    def on_blue_click(self):
        if self.is_dragging:
            return
        threading.Thread(target=self._run_screenshot, daemon=True).start()

    def _run_screenshot(self):
        self.dismiss_hud()
        self.canvas.itemconfig(self.btn_blue, fill="#2563eb")
        self.root.withdraw()
        time.sleep(0.18)
        try:
            # Crop strictly to question area with high recognizable quality
            bbox = get_question_crop_bbox(self.screen_w, self.screen_h)
            cropped_img = ImageGrab.grab(bbox=bbox)
            
            # Save high quality snapshot to clipboard via xclip
            tmp_path = "/tmp/oas_snip.png"
            cropped_img.save(tmp_path, format="PNG")
            os.system(f"xclip -selection clipboard -t image/png -i {tmp_path} 2>/dev/null || true")

            self.root.deiconify()
            self.canvas.itemconfig(self.btn_blue, fill="#3b82f6")
            self.flash_tip("Question captured! Solving...")

            # Run OCR on the high-quality captured area
            raw_text = ocr_engine.recognize(cropped_img)
            question_text = clean_ocr_text(raw_text)

            if not question_text:
                self.flash_tip("No text detected in question area")
                return

            print(f"[Captured Question via Screenshot]:\n{question_text}\n{'='*40}")

            # Solve via AI
            ans = query_ai_solver(question_text)
            if ans:
                print(f"[AI Answer]: {ans}")
                self.root.after(0, lambda: self.show_answer_hud(ans))
            else:
                self.flash_tip("AI solve failed (check API keys)")
        except Exception as e:
            print(f"[Screenshot error]: {e}")
            self.root.deiconify()
            self.canvas.itemconfig(self.btn_blue, fill="#3b82f6")
            self.flash_tip("Error capturing")

    # ── Button 2: Green Dot (Stealth Browser) ────────────────────────────────
    def on_green_click(self):
        if self.is_dragging:
            return
        # Open multi-tab browser options or launch test page
        self.open_test_page()

    # ── Button 3: Orange Dot (Question OCR + AI Solver) ──────────────────────
    def on_orange_click(self):
        if self.is_dragging:
            return
        self.dismiss_hud()
        threading.Thread(target=self._run_ocr_solver, daemon=True).start()

    def _run_ocr_solver(self):
        self.canvas.itemconfig(self.btn_orange, fill="#ea580c")
        self.root.withdraw()
        time.sleep(0.18)
        try:
            # Crop strictly to question area
            bbox = get_question_crop_bbox(self.screen_w, self.screen_h)
            cropped_img = ImageGrab.grab(bbox=bbox)
            self.root.deiconify()
            self.flash_tip("Analyzing question...")

            # Run OCR
            raw_text = ocr_engine.recognize(cropped_img)
            question_text = clean_ocr_text(raw_text)

            if not question_text:
                self.flash_tip("No question detected")
                return

            print(f"[Captured Question]:\n{question_text}\n{'='*40}")

            # Solve via AI
            ans = query_ai_solver(question_text)
            if ans:
                print(f"[AI Answer]: {ans}")
                self.root.after(0, lambda: self.show_answer_hud(ans))
            else:
                self.flash_tip("AI solve failed (check keys.txt)")
        except Exception as e:
            print(f"[Solver Error]: {e}")
            self.root.deiconify()
            self.flash_tip("Error capturing")

    def show_answer_hud(self, answer_text):
        self.dismiss_hud()

        # HUD Dimensions and Positioning
        ans_x = max(36, int(self.screen_w * 0.03))
        ans_y = max(360, int(self.screen_h * 0.57))

        self.hud_win = tk.Toplevel(self.root)
        self.hud_win.overrideredirect(True)
        self.hud_win.attributes("-topmost", True)
        self.hud_win.config(bg="#181a24")

        # Container Frame
        frm = tk.Frame(self.hud_win, bg="#181a24", highlightbackground="#3e4359", highlightthickness=1, padx=12, pady=6)
        frm.pack(fill=tk.BOTH, expand=True)

        lbl = tk.Label(frm, text=answer_text, font=("Segoe UI", 10, "bold"), fg="#4ade80", bg="#181a24", cursor="hand2")
        lbl.pack(side=tk.LEFT, padx=(0, 10))

        close_btn = tk.Label(frm, text="×", font=("Segoe UI", 11, "bold"), fg="#94a3b8", bg="#181a24", cursor="hand2")
        close_btn.pack(side=tk.RIGHT)

        # Click ANYWHERE on HUD to dismiss immediately!
        dismiss = lambda e: self.dismiss_hud()
        self.hud_win.bind("<Button-1>", dismiss)
        frm.bind("<Button-1>", dismiss)
        lbl.bind("<Button-1>", dismiss)
        close_btn.bind("<Button-1>", dismiss)

        self.hud_win.update_idletasks()
        w = max(260, frm.winfo_reqwidth() + 4)
        h = max(38, frm.winfo_reqheight() + 4)
        self.hud_win.geometry(f"{w}x{h}+{ans_x}+{ans_y}")

        # Auto-dismiss after 35s
        self.hud_timer = self.root.after(35000, self.dismiss_hud)

    def dismiss_hud(self):
        if self.hud_timer:
            self.root.after_cancel(self.hud_timer)
            self.hud_timer = None
        if self.hud_win:
            try:
                self.hud_win.destroy()
            except Exception:
                pass
            self.hud_win = None

    def flash_tip(self, text):
        tip = tk.Toplevel(self.root)
        tip.overrideredirect(True)
        tip.attributes("-topmost", True)
        tx = self.root.winfo_x() + 10
        ty = self.root.winfo_y() - 28
        tip.geometry(f"+{tx}+{ty}")
        lbl = tk.Label(tip, text=text, bg="#2563eb", fg="#ffffff", font=("Segoe UI", 8, "bold"), padx=6, pady=2)
        lbl.pack()
        self.root.after(1600, lambda: tip.destroy() if tip else None)

    def quit_app(self):
        ocr_engine.cleanup()
        self.dismiss_hud()
        self.root.destroy()
        sys.exit(0)

    def run(self):
        self.root.mainloop()

if __name__ == "__main__":
    app = LinuxOverlayApp()
    app.run()
