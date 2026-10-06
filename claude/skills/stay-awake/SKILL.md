---
name: stay-awake
description: >-
  Keep this Mac awake so remote sessions (SSH, screen sharing, remote control)
  stay reachable, with a daily morning check-in that renews automatically unless
  the user says stop. Use when the user wants to prevent idle sleep for a long
  remote-work session. Triggers on "/stay-awake" (and "/stay-awake stop" to end
  it). An argument like "/stay-awake 08:15" sets the morning check-in time.
---

# Stay Awake

Hold a macOS power assertion (`caffeinate`) that survives Claude session ends and
connection drops, and check in once each morning. **The check-in renews first and
asks second**, so silence means "keep going".

## How it works (read this before acting)

- `caffeinate` registers a system-wide IOKit power assertion. **One** is enough —
  the whole Mac stays awake as long as it runs. Launch it **detached** (`nohup`)
  so it outlives this shell, this Claude session, and any dropped connection.
- A **hard timeout backstop** (`-t 90000` = 25 h) guarantees it self-expires if
  the daily check-in never fires. 25 h deliberately exceeds the 24 h cycle so a
  punctual renewal never leaves a coverage gap.
- The **daily check-in is a session-only cron** (`CronCreate`, `recurring: true`).
  It only fires while *this Claude session* is running and idle, and it
  **auto-expires after 7 days**. If the session closes, the reminder is lost but
  the caffeinate keeps protecting the Mac until its 25-hour backstop. **State
  both limits to the user when you start it.**

## Renew-first: why the check-in does not block on an answer

`AskUserQuestion` blocks until the user replies — there is no timeout, and
nothing runs alongside it. A check-in that asks *before* renewing therefore
stalls indefinitely when the user is away, and the assertion lapses while the
question sits unanswered.

So the check-in **renews the assertion immediately, then asks whether to stop.**
No reply leaves the Mac awake for another 24 h, which is the desired default.
A late `STOP` still works — killing a fresh assertion costs nothing.

**Never** gate the renewal behind the answer.

## Which mode is active? Check launchd first

Two mechanisms can hold the assertion. **Always check for the LaunchAgent before
touching the pidfile** — if the agent is loaded, it owns the assertion and the
pidfile is stale.

```bash
launchctl print gui/$(id -u)/com.$USER.stay-awake >/dev/null 2>&1 \
  && echo "launchd mode (durable)" || echo "session mode (pidfile)"
```

- **launchd mode** — a LaunchAgent runs `caffeinate -i -s` with `KeepAlive`.
  Survives session death, connection drops, and reboots. No drift, no expiry, no
  daily check-in. Runs until explicitly booted out. This is the durable setup.
- **session mode** — the `nohup` + pidfile + cron approach below. Use only when
  the user explicitly wants the time-boxed, check-in-driven behavior.

Never run both: two assertions are redundant, and the session cron's renewal
would spawn a second `caffeinate` outside launchd's control.

## If the argument is `stop`

Run the stop path and finish — do not start or schedule anything. Handle **both**
mechanisms, since either may be active.

```bash
# 1. launchd mode — bootout the agent (KeepAlive means killing the PID is not enough)
if launchctl print gui/$(id -u)/com.$USER.stay-awake >/dev/null 2>&1; then
  launchctl bootout gui/$(id -u)/com.$USER.stay-awake \
    && echo "booted out LaunchAgent"
else
  echo "no LaunchAgent loaded"
fi

# 2. session mode — kill the tracked PID
PIDFILE="$HOME/.claude/stay-awake.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  kill "$(cat "$PIDFILE")" && echo "stopped caffeinate PID $(cat "$PIDFILE")"
else
  echo "no session caffeinate was running"
fi
rm -f "$PIDFILE"
```

**`kill` alone will not stop launchd mode** — `KeepAlive` respawns it within
seconds. `bootout` is required.

To disable it across reboots as well, also remove the plist:
`rm ~/Library/LaunchAgents/com.$USER.stay-awake.plist`. Leaving the plist
in place but booted out means it returns at next login.

