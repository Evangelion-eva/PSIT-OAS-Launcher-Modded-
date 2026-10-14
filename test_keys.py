#!/usr/bin/env python3
"""
PSIT OAS Launcher - API Key Diagnostics & Testing Suite
Tests all configured AI and Integration keys (Gemini, Groq, OpenRouter, Notion)
with live endpoint verification, latency measurement, and quota detection.
"""

import sys
import os
import json
import time
import base64
import argparse
import urllib.request
import urllib.error

# ANSI Color Codes for terminal
CLR_RESET   = "\033[0m"
CLR_BOLD    = "\033[1m"
CLR_GREEN   = "\033[92m"
CLR_YELLOW  = "\033[93m"
CLR_RED     = "\033[91m"
CLR_CYAN    = "\033[96m"
CLR_BLUE    = "\033[94m"
CLR_GRAY    = "\033[90m"

FALLBACK_B64 = "Z3JvcTpnc2tfYUxCbWJwTm50SzE1dVU1QTNjajBXR2R5YjNGWVRIRXRwQjFkUkV1YzJVcENLSjJJRGdGaTtncm9xOmdza19pNVA3SDVzaG9iTm1odzNHcmVleldHZHliM0ZZalFLZUh2UGp2VHlaWGk2OVRGbXFUTlpvO2dlbWluaTpBUS5BYjhSTjZKVlo2Vk40MVF4UWh0OGc5TmhiQlI2dXpKQ3o0UkRYdTJIUFJRM1NZNFlwUQ=="

def mask_key(k: str) -> str:
    """Safely mask key for display without revealing sensitive token."""
    if not k:
        return "<empty>"
    k = k.strip()
    if len(k) <= 8:
        return "***"
    return f"{k[:5]}...{k[-4:]}"

def load_keys(keys_file: str, include_env: bool = True, include_fallback: bool = False):
    """Load and deduplicate keys from file, environment, and optional fallback."""
    keys = []
    seen = set()

    # 1. Load from file
    if os.path.exists(keys_file):
        with open(keys_file, "r", encoding="utf-8", errors="ignore") as f:
            for idx, line in enumerate(f, 1):
                line = line.strip()
                if not line or line.startswith("#"):
                    continue
                if ":" in line:
                    parts = line.split(":", 1)
                    prov = parts[0].strip().lower()
                    key_val = parts[1].strip()
                    if key_val and (prov, key_val) not in seen:
                        seen.add((prov, key_val))
                        keys.append({
                            "source": f"{os.path.basename(keys_file)}:L{idx}",
                            "provider": prov,
                            "key": key_val
                        })

    # 2. Load from environment
    if include_env:
        # Generic OAS_AI_KEYS (semicolon or newline separated)
        oas_env = os.environ.get("OAS_AI_KEYS", "")
        if oas_env:
            for item in oas_env.replace("\r", "\n").replace(";", "\n").split("\n"):
                item = item.strip()
                if ":" in item:
                    prov, key_val = item.split(":", 1)
                    prov = prov.strip().lower()
                    key_val = key_val.strip()
                    if key_val and (prov, key_val) not in seen:
                        seen.add((prov, key_val))
                        keys.append({
                            "source": "ENV:OAS_AI_KEYS",
                            "provider": prov,
                            "key": key_val
                        })

        # Individual env keys
        env_map = {
            "GEMINI_API_KEY": "gemini",
            "GOOGLE_API_KEY": "gemini",
            "GROQ_API_KEY": "groq",
            "OPENROUTER_API_KEY": "openrouter",
            "NOTION_API_KEY": "notion",
            "NOTION_TOKEN": "notion"
        }
        for env_var, prov in env_map.items():
            val = os.environ.get(env_var, "").strip()
            if val and (prov, val) not in seen:
                seen.add((prov, val))
                keys.append({
                    "source": f"ENV:{env_var}",
                    "provider": prov,
                    "key": val
                })

    # 3. Fallback built-in keys
    if include_fallback and not keys:
        try:
            decoded = base64.b64decode(FALLBACK_B64).decode("utf-8")
            for item in decoded.split(";"):
                item = item.strip()
                if ":" in item:
                    prov, key_val = item.split(":", 1)
                    prov = prov.strip().lower()
                    key_val = key_val.strip()
                    if key_val and (prov, key_val) not in seen:
                        seen.add((prov, key_val))
                        keys.append({
                            "source": "BUILTIN:FALLBACK",
                            "provider": prov,
                            "key": key_val
                        })
        except Exception:
            pass

    return keys

