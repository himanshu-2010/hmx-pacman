# hmx — signed pacman repository

The official pacman repository for [hmx](https://github.com/himanshu-2010/hmx-lang),
a small statically typed systems language that transpiles to C.

This exists because **hmx is not in the AUR yet** — the AUR is currently behind an
Anubis anti-bot challenge that blocks both automated access and, right now,
registration. The AUR remains the better answer and the package here is built
from the same `PKGBUILD`, so this repo should become a mirror of it rather than a
competing one. See "This is a stopgap" below.

## Install

```bash
# 1. Import the signing key. Until this is done, pacman will refuse to sync --
#    that is the intended behaviour, not a problem to work around.
curl -fsSL https://himanshu-2010.github.io/hmx-pacman/hmx-signing-key.asc \
  | gpg --import

# 2. Trust it, at the right trust level. "ultimate" means "I have checked that
#    this fingerprint really belongs to the person who says it does".
#    Full fingerprint:  E203 38C6 BEB6 BBE9 78F9 13DB E6AE D9C6 13DD CF5E
gpg --lsign-key 3D987F64DC5DE0F56A383805117A9800DEC4FCCC

# 3. Add the repository.
echo "[hmx]
SigLevel = Required DatabaseRequired
Server = https://himanshu-2010.github.io/hmx-pacman/\$arch" | sudo tee -a /etc/pacman.conf

# 4. Install.
sudo pacman -Sy hmx
```

Or let `install.sh` do steps 3 and 4:

```bash
curl -fsSL https://raw.githubusercontent.com/himanshu-2010/hmx-lang/main/install/install.sh | bash
```

## What is in here

| Path | What it is |
|---|---|
| `x86_64/hmx.db` | the package database |
| `x86_64/hmx.db.sig` | its signature — pacman checks this before trusting the database |
| `x86_64/hmx-*.pkg.tar.zst` | the package |
| `x86_64/hmx-*.pkg.tar.zst.sig` | its signature |
| `hmx-signing-key.asc` | the public half of the signing key |
| `build-repo.sh` | rebuilds all of the above from an hmx-lang tag |
| `hmx-pacman.conf` | the `pacman.conf` stanza, for reading |
| `SHA256SUMS` | checksums for everything above |

`hmx.db` and `hmx.files` are **real files, not symlinks**, even though `repo-add`
creates them as symlinks: git stores a symlink as a small file containing its
target path, so committing them directly would make pacman fetch the literal text
`hmx.db.tar.gz` and fail with a gzip error pointing at the wrong problem.
`build-repo.sh` dereferences them and then asserts none survived.

## Rebuilding

```bash
GPG_KEY_ID=<fingerprint> ./build-repo.sh 0.10.0
```

Runs on Arch with `base-devel`. The `PKGBUILD` is fetched from the upstream
**tag**, not from a local checkout, so this repository cannot drift from the
manifest that is already `makepkg`-verified. Requires cmake, flex, bison, git
and gpg.

The signing key is never generated or stored here. A key that lives in a build
script is a key in a git history.

## This is a stopgap

A third-party pacman repository is real infrastructure with real obligations:
somebody is promising that the bytes at this URL stay unchanged and stay signed.
`hmx-pacman` is maintained by the same person who maintains hmx, so that promise
is as good as the account — but it is still one GitHub account, with no
independent audit, which is exactly what the AUR's build process and the
distribution's own signing are for.

Once AUR registration reopens, the intended sequence is: submit `PKGBUILD` to
the AUR, then point this repo's `build-repo.sh` at the AUR tarball, or retire it
and let `install.sh` prefer the AUR. `install.sh` already checks the AUR RPC
first and will hand off to the AUR automatically once `hmx` is there — this repo
is only reached when the AUR says no.

Third-party repos are a real practice and are used by plenty of projects. They are
also strictly worse practice than the AUR for anything with a working account,
and this file says so plainly rather than presenting the stopgap as the plan.

## Licence

MIT, same as hmx. The package metadata, the signing key and this repository's
configuration are the work of the hmx maintainer.
