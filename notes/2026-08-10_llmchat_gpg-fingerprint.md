<!-- vim: expandtab:shiftwidth=4

<!--
   -
   - ~chewygumxx/pgp.git
   - ::: :/notes/2026-08-10_llmchat_gpg-fingerprint.md
   -
   -->

# LLM Chat: PGP Key Fingerprint with `gpg`

[Link](<https://claude.ai/share/0236a9f8-c8d5-47ad-9684-5edb3d70cea7>)

---

## chewygumxx

What command may invoke to get the fingerprint of a public pgpkey from a
keyID/file such that it may be programmatically stored within a bash variable?

```sh
fprint="$(gpg --with-fingerprint <file>)"
fprint="$(gpg --keyserver hkps://<...> --recv-keys <keyID>; gpg --fingerprint <keyID>)"
```

---

## Claude

### Programmatic Fingerprint Extraction

`gpg --with-fingerprint` is meant for human-readable output, not parsing. For a
script-safe value, use `--with-colons`, which gives a stable, machine-parseable
field format, then pull the `fpr` record.

### From a Key File

```sh
fprint="$(gpg --with-colons --with-fingerprint --show-keys <file> | awk -F: '/^fpr:/ {print $10; exit}')"
```

`--show-keys` inspects the file without importing it into your keyring.
`--with-fingerprint` (once here) ensures `fpr:` records are emitted alongside
the `pub:`/ `sub:` records.

### From a KeyID Already in Your Keyring

```sh
fprint="$(gpg --with-colons --fingerprint <keyID> | awk -F: '/^fpr:/ {print $10; exit}')"
```

### From a KeyID via Keyserver (Fetch Then Extract)

```sh
gpg --keyserver hkps://keys.openpgp.org --recv-keys <keyID>
fprint="$(gpg --with-colons --fingerprint <keyID> | awk -F: '/^fpr:/ {print $10; exit}')"
```

Separating the fetch (`--recv-keys`) from the query avoids relying on
`--fingerprint` 's human-formatted stderr/stdout mix, and the `; exit` in `awk`
guards against multi-subkey output returning more than one line.

### Why --with-colons

This is GnuPG's own de facto stable interface for scripting (documented in
`doc/DETAILS` in the GnuPG source tree) — field positions and record types
(`pub`, `fpr`, `uid`, `sub`, etc.) are guaranteed not to change between
versions, unlike the plain human-readable output, which has shifted format
across GnuPG releases.

### Alternatives Worth Considering

- `gpg --show-keys --with-colons <file>` piped into `grep '^fpr:' | cut -d:
  -f10` — functionally identical to the `awk` version above, just a matter of
  taste (`awk` avoids a second process).
- `sq` (Sequoia-PGP's CLI, e.g. `sq inspect --keyring <file>`) — a newer,
  memory-safe reimplementation with more consistently structured output, if
  you're open to a non-GnuPG toolchain.
- `gpg --list-options show-only-fpr-mbox` variants exist in some GnuPG builds
  but aren't portable across versions — stick with `--with-colons` for
  portability.

---

## chewygumxx

How may I check if a fingerprint already exists in the keyring?

---

## Claude

### Checking Fingerprint Presence in the Keyring

The cleanest approach is to query `--list-keys` (or `--list-secret-keys` for
private keys) directly by fingerprint and check the exit status — GnuPG accepts
a full fingerprint as a key specifier.

#### Boolean Existence Check

```sh
if gpg --list-keys "$fprint" &>/dev/null; then
    print "Key present in keyring"
else
    print "Key not found"
fi
```

`gpg` exits non-zero when no key matches the given specifier, so this needs no
output parsing at all.

#### As a Reusable Function

```sh
__gpg_key_exists() {
    gpg --list-keys "$1" &>/dev/null
}

if __gpg_key_exists "$fprint"; then
    print "already present"
fi
```

#### Stricter Match (Colon Output, Exact Field Comparison)

If you want to guard against substring/partial-match ambiguity (unlikely with a
full 40-char v4 fingerprint, but relevant if you're working with shortened
IDs), compare against the parsed `fpr:` field explicitly:

```sh
__gpg_key_exists() {
    local target=$1
    gpg --with-colons --list-keys 2>/dev/null | awk -F: -v t="$target" '/^fpr:/ && $10 == t {found=1} END {exit !found}'
}
```

### Checking Secret Keys Instead

Swap `--list-keys` for `--list-secret-keys` if you need to confirm the private
key material is present rather than just the public key.

### Note on Specifier Formats

`gpg` will also accept a bare keyID (short or long form) in place of the
fingerprint for these same checks, but since keyIDs aren't collision-resistant,
using the full fingerprint (as you're already doing per your earlier `$fprint`
variable) is the safer specifier — this is the same rationale behind RFC
4880bis' push toward fingerprint-based key references over keyIDs.
