#!/usr/bin/env -S just --working-directory . --justfile
# vim: expandtab:shiftwidth=4

# 
# 
# ~/ref/openpgpkey/justfile
# 
# 

set positional-arguments
set default-list := true

keyserver := 'keys.openpgp.org'


[doc('Resolve WKD hash of KeyID')]
wkd-hash email:
    gpg-wks-client --print-wkd-hash {{email}} | awk '{ print $1 }'

[doc('Export all')]
export-all email: (export-wkd email) (export-asc email) (export-keyserver email)

[doc('Export binary to WKD')]
export-wkd email:
    #!/usr/bin/env bash
    hash="$(gpg-wks-client --print-wkd-hash {{email}} | awk '{ print $1 }')"
    domain="$(gpg-wks-client --print-wkd-hash {{email}} | awk '{split($2, a, "@"); print a[2]}' )"
    output="{{justfile_directory()}}/.well-known/openpgpkey/$domain/hu/$hash"
    [ ! -d "${output%/*}" ] && mkdir -p "${output%/*}"
    [   -e "${output}"    ] && rm -fi   "${output}"
    gpg --export --output "$output" {{email}}

[doc('Export armored to asc')]
export-asc email:
    #!/usr/bin/env bash
    output="{{justfile_directory()}}/asc/{{email}}.pgp.asc"
    [ ! -d "${output%/*}" ] && mkdir -p "${output%/*}"
    [   -e "${output}"    ] && rm -fi   "${output}"
    gpg --export --armor --output "$output" {{email}}

[doc('Export to keyserver')]
export-keyserver email:
    gpg --export {{email}} | curl -T - https://{{keyserver}}


