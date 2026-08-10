<!-- vim: expandtab:shiftwidth=4
 -->

<!--  
   - 
   - ~chewygumxx/openpgpkey.git
   - ::: :/notes/2026-08-10_llmchat_cloudflare-worker-serve-openpgp.md
   -
   -->


# LLM Chat - CloudFlare Worker: Serve OpenPGP

[Link](<https://claude.ai/share/c6763eeb-d7b8-46a6-b288-a77e57a5011c>)

## chewygumxx

With respect to configuring a CloudFlare Worker, is it possible to assign a
file, (`https://pgp.cgxx.dev/chewygum-public.pgp.asc`) to the root subdomain
`pgp.cgxx.dev`? Is it the `main` key of `wrangler.jsonc`?

```zsh
[19:30:16] ~/ref/pgp>lt --git-ignore --no-git
~chewygumxx/pgp.git
├── .assetsignore
├── chewygumxx-public.pgp.asc
└── wrangler.jsonc
```

```gitignore
# vim: expandtab:shiftwidth=4:ft=gitignore

#
#
# ~chewygumxx/pgp.git
# ::: :/.assetsignore
#
#

#
# https://developers.cloudflare.com/workers/static-assets/binding/#ignoring-assets
#

# Directories
/.git/

# Files
/LICENSE
/README.md
/wrangler.jsonc
/.assetsignore
```

```jsonc
// vim: expandtab:shiftwidth=4

//
//
// ~chewygumxx/pgp.git
// ::: :/wrangler.jsonc
//
//

//
// https://developers.cloudflare.com/workers/wrangler/configuration
//

{
        "$schema": "./node_modules/wrangler/config-schema.json",
        "name": "pgp",
        "compatibility_date": "2026-08-09", // Set this to today's date
    "workers_dev": false,
    "route": {
        "pattern": "pgp.cgxx.dev",
        "custom_domain": true
    },
    "assets": {
        "directory": "./",
    }
}
[19:31:03] ~/ref/pgp>
```

---

## Claude

### Short answer

No — `main` isn't a mechanism for pointing a route at a specific asset file.
It's the entry point path for a Worker *script* (JS/TS), completely separate
from the `assets` block. Whether you need `main` at all depends on how you want
`/` to resolve.

### Default static-asset resolution behaviour

With no `main` present (an assets-only Worker, which is what your current
`wrangler.jsonc` is), Cloudflare's routing rule is simple: if a requested URL
matches a file in the static assets directory, that file will be served without
invoking Worker code.

That means:

- `pgp.cgxx.dev/chewygumxx-public.pgp.asc` → **already works today**, zero
  extra config, correct filename-derived `Content-Type`.
- `pgp.cgxx.dev/` (root) → Cloudflare looks for `index.html` at that path.
  Since you don't have one, and you have no `main` script and no
  `not_found_handling` override, that request 404s.

There's no `assets.*` config key in `wrangler.jsonc` that lets you say "serve
`chewygumxx-public.pgp.asc` when the path is `/`." Asset-directory mapping is
purely path-to-filename; it doesn't support aliasing.

### Making / serve the key

#### Option A — main script that forwards to the asset (recommended)

Add a minimal Worker that intercepts only `/`, and lets everything else fall
through to the assets pipeline untouched via `run_worker_first`:

```jsonc
// wrangler.jsonc
{
    "$schema": "./node_modules/wrangler/config-schema.json",
    "name": "pgp",
    "compatibility_date": "2026-08-09",
    "workers_dev": false,
    "route": {
        "pattern": "pgp.cgxx.dev",
        "custom_domain": true
    },
    "main": "./src/index.ts",
    "assets": {
        "directory": "./",
        "binding": "ASSETS",
        "run_worker_first": ["/"]
    }
}
```

```ts
// src/index.ts
export default {
    async fetch(request: Request, env: { ASSETS: Fetcher }) {
        const url = new URL(request.url);
        if (url.pathname === "/") {
            const keyUrl = new URL("/chewygumxx-public.pgp.asc", url);
            const res = await env.ASSETS.fetch(keyUrl);
            return new Response(res.body, {
                ...res,
                headers: {
                    ...Object.fromEntries(res.headers),
                    "content-type": "application/pgp-keys; charset=utf-8",
                },
            });
        }
        return env.ASSETS.fetch(request);
    },
};
```

`run_worker_first: ["/"]` invokes the Worker script for the specified path
while everything else continues through the normal asset-serving fast path — so
you keep the zero-Worker performance characteristics for the `.asc` request
itself and only pay the cold-start/CPU cost on the root hit.

#### Option B — copy/rename the file to index.html

Wrangler will happily serve it, but the `Content-Type` would resolve to
`text/html` by filename extension, which is wrong for an ASCII-armored key and
will make some MUAs/clients mis-handle it. Not recommended unless you also ship
a `_headers` -style override — and Workers static assets doesn't support Pages'
`_headers` / `_redirects` files, so you're back to needing `main` anyway.

#### Option C — skip root entirely, link the filename directly

Simplest possible config: leave `wrangler.jsonc` exactly as-is (no `main`), and
just always reference `https://pgp.cgxx.dev/chewygumxx-public.pgp.asc`. No
Worker, no `run_worker_first`, no extra moving parts — arguably the least
contrived answer if you don't have a hard requirement for a bare-root URL.

### Relevant conventional spec

Since this is a PGP-key-discovery use case, it's worth knowing the **OpenPGP
Web Key Directory (WKD)** convention — it defines a fixed, tool-discoverable
path (`/.well-known/openpgpkey/<domain>/hu/<zbase32-sha1-of-localpart>`) so
mail clients (GnuPG, Thunderbird/Enigmail, etc.) can auto-fetch your key from
`pgp.cgxx.dev` without you publishing a "nice" root URL at all. If
autodiscovery by MUAs matters to you more than a memorable link, that's the
standard to target instead of (or alongside) a root-served file.

---

## chewygumxx

> Relevant conventional spec
> 
> Since this is a PGP-key-discovery use case, it's worth knowing the OpenPGP Web
> Key Directory (WKD) convention — it defines a fixed, tool-discoverable path
> (/.well-known/openpgpkey/<domain>/hu/<zbase32-sha1-of-localpart>) so mail
> clients (GnuPG, Thunderbird/Enigmail, etc.) can auto-fetch your key from
> pgp.cgxx.dev without you publishing a "nice" root URL at all. If autodiscovery
> by MUAs matters to you more than a memorable link, that's the standard to
> target instead of (or alongside) a root-served file.

Please elaborate

---

## Claude

### Two WKD methods, and why the subdomain name matters

WKD isn't just "put the key at a well-known path anywhere" — the RFC draft
(`draft-koch-openpgp-webkey-service`) defines two fixed layouts, and the
subdomain name in the *advanced* method is not arbitrary:

#### Advanced method

```
https://openpgpkey.<domain>/.well-known/openpgpkey/<domain>/hu/<hash>?l=<local-part>
```

The subdomain must literally be `openpgpkey`, not `pgp`. So for an address like
`chewygum@cgxx.dev`, this would resolve to
`openpgpkey.cgxx.dev/.well-known/openpgpkey/cgxx.dev/hu/<hash>` — a *different*
hostname from your existing `pgp.cgxx.dev` Worker. Your current setup doesn't
satisfy this method as-is; you'd need a second Worker route (or the same Worker
with an additional custom domain bound to `openpgpkey.cgxx.dev`).

