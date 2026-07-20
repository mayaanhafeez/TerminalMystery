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
    python3 headless/llm_player.py --full-explore --max-turns 150

--full-explore forces a completionist playthrough: the model is told to visit
every room and read every file before accusing, and any `accuse` attempted
before that (per headless/serve.lua's rooms=/files= coverage fields) is
intercepted client-side and never reaches the game — the model is shown
exactly what it's missing (via the engine's `__coverage__` query) and gets
another turn instead. Without the flag, behavior is unchanged: the model can
accuse the moment it decides to, same as before.
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

The house is a TREE, not a flat list of rooms: almost every room hangs off \
one central room (shown as `~`), and `cd <room>` ONLY works if <room> is \
either that central room or one of its direct children — you cannot jump \
directly between two side rooms. Every turn you'll be shown your exact \
location as a path, e.g. "[You are in: ~/home_office]" or \
"[You are in: ~/den/.closet]" (a room nested inside another room). Read that \
line before every `cd`:
  - If you're at "~" (the central room), `cd <room>` reaches any of its \
direct children directly.
  - If you're anywhere else (e.g. "~/home_office"), `cd <room>` only reaches \
"~" itself (via `cd ..`) or a room nested under where you are — to reach a \
DIFFERENT room, first go up with `cd ..`, then `cd <room>` (or do both at \
once: `cd ../<room>`).
Never assume a `cd` will work just because the room exists somewhere in the \
house — check your current path first.

Available commands:
  ls [-a]                    list this room (-a shows hidden files)
  cd <room>                  move to a direct child of here, or `cd ..` to go up (see the path rule above)
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

For EVERY turn, respond with ONLY a single JSON object, nothing before or \
after it — no markdown fences, no extra prose:

{"reason": "<one short sentence — why this command, given what you've learned so far>", "command": "<a single valid command from the list above>"}

Keep "reason" to one short sentence. "command" is what actually runs, so it \
must be exactly one command with no extra words. Do not explain your \
reasoning outside the "reason" field — decide, then answer immediately.
"""

FULL_EXPLORE_ADDENDUM = """