def test_gemini_key(key: str, verbose: bool = False):
    """Test Google Gemini API key across candidate models."""
    models_to_test = [
        "gemini-flash-lite-latest",
        "gemini-flash-latest",
        "gemini-2.5-flash-lite",
        "gemini-3.8-flash",
        "gemini-2.5-flash"
    ]

    best_result = {
        "status": "FAIL",
        "code": 0,
        "model": None,
        "latency_ms": 0,
        "details": "No models succeeded",
        "supports_vision": False
    }

    prompt_payload = json.dumps({
        "contents": [{"parts": [{"text": "Reply with strictly the single word: PONG"}]}],
        "generationConfig": {"maxOutputTokens": 10, "temperature": 0.0}
    }).encode("utf-8")

    for model in models_to_test:
        url = f"https://generativelanguage.googleapis.com/v1beta/models/{model}:generateContent?key={key}"
        headers = {"Content-Type": "application/json"}
        req = urllib.request.Request(url, data=prompt_payload, headers=headers)

        t0 = time.time()
        try:
            with urllib.request.urlopen(req, timeout=8) as resp:
                elapsed = int((time.time() - t0) * 1000)
                body = json.loads(resp.read().decode("utf-8"))
                candidates = body.get("candidates", [])
                text = ""
                if candidates and "parts" in candidates[0].get("content", {}):
                    text = candidates[0]["content"]["parts"][0].get("text", "").strip()

                # Also test vision capabilities
                has_vision = False
                try:
                    # 1x1 white png
                    tiny_png = "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII="
                    v_payload = json.dumps({
                        "contents": [{
                            "parts": [
                                {"inline_data": {"mime_type": "image/png", "data": tiny_png}},
                                {"text": "Respond OK"}
                            ]
                        }]
                    }).encode("utf-8")
                    v_req = urllib.request.Request(url, data=v_payload, headers=headers)
                    with urllib.request.urlopen(v_req, timeout=6) as v_resp:
                        if v_resp.status == 200:
                            has_vision = True
                except Exception:
                    pass

                return {
                    "status": "PASS",
                    "code": 200,
                    "model": model,
                    "latency_ms": elapsed,
                    "details": f"Text & {'Vision' if has_vision else 'NoVision'} verified (reply: '{text[:12]}')",
                    "supports_vision": has_vision
                }

        except urllib.error.HTTPError as e:
            elapsed = int((time.time() - t0) * 1000)
            err_text = ""
            try:
                err_body = json.loads(e.read().decode("utf-8"))
                err_text = err_body.get("error", {}).get("message", "")
            except Exception:
                pass

            if e.code == 429:
                best_result = {
                    "status": "QUOTA",
                    "code": 429,
                    "model": model,
                    "latency_ms": elapsed,
                    "details": "Quota / Rate limit exceeded (429)",
                    "supports_vision": False
                }
                break  # Key is rate limited on project level
            elif e.code == 503:
                best_result = {
                    "status": "BUSY",
                    "code": 503,
                    "model": model,
                    "latency_ms": elapsed,
                    "details": "Model service temporarily busy / high demand (503)",
                    "supports_vision": False
                }
            elif e.code == 404:
                # Model deprecated or unavailable, continue to next model
                continue
            elif e.code in (400, 401, 403):
                return {
                    "status": "INVALID",
                    "code": e.code,
                    "model": model,
                    "latency_ms": elapsed,
                    "details": f"Auth failed ({e.code}): {err_text[:40] if err_text else 'Invalid or expired key'}",
                    "supports_vision": False
                }
        except Exception as ex:
            best_result["details"] = str(ex)[:40]

    return best_result

