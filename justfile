#!/usr/bin/env -S just --working-directory . --justfile
# vim:set expandtab shiftwidth=4 filetype=just:

# 
# 
# ~chewygumxx/pgp.git
# ::: :/justfile
# 
# 

set positional-arguments


[private]
default:
    @just --list


[doc('List exported keys')]
list-keys:
    @just wkd-hash $(basename -s .pgp.asc "{{justfile_directory()}}"/asc/*) 

[doc('Print email WKD hashes')]
wkd-hash +emails:
    @gpg-wks-client --print-wkd-hash {{emails}}

[doc('Export email PGP key')]
export email: (_export-wkd email) (_export-asc email) index
    git -C "{{justfile_directory()}}" commit --all --message "Added {{email}}"

[doc('Regenerate the asset index page')]
index:
    @just _gen-index > "{{justfile_directory()}}/index.html"


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


# ----------------
# Helpers: Index
# ----------------

[doc('Render index.html to stdout')]
_gen-index:
    #!/usr/bin/env bash
    set -euo pipefail
    
    fmt_fpr() { printf '%s' "$1" | fold -w4 | paste -sd' '; }
    
    cat <<'HTML'
    <!-- vim:set expandtab shiftwidth=4 filetype=html: -->
    
    <!--
       -
       - ~chewygumxx/pgp.git
       - ::: :/index.html
       -
       -->
    
    <!DOCTYPE html>
    <html lang="en">
    <head>
        <meta charset="utf-8">
        <meta name="viewport" content="width=device-width, initial-scale=1">
        <title>chewygumxx — PGP keys</title>
        <style>
            :root { color-scheme: light dark; }
            body {
                font-family: ui-monospace, "SF Mono", Consolas, monospace;
                max-width: 40rem;
                margin: 3rem auto;
                padding: 0 1rem;
                line-height: 1.5;
            }
            h1 { font-size: 1.25rem; }
            ul { list-style: none; padding: 0; }
            li {
                border: 1px solid currentColor;
                border-radius: 4px;
                padding: 0.75rem 1rem;
                margin-bottom: 0.75rem;
            }
            li a { font-weight: bold; text-decoration: none; }
            li a:hover { text-decoration: underline; }
            code {
                display: block;
                margin-top: 0.35rem;
                font-size: 0.85em;
                opacity: 0.8;
                word-break: break-all;
            }
            footer { font-size: 0.85em; opacity: 0.7; margin-top: 2rem; }
        </style>
    </head>
    <body>
        <h1>PGP Keys</h1>
        <ul>
    HTML
    
    for f in "{{justfile_directory()}}"/asc/*.pgp.asc; do
        [ -e "$f" ] || continue
        email="$(basename "$f" .pgp.asc)"
        fpr="$(gpg --show-keys --with-colons --with-fingerprint "$f" \
            | awk -F: '/^fpr:/ {print $10; exit}')"
        printf '        <li>\n'
        printf '            <a href="/asc/%s">%s</a>\n' "$(basename "$f")" "$email"
        printf '            <code>%s</code>\n' "$(fmt_fpr "$fpr")"
        printf '        </li>\n'
    done
    
    cat <<'HTML'
        </ul>
        <footer>
            WKD-aware clients can autodiscover these keys directly
        </footer>
    </body>
    </html>
    HTML
