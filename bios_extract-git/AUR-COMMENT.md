# Comment to post on https://aur.archlinux.org/packages/bios_extract-git

Paste the block below as an AUR comment. It states the mechanism, gives a
copy-pasteable reproduction, and hands the maintainer the one-line patch, so it
should be actionable without any back-and-forth.

---

`pkgver()` produces the literal string `r.`, so the package installs as version
`r.-1` and every `-Syu` offers the same phantom upgrade forever.

Cause: upstream `coreboot/bios_extract` renamed its default branch from `master`
to `main`. A fresh `git clone` therefore creates no local `master` ref, and both
substitutions in `pkgver()` fail:

```
$ git clone https://github.com/coreboot/bios_extract && cd bios_extract
$ git symbolic-ref --short HEAD
main
$ git branch --format='%(refname:short)'
main
$ git rev-list --count master
fatal: ambiguous argument 'master': unknown revision or path not in the working tree.
```

Both `$(git rev-list --count master)` and `$(git rev-parse --short master)`
expand to nothing, so `echo r$(...).$(...)` yields `r.`.

Fix, using `HEAD` so it tracks whichever branch makepkg checked out and survives
any future rename:

```diff
 pkgver() {
   cd bios_extract
-  echo r$(git rev-list --count master).$(git rev-parse --short master)
+  echo "r$(git rev-list --count HEAD).$(git rev-parse --short HEAD)"
 }
```

With that applied the version resolves correctly, currently `r131.0a7bc1d`.

Hardcoding `main` would also work today but breaks again on the next rename;
`HEAD` is what the `VCS package guidelines` recommend for exactly this reason.

The build itself is unaffected -- `build()` and `package()` succeed and all four
binaries install correctly. Only the version string is wrong.
