#!/usr/bin/env -S just --working-directory . --justfile
# vim: expandtab:shiftwidth=4

# 
# 
# ~chewygumxx/pgp.git
# ::: :/justfile
# 
# 

set positional-arguments
set default-list := true


[doc('List exported keys')]
list-keys:
    @just wkd-hash $(basename -s .pgp.asc "{{justfile_directory()}}"/asc/*) 

[doc('Print email WKD hashes')]
wkd-hash +emails:
    @gpg-wks-client --print-wkd-hash {{emails}}

[doc('Export email PGP key')]
export email: (_export-wkd email) (_export-asc email)
    git -C "{{justfile_directory()}}" commit --all --message "Added {{email}}"


# ----------------
# Helpers: Export
# ----------------

[doc('Export binary to WKD')]
_export-wkd email:
    #!/usr/bin/env bash
    set -euo pipefail
    hash="$(just wkd-hash {{email}} | awk '{ print $1 }')"
    email="{{email}}"
    domain="${email#*@}"
    just _export-key "{{justfile_directory()}}/.well-known/openpgpkey/$domain/hu/$hash" {{email}}

[doc('Export armored to asc')]
_export-asc email:
    @just _export-key --armor "{{justfile_directory()}}/asc/{{email}}.pgp.asc" {{email}}

[doc('gpg export wrapper')]
[arg("armor",  long, value="--armor")]
[arg('email', pattern='^[a-zA-Z0-9._-]+@[a-zA-Z0-9]+\.\w{2,}$')]
_export-key armor="" output email:
    #!/usr/bin/env bash
    set -euo pipefail
    if ! gpg --list-keys "{{email}}" >/dev/null 2>&1; then
        echo "Email does not exist in keyring: {{email}}" >&2
        exit 1
    fi
    
    confirm() {
        read -rp "$1 [y/N] " reply
        reply="${reply,,}"
        [[ "${reply:0:1}" == y ]] || exit 1
    }

    repo_relative() {
        printf "%s" "$1" | sed 's#^{{justfile_directory()}}#\.#'
    }
    
    output="{{output}}"
    if [ ! -d "${output%/*}" ]; then
        confirm "Create new directory '$(repo_relative "${output%/*}")'?"
        mkdir -p "${output%/*}"
    fi
    
    if [ -e "$output" ]; then
        confirm "Overwrite '$(repo_relative "${output}")'?"
        rm -f "$output"
    fi
    
    gpg --export {{armor}} "{{email}}" > "$output"