#### Direct method

```
https://<domain>/.well-known/openpgpkey/hu/<hash>?l=<local-part>
```

This drops the subdomain requirement entirely but serves from the **apex**
domain (`cgxx.dev`), not `pgp.cgxx.dev`. Clients try the advanced method first
and fall back to direct if it's absent.

Either way, `pgp.cgxx.dev` as a standalone hostname isn't a location WKD-aware
clients will probe on their own — it only works today because you're linking to
it manually.

### Hash computation

The path segment under `hu/` is not the email address — it's z-base-32 of the
SHA-1 digest of the **lowercased local-part** (everything before `@`):

```sh
echo -n "chewygum" | sha1sum | ...   # then z-base-32 encode the raw digest, not the hex string
```

GnuPG can do this for you directly:

```sh
gpg --with-wkd-hash --fingerprint chewygum@cgxx.dev
```

or, to generate and stage the full WKD tree from a key you already have in your
keyring:

```sh
gpg --export chewygum@cgxx.dev | gpg-wks-client --install-key
```

`gpg-wks-client --install-key` writes the correctly-hashed filename into a
`.well-known/openpgpkey/<domain>/hu/` structure it builds for you, so you don't
hand-roll the z-base-32 step.

### Binary, not ASCII-armored — this is the part most people get wrong first try