def test_groq_key(key: str, verbose: bool = False):
    """Test Groq API key."""
    url = "https://api.groq.com/openai/v1/chat/completions"
    payload = json.dumps({
        "model": "llama-3.3-70b-versatile",
        "messages": [{"role": "user", "content": "Reply with 1 word: PONG"}],
        "max_tokens": 10
    }).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {key}"
    }

    t0 = time.time()
    try:
        req = urllib.request.Request(url, data=payload, headers=headers)
        with urllib.request.urlopen(req, timeout=10) as resp:
            elapsed = int((time.time() - t0) * 1000)
            data = json.loads(resp.read().decode("utf-8"))
            ans = data["choices"][0]["message"]["content"].strip()
            return {
                "status": "PASS",
                "code": 200,
                "model": "llama-3.3-70b-versatile",
                "latency_ms": elapsed,
                "details": f"Success (reply: '{ans[:12]}')",
                "supports_vision": False
            }
    except urllib.error.HTTPError as e:
        elapsed = int((time.time() - t0) * 1000)
        if e.code == 429:
            return {"status": "QUOTA", "code": 429, "model": "llama-3.3-70b", "latency_ms": elapsed, "details": "Rate limit exceeded (429)", "supports_vision": False}
        elif e.code in (401, 403):
            return {"status": "INVALID", "code": e.code, "model": "llama-3.3-70b", "latency_ms": elapsed, "details": "Forbidden / Invalid API Key", "supports_vision": False}
        return {"status": "FAIL", "code": e.code, "model": "llama-3.3-70b", "latency_ms": elapsed, "details": f"HTTP {e.code}", "supports_vision": False}
    except Exception as e:
        return {"status": "FAIL", "code": 0, "model": "llama-3.3-70b", "latency_ms": 0, "details": str(e)[:35], "supports_vision": False}

def test_openrouter_key(key: str, verbose: bool = False):
    """Test OpenRouter API key."""
    url = "https://openrouter.ai/api/v1/chat/completions"
    payload = json.dumps({
        "model": "openrouter/free",
        "messages": [{"role": "user", "content": "Reply with 1 word: PONG"}],
        "max_tokens": 10
    }).encode("utf-8")
    headers = {
        "Content-Type": "application/json",
        "Authorization": f"Bearer {key}",
        "HTTP-Referer": "https://github.com/Evangelion-eva/PSIT-OAS-Launcher-Modded-",
        "X-Title": "PSIT OAS"
    }

    t0 = time.time()
    try:
        req = urllib.request.Request(url, data=payload, headers=headers)
        with urllib.request.urlopen(req, timeout=12) as resp:
            elapsed = int((time.time() - t0) * 1000)
            data = json.loads(resp.read().decode("utf-8"))
            ans = data["choices"][0]["message"]["content"].strip()
            return {
                "status": "PASS",
                "code": 200,
                "model": "openrouter/free",
                "latency_ms": elapsed,
                "details": f"Success (reply: '{ans[:12]}')",
                "supports_vision": False
            }
    except urllib.error.HTTPError as e:
        elapsed = int((time.time() - t0) * 1000)
        if e.code == 429:
            return {"status": "QUOTA", "code": 429, "model": "openrouter/free", "latency_ms": elapsed, "details": "Quota / Rate limited", "supports_vision": False}
        return {"status": "INVALID" if e.code in (401, 403) else "FAIL", "code": e.code, "model": "openrouter/free", "latency_ms": elapsed, "details": f"HTTP {e.code}", "supports_vision": False}
    except Exception as e:
        return {"status": "FAIL", "code": 0, "model": "openrouter/free", "latency_ms": 0, "details": str(e)[:35], "supports_vision": False}