Then call `CronList` and `CronDelete` **every** job whose prompt mentions
`stay-awake` (including the recurring daily one), and confirm to the user that
the Mac can now sleep normally. Verify with
`pmset -g assertions | grep PreventUserIdleSystemSleep`.

## Start path (default, no argument)

### Step 1 — Launch a detached caffeinate, retiring any predecessor

Retire an existing assertion rather than refusing to start, so re-invoking always
yields a full fresh window while keeping exactly one assertion alive.

```bash
PIDFILE="$HOME/.claude/stay-awake.pid"
if [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null; then
  OLD="$(cat "$PIDFILE")"
  kill "$OLD" && echo "retired old assertion: PID $OLD"
else
  echo "no prior assertion running"
fi
rm -f "$PIDFILE"
nohup caffeinate -i -s -t 90000 >/dev/null 2>&1 &
echo $! > "$PIDFILE"
echo "started 25h assertion: PID $(cat "$PIDFILE")"
```

Flags: `-i` prevents idle sleep (keeps remote access alive), `-s` prevents full
system sleep on AC power, `-t 90000` is the 25-hour backstop. Note for the user:
`-s` is a no-op on battery, and `-i` does not stop laptop-lid-close (clamshell)
sleep — for an unattended remote Mac, keep it plugged in and lid handling
configured.

Confirm it detached (`PPID` should be `1`):

```bash
ps -o pid,ppid,lstart,command -p "$(cat "$HOME/.claude/stay-awake.pid")"
```

Ignore any `caffeinate -i -t 300` processes — those are Claude Code's own
short-lived in-flight assertions, not yours. Only the `-t 90000` one is managed
here.

### Step 2 — Pick the morning check-in time

Default to **07:03**. If the user passed a time as the argument, use that instead.
Avoid `:00` and `:30` — off-minutes reduce scheduler contention.

### Step 3 — Clear stale reminders, then schedule the daily job

Call `CronList`. `CronDelete` any job whose prompt mentions `stay-awake`, so
re-invoking never stacks duplicates.

Then `CronCreate` with:
- `cron`: `"<minute> <hour> * * *"` from Step 2
- `recurring`: `true`
- `prompt`: exactly —

  > stay-awake daily check-in. RENEW FIRST, ASK SECOND — do not gate the renewal
  > on the user's answer. Step 1: report status with `PIDFILE="$HOME/.claude/stay-awake.pid";
  > [ -f "$PIDFILE" ] && kill -0 "$(cat "$PIDFILE")" 2>/dev/null && echo "still
  > awake: PID $(cat "$PIDFILE")" || echo "caffeinate already exited"`. Step 2:
  > immediately renew — kill the pidfile PID if alive, then `nohup caffeinate -i
  > -s -t 90000 >/dev/null 2>&1 &` and write `$!` to the pidfile. Step 3: only
  > now use AskUserQuestion to ask whether to CONTINUE (already renewed, no
  > action needed) or STOP. If STOP, invoke the stay-awake skill with argument
  > `stop`, which kills the process, clears the pidfile, and CronDeletes this
  > recurring job. Do NOT create a new cron job — the recurring daily job already
  > handles scheduling. If the check-in fires twice in close succession (a
  > catch-up re-fire), skip the redundant renewal and say so rather than churning
  > a healthy assertion.

### Step 4 — Report to the user

Tell them: the caffeinate PID, that it survives session/connection drops, the
25-hour backstop, that the check-in renews automatically so no reply means keep
going, and — importantly — that the recurring job is session-coupled **and
auto-expires after 7 days**. Remind them `/stay-awake stop` ends it anytime.

## Do's and Don'ts

- **Do** keep it to a single managed assertion — retire the old one before
  starting a new one; the pidfile is the source of truth.
- **Do** renew before asking. Silence must mean "keep going", never "lapse".
- **Do** be honest that the reminder is session-coupled and 7-day-limited while
  the caffeinate is not.
- **Don't** drop the `-t` backstop — without it a lost session leaves the Mac
  awake indefinitely.
- **Don't** use `run_in_background` for the caffeinate; that ties it to the
  session. `nohup … &` is required so it survives.
- **Don't** kill `caffeinate -i -t 300` processes — they belong to Claude Code.