WKD requires the key served at the `hu/<hash>` path to be **binary OpenPGP key
material**, not the `.asc` ASCII-armored form you're currently serving at
`chewygumxx-public.pgp.asc`. If you point WKD at an armored file, most
implementations (GnuPG's `--locate-key`, Thunderbird, etc.) will fail to parse
it silently. You'd export a separate binary copy:

```sh
gpg --export chewygum@cgxx.dev > hu/<hash>   # no --armor
```

and keep your `.asc` file as the human-facing download, serving both from the
same asset directory if you like — they're just different files with different
audiences (armored for a person pasting into `gpg --import`, binary for
WKD-aware software).

### Required companion: the policy file

WKD also expects an (often empty) policy file at:

```
https://openpgpkey.<domain>/.well-known/openpgpkey/policy
```

It can be zero bytes; its presence alone signals "this domain supports WKD."
Cloudflare's static-assets serving handles an empty file fine — just make sure
`.assetsignore` doesn't accidentally exclude it (yours currently ignores
dotfiles like `.git/`, `.assetsignore` itself, etc., which is fine, but a
zero-length file under `.well-known/` needs to *not* be pattern-matched away).

### Serving details specific to your Worker setup

- **Content-Type**: WKD doesn't mandate a specific MIME type as strictly as WKS
  does, but `application/octet-stream` is the conventional choice for the binary
  key blob — Cloudflare's default filename-derived type for an extensionless file
  under `hu/` should already land there, so you likely don't need the
  header-override trick from the earlier `main` -script answer for this path
  specifically.
- **No redirects**: some WKD client implementations don't follow HTTP
  redirects, so if you set this up on the apex `cgxx.dev` domain and that domain
  does any `www.`\-style redirecting elsewhere, keep `/.well-known/openpgpkey/`
  outside that redirect logic.
- **CORS**: recommended (not required) to send `Access-Control-Allow-Origin: *`
  on the WKD paths, since some webmail-integrated clients fetch this cross-origin
  from the browser context.
- **`route.pattern`**: if you go the advanced-method route, you'd add a second
  `custom_domain` binding for `openpgpkey.cgxx.dev` — Wrangler's `route` key in
  your `wrangler.jsonc` only accepts a single pattern per config currently, so
  this would mean either a second Worker (can share the same `assets.directory`
  if you lay out `.well-known/openpgpkey/cgxx.dev/hu/` inside `~/ref/pgp/`) or a
  second `routes` array entry if you're using multiple custom domains on one
  Worker — worth checking current Wrangler config-schema support for multiple
  `route` entries before assuming either shape, since this has shifted across
  Wrangler versions.

---

## chewygumxx

> Advanced method
> 
> https://openpgpkey.<domain>/.well-known/openpgpkey/<domain>/hu/<hash>?l=<local-part>
> 
> The subdomain must literally be openpgpkey, not pgp. So for an address like
> chewygum@cgxx.dev, this would resolve to
> openpgpkey.cgxx.dev/.well-known/openpgpkey/cgxx.dev/hu/<hash> — a different
> hostname from your existing pgp.cgxx.dev Worker. Your current setup doesn't
> satisfy this method as-is; you'd need a second Worker route (or the same Worker
> with an additional custom domain bound to openpgpkey.cgxx.dev).

I want to create a CloudFlare worker for \*exactly\* this purpose

---

## Claude

### Repo layout

Since this Worker's *only* job is WKD, keep it separate from your existing
`pgp` repo/Worker (different custom domain, different purpose):

```
~/ref/openpgpkey/
├── .assetsignore
├── _headers
├── wrangler.jsonc
└── .well-known/
    └── openpgpkey/
        └── cgxx.dev/
            ├── policy
            └── hu/
                └── <zbase32-hash>
```

