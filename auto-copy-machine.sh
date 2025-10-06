#!/usr/bin/env bash
# auto-copy-machine.sh — ACM: Automatic Copying Machine (Debian/Ubuntu)
# - Detects removable media insertions (udev → systemd)
# - Mounts read-only and copies to DEST/YYYY-MM-DD [Label]
# - Live Discord progress (single updating message, text-only)
# - Buttons (Wipe & Eject / Just Eject) usable during and after copy
# - Auto-eject (no wipe) after timeout if nobody responds
# - Classic blue ncurses prompts via whiptail
# - All messages are text-only (no emojis)

set -euo pipefail

if [[ $EUID -ne 0 ]]; then
  echo "Please run as root (sudo -i)."; exit 1
fi

command -v whiptail >/dev/null 2>&1 || { apt-get update; apt-get install -y whiptail; }

TITLE="ACM Setup"
BACKTITLE="ACM – Automatic Copying Machine (Removable Media → Discord)"

info () { whiptail --title "$TITLE" --backtitle "$BACKTITLE" --msgbox "$1" 12 78; }
aski () { whiptail --title "$TITLE" --backtitle "$BACKTITLE" --inputbox "$1" 10 78 "${2:-}" 3>&1 1>&2 2>&3; }
askp () { whiptail --title "$TITLE" --backtitle "$BACKTITLE" --passwordbox "$1" 10 78 "${2:-}" 3>&1 1>&2 2>&3; }
asky () { whiptail --title "$TITLE" --backtitle "$BACKTITLE" --yesno "$1" 10 78; }

info "Welcome to ACM – Automatic Copying Machine.\n
This will:\n
• Install packages (rsync, jq, curl, filesystem drivers, Python bot)\n
• Create udev rules and systemd services (acm@.service)\n
• Copy media read-only to a dated folder under your destination\n
• Post progress and action buttons to Discord\n
• Auto-eject after finish if nobody clicks within the timeout."

DEST_DIR_ROOT="$(aski 'Destination root for copies (contents -> YYYY-MM-DD [Label] inside):' '/mnt/acm-copies' || true)"
[[ -n "${DEST_DIR_ROOT}" ]] || DEST_DIR_ROOT="/mnt/acm-copies"

WEBHOOK_URL="$(aski 'Discord Webhook URL for silent start (optional, leave blank to skip):' '' || true)"

BOT_TOKEN="$(askp 'Discord Bot Token (required for progress + buttons):' || true)"
while [[ -z "${BOT_TOKEN}" ]]; do
  info "Bot Token is required for interactive buttons and progress."
  BOT_TOKEN="$(askp 'Discord Bot Token (required):' || true)"
done

CHANNEL_ID="$(aski 'Discord Channel ID (numeric):' '' || true)"
while [[ -z "${CHANNEL_ID}" ]]; do
  info "Channel ID is required."
  CHANNEL_ID="$(aski 'Discord Channel ID (numeric):' '' || true)"
done

POST_INT="$(aski 'Progress edit interval (seconds, normal media):' '3' || true)";              [[ -n "${POST_INT}" ]] || POST_INT="3"
POST_INT_SLOW="$(aski 'Progress edit interval for large media (>256GB):' '6' || true)";        [[ -n "${POST_INT_SLOW}" ]] || POST_INT_SLOW="6"
MIN_DELTA_PCT="$(aski 'Minimum % change before editing message again:' '1' || true)";          [[ -n "${MIN_DELTA_PCT}" ]] || MIN_DELTA_PCT="1"
MIN_DELTA_ETA="$(aski 'Minimum ETA change (seconds) before edit:' '5' || true)";               [[ -n "${MIN_DELTA_ETA}" ]] || MIN_DELTA_ETA="5"
GLOBAL_MIN_EDIT="$(aski 'Global minimum edit spacing across all jobs (seconds):' '1.2' || true)"; [[ -n "${GLOBAL_MIN_EDIT}" ]] || GLOBAL_MIN_EDIT="1.2"
MAX_CONC_EDITS="$(aski 'Max concurrent jobs that update progress in Discord:' '4' || true)";   [[ -n "${MAX_CONC_EDITS}" ]] || MAX_CONC_EDITS="4"
FINISH_TIMEOUT_MIN="$(aski 'Minutes to wait after finish before auto-eject (no wipe):' '10' || true)"; [[ -n "${FINISH_TIMEOUT_MIN}" ]] || FINISH_TIMEOUT_MIN="10"

