#!/usr/bin/env python3
"""
Test runner for user's benchmark questions across Gemini and Groq (Text & Vision).
Verifies:
1. Question 19 (Anjali Data Sufficiency) -> Ans: D
2. Seating Arrangement (S1..S8) -> Ans: B
3. Syllogisms (Eye drops / liquids) -> Ans: D
"""

import urllib.request
import json
import base64
import os
import re

import sys

# Ensure clean utf-8 output on Windows terminal
if sys.stdout.encoding.lower() != 'utf-8':
    sys.stdout.reconfigure(encoding='utf-8', errors='replace')

from test_keys import load_keys

def parse_answer(raw_text):
    if not raw_text:
        return None
    clean = raw_text.replace('**', '').replace('"', '').strip()
    lines = [l.strip() for l in clean.splitlines() if l.strip()]

    pat_a = re.compile(
        r'(?i)(?:^Ans(?:wer)?\s*[:\-]?\s*|(?:correct|final)\s+(?:option|answer|choice)\s+(?:is\s*)?[:\-]?\s*)'
        r'\[?([A-D])\]?'
        r'(?:\s*[:\.\-]\s*|\s*[\[\(]|\s+)'
        r'([^\]\)\r\n]*)'
    )
    pat_b = re.compile(
        r'(?i)(?:^Ans(?:wer)?\s*[:\-]?\s*|(?:correct|final)\s+(?:option|answer|choice)\s+(?:is\s*)?[:\-]?\s*)'
        r'\[?([A-D])\]?[\.\:\-]?$'
    )

    for l in reversed(lines):
        m = pat_a.search(l)
        if m:
            return m.group(1).upper(), m.group(2).strip().rstrip(']').strip()
        m2 = pat_b.search(l)
        if m2:
            return m2.group(1).upper(), ''

    start_idx = max(0, len(lines) - 3)
    pat_c = re.compile(r'(?i)^\[?([A-D])\]?\s*(?:[:\.\-]\s*|[\[\(])\s*([^\]\)\r\n]+)[\]\)]?$')
    for l in reversed(lines[start_idx:]):
        m3 = pat_c.search(l)
        if m3:
            return m3.group(1).upper(), m3.group(2).strip().rstrip(']').strip()

    return None, None

def run_gemini(key, question):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-lite-latest:generateContent?key={key}"
    prompt = (
        "You are an expert exam solver. Read the question and all options carefully. "
        "Reason step-by-step to determine the single correct option. "
        "On the VERY LAST LINE, output strictly in this exact format: "
        "Ans: [Letter] [Option Text]. Example: Ans: B [Third to the left]"
    )
    payload = json.dumps({
        "contents": [{"parts": [{"text": f"{prompt}\n\nQuestion & Options:\n{question}"}]}],
        "generationConfig": {"maxOutputTokens": 2048, "temperature": 0.0}
    }).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data["candidates"][0]["content"]["parts"][0]["text"]
    except Exception as e:
        return f"ERROR: {e}"

def run_gemini_vision(key, question, png_b64):
    url = f"https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-lite-latest:generateContent?key={key}"
    prompt = (
        "You are an expert exam solver. Look at this exam question image and read all options carefully. "
        "Reason step-by-step to determine the single correct option. "
        "On the VERY LAST LINE, output strictly in this exact format: "
        "Ans: [Letter] [Option Text]. Example: Ans: B [Third to the left]"
    )
    payload = json.dumps({
        "contents": [{
            "parts": [
                {"inline_data": {"mime_type": "image/png", "data": png_b64}},
                {"text": f"{prompt}\n\nQuestion context: {question}"}
            ]
        }],
        "generationConfig": {"maxOutputTokens": 2048, "temperature": 0.0}
    }).encode("utf-8")
    req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return data["candidates"][0]["content"]["parts"][0]["text"]
    except Exception as e:
        return f"ERROR: {e}"

def main():
    keys = load_keys("keys.txt", include_env=True)
    gemini_key = None
    for k in keys:
        if k["provider"] == "gemini":
            gemini_key = k["key"]
            break

    if not gemini_key:
        print("[!] No working Gemini key found in keys.txt")
        return

    questions = [
        {
            "name": "Question 19 (Anjali Data Sufficiency)",
            "expected": "D",
            "text": """Question No: 19
Directions: In the questions below consists of a question and two statements numbered I and II given below it. You have to decide whether the data provided in the statements are sufficient to answer the question. Read all the statements and give answer.

On which date of the month was Anjali born in February 2004 ?
Statements:
I. Anjali was born on an even date of the month.
II. Anjali's birth date was a prime number.
A. If the data in statement I alone is sufficient to answer the question, while the data in statement II alone is not sufficient
B. If the data in statement II alone is sufficient to answer the question, while the data in statement I alone is not sufficient
C. If the data either in statement I alone or in statement II alone is sufficient to answer the question
D. If the data in both statements I and II together are necessary to answer the question"""
        },
        {
            "name": "Seating Arrangement (Circular 8 persons)",
            "expected": "B",
            "text": """Direction: Answer the questions based on the information given below.
There are eight persons S1, S2, S3, S4, S5, S6, S7 and S8 sitting around a circular table not necessarily in the same order. Each of the persons is facing towards the centre. S7 sits second to the right of S3. S2 sits third to the left of S4, who is the neighbour of S7. S6 is neither the neighbour of S2 nor S7. Neither S1 is the neighbour of S2 nor S5 is the neighbour of S3.

What is the position of S8 with respect to S7?
A. Second to the left
B. Third to the left
C. Immediate left
D. Third to the right"""
        },
        {
            "name": "Syllogisms (Eye drops / Liquids)",
            "expected": "D",
            "text": """Syllogisms
Statements:
All eye drops are liquids.
Some eye drops are ear drops.

Conclusions:
I. Some eye drops are drinkable.
II. Some ear drops are drinkable.
III. All liquids are eye drops.
A. I and II follow
B. II and III follow
C. Only III follows
D. None follows"""
        }
    ]

    print("================================================================================")
    print("                BENCHMARK VERIFICATION ON USER QUESTIONS")
    print("================================================================================\n")

    for q in questions:
        print(f"[*] Testing: {q['name']}")
        print(f"    Expected: {q['expected']}")

        # 1. Text solver test
        raw = run_gemini(gemini_key, q["text"])
        letter, content = parse_answer(raw)
        status = "PASS ✅" if letter == q["expected"] else f"FAIL ❌ (got {letter})"
        c_disp = (content or '')[:35]
        print(f"    Text Mode Result   : {status} -> Ans: {letter} [{c_disp}...]")

        # 2. Vision solver test (with image data)
        # 1x1 test png
        tiny_png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII="
        v_raw = run_gemini_vision(gemini_key, q["text"], tiny_png)
        v_letter, v_content = parse_answer(v_raw)
        v_status = "PASS ✅" if v_letter == q["expected"] else f"FAIL ❌ (got {v_letter})"
        vc_disp = (v_content or '')[:35]
        print(f"    Vision Mode Result : {v_status} -> Ans: {v_letter} [{vc_disp}...]\n")

if __name__ == "__main__":
    main()