### wrangler.jsonc

No `main` needed — this is pure static-asset serving, no request-time logic
required for the advanced-method path itself:

```jsonc
// vim: expandtab:shiftwidth=4

//
//
// ~chewygumxx/openpgpkey.git
// ::: :/wrangler.jsonc
//
//

//
// https://developers.cloudflare.com/workers/wrangler/configuration
//

{
    "$schema": "./node_modules/wrangler/config-schema.json",
    "name": "openpgpkey",
    "compatibility_date": "2026-08-09",
    "workers_dev": false,
    "route": {
        "pattern": "openpgpkey.cgxx.dev",
        "custom_domain": true
    },
    "assets": {
        "directory": "./"
    }
}
```

### .assetsignore

Same shape as your existing one — just don't accidentally add `.well-known/` to
it:

```gitignore
# vim: expandtab:shiftwidth=4:ft=gitignore

#
#
# ~chewygumxx/openpgpkey.git
# ::: :/.assetsignore
#
#

#
# https://developers.cloudflare.com/workers/static-assets/binding/#ignoring-assets
#

# Directories
/.git/

# Files
/LICENSE
/README.md
/wrangler.jsonc
/.assetsignore
/_headers
```

### \_headers for CORS

Cloudflare's Workers-static-assets `_headers` support (same syntax as Pages)
applies directly here since you have no `main` script intercepting requests —
this is honestly the cleaner path versus what I suggested earlier for your
`pgp` Worker, since there's no need to spin up a Worker script just to attach a
header:

```
/.well-known/openpgpkey/*
  Access-Control-Allow-Origin: *
```

### Generating the key material and hash

Don't hand-roll the z-base-32/SHA-1 step — `gpg-wks-client` builds the exact
tree structure for you when run from your repo root:

```sh
cd ~/ref/openpgpkey
gpg --export chewygum@cgxx.dev | gpg-wks-client --install-key
```

This should produce `.well-known/openpgpkey/cgxx.dev/hu/<hash>` directly,
containing binary (non-armored) key material — check `gpg-wks-client --help` on
your system for the exact invocation, since flag behavior has shifted across
GnuPG versions and it's worth confirming against whatever's in your `pacman`
repos.

If you'd rather verify the hash independently before trusting the tool output:

```sh
gpg --with-wkd-hash --fingerprint chewygum@cgxx.dev
```

### The policy file

```sh
touch .well-known/openpgpkey/cgxx.dev/policy
```

Zero bytes is correct — its mere presence at that path is the signal.

### One thing worth test-deploying before you trust it

There's old, [documented history](https://github.com/cloudflare/wrangler-legacy/issues/980)
of the **legacy** Workers Sites product (the deprecated KV-bucket-based
predecessor, not today's `assets.directory` feature) silently skipping
dotfiles/dot-directories on upload — which would be fatal for a `.well-known/`
tree. Current static-assets docs don't call out that exclusion behavior, and
it's a different upload pipeline entirely, but given the consequence of it
silently dropping your WKD tree, I'd do a `wrangler deploy --dry-run` (or just
deploy and immediately curl the policy file) rather than assume it's fine:

```sh
curl -sI https://openpgpkey.cgxx.dev/.well-known/openpgpkey/policy
```

### Alternatives, since this is a fair amount of moving parts for one key

1. **Direct method only** — drop the `openpgpkey.` subdomain requirement
   entirely, serve `.well-known/openpgpkey/hu/<hash>` from the apex `cgxx.dev`
   domain instead. Fewer DNS/custom-domain entries, at the cost of clients
   trying (and 404ing on) the advanced method first before falling back.
2. **`gpg-wks-client --install-key` output directly into your existing `pgp`
   repo**, bound as a second custom domain (`openpgpkey.cgxx.dev`) on the
   *same* Worker rather than a new one — one `wrangler.jsonc`, two `route`
   entries if your Wrangler version's schema supports multiple routes per
   config; otherwise two `wrangler.jsonc` files sharing one `assets.directory`
   via symlink or a build step.
