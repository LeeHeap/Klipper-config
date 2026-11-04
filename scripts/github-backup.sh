#!/usr/bin/env bash
#####################################################################
### GitHub config backup for Voron printer
###
### Runs:
###   1. On Klipper startup via common/startup.cfg delayed_gcode
###   2. Daily at 00:00 via lee's crontab
###
### DESIGN NOTES (read before editing):
### - Uses absolute paths. Do NOT use "~" or "$HOME" -- cron runs with
###   different $HOME depending on the user, and that's how this script
###   broke silently for weeks in the past.
### - Runs as user `lee`. Pushes use HTTPS via the credential store at
###   /home/lee/.git-credentials. That file MUST be owned by lee:lee
###   with mode 0600. If you ever see "could not read Username for
###   'https://github.com'", check ownership of .git-credentials first.
### - Writes a status summary to /tmp/github-backup-status so you can
###   check whether the last run succeeded without tailing logs.
### - Exits non-zero on ANY failure so systemd/cron mail and the Klipper
###   gcode_shell_command wrapper can surface problems.
#####################################################################

set -euo pipefail

# Absolute paths only. Change these only if the printer is rebuilt with
# a different username or directory layout.
CONFIG_FOLDER="/home/lee/printer_data/config"
KLIPPER_FOLDER="/home/lee/klipper"
MOONRAKER_FOLDER="/home/lee/moonraker"
FLUIDD_FOLDER="/home/lee/fluidd"
STATUS_FILE="/tmp/github-backup-status"

# Force git to use lee's HOME for credential lookup, even if this script
# is run under cron or systemd with a different HOME. This single line
# prevents the recurring "could not read Username" failure.
export HOME=/home/lee

# Always record what happened, even if we exit early.
log_status() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') [$1] $2" > "$STATUS_FILE"
}

# Die loudly -- no silent failures.
die() {
    log_status "FAIL" "$1"
    echo "ERROR: $1" >&2
    exit 1
}

grab_version() {
    local versions=""
    if [[ -d "$KLIPPER_FOLDER" ]]; then
        versions+="Klipper: $(cd "$KLIPPER_FOLDER" && git describe --always --tags 2>/dev/null || echo '?')"
    fi
    if [[ -d "$MOONRAKER_FOLDER" ]]; then
        versions+=" | Moonraker: $(cd "$MOONRAKER_FOLDER" && git describe --always --tags 2>/dev/null || echo '?')"
    fi
    if [[ -f "$FLUIDD_FOLDER/.version" ]]; then
        versions+=" | Fluidd: $(head -n 1 "$FLUIDD_FOLDER/.version")"
    fi
    echo "$versions"
}

main() {
    [[ -d "$CONFIG_FOLDER/.git" ]] || die "Not a git repo: $CONFIG_FOLDER"
    cd "$CONFIG_FOLDER"

    # Pull first if remote has moved. Non-fatal if network is down.
    if ! git fetch origin 2>/dev/null; then
        log_status "WARN" "git fetch failed (network or auth); proceeding without rebase"
    else
        local LOCAL REMOTE
        LOCAL=$(git rev-parse HEAD)
        REMOTE=$(git rev-parse '@{u}' 2>/dev/null || echo "$LOCAL")
        if [[ "$LOCAL" != "$REMOTE" ]]; then
            # Check if we're ahead, behind, or diverged before rebasing.
            local BEHIND AHEAD
            BEHIND=$(git rev-list --count HEAD..@{u} 2>/dev/null || echo "0")
            AHEAD=$(git rev-list --count @{u}..HEAD 2>/dev/null || echo "0")
            if [[ "$BEHIND" -gt 0 ]]; then
                git pull --rebase --autostash || die "git pull --rebase failed; manual intervention needed"
            fi
            # If only ahead, the push later will handle it.
        fi
    fi

    # Commit any dirty state.
    if git diff --quiet && git diff --staged --quiet && [[ -z "$(git ls-files --others --exclude-standard)" ]]; then
        local commit_action="clean"
    else
        git add -A
        local version_info
        version_info=$(grab_version)
        git commit -m "Autocommit $(date +'%Y-%m-%d %H:%M')" -m "$version_info" \
            || die "git commit failed (probably a pre-commit hook rejection)"
        local commit_action="committed"
    fi

    # Push if there are unpushed commits. This is the step that used to
    # fail silently; now we fail loudly so cron mail surfaces the issue.
    local AHEAD
    AHEAD=$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo "0")
    if [[ "$AHEAD" -gt 0 ]]; then
        if git push 2>&1; then
            log_status "OK" "$commit_action, pushed $AHEAD commit(s)"
        else
            die "git push failed; check /home/lee/.git-credentials ownership (must be lee:lee 0600)"
        fi
    else
        log_status "OK" "$commit_action, nothing to push"
    fi
}

main "$@"