def test_notion_key(key: str, verbose: bool = False):
    """Test Notion Integration API Token."""
    url = "https://api.notion.com/v1/users/me"
    headers = {
        "Authorization": f"Bearer {key}",
        "Notion-Version": "2022-06-28"
    }

    t0 = time.time()
    try:
        req = urllib.request.Request(url, headers=headers)
        with urllib.request.urlopen(req, timeout=8) as resp:
            elapsed = int((time.time() - t0) * 1000)
            data = json.loads(resp.read().decode("utf-8"))
            name = data.get("name", "Notion Bot")
            bot_owner = data.get("bot", {}).get("owner", {}).get("type", "workspace")
            return {
                "status": "PASS",
                "code": 200,
                "model": "Notion API v1",
                "latency_ms": elapsed,
                "details": f"Connected as '{name}' ({bot_owner})",
                "supports_vision": False
            }
    except urllib.error.HTTPError as e:
        elapsed = int((time.time() - t0) * 1000)
        return {
            "status": "INVALID" if e.code in (401, 403) else "FAIL",
            "code": e.code,
            "model": "Notion API v1",
            "latency_ms": elapsed,
            "details": f"Notion auth error ({e.code})",
            "supports_vision": False
        }
    except Exception as e:
        return {"status": "FAIL", "code": 0, "model": "Notion API v1", "latency_ms": 0, "details": str(e)[:35], "supports_vision": False}

def run_suite(keys_file="keys.txt", verbose=False, include_fallback=False):
    """Run full diagnostic test on all discovered keys."""
    keys = load_keys(keys_file, include_env=True, include_fallback=include_fallback)

    print(f"\n{CLR_BOLD}================================================================================{CLR_RESET}")
    print(f"{CLR_BOLD}         PSIT OAS Launcher - API Key Diagnostic & Health Suite{CLR_RESET}")
    print(f"{CLR_BOLD}================================================================================{CLR_RESET}")
    print(f"Target Key File : {keys_file} ({'Found' if os.path.exists(keys_file) else 'Not Found'})")
    print(f"Total Discovered: {len(keys)} key(s)\n")

    if not keys:
        print(f"{CLR_RED}[!] No keys found in '{keys_file}' or environment variables.{CLR_RESET}")
        print("    Add keys in format:  gemini:<key>  or  groq:<key>  or  notion:<key>")
        print("    Run with --help for details.\n")
        return {"total": 0, "active": 0, "results": []}

    results = []
    print(f"{'#':<3} | {'Provider':<10} | {'Masked Key':<15} | {'Source':<16} | {'Status':<10} | {'Latency':<8} | {'Model / Details'}")
    print("-" * 88)

    for i, item in enumerate(keys, 1):
        prov = item["provider"]
        raw_key = item["key"]
        masked = mask_key(raw_key)
        src = item["source"]

        # Run test
        if prov == "gemini":
            res = test_gemini_key(raw_key, verbose=verbose)
        elif prov == "groq":
            res = test_groq_key(raw_key, verbose=verbose)
        elif prov == "openrouter":
            res = test_openrouter_key(raw_key, verbose=verbose)
        elif prov == "notion":
            res = test_notion_key(raw_key, verbose=verbose)
        else:
            res = {"status": "SKIP", "code": 0, "model": "N/A", "latency_ms": 0, "details": f"Unknown provider '{prov}'", "supports_vision": False}

        res["provider"] = prov
        res["masked_key"] = masked
        res["source"] = src
        res["raw_key"] = raw_key
        results.append(res)

        # Format status badge
        status = res["status"]
        if status == "PASS":
            status_badge = f"{CLR_GREEN}{CLR_BOLD}[PASS]{CLR_RESET}"
        elif status == "QUOTA":
            status_badge = f"{CLR_YELLOW}[QUOTA]{CLR_RESET}"
        elif status == "BUSY":
            status_badge = f"{CLR_YELLOW}[BUSY]{CLR_RESET}"
        elif status == "INVALID":
            status_badge = f"{CLR_RED}[INVALID]{CLR_RESET}"
        else:
            status_badge = f"{CLR_GRAY}[{status}]{CLR_RESET}"

        lat_str = f"{res['latency_ms']}ms" if res["latency_ms"] > 0 else "-"
        detail_str = f"{res.get('model') or ''}: {res.get('details', '')}"

        print(f"{i:<3} | {prov:<10} | {masked:<15} | {src:<16} | {status_badge:<19} | {lat_str:<8} | {detail_str}")

    print("-" * 88)
    active_count = sum(1 for r in results if r["status"] == "PASS")
    quota_count  = sum(1 for r in results if r["status"] in ("QUOTA", "BUSY"))
    failed_count = sum(1 for r in results if r["status"] in ("INVALID", "FAIL"))

    print(f"\n{CLR_BOLD}Summary Report:{CLR_RESET}")
    print(f"  {CLR_GREEN}Active / Working Keys:{CLR_RESET} {active_count}")
    print(f"  {CLR_YELLOW}Rate Limited / Busy  :{CLR_RESET} {quota_count}")
    print(f"  {CLR_RED}Invalid / Expired    :{CLR_RESET} {failed_count}")

    if active_count > 0:
        first_pass = next(r for r in results if r["status"] == "PASS")
        print(f"\n{CLR_GREEN}{CLR_BOLD}[OK] System is READY for stealth exam solving!{CLR_RESET}")
        print(f"  Primary working provider: {first_pass['provider'].upper()} ({first_pass['model']})")
    else:
        print(f"\n{CLR_RED}{CLR_BOLD}[!] WARNING: No working keys currently active.{CLR_RESET}")
        print("  Update 'keys.txt' with a valid Gemini, Groq, or OpenRouter API key.")

    return {"total": len(keys), "active": active_count, "results": results}

