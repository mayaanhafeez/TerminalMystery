#!/usr/bin/env python3
"""headless/llm_player.py — drive Terminal Mystery with a local Ollama model.

Spawns `lua headless/serve.lua` per playthrough and holds a chat loop with a
local Ollama model: the game's output becomes the user turn, and the model is
asked to reply with both a one-line REASON and a COMMAND — only the COMMAND is
sent to the game, but the reasoning is printed live and saved in the
transcript, so a human can read back *why* the model made each move. Runs one
or more playthroughs back to back and reports solved?/commands/time per run
plus an aggregate summary — the "play it on a loop, check solve times" half of
the headless tooling (the other half is headless/fuzz.lua, which hunts
crashes with a scripted fuzzer instead of an LLM).

No third-party dependencies — stdlib only (urllib for the Ollama HTTP call).

Usage:
    python3 headless/llm_player.py --runs 5
    python3 headless/llm_player.py --model gemma3n:e4b --max-turns 80
    python3 headless/llm_player.py --seed 42 --log-dir headless/llm_logs
"""

import argparse
import json
import os
import subprocess
import sys
import time
import urllib.error
import urllib.request

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
SERVE_SCRIPT = os.path.join(ROOT, "headless", "serve.lua")

SYSTEM_PROMPT = """You are a detective playing a text-adventure murder mystery \
through a Unix-like terminal.

Available commands:
  ls [-a]                    list this room (-a shows hidden files)
  cd <room>                  move to an adjacent room (cd .. goes back, cd goes home)
  pwd / cwd                  print current / previous room
  cat <file>                 read a file
  grep [-r -v -n -l -a] <pattern> [file|*|.[^.]*]   search (grep -r searches every visited room)
  find <name>                find a file by name across visited rooms
  diff <file1> <file2>       compare two files (both must be cat'd first)
  sed 's/old/new/[g]' <file>          preview a substitution
  sed -i 's/old/new/[g]' <file>       apply it in place (needs chmod +w first)
  mv <file> <room>           move a file to a visited room
  cp <file> <room>           copy a file to a visited room
  chmod <mode> <target>      chmod +w <file> to make it writable; chmod <code> <room> to unlock a keypad door
  rm -f <file>                destroy a file (irreversible)
  help                       list commands in-game
  accuse <name>               name the murderer — only do this once you are certain

Explore every room, read the evidence, and cross-reference names and times.
When you have solid proof of who did it, respond with: accuse <surname>

For EVERY turn, respond in EXACTLY this two-line format and nothing else — no \
markdown fences, no extra lines:

REASON: <one short sentence — why this command, given what you've learned so far>
COMMAND: <a single valid command from the list above>

The REASON line is read by a human afterward, not executed. The COMMAND line \
is what actually runs, so it must be exactly one command with no extra words.
"""

STALL_WINDOW = 8  # identical trailing commands within this window => stalled


def read_turn(proc):
    """Reads one turn from serve.lua: output lines up to <<END>>, then the
    STATUS line (and ERROR_DETAIL line, if present). Returns a dict."""
    lines = []
    while True:
        line = proc.stdout.readline()
        if line == "":
            return {"output": "\n".join(lines), "status": "CRASHED",
                    "commands": None, "elapsed": None, "room": None, "error": "subprocess exited unexpectedly"}
        line = line.rstrip("\n")
        if line == "<<END>>":
            break
        lines.append(line)

    status_line = proc.stdout.readline().rstrip("\n")
    # STATUS <word> commands=<n> elapsed=<n> room=<id>
    parts = status_line.split()
    status = parts[1] if len(parts) > 1 else "ERROR"
    fields = {}
    for p in parts[2:]:
        if "=" in p:
            k, v = p.split("=", 1)
            fields[k] = v

    error_detail = None
    if status == "ERROR":
        detail_line = proc.stdout.readline().rstrip("\n")
        if detail_line.startswith("ERROR_DETAIL "):
            error_detail = detail_line[len("ERROR_DETAIL "):]

    return {
        "output": "\n".join(lines),
        "status": status,
        "commands": int(fields["commands"]) if "commands" in fields else None,
        "elapsed": float(fields["elapsed"]) if "elapsed" in fields else None,
        "room": fields.get("room"),
        "error": error_detail,
    }