COMPLETIONIST MODE: before you accuse, you must visit every room and read \
every file — including hidden ones (try `ls -a` in each room; some evidence \
only shows up that way, and at least one room isn't listed by plain `ls` at \
all). You can check your progress anytime with the command `__coverage__`, \
which reports how many rooms/files you've covered and lists exactly what's \
left. If you try to accuse before everything is covered, it will be blocked \
and you'll be shown what's missing instead — so keep exploring until \
`__coverage__` shows full coverage, then accuse.
"""

STALL_WINDOW = 8  # identical trailing commands within this window => stalled
MAX_PARSE_RETRIES = 2  # extra Ollama calls per turn if the reply has no usable command
MAX_CONSECUTIVE_PARSE_FAILURES = 3  # whole turns (each already retried) before giving up the run

KNOWN_VERBS = {
    "ls", "cd", "pwd", "cwd", "cat", "grep", "find", "diff", "sed",
    "mv", "cp", "rm", "chmod", "echo", "help", "accuse", "__coverage__",
    "exit", "quit",  # not advertised to the model, but real engine.lua verbs
}

# Ollama structured-output schema (the "format" field): grammar-constrains
# decoding so the model can't wander off into prose without ever producing a
# command, the failure mode that motivated this file's REASON:/COMMAND: text
# format in the first place. Older Ollama servers that don't understand a
# schema object here return an HTTP error, in which case call_ollama's caller
# falls back to plain-text prompting (parse_reply understands both).
RESPONSE_SCHEMA = {
    "type": "object",
    "properties": {
        "reason": {"type": "string"},
        "command": {"type": "string"},
    },
    "required": ["command"],
}

FORMAT_NUDGE = (
    'Your last reply did not contain a usable command. Respond again with ONLY '
    'one line of valid JSON: {"reason": "...", "command": "..."} where "command" '
    "is exactly one of: " + ", ".join(sorted(KNOWN_VERBS - {"__coverage__"})) + "."
)


def read_turn(proc):
    """Reads one turn from serve.lua: output lines up to <<END>>, then the
    STATUS line (and ERROR_DETAIL line, if present). Returns a dict."""
    lines = []
    while True:
        line = proc.stdout.readline()
        if line == "":
            return {"output": "\n".join(lines), "status": "CRASHED",
                    "commands": None, "elapsed": None, "room": None, "error": "subprocess exited unexpectedly",
                    "rooms_visited": None, "rooms_total": None, "files_read": None, "files_total": None,
                    "path": None}
        line = line.rstrip("\n")
        if line == "<<END>>":
            break
        lines.append(line)

    status_line = proc.stdout.readline().rstrip("\n")
    # STATUS <word> commands=<n> elapsed=<n> room=<id> rooms=<v>/<t> files=<r>/<t> path=<~/room/subroom>
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

    rooms_visited = rooms_total = files_read = files_total = None
    if "/" in fields.get("rooms", ""):
        rooms_visited, rooms_total = (int(x) for x in fields["rooms"].split("/", 1))
    if "/" in fields.get("files", ""):
        files_read, files_total = (int(x) for x in fields["files"].split("/", 1))

    return {
        "output": "\n".join(lines),
        "status": status,
        "commands": int(fields["commands"]) if "commands" in fields else None,
        "elapsed": float(fields["elapsed"]) if "elapsed" in fields else None,
        "room": fields.get("room"),
        "error": error_detail,
        "rooms_visited": rooms_visited,
        "rooms_total": rooms_total,
        "files_read": files_read,
        "files_total": files_total,
        "path": fields.get("path"),
    }


def send_and_read(proc, command):
    proc.stdin.write(command + "\n")
    proc.stdin.flush()
    return read_turn(proc)


def with_location(turn):
    """Prepends the current ~/room/subroom path to a turn's output before it
    goes to the model — the room tree isn't flat, and a model that only sees
    prose descriptions loses track of where `cd ..` vs `cd <room>` leads."""
    if turn.get("path"):
        return f"[You are in: {turn['path']}]\n\n{turn['output']}"
    return turn["output"]


def coverage_complete(turn):
    return (turn.get("rooms_visited") is not None
            and turn["rooms_visited"] >= turn["rooms_total"]
            and turn["files_read"] >= turn["files_total"])


def call_ollama(host, model, messages, timeout=120, use_schema=True):
    body_obj = {"model": model, "messages": messages, "stream": False,
                "options": {"num_predict": 512}}
    if use_schema:
        body_obj["format"] = RESPONSE_SCHEMA
    body = json.dumps(body_obj).encode("utf-8")
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
    """Splits a model reply into (reason, command, ok).

    Tries structured JSON first (what the schema in call_ollama asks for),
    then the legacy REASON:/COMMAND: text labels (in case the Ollama server
    doesn't support `format` schemas and the model fell back to prose), then
    best-effort single-line extraction as a last resort.

    ok is True only if `command`'s first token is a known game verb — a small
    model can produce syntactically fine JSON/text whose "command" is really
    just more rambling (e.g. {"command": "I should check the den next"}), and
    that's exactly the case a bare parse can't distinguish from a real command
    without this check. The caller uses ok to decide whether to retry rather
    than forward garbage into the game.
    """
    reason, command = None, None

    try:
        data = json.loads(reply.strip())
        if isinstance(data, dict) and data.get("command"):
            reason = str(data.get("reason") or "").strip() or None
            command = clean_command_token(str(data["command"]))
    except (json.JSONDecodeError, TypeError):
        pass

    if command is None:
        for raw_line in reply.splitlines():
            line = raw_line.strip()
            upper = line.upper()
            if upper.startswith("REASON:"):
                reason = line.split(":", 1)[1].strip()
            elif upper.startswith("COMMAND:"):
                command = clean_command_token(line.split(":", 1)[1])

    if command is None:
        command = extract_command(reply)

    reason = reason or "(no reason given)"
    first_token = command.split(None, 1)[0].lower() if command else ""
    ok = first_token in KNOWN_VERBS
    return reason, command, ok


def run_once(model, host, seed, max_turns, verbose, full_explore=False):
    args = ["lua", SERVE_SCRIPT]
    if seed is not None:
        args += ["--seed", str(seed)]
    proc = subprocess.Popen(
        args, cwd=ROOT, stdin=subprocess.PIPE, stdout=subprocess.PIPE,
        text=True, bufsize=1,
    )

    transcript = []
    system_prompt = SYSTEM_PROMPT + (FULL_EXPLORE_ADDENDUM if full_explore else "")
    messages = [{"role": "system", "content": system_prompt}]

    turn = read_turn(proc)
    messages.append({"role": "user", "content": with_location(turn)})
    transcript.append({"turn": 0, "game_output": turn["output"], "reason": None, "command": None})

    recent_commands = []
    result = {"solved": False, "turns": 0, "commands": 0, "elapsed": 0,
              "final_room": turn["room"], "stalled": False, "status": turn["status"],
              "rooms_visited": turn["rooms_visited"], "rooms_total": turn["rooms_total"],
              "files_read": turn["files_read"], "files_total": turn["files_total"],
              "parse_failures": 0}

    if turn["status"] != "OK":
        proc.wait(timeout=5)
        result["status"] = turn["status"]
        return result, transcript

    schema_supported = True

    def ask_model():
        nonlocal schema_supported
        if schema_supported:
            try:
                return call_ollama(host, model, messages, use_schema=True)
            except urllib.error.HTTPError:
                schema_supported = False  # this Ollama server/model rejects the schema; don't retry it every turn
        return call_ollama(host, model, messages, use_schema=False)

    consecutive_parse_failures = 0
    start_wall = time.time()
    for i in range(1, max_turns + 1):
        reason = command = None
        ok = False
        try:
            for attempt in range(MAX_PARSE_RETRIES + 1):
                reply = ask_model()
                reason, command, ok = parse_reply(reply)
                if ok:
                    break
                # Malformed: let the model see its own reply (truncated, so a
                # rambling non-answer doesn't balloon context) plus a nudge,
                # then retry within the same turn.
                messages.append({"role": "assistant", "content": reply.strip()[:300]})
                messages.append({"role": "user", "content": FORMAT_NUDGE})
        except (urllib.error.URLError, TimeoutError) as e:
            result["status"] = "OLLAMA_ERROR"
            result["error"] = str(e)
            break

        print(f"  [{i}] {command}" + ("" if ok else "  [unparseable after retries — not sent]"))
        print(f"       reason: {reason}")

        if not ok:
            # Every retry produced something that isn't a real command
            # (rambling, truncation, wrong format). Forwarding it would just
            # burn a turn on "you mutter ... under your breath" — skip the
            # game entirely and let the model try again next turn.
            transcript.append({"turn": i, "game_output": None, "reason": reason,
                                "command": command, "blocked": False, "parse_failed": True})
            result["turns"] = i
            result["parse_failures"] += 1
            consecutive_parse_failures += 1
            if consecutive_parse_failures >= MAX_CONSECUTIVE_PARSE_FAILURES:
                result["status"] = "PARSE_FAILED"
                break
            continue
        consecutive_parse_failures = 0

        # Feed the model's own (raw) reply back as its turn in the
        # conversation, not just the bare command — keeps it consistent about
        # the expected format across turns.
        messages.append({"role": "assistant", "content": reply.strip()})

        blocked = full_explore and command.strip().lower().startswith("accuse") and not coverage_complete(turn)
        try:
            if blocked:
                # Don't forward the accusation at all — query coverage instead
                # so the model sees exactly what it's missing, and gets
                # another turn rather than ending the game early.
                turn = send_and_read(proc, "__coverage__")
                turn["output"] += (
                    f"\n\nYour `{command}` was NOT sent — investigation is incomplete "
                    "(see above). Keep exploring: visit every remaining room and read "
                    "every remaining file, then accuse."
                )
            else:
                turn = send_and_read(proc, command)
        except BrokenPipeError:
            result["status"] = "CRASHED"
            break

        transcript.append({"turn": i, "game_output": turn["output"], "reason": reason,
                            "command": command, "blocked": blocked})
        messages.append({"role": "user", "content": with_location(turn)})

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
        if turn["rooms_visited"] is not None:
            result["rooms_visited"] = turn["rooms_visited"]
            result["rooms_total"] = turn["rooms_total"]
            result["files_read"] = turn["files_read"]
            result["files_total"] = turn["files_total"]

        if blocked:
            # The real game state is untouched (we sent __coverage__, not the
            # accusation) — a blocked attempt can never end the run.
            if stalled:
                result["stalled"] = True
                break
            continue

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
    ap.add_argument("--full-explore", action="store_true",
                     help="force a completionist run: block `accuse` until every room and "
                          "file has been covered (default: model can accuse whenever it wants)")
    args = ap.parse_args()

    os.makedirs(args.log_dir, exist_ok=True)

    summaries = []
    for run_i in range(1, args.runs + 1):
        run_seed = (args.seed + run_i) if args.seed is not None else None
        print(f"Run {run_i}/{args.runs} (model={args.model}, seed={run_seed}) ...")
        result, transcript = run_once(args.model, args.host, run_seed, args.max_turns, args.verbose,
                                       full_explore=args.full_explore)
        summaries.append(result)

        log_path = os.path.join(args.log_dir, f"run_{run_i}_{int(time.time())}.json")
        with open(log_path, "w") as f:
            json.dump({"result": result, "transcript": transcript}, f, indent=2)

        status_word = "SOLVED" if result["solved"] else ("STALLED" if result.get("stalled") else result["status"])
        print(f"  -> {status_word} in {result['turns']} turns, "
              f"{result['commands']} commands, {result['elapsed']:.0f}s in-game, "
              f"room={result['final_room']}, "
              f"rooms={result['rooms_visited']}/{result['rooms_total']} "
              f"files={result['files_read']}/{result['files_total']}  [log: {log_path}]")
        if result.get("parse_failures"):
            print(f"     {result['parse_failures']} turn(s) had no usable command even after retries")
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