def main():
    parser = argparse.ArgumentParser(description="PSIT OAS API Key Diagnostics & Testing Suite")
    parser.add_argument("--file", "-f", default="keys.txt", help="Path to keys.txt file (default: keys.txt)")
    parser.add_argument("--json", action="store_true", help="Output results in JSON format")
    parser.add_argument("--verbose", "-v", action="store_true", help="Print detailed diagnostic payloads")
    parser.add_argument("--include-fallbacks", action="store_true", help="Test built-in launcher fallback keys as well")
    parser.add_argument("--export-active", metavar="OUT_FILE", help="Export active verified keys to a clean keys file")
    args = parser.parse_args()

    summary = run_suite(keys_file=args.file, verbose=args.verbose, include_fallback=args.include_fallbacks)

    if args.export_active and summary["active"] > 0:
        active_keys = [r for r in summary["results"] if r["status"] == "PASS"]
        with open(args.export_active, "w", encoding="utf-8") as out:
            out.write("# PSIT OAS Active Verified Keys\n")
            for r in active_keys:
                out.write(f"{r['provider']}:{r['raw_key']}\n")
        print(f"\n{CLR_CYAN}[i] Exported {len(active_keys)} active key(s) to '{args.export_active}'{CLR_RESET}")

    if args.json:
        # Strip raw keys before JSON output for security
        clean_results = []
        for r in summary["results"]:
            c = dict(r)
            c.pop("raw_key", None)
            clean_results.append(c)
        json_summary = {
            "timestamp": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
            "total_keys": summary["total"],
            "active_keys": summary["active"],
            "keys": clean_results
        }
        with open("keys_health_status.json", "w", encoding="utf-8") as jf:
            json.dump(json_summary, jf, indent=2)
        print(f"{CLR_CYAN}[i] Saved machine-readable status to 'keys_health_status.json'{CLR_RESET}")

    sys.exit(0 if summary["active"] > 0 else 1)

if __name__ == "__main__":
    main()
