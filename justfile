#!/usr/bin/env -S just --working-directory . --justfile
# vim: expandtab:shiftwidth=4

# 
# 
# ~/ref/openpgpkey/justfile
# 
# 

set positional-arguments
set default-list := true

[doc('Resolve WKD hash of KeyID')]
wkd-hash email:
    #!/usr/bin/env bash
    set -euo pipefail
    gpg-wks-client --print-wkd-hash "{{email}}" | awk '{ print $1 }'

[doc('Export email PGP key')]
export email: (_export-wkd email) (_export-asc email)

[doc('Export binary to WKD')]
_export-wkd email:
    #!/usr/bin/env bash
    set -euo pipefail
    hash="$(gpg-wks-client --print-wkd-hash {{email}} | awk '{ print $1 }')"
    domain="$(gpg-wks-client --print-wkd-hash {{email}} | awk '{split($2, a, "@"); print a[2]}' )"
    output="{{justfile_directory()}}/.well-known/openpgpkey/$domain/hu/$hash"
    [ ! -d "${output%/*}" ] && mkdir -p "${output%/*}"
    [   -e "${output}"    ] && rm -fi   "${output}"
    gpg --export --output "$output" "{{email}}"

[doc('Export armored to asc')]
_export-asc email:
    #!/usr/bin/env bash
    set -euo pipefail
    output="{{justfile_directory()}}/asc/{{email}}.pgp.asc"
    [ ! -d "${output%/*}" ] && mkdir -p "${output%/*}"
    [   -e "${output}"    ] && rm -fi   "${output}"
    gpg --export --armor --output "$output" "{{email}}"