INCLUDE_LIST="0"
if asky "Include a short file list (top 50 paths, depth ≤ 2) in the finished message?"; then INCLUDE_LIST="1"; fi

EXCLUDES_DEFAULT=$'System Volume Information/\n$RECYCLE.BIN/\n*.DS_Store\n._*'
if asky "Add a default exclude list (System Volume Information/, $RECYCLE.BIN/, macOS dotfiles)?"; then USE_EXCLUDES="1"; else USE_EXCLUDES="0"; fi

export DEBIAN_FRONTEND=noninteractive
apt-get update
apt-get install -y rsync jq curl python3 python3-venv python3-pip util-linux coreutils \
                   exfat-fuse exfatprogs ntfs-3g udisks2

install -d -m 0755 "${DEST_DIR_ROOT}"
install -d -m 0755 /etc/acm
install -d -m 0755 /run/acm/jobs

cat >/etc/acm/acm.conf <<EOF
# === ACM config ===
DEST_DIR_ROOT=${DEST_DIR_ROOT}
WEBHOOK_URL=${WEBHOOK_URL}
DISCORD_BOT_TOKEN=${BOT_TOKEN}
DISCORD_CHANNEL_ID=${CHANNEL_ID}

# Interaction / timings
POST_PROGRESS_INTERVAL=${POST_INT}
POST_PROGRESS_INTERVAL_SLOW=${POST_INT_SLOW}
POST_PROGRESS_MIN_DELTA_PCT=${MIN_DELTA_PCT}
POST_PROGRESS_MIN_DELTA_ETA=${MIN_DELTA_ETA}
GLOBAL_MIN_EDIT_INTERVAL=${GLOBAL_MIN_EDIT}
MAX_CONCURRENT_PROGRESS_EDITS=${MAX_CONC_EDITS}

# Auto-eject (no wipe) if no click within this many seconds after finish
FINISH_DECISION_TIMEOUT=$(( FINISH_TIMEOUT_MIN*60 ))

# Optional behavior
INCLUDE_FILE_LIST=${INCLUDE_LIST}
# Extra rsync args (e.g., --exclude-from=/etc/acm/excludes.txt)
RSYNC_EXTRA=
EOF
chmod 0640 /etc/acm/acm.conf

if [[ "${USE_EXCLUDES}" == "1" ]]; then
  printf "%s\n" "${EXCLUDES_DEFAULT}" >/etc/acm/excludes.txt
  chmod 0644 /etc/acm/excludes.txt
  echo 'RSYNC_EXTRA=--exclude-from=/etc/acm/excludes.txt' >>/etc/acm/acm.conf
fi

# Worker: /usr/local/bin/acm.sh
install -m 0755 /dev/stdin /usr/local/bin/acm.sh <<'EOF'
#!/usr/bin/env bash
# acm.sh — per-device copy worker
set -euo pipefail
DEV_BASENAME="${1:?need device like sdb1}"
DEV_PATH="/dev/${DEV_BASENAME}"

. /etc/acm/acm.conf || true
: "${DEST_DIR_ROOT:=/mnt/acm-copies}"
: "${WEBHOOK_URL:=}"
: "${INCLUDE_FILE_LIST:=0}"
: "${RSYNC_EXTRA:=}"

ts() { date -Is | sed 's/+.*//'; }

post_webhook() {
  local content="$1" flags="${2:-0}"
  [[ -n "$WEBHOOK_URL" ]] || return 0
  curl -fsSL -X POST "$WEBHOOK_URL" -H 'Content-Type: application/json' \
    -d "$(jq -n --arg c "$content" --argjson f "$flags" '{content:$c, flags:$f}')" >/dev/null || true
}

