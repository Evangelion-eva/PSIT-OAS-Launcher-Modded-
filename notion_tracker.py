#!/usr/bin/env python3
"""
PSIT OAS Launcher - Real Notion Tracking & Sync Engine
Synchronizes engineering tasks, bug audits, and API key health diagnostics
directly with Notion Database via the official Notion API (v1).
"""

import sys
import os
import json
import time
import re
import argparse
import urllib.request
import urllib.error

NOTION_API_VERSION = "2022-06-28"
NOTION_API_BASE = "https://api.notion.com/v1"

# ANSI Color Codes
CLR_RESET   = "\033[0m"
CLR_BOLD    = "\033[1m"
CLR_GREEN   = "\033[92m"
CLR_YELLOW  = "\033[93m"
CLR_RED     = "\033[91m"
CLR_CYAN    = "\033[96m"
CLR_BLUE    = "\033[94m"
CLR_MAGENTA = "\033[95m"

def get_notion_token(keys_file="keys.txt"):
    """Fetch Notion API token from env or keys.txt."""
    token = os.environ.get("NOTION_API_KEY") or os.environ.get("NOTION_TOKEN")
    if token:
        return token.strip()

    if os.path.exists(keys_file):
        with open(keys_file, "r", encoding="utf-8", errors="ignore") as f:
            for line in f:
                line = line.strip()
                if line.startswith("#") or not line:
                    continue
                if line.lower().startswith("notion:"):
                    return line.split(":", 1)[1].strip()
    return None

def parse_notion_tracking_md(md_path="NOTION_TRACKING.md"):
    """Parse tasks and bugs from NOTION_TRACKING.md."""
    if not os.path.exists(md_path):
        return []

    tasks = []
    with open(md_path, "r", encoding="utf-8", errors="ignore") as f:
        content = f.read()

    # Match table rows: | ID | Issue / Feature | Root Cause | Fix / Solution | Status |
    table_row_re = re.compile(
        r"^\|\s*\*\*([A-Z]+-\d+)\*\*\s*\|\s*\*\*([^*]+)\*\*\s*\|\s*([^|]+)\|\s*([^|]+)\|\s*([^|]+)\|",
        re.MULTILINE
    )

    for match in table_row_re.finditer(content):
        task_id = match.group(1).strip()
        title = match.group(2).strip()
        root_cause = match.group(3).strip().replace("<br>", " ")
        solution = match.group(4).strip().replace("<br>", " ")
        status = match.group(5).strip().replace("**", "")

        category = "Bug" if "BUG" in task_id else ("Feature" if "FEAT" in task_id else "Ops")
        priority = "P0" if "BUG" in task_id else "P1"

        tasks.append({
            "id": task_id,
            "title": title,
            "category": category,
            "priority": priority,
            "root_cause": root_cause,
            "solution": solution,
            "status": "Verified" if "Verified" in status or "Completed" in status else "In Progress"
        })

    return tasks

def check_notion_connection(token):
    """Verify Notion API authentication token."""
    url = f"{NOTION_API_BASE}/users/me"
    headers = {
        "Authorization": f"Bearer {token}",
        "Notion-Version": NOTION_API_VERSION
    }
    req = urllib.request.Request(url, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=10) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return True, data
    except urllib.error.HTTPError as e:
        return False, f"HTTP {e.code}: {e.read().decode('utf-8', errors='ignore')[:150]}"
    except Exception as e:
        return False, str(e)

def push_task_to_notion(token, database_id, task):
    """Create or update a task item in a Notion Database."""
    url = f"{NOTION_API_BASE}/pages"
    headers = {
        "Authorization": f"Bearer {token}",
        "Notion-Version": NOTION_API_VERSION,
        "Content-Type": "application/json"
    }

    payload = {
        "parent": {"database_id": database_id},
        "properties": {
            "Task ID": {
                "rich_text": [{"text": {"content": task["id"]}}]
            },
            "Name": {
                "title": [{"text": {"content": f"[{task['id']}] {task['title']}"}}]
            },
            "Category": {
                "select": {"name": task["category"]}
            },
            "Priority": {
                "select": {"name": task["priority"]}
            },
            "Status": {
                "status": {"name": "Done" if task["status"] == "Verified" else "In progress"}
            }
        },
        "children": [
            {
                "object": "block",
                "type": "heading_3",
                "heading_3": {
                    "rich_text": [{"type": "text", "text": {"content": "Root Cause Analysis"}}]
                }
            },
            {
                "object": "block",
                "type": "paragraph",
                "paragraph": {
                    "rich_text": [{"type": "text", "text": {"content": task["root_cause"]}}]
                }
            },
            {
                "object": "block",
                "type": "heading_3",
                "heading_3": {
                    "rich_text": [{"type": "text", "text": {"content": "Engineering Fix & Solution"}}]
                }
            },
            {
                "object": "block",
                "type": "paragraph",
                "paragraph": {
                    "rich_text": [{"type": "text", "text": {"content": task["solution"]}}]
                }
            }
        ]
    }

    req = urllib.request.Request(url, data=json.dumps(payload).encode("utf-8"), headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=12) as resp:
            data = json.loads(resp.read().decode("utf-8"))
            return True, data.get("url", "")
    except urllib.error.HTTPError as e:
        return False, f"HTTP {e.code}: {e.read().decode('utf-8', errors='ignore')[:120]}"
    except Exception as e:
        return False, str(e)

