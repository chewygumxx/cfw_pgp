#!/bin/sh
# vim: expandtab:shiftwidth=4

# 
# 
# ~chewygumxx/openpgpkey.git
# ::: :/scripts/install-key.sh
# 
# 

#
# Installs OpenPGP key data at appropriate filepaths
#

#
# Note: Yo fuck this
#

set -eu
__this_file="${0##*/}"

for cmd in gpg date mkdir mktemp; do
    if ! command -v gpg &>/dev/null 2>&1; then
        command printf '%s: [FATAL] Command not found:\n' "$__this_file" >&2
    	exit 127
    fi
done

# --------------
# Parse Options
# --------------

VERBOSE=0
KEEP_KEYS=0 # Keep imported keys in gpg keyring

while [ "$#" -gt 0 ]; do
    case "$1" in
        -v|--verbose) VERBOSE=1;   shift;;
        --keep-keys)  KEEP_KEYS=1; shift;;
        --keyserver)               break;;
        --)           shift;       break;;
        -*) 
            command printf '%s: Unknown option: %s\n' "${__this_file}" "$1" >&2
            exit 2
            ;;
        *) break ;;
    esac
done

# ----------
# Setup Log
# ----------

log_file="${XDG_STATE_HOME:-${HOME}/.local/state}/${__this_file}.log"

log() {
    level="$1"; shift

    if timestamp=$(command date -u +'%Y-%m-%dT%H:%M:%SZ'); then :; else
        printf '%s: [FATAL] Failed to resolve timestamp:\n' "$__this_file" >&2
        printf '%s: [FATAL] %s\n' "$__this_file" "$timestamp" >&2
        exit 1
    fi

	command printf '%s [%s] %s\n' "$timestamp" "$level" "$*" >> "$log_file" 2>/dev/null || true

	case "$level" in
	    NOTICE|WARN|ERROR|FATAL)
            command printf '%s: [%s] %s\n' "${__this_file}" "$level" "$*" >&2
            ;;
	    *) 
            if [ "$VERBOSE" -eq 1 ]; then
                command printf '%s: [%s] %s\n' "${__this_file}" "$level" "$*" >&2
            fi
            ;;
    esac
}

if [ ! -d "${log_file%%/*}" ]; then
    if mkdir_stdouterr="$(command mkdir -p "${log_file%%/*}" 2>&1)"; then :; else
        mkdir_exit=$?
        log FATAL "Failed to create log file directory at: ${log_file%%/*}"
        log FATAL "$mkdir_stdouterr"
        exit $mkdir_exit
    fi
fi

clean_temp () {
    for tempfile in "$fprint_log" "$imported_log"; do
        if [ -e "$tempfile" ]; then
            if rm_stdouterr="$(command rm -f "$tempfile" 2>&1)"; then :; else
                rm_exit=$?
                log FATAL "Failed to cleanup temporary file: $tempfile"
                log FATAL "$rm_stdouterr"
                exit $rm_exit
            fi
            log INFO "Removed temporary file: $tempfile"
        fi
    done
}

if fprint_log="$(command mktemp 2>&1)"; then :; else
    mktemp_exit=$?
    log FATAL "Failed to create temporary fingerprint log"
    log FATAL "$fprint_log"
    clean_temp
    exit $mktemp_exit
fi
log INFO "Created temporary fingerprint log: $fprint_log"

if (( KEEP_KEYS = 0 )); then
    if imported_log="$(command mktemp 2>&1)"; then :; else
        mktemp_exit=$?
        log FATAL "Failed to create temporary imported keys log"
        log FATAL "$imported_log"
        clean_temp
        exit $mktemp_exit
    fi
    log INFO "Created temporary imported keys log: $imported_log"
fi


# -----------------------------------
# Import Keys and Log Fingerprints
# -----------------------------------

log_fprint () {
    if [ -r "$1" ]; then
        if gpg_stdouterr="$(command gpg --import --verbose "$1" 2>&1)"; then :; else
            gpg_exit=$?
            log FATAL "gpg exited non-zero while importing: $1"
            log FATAL "$gpg_stdouterr"
            clean_temp
            exit $gpg_exit
        fi

    fi

    if gpg_stdouterr="$(command gpg --with-colons --fingerprint "$1" 2>&1)"; then :; else
        gpg_exit=$?
        log FATAL "gpg exited non-zero resolving fingerprint of: $1"
        log FATAL "$gpg_stdouterr"
        clean_temp
        exit $gpg_exit
    fi
    fprint="$(printf "%s" "$gpg_stdouterr" | command awk -F: '/^fpr:/ {print $10; exit}')"

    echo "$fprint" >> "$fprint_log"
    (( imported = 1 )) && echo "$fprint" >> "$imported_log" 2>/dev/null || true

    if [ "$1" = "$fprint" ]; then
        log INFO "Logged Fingerprint: $fprint"
    else
        log INFO "Logged Fingerprint: $fprint of $1"
    fi
}

from_keyserver() {
    keyserver="$1"; shift

    while [ -n "$1" ]; do
        case "$1" in 
            -*) # No more keys from this keyserver
                return 0
                ;; 
            *)  # KeyID
                if gpg --list-keys "$1"; then
                    log INFO "Already in keyring: $1"
                elif gpg_stdouterr="$(gpg --keyserver "$keyserver" --receive-keys "$1" 2>&1)"; then 
                    imported=1
                    log INFO "imported from $keyserver: $1"
                else
                    gpg_exit=$?
                    log FATAL "gpg returned non-zero:"
                    log FATAL "$gpg_stdouterr"
                    clean_temp
                    exit $gpg_exit
                fi

                log_fprint ${imported:+"--imported"} "$1"
                shift
                ;;
        esac
    done
}

while [ -n "$1" ]; do
    case "$1" in
        --keyserver)
            shift
            from_keyserver "$@"
            ;;
        hkps://*)
            from_keyserver "$@"
            ;;
        --)
            shift
            ;;
        *)
            log_fprint
            shift
            ;;
    esac
done


            
            