def call_ollama(host, model, messages, timeout=120):
    body = json.dumps({"model": model, "messages": messages, "stream": False}).encode("utf-8")
    req = urllib.request.Request(
        f"{host}/api/chat", data=body,
        headers={"Content-Type": "application/json"}, method="POST",
    )
    with urllib.request.urlopen(req, timeout=timeout) as resp:
        data = json.loads(resp.read().decode("utf-8"))
    return data["message"]["content"]


def clean_command_token(text):
    """Strip fencing/prompt cruft a model might wrap a bare command in."""
    text = text.strip().strip("`").strip()
    text = text.lstrip("$> ").strip()
    return text


def extract_command(reply):
    """Fallback for a reply that didn't follow the REASON:/COMMAND: format:
    best-effort pull of one command line out of whatever came back, which may
    include code fences or stray commentary."""
    text = reply.strip()
    if "```" in text:
        parts = text.split("```")
        # Prefer the first fenced block's content if one exists.
        if len(parts) >= 2:
            fenced = parts[1]
            fenced = fenced.split("\n", 1)[-1] if "\n" in fenced else fenced
            text = fenced.strip() or text
    line = text.splitlines()[0].strip() if text.splitlines() else text
    return clean_command_token(line)


def parse_reply(reply):
    """Splits a model reply into (reason, command) per the REASON:/COMMAND:
    format the system prompt asks for. Falls back to best-effort single-line
    command extraction if the model didn't follow it (small models sometimes
    drift from the format despite instructions)."""
    reason, command = None, None
    for raw_line in reply.splitlines():
        line = raw_line.strip()
        upper = line.upper()
        if upper.startswith("REASON:"):
            reason = line.split(":", 1)[1].strip()
        elif upper.startswith("COMMAND:"):
            command = clean_command_token(line.split(":", 1)[1])
    if command:
        return reason or "(no reason given)", command
    return "(model did not follow the REASON:/COMMAND: format)", extract_command(reply)


def run_once(model, host, seed, max_turns, verbose):
    args = ["lua", SERVE_SCRIPT]
    if seed is not None:
        args += ["--seed", str(seed)]
    proc = subprocess.Popen(
        args, cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        text=True, bufsize=1,
    )

    transcript = []
    messages = [{"role": "system", "content": SYSTEM_PROMPT}]

    turn = read_turn(proc)
    messages.append({"role": "user", "content": turn["output"]})
    transcript.append({"turn": 0, "game_output": turn["output"], "reason": None, "command": None})

    recent_commands = []
    result = {"solved": False, "turns": 0, "commands": 0, "elapsed": 0,
              "final_room": turn["room"], "stalled": False, "status": turn["status"]}

    if turn["status"] != "OK":
        proc.wait(timeout=5)
        result["status"] = turn["status"]
        return result, transcript

    start_wall = time.time()
    for i in range(1, max_turns + 1):
        try:
            reply = call_ollama(host, model, messages)
        except (urllib.error.URLError, TimeoutError) as e:
            result["status"] = "OLLAMA_ERROR"
            result["error"] = str(e)
            break

        reason, command = parse_reply(reply)
        print(f"  [{i}] {command}")
        print(f"       reason: {reason}")

        # Feed the model's own (raw) reply back as its turn in the
        # conversation, not just the bare command — keeps it consistent about
        # the REASON:/COMMAND: format across turns.
        messages.append({"role": "assistant", "content": reply.strip()})

        try:
            proc.stdin.write(command + "\n")
            proc.stdin.flush()
        except BrokenPipeError:
            result["status"] = "CRASHED"
            break

        turn = read_turn(proc)
        transcript.append({"turn": i, "game_output": turn["output"], "reason": reason, "command": command})
        messages.append({"role": "user", "content": turn["output"]})

        if verbose:
            print(f"       -> {turn['output'][:300]}{'...' if len(turn['output']) > 300 else ''}")

        recent_commands.append(command.lower())
        if len(recent_commands) > STALL_WINDOW:
            recent_commands.pop(0)
        stalled = (len(recent_commands) == STALL_WINDOW
                   and len(set(recent_commands)) <= 2)

        result["turns"] = i
        result["commands"] = turn["commands"] if turn["commands"] is not None else result["commands"]
        result["elapsed"] = turn["elapsed"] if turn["elapsed"] is not None else result["elapsed"]
        result["final_room"] = turn["room"] or result["final_room"]
        result["status"] = turn["status"]

        if turn["status"] == "WON":
            result["solved"] = True
            break
        if turn["status"] in ("ENDED", "ERROR", "CRASHED"):
            if turn["status"] == "ERROR":
                result["error"] = turn["error"]
            break
        if stalled:
            result["stalled"] = True
            break

    result["wall_time"] = time.time() - start_wall

    if proc.poll() is None:
        proc.terminate()
        try:
            proc.wait(timeout=5)
        except subprocess.TimeoutExpired:
            proc.kill()

    return result, transcript