def display_cli_board(tasks):
    """Display an interactive Notion-style Kanban Board in console."""
    print(f"\n{CLR_BOLD}================================================================================{CLR_RESET}")
    print(f"{CLR_BOLD}        PSIT OAS Launcher - Notion Engineering Tracker Board{CLR_RESET}")
    print(f"{CLR_BOLD}================================================================================{CLR_RESET}\n")

    print(f"{'ID':<10} | {'Type':<8} | {'Pri':<4} | {'Status':<12} | {'Task / Feature Title'}")
    print("-" * 88)

    for t in tasks:
        pri_color = CLR_RED if t["priority"] == "P0" else CLR_YELLOW
        status_color = CLR_GREEN if t["status"] == "Verified" else CLR_CYAN
        cat_badge = f"{CLR_MAGENTA}{t['category']:<8}{CLR_RESET}"
        status_badge = f"{status_color}{t['status']:<12}{CLR_RESET}"

        print(f"{t['id']:<10} | {cat_badge} | {pri_color}{t['priority']:<4}{CLR_RESET} | {status_badge} | {t['title'][:45]}")

    print("-" * 88)
    verified_count = sum(1 for t in tasks if t["status"] == "Verified")
    print(f"{CLR_BOLD}Board Stats:{CLR_RESET} Total Tasks: {len(tasks)} | Verified: {verified_count} | Pending: {len(tasks) - verified_count}\n")

def export_notion_schema(tasks, out_file="notion_database_template.json"):
    """Export complete Notion database schema and rows as JSON."""
    schema = {
        "title": "PSIT OAS Launcher Engineering & Audit Tracker",
        "description": "Notion tracking database export for PSIT OAS Launcher (Modded)",
        "last_synced": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "schema_properties": {
            "Task ID": {"type": "rich_text"},
            "Name": {"type": "title"},
            "Category": {"type": "select", "options": ["Bug", "Feature", "Ops"]},
            "Priority": {"type": "select", "options": ["P0", "P1", "P2"]},
            "Status": {"type": "status", "options": ["Done", "In progress", "Not started"]}
        },
        "records": tasks
    }
    with open(out_file, "w", encoding="utf-8") as f:
        json.dump(schema, f, indent=2)
    print(f"{CLR_CYAN}[i] Exported Notion database template to '{out_file}'{CLR_RESET}")

def main():
    parser = argparse.ArgumentParser(description="PSIT OAS Launcher - Notion Tracking Engine")
    parser.add_argument("--sync", action="store_true", help="Sync tasks to remote Notion database")
    parser.add_argument("--database-id", "-d", help="Notion Database ID to sync into")
    parser.add_argument("--token", "-t", help="Notion API integration token")
    parser.add_argument("--export", action="store_true", help="Export Notion schema template JSON")
    parser.add_argument("--tracker-file", default="NOTION_TRACKING.md", help="Path to NOTION_TRACKING.md")
    args = parser.parse_args()

    tasks = parse_notion_tracking_md(args.tracker_file)
    display_cli_board(tasks)

    if args.export or not args.sync:
        export_notion_schema(tasks)

    if args.sync:
        token = args.token or get_notion_token()
        db_id = args.database_id or os.environ.get("NOTION_DATABASE_ID")

        if not token:
            print(f"{CLR_RED}[!] Error: Notion API token not found.{CLR_RESET}")
            print("    Please set NOTION_API_KEY environment variable or add 'notion:<secret_token>' in keys.txt")
            sys.exit(1)

        print(f"{CLR_CYAN}[i] Authenticating with Notion API...{CLR_RESET}")
        ok, auth_data = check_notion_connection(token)
        if not ok:
            print(f"{CLR_RED}[!] Notion authentication failed: {auth_data}{CLR_RESET}")
            sys.exit(1)

        bot_name = auth_data.get("name", "Notion Bot")
        print(f"{CLR_GREEN}[✓] Authenticated as '{bot_name}'!{CLR_RESET}")

        if not db_id:
            print(f"\n{CLR_YELLOW}[i] No Notion Database ID provided.{CLR_RESET}")
            print("    To sync directly into an existing Notion database, supply --database-id <id>")
            print("    or set the NOTION_DATABASE_ID environment variable.")
            print("    All tasks and schema are exported in 'notion_database_template.json' for instant import.")
        else:
            print(f"{CLR_CYAN}[i] Syncing {len(tasks)} items to Notion Database '{db_id}'...{CLR_RESET}")
            pushed = 0
            for t in tasks:
                ok, res = push_task_to_notion(token, db_id, t)
                if ok:
                    print(f"  {CLR_GREEN}[✓]{CLR_RESET} [{t['id']}] Synced -> {res}")
                    pushed += 1
                else:
                    print(f"  {CLR_RED}[✗]{CLR_RESET} [{t['id']}] Failed: {res}")
            print(f"\n{CLR_GREEN}[✓] Successfully synced {pushed}/{len(tasks)} tasks to Notion!{CLR_RESET}")

if __name__ == "__main__":
    main()