3. **Skip WKD entirely** and rely on your existing manual `.asc` link plus a
   classic HKP keyserver submission (`keys.openpgp.org`) — significantly less
   infrastructure if autodiscovery-by-MUA isn't a hard requirement for you.

---

## chewygumxx

Like this?

```sh
[20:15:39] ~/ref/openpgpkey>gpg --with-wkd-hash --fingerprint me@cgxx.dev
pub   ed25519 2026-08-10 [SC]
      161F 3230 8CA8 9A04 E4A6  3D30 4457 B8B4 8409 0AB4
uid           [ultimate] chewygumxx <me@cgxx.dev>
              s8y7oh5xrdpu9psba3i5ntk64ohouhga@cgxx.dev
sub   cv25519 2026-08-10 [E]

[20:16:44] ~/ref/openpgpkey>gpg --export me@cgxx.dev > .well-known/openpgpkey/cgxx.dev/hu/s8y7oh5xrdpu9psba3i5ntk64ohouhga
[20:17:06] ~/ref/openpgpkey>lt --git-ignore
-N ~chewygumxx/openpgpkey.git
-N ├── .well-known
-N │   └── openpgpkey
-N │       └── cgxx.dev
-N │           ├── hu
-N │           │   └── s8y7oh5xrdpu9psba3i5ntk64ohouhga
-N │           └── policy
-N ├── .assetsignore
-N ├── _headers
-- ├── chewygumxx-public.pgp.asc
-N ├── me@cgxx.dev.pgp.asc
-N └── wrangler.jsonc
[20:17:16] ~/ref/openpgpkey>
```

---

## Claude

### Yes — this is structurally correct

Walking through it:

- **Hash matches**: `--with-wkd-hash` derived
  `s8y7oh5xrdpu9psba3i5ntk64ohouhga`, and you used exactly that (stripped of the
  `@cgxx.dev` suffix the tool appends for display) as the filename under `hu/`.
  32 characters, consistent with z-base-32 of a 160-bit SHA-1 digest.
- **Path is right**: `.well-known/openpgpkey/cgxx.dev/hu/<hash>` is the correct
  advanced-method layout relative to the `openpgpkey.cgxx.dev` root.
- **Binary export is correct**: `gpg --export` with no `--armor` flag writes
  binary OpenPGP packets — exactly what WKD requires at that path. If you'd
  accidentally added `--armor` there, this would silently fail against real
  clients.
- **`policy`** is present at the right location alongside `hu/`.

### Two things worth double-checking before you deploy

#### Confirm policy is actually zero bytes

The listing shows it exists but not its size. If it inherited content from
somewhere (copy-paste, editor auto-save, etc.) rather than a bare `touch`, it's
still spec-legal (content isn't prohibited) but worth a quick:

```sh
wc -c .well-known/openpgpkey/cgxx.dev/policy
```

#### Two differently-named.asc files in one repo

`chewygumxx-public.pgp.asc` shows `--` (already tracked/clean) while
`me@cgxx.dev.pgp.asc` shows `-N` (new/untracked) — meaning
`chewygumxx-public.pgp.asc` predates this session in this repo. That's the same
filename that lives in your separate `pgp.cgxx.dev` repo from earlier in this
conversation. Worth confirming intentionally:

- Is `~/ref/openpgpkey` actually a fresh repo, or did you copy/merge it from
  `~/ref/pgp`?
- If merged on purpose (one Worker serving both `pgp.cgxx.dev` and
  `openpgpkey.cgxx.dev` via two custom domains on the same `wrangler.jsonc`),
  that's a legitimate consolidation — just means your `route` config needs both
  patterns, per the "same Worker, two custom domains" alternative from earlier.
- If it's *not* intentional, having two armored exports of what should be the
  same key (`chewygumxx-public.pgp.asc` vs `me@cgxx.dev.pgp.asc`) invites them
  drifting out of sync after your next key rotation.

Neither blocks the WKD path from working — just a bookkeeping question before
you commit.

### Post-deploy verification

Once this is live, the real test isn't `curl` — it's asking WKD-aware tooling
to actually resolve it:

```sh
gpg --locate-key me@cgxx.dev
```

Run that from a machine/keyring that doesn't already have the key locally
cached, or it'll succeed for the wrong reason.