def main():
    ap = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    ap.add_argument("--model", default="gemma4:e4b", help="Ollama model tag (default: gemma4:e4b)")
    ap.add_argument("--host", default="http://localhost:11434", help="Ollama API base URL")
    ap.add_argument("--runs", type=int, default=1, help="number of playthroughs to run back to back")
    ap.add_argument("--max-turns", type=int, default=60, help="turn cap per playthrough")
    ap.add_argument("--seed", type=int, default=None, help="base seed; each run uses seed+run_index")
    ap.add_argument("--log-dir", default=os.path.join(ROOT, "headless", "llm_logs"),
                     help="directory to write per-run transcript JSON files")
    ap.add_argument("--verbose", action="store_true",
                     help="also print a snippet of the game's response after each command "
                          "(the command + its reasoning are always printed)")
    args = ap.parse_args()

    os.makedirs(args.log_dir, exist_ok=True)

    summaries = []
    for run_i in range(1, args.runs + 1):
        run_seed = (args.seed + run_i) if args.seed is not None else None
        print(f"Run {run_i}/{args.runs} (model={args.model}, seed={run_seed}) ...")
        result, transcript = run_once(args.model, args.host, run_seed, args.max_turns, args.verbose)
        summaries.append(result)

        log_path = os.path.join(args.log_dir, f"run_{run_i}_{int(time.time())}.json")
        with open(log_path, "w") as f:
            json.dump({"result": result, "transcript": transcript}, f, indent=2)

        status_word = "SOLVED" if result["solved"] else ("STALLED" if result.get("stalled") else result["status"])
        print(f"  -> {status_word} in {result['turns']} turns, "
              f"{result['commands']} commands, {result['elapsed']:.0f}s in-game, "
              f"room={result['final_room']}  [log: {log_path}]")
        if result.get("error"):
            print(f"     error: {result['error']}")

    solved = [r for r in summaries if r["solved"]]
    print(f"\n{len(solved)}/{len(summaries)} runs solved.")
    if solved:
        avg_cmds = sum(r["commands"] for r in solved) / len(solved)
        avg_elapsed = sum(r["elapsed"] for r in solved) / len(solved)
        avg_turns = sum(r["turns"] for r in solved) / len(solved)
        print(f"  solved avg: {avg_turns:.1f} LLM turns, {avg_cmds:.1f} commands, {avg_elapsed:.0f}s in-game")
    unsolved = [r for r in summaries if not r["solved"]]
    if unsolved:
        rooms = {}
        for r in unsolved:
            rooms[r["final_room"]] = rooms.get(r["final_room"], 0) + 1
        print(f"  unsolved stuck-room breakdown: {rooms}")


if __name__ == "__main__":
    try:
        main()
    except KeyboardInterrupt:
        sys.exit(130)