# Ensure it is a filesystem partition
if ! blkid "$DEV_PATH" >/dev/null 2>&1; then exit 0; fi

LABEL="$(blkid -o value -s LABEL "$DEV_PATH" || true)"
UUID="$(blkid -o value -s UUID "$DEV_PATH" || true)"
FSTYPE="$(blkid -o value -s TYPE "$DEV_PATH" || true)"
[[ -z "$LABEL" ]] && LABEL="UNLABELED-${UUID:0:8}"
SAFE_LABEL="$(printf '%s' "$LABEL" | tr -cd 'A-Za-z0-9 ._-')"; [[ -n "$SAFE_LABEL" ]] || SAFE_LABEL="UNLABELED-${UUID:0:8}"

TODAY="$(date +%F)"
DEST_DIR="${DEST_DIR_ROOT}/${TODAY} [${SAFE_LABEL}]"
TMP_MNT="/mnt/acm-${DEV_BASENAME}"
mkdir -p "$TMP_MNT" "$DEST_DIR"

# Silent start (webhook)
post_webhook "Ingest started at $(ts)
• Device: \`$DEV_PATH\`
• FS: \`$FSTYPE\`
• Label: \`$LABEL\`
• Target: \`$DEST_DIR\`" 4096

# Mount read-only
mount -o ro,nosuid,nodev,noexec "$DEV_PATH" "$TMP_MNT"

WHOLEDISK="$(lsblk -no PKNAME "$DEV_PATH" 2>/dev/null | sed 's#^#/dev/#')"
[[ -z "$WHOLEDISK" ]] && WHOLEDISK="${DEV_PATH%[0-9]}"

# Total bytes for progress
BYTES_TOTAL="$(du -sb --apparent-size "$TMP_MNT" 2>/dev/null | awk '{print $1}')"
[[ -z "$BYTES_TOTAL" ]] && BYTES_TOTAL=0

JOB_ID="$(date +%s)-$DEV_BASENAME-$$"
JOB_DIR="/run/acm/jobs"
JOB_JSON="${JOB_DIR}/${JOB_ID}.json"
PROG_JSON="${JOB_DIR}/${JOB_ID}.progress.json"

jq -n \
  --arg job_id "$JOB_ID" \
  --arg dev "$DEV_PATH" \
  --arg disk "$WHOLEDISK" \
  --arg mnt "$TMP_MNT" \
  --arg label "$LABEL" \
  --arg dest "$DEST_DIR" \
  --arg fstype "$FSTYPE" \
  --argjson total "$BYTES_TOTAL" \
  --arg state "copying" \
  '{job_id:$job_id, dev:$dev, disk:$disk, mount:$mnt, label:$label, dest:$dest, fstype:$fstype,
    bytes_total:$total, bytes_done:0, state:$state, created:now, desired_action:null}' >"$JOB_JSON"

# Notify bot to post progress/buttons
systemctl start acm-notify@"$JOB_ID".service || true

RSYNC_ARGS=(-aHAX --info=progress2 --mkpath)
[[ -n "$RSYNC_EXTRA" ]] && RSYNC_ARGS+=($RSYNC_EXTRA)

START_TS=$(date +%s)
(
  rsync "${RSYNC_ARGS[@]}" "$TMP_MNT"/ "$DEST_DIR"/ 2>&1 1>/dev/null || true
) | stdbuf -oL tr '\r' '\n' | awk -v job="$JOB_ID" -v total="$BYTES_TOTAL" -v start="$START_TS" '
  /to-chk/ {
    gsub(/,/, "", $0)
    bytes=$1
    if (bytes ~ /^[0-9]+$/) {
      now = systime()
      done = bytes
      pct = (total>0)? int((done*100)/total) : 0
      delta = now - start
      rate = (delta>0)? (done/delta) : 0
      remain = (total>done)? (total-done) : 0
      eta = (rate>0)? int(remain/rate) : -1
      tmp="/run/acm/jobs/"job".progress.tmp"
      json="{\"job_id\":\""job"\",\"bytes_done\":"done",\"bytes_total\":"total",\"pct\":"pct",\"eta\":"eta",\"rate\":"rate",\"ts\":"now"}"
      print json > tmp
      close(tmp)
      system("mv -f " tmp " /run/acm/jobs/"job".progress.json")
    }
  }
'

COUNT_FILES="$( (find "$DEST_DIR" -type f 2>/dev/null | wc -l) || echo 0 )"
TOTAL_HUMAN="$( (du -sh --apparent-size "$DEST_DIR" 2>/dev/null | awk '{print $1}') || echo 0 )"
if [[ "$INCLUDE_FILE_LIST" == "1" ]]; then
  FILE_LIST="$( (cd "$DEST_DIR" && find . -maxdepth 2 -type f | sort | head -n 50) || true )"
else
  FILE_LIST=""
fi

jq '.bytes_done = .bytes_total | .state = "finished" | .finished = now' "$JOB_JSON" >"$JOB_JSON.tmp" && mv -f "$JOB_JSON.tmp" "$JOB_JSON"

SUMMARY="${JOB_DIR}/${JOB_ID}.summary.txt"
{
  echo "Files: $COUNT_FILES"
  echo "Size:  $TOTAL_HUMAN"
  [[ -n "$FILE_LIST" ]] && { echo; echo "$FILE_LIST" | sed 's/^/ - /'; }
} >"$SUMMARY"

exit 0
EOF

# per-job notifier (bot watches its start)
cat >/etc/systemd/system/acm-notify@.service <<'EOF'
[Unit]
Description=ACM: notify Discord (progress + interactive) for job %I
After=acm-bot.service
Requires=acm-bot.service

[Service]
Type=oneshot
ExecStart=/usr/bin/true
EOF

# udev and systemd unit
cat >/etc/udev/rules.d/99-acm.rules <<'EOF'
# USB filesystem partitions
ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_USAGE}=="filesystem", ENV{ID_BUS}=="usb", TAG+="systemd", ENV{SYSTEMD_WANTS}+="acm@%k.service"
# Any removable FS partitions (covers many card readers)
ACTION=="add", SUBSYSTEM=="block", ENV{ID_FS_USAGE}=="filesystem", ATTR{removable}=="1", TAG+="systemd", ENV{SYSTEMD_WANTS}+="acm@%k.service"
EOF

cat >/etc/systemd/system/acm@.service <<'EOF'
[Unit]
Description=ACM: copy newly-inserted removable media (%I)
Requires=dev-%i.device
After=dev-%i.device

[Service]
Type=oneshot
ExecStart=/usr/local/bin/acm.sh %i
TimeoutStartSec=3h
EOF

# Discord bot (progress + buttons, rate-limited, no emojis)
install -d -m 0755 /opt/acm-bot
python3 -m venv /opt/acm-bot/venv
/opt/acm-bot/venv/bin/pip install --upgrade pip
/opt/acm-bot/venv/bin/pip install "discord.py>=2.4,<3" "aiofiles>=23,<24"

cat >/opt/acm-bot/bot.py <<'EOF'
import os, json, time, glob, asyncio, aiofiles, subprocess
import discord

CONF = "/etc/acm/acm.conf"
JOBS_DIR = "/run/acm/jobs"

def read_conf():
    conf = {
        "DEST_DIR_ROOT": "/mnt/acm-copies",
        "WEBHOOK_URL": "",
        "DISCORD_BOT_TOKEN": "",
        "DISCORD_CHANNEL_ID": "",
        "POST_PROGRESS_INTERVAL": "3",
        "POST_PROGRESS_INTERVAL_SLOW": "6",
        "POST_PROGRESS_MIN_DELTA_PCT": "1",
        "POST_PROGRESS_MIN_DELTA_ETA": "5",
        "GLOBAL_MIN_EDIT_INTERVAL": "1.2",
        "MAX_CONCURRENT_PROGRESS_EDITS": "4",
        "FINISH_DECISION_TIMEOUT": "600",
        "INCLUDE_FILE_LIST": "0",
    }
    try:
        with open(CONF, "r") as f:
            for line in f:
                s=line.strip()
                if not s or s.startswith("#") or "=" not in s: continue
                k,v = s.split("=",1)
                conf[k.strip()] = v.strip()
    except FileNotFoundError:
        pass
    return conf

def fmt_eta(sec):
    if sec is None or sec < 0: return "ETA --:--"
    m, s = divmod(int(sec), 60)
    h, m = divmod(m, 60)
    return f"ETA {h:d}:{m:02d}:{s:02d}" if h else f"ETA {m:02d}:{s:02d}"

def human_rate(bps):
    if bps <= 0: return "-- MB/s"
    units = ["B/s","KB/s","MB/s","GB/s","TB/s"]
    i=0
    while bps>=1024 and i<len(units)-1:
        bps/=1024; i+=1
    return f"{bps:.1f} {units[i]}"

def bar(pct):
    pct = max(0, min(100, int(pct)))
    width=20
    filled = int((pct*width)/100)
    return "█"*filled + "░"*(width-filled)

class ProgressMessage:
    def __init__(self, job_id):
        self.job_id = job_id
        self.msg: discord.Message|None = None
        self.last_sent = 0.0
        self.last_pct = -1
        self.last_eta = None
        self.slow = False
        self.closed = False
        self.finish_ts = None
        self.summary_sent = False

class ACMBot(discord.Client):
    def __init__(self, **kwargs):
        super().__init__(**kwargs)
        self.jobs: dict[str, ProgressMessage] = {}
        self.conf = read_conf()
        self.channel: discord.abc.Messageable | None = None
        self.post_interval = float(self.conf.get("POST_PROGRESS_INTERVAL","3") or "3")
        self.post_interval_slow = float(self.conf.get("POST_PROGRESS_INTERVAL_SLOW","6") or "6")
        self.min_delta_pct = int(self.conf.get("POST_PROGRESS_MIN_DELTA_PCT","1") or "1")
        self.min_delta_eta = int(self.conf.get("POST_PROGRESS_MIN_DELTA_ETA","5") or "5")
        self.global_min_edit = float(self.conf.get("GLOBAL_MIN_EDIT_INTERVAL","1.2") or "1.2")
        self.max_conc_edits = int(self.conf.get("MAX_CONCURRENT_PROGRESS_EDITS","4") or "4")
        self.finish_timeout = int(self.conf.get("FINISH_DECISION_TIMEOUT","600") or "600")
        self.global_last_edit = 0.0

    async def setup_hook(self):
        asyncio.create_task(self.watcher())
        asyncio.create_task(self.progress_loop())

    async def on_ready(self):
        try:
            ch_id = int(self.conf.get("DISCORD_CHANNEL_ID","0") or "0")
        except:
            ch_id = 0
        self.channel = self.get_channel(ch_id)
        print(f"ACM bot online as {self.user}; channel={self.channel}")

    async def watcher(self):
        while True:
            try:
                for jf in glob.glob(os.path.join(JOBS_DIR,"*.json")):
                    jid = os.path.basename(jf).replace(".json","")
                    if jid in self.jobs:
                        continue
                    async with aiofiles.open(jf,"r") as f:
                        job = json.loads(await f.read())
                    pm = ProgressMessage(jid)
                    self.jobs[jid] = pm
                    if self.channel:
                        label = job.get("label"); dest = job.get("dest")
                        dev = job.get("dev"); fstype = job.get("fstype")
                        content = f"Copying {os.path.basename(dest)} — 0% • {fmt_eta(-1)}\n`{dev}` • {fstype}"
                        view = discord.ui.View(timeout=None)
                        view.add_item(discord.ui.Button(label="Wipe & Eject", style=discord.ButtonStyle.danger, custom_id=f"wipe::{jid}"))
                        view.add_item(discord.ui.Button(label="Just Eject", style=discord.ButtonStyle.secondary, custom_id=f"eject::{jid}"))
                        try:
                            pm.msg = await self.channel.send(content=content, view=view)
                            pm.last_sent = time.time()
                        except Exception as e:
                            print("send error:", e)
            except Exception as e:
                print("watcher error:", e)
            await asyncio.sleep(1)

    async def progress_loop(self):
        while True:
            now = time.time()
            active = 0
            for jid, pm in list(self.jobs.items()):
                if pm.closed: continue
                pj = os.path.join(JOBS_DIR, f"{jid}.progress.json")
                jf = os.path.join(JOBS_DIR, f"{jid}.json")
                try:
                    async with aiofiles.open(jf,"r") as f:
                        job = json.loads(await f.read())
                except:
                    continue
                state = job.get("state","copying")
                if state == "finished" and pm.finish_ts is None:
                    pm.finish_ts = time.time()

                # Determine interval
                total = int(job.get("bytes_total") or 0)
                interval = self.post_interval
                if total >= 256*1024*1024*1024:  # >256GB
                    interval = self.post_interval_slow
                    pm.slow = True

                # Load progress snapshot
                pct = 0; eta = -1; rate = 0.0
                if os.path.exists(pj):
                    try:
                        async with aiofiles.open(pj,"r") as f:
                            pr = json.loads(await f.read())
                        pct = int(pr.get("pct",0))
                        eta = int(pr.get("eta",-1))
                        rate = float(pr.get("rate",0.0))
                    except:
                        pass

                # Coalescing and global throttle
                due = (now - pm.last_sent) >= interval
                delta_ok = (abs(pct - pm.last_pct) >= self.min_delta_pct) or (pm.last_eta is None) or (abs((eta if eta>=0 else 0) - (pm.last_eta if pm.last_eta else 0)) >= self.min_delta_eta)
                global_ok = (now - self.global_last_edit) >= self.global_min_edit
                can_edit = (state == "copying") and due and delta_ok and global_ok and active < self.max_conc_edits and self.channel and pm.msg

                if can_edit:
                    active += 1
                    content = f"Copying {os.path.basename(job.get('dest',''))} — {pct}% • {human_rate(rate)} • {fmt_eta(eta)}\n{bar(pct)}"
                    try:
                        await pm.msg.edit(content=content)
                        pm.last_sent = now
                        pm.last_pct = pct
                        pm.last_eta = eta
                        self.global_last_edit = now
                    except Exception as e:
                        await asyncio.sleep(1.0)

                # After finish: switch to summary (keep buttons), then auto-eject
                if state == "finished":
                    if not pm.summary_sent and pm.msg:
                        summary_path = os.path.join(JOBS_DIR, f"{jid}.summary.txt")
                        summary = ""
                        try:
                            async with aiofiles.open(summary_path,"r") as f:
                                summary = await f.read()
                        except:
                            pass
                        embed = discord.Embed(title="Finished", description=summary if summary else None, color=0x43B581)
                        view = discord.ui.View(timeout=None)
                        view.add_item(discord.ui.Button(label="Wipe & Eject", style=discord.ButtonStyle.danger, custom_id=f"wipe::{jid}"))
                        view.add_item(discord.ui.Button(label="Just Eject", style=discord.ButtonStyle.secondary, custom_id=f"eject::{jid}"))
                        try:
                            await pm.msg.edit(content=None, embed=embed, view=view)
                            pm.summary_sent = True
                        except Exception:
                            pass
                    if pm.finish_ts and (now - pm.finish_ts) >= self.finish_timeout and not pm.closed:
                        await self.do_eject(job, pm, auto=True)
            await asyncio.sleep(0.5)

    async def on_interaction(self, interaction: discord.Interaction):
        cid = interaction.data.get("custom_id","")
        if not cid: return
        action, jid = cid.split("::",1)
        pm = self.jobs.get(jid)
        if not pm or not os.path.exists(os.path.join(JOBS_DIR, f"{jid}.json")):
            await interaction.response.send_message("Job not found.", ephemeral=True)
            return
        await interaction.response.defer(ephemeral=True, thinking=True)
        async with aiofiles.open(os.path.join(JOBS_DIR, f"{jid}.json"),"r") as f:
            job = json.loads(await f.read())
        if action == "eject":
            await self.do_eject(job, pm, auto=False)
            await interaction.followup.send("Ejected.", ephemeral=True)
        elif action == "wipe":
            await self.do_wipe(job, pm)
            await interaction.followup.send("Wiped and ejected.", ephemeral=True)

    async def do_eject(self, job, pm: ProgressMessage, auto=False):
        if pm.closed: return
        dev = job.get("dev"); disk = job.get("disk"); mnt = job.get("mount")
        subprocess.run(["umount", mnt], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        subprocess.run(["udisksctl","power-off","-b", disk], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        pm.closed = True
        if pm.msg:
            try:
                note = "Auto-ejected (no reply)." if auto else "Ejected."
                await pm.msg.edit(content=note, embed=None, view=None)
            except: pass

    async def do_wipe(self, job, pm: ProgressMessage):
        if pm.closed: return
        dev = job.get("dev"); disk = job.get("disk"); mnt = job.get("mount")
        fstype = job.get("fstype"); label = job.get("label") or "REMOVABLE"
        subprocess.run(["umount", mnt], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        disc = subprocess.run(["blkdiscard","-f", disk], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        if disc.returncode != 0:
            try:
                if fstype == "vfat":
                    subprocess.run(["mkfs.vfat","-F","32","-n", label[:11], dev], check=True)
                elif fstype == "exfat":
                    subprocess.run(["mkfs.exfat","-n", label[:15], dev], check=True)
                elif fstype == "ntfs":
                    subprocess.run(["mkfs.ntfs","-Q","-L", label[:32], dev], check=True)
                elif fstype and fstype.startswith("ext"):
                    subprocess.run([f"mkfs.{fstype}","-F","-L", label[:16], dev], check=True)
                elif fstype == "xfs":
                    subprocess.run(["mkfs.xfs","-f","-L", label[:12], dev], check=True)
                else:
                    subprocess.run(["mount","-o","rw,nosuid,nodev,noexec", dev, mnt], check=False)
                    subprocess.run(["bash","-lc", f"shopt -s dotglob; rm -rf {mnt}/* || true; sync"], check=False)
                    subprocess.run(["umount", mnt], check=False)
            except Exception:
                pass
        subprocess.run(["udisksctl","power-off","-b", disk], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        pm.closed = True
        if pm.msg:
            try:
                await pm.msg.edit(content="Wiped and ejected.", embed=None, view=None)
            except: pass

intents = discord.Intents.default()
client = ACMBot(intents=intents)

def main():
    conf = client.conf
    token = conf.get("DISCORD_BOT_TOKEN","")
    if not token:
        print("Missing DISCORD_BOT_TOKEN in config.")
        return
    client.run(token)

if __name__ == "__main__":
    main()
EOF

cat >/etc/systemd/system/acm-bot.service <<'EOF'
[Unit]
Description=ACM Discord bot (progress + interactive actions)
After=network-online.target
Wants=network-online.target

[Service]
Type=simple
User=root
Environment=PYTHONUNBUFFERED=1
ExecStart=/opt/acm-bot/venv/bin/python /opt/acm-bot/bot.py
Restart=always
RestartSec=3

[Install]
WantedBy=multi-user.target
EOF

# enable services & reload rules
systemctl daemon-reload
systemctl enable --now acm-bot.service
udevadm control --reload

info "ACM setup complete.

Copies will go under: ${DEST_DIR_ROOT}/YYYY-MM-DD [Label]
Plug a USB/SD and watch your Discord channel for progress and buttons.
Start message (optional) is silent via your webhook (if set).
If nobody clicks within ${FINISH_TIMEOUT_MIN} minutes after finish, ACM auto-ejects without wiping.

Edit /etc/acm/acm.conf anytime, then run:
  systemctl restart acm-bot.service
"
