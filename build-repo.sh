#!/usr/bin/env bash
# Rebuild this pacman repository from an hmx-lang tag.
#
#   GPG_KEY_ID=<fpr> ./build-repo.sh 0.10.0
#
# Requires an Arch machine with base-devel: cmake flex bison git gpg.
# The signing key must already be in the caller's keyring (GPG_FINGERPRINT /
# GPG_KEY_ID, or gpg's default-key). Nothing here generates or stores a key --
# a signing key in a CI log is a signing key in a git history.
#
# What it does, in order:
#   1. fetch the PKGBUILD from the hmx-lang tag, so the repo can never drift
#      from the manifest that is already makepkg-verified
#   2. build the package from the tag's source tarball
#   3. sign the package
#   4. build and sign the repo database
#   5. dereference repo-add's symlinks, because git stores a symlink as a file
#      containing its target path -- committed raw, pacman would fetch the text
#      "hmx.db.tar.gz" and fail with a gzip error that names the wrong problem
#   6. write SHA256SUMS
set -euo pipefail

VERSION="${1:?usage: $0 <version>   (e.g. 0.10.0)}"
ARCH_NAME="${ARCH_NAME:-x86_64}"
UPSTREAM="himanshu-2010/hmx-lang"
HERE="$(cd "$(dirname "$0")" && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

if ! command -v makepkg >/dev/null 2>&1; then
    echo "error: makepkg not found -- this must run on Arch (pacman -S base-devel)" >&2
    exit 1
fi
if ! command -v repo-add >/dev/null 2>&1; then
    echo "error: repo-add not found -- it ships in the pacman package" >&2
    exit 1
fi

# 1. the PKGBUILD comes from upstream, never from a local checkout that might be
#    ahead of it. This is the whole reason the AUR and this repo agree.
#
#    main is tried first and the tag second, and the order matters. Fetching from
#    the tag sounds stricter, but the tag is frozen at whatever the manifest looked
#    like on release day, so it silently keeps every fix made since. v0.10.0 is
#    the live example: the tag still has the file called PKBUILD, because the
#    rename to PKGBUILD landed after the release, so a tag-only fetch 404s on a
#    manifest that is perfectly good on main.
#
#    Fetching from main is safe because of the pkgver assertion below: main's
#    PKGBUILD declares which release it builds, so asking for 0.10.0 and getting
#    a manifest for 0.11.0 fails loudly instead of shipping the wrong thing.
echo "==> fetching PKGBUILD from ${UPSTREAM}"
PKGBUILD_URL=""
for ref_and_path in "main:packaging/arch/PKGBUILD" "main:packaging/arch/PKBUILD" "v${VERSION}:packaging/arch/PKGBUILD" "v${VERSION}:packaging/arch/PKBUILD"; do
    ref="${ref_and_path%%:*}"
    path="${ref_and_path#*:}"
    url="https://raw.githubusercontent.com/${UPSTREAM}/${ref}/${path}"
    if curl -fsSL "$url" -o "$WORK/PKGBUILD" 2>/dev/null; then
        PKGBUILD_URL="$url"
        echo "    found ${ref}/${path}"
        break
    fi
done
if [ -z "$PKGBUILD_URL" ]; then
    echo "error: no PKGBUILD found in ${UPSTREAM} (tried main and v${VERSION}," >&2
    echo "       at packaging/arch/PKGBUILD and packaging/arch/PKBUILD)" >&2
    exit 1
fi

PKGVER="$(sed -n 's/^pkgver=//p' "$WORK/PKGBUILD" | head -1)"
PKGREL="$(sed -n 's/^pkgrel=//p' "$WORK/PKGBUILD" | head -1)"
if [ "$PKGVER" != "$VERSION" ]; then
    echo "error: asked for $VERSION but that PKGBUILD declares pkgver=$PKGVER" >&2
    exit 1
fi

# 2. build. --nosign because makepkg's signing runs inside fakeroot and needs the
#    keyring readable there; the package is signed explicitly in step 3 instead.
echo "==> building hmx ${PKGVER}-${PKGREL}"
( cd "$WORK" && makepkg -sf --noconfirm --nosign --nodeps ) >"$WORK/build.log" 2>&1 || {
    echo "error: makepkg failed; last lines:" >&2
    tail -20 "$WORK/build.log" >&2
    exit 1
}
PKG="hmx-${PKGVER}-${PKGREL}-${ARCH_NAME}.pkg.tar.zst"
[ -f "$WORK/$PKG" ] || { echo "error: expected $PKG, not built" >&2; exit 1; }

# 3. sign the package
echo "==> signing $PKG"
gpg --batch --yes --detach-sign --local-user "${GPG_KEY_ID:?set GPG_KEY_ID}" "$WORK/$PKG"

# 4. build and sign the database
#    repo-add's --sign takes no key argument: it reads the key from $GPGKEY (or
#    gpg's default-key). Passing the fingerprint positionally is not a warning,
#    it is an error about "database archive extension", which reads like the
#    output file is the problem. Export the variable instead.
echo "==> building and signing the database"
mkdir -p "$HERE/$ARCH_NAME"
cp "$WORK/$PKG" "$HERE/$ARCH_NAME/"
cp "$WORK/$PKG.sig" "$HERE/$ARCH_NAME/"
( cd "$HERE" && GPGKEY="${GPG_KEY_ID}" repo-add --sign "$ARCH_NAME/hmx.db.tar.gz" "$ARCH_NAME/$PKG" ) >/dev/null

# 5. dereference repo-add's symlinks (see the header -- this is not optional)
echo "==> dereferencing symlinks"
for f in hmx.db hmx.db.sig hmx.files hmx.files.sig; do
    if [ -L "$HERE/$ARCH_NAME/$f" ]; then
        cp -L "$HERE/$ARCH_NAME/$f" "$HERE/$ARCH_NAME/$f.real"
        mv "$HERE/$ARCH_NAME/$f.real" "$HERE/$ARCH_NAME/$f"
    fi
done
for f in "$ARCH_NAME"/*; do
    if [ -L "$f" ]; then
        echo "error: $f is still a symlink -- git would store the target path as file contents" >&2
        exit 1
    fi
done

# 6. checksums
echo "==> writing SHA256SUMS"
( cd "$HERE" && sha256sum "$ARCH_NAME"/* hmx-signing-key.asc > SHA256SUMS )

echo
echo "==> done. ${ARCH_NAME}/ now holds:"
ls -1 "$HERE/$ARCH_NAME" | sed 's/^/    /'
echo
echo "Verify before publishing:"
echo "  sha256sum -c SHA256SUMS"
echo "  gpg --verify ${ARCH_NAME}/hmx.db.sig ${ARCH_NAME}/hmx.db.tar.gz"
echo "  gpg --verify ${ARCH_NAME}/${PKG}.sig ${ARCH_NAME}/${PKG}"
