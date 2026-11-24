# imp - Fixed PKGBUILD

## Package Information
- **Package**: imp (Image Manipulation Program)
- **Version**: 1.3.0-3
- **Upstream**: https://github.com/jangler/imp
- **AUR**: https://aur.archlinux.org/packages/imp

## Problem
The original AUR PKGBUILD (pkgrel=2) fails to build with modern Go versions (1.25.4+) because:
1. The upstream project is an old Go project without go.mod (pre-modules era)
2. Modern Go requires modules by default
3. The PKGBUILD uses GOPATH-based workflow which doesn't work anymore

## Fix Applied
1. Added `GO111MODULE=off` to disable Go modules and use GOPATH mode
2. Changed `mv` commands to `cp -r` to avoid build artifact conflicts
3. Added imp.go to the copy list
4. Specified full import path in go build command
5. Incremented pkgrel to 3

## Key Changes
```diff
- pkgrel=2
+ pkgrel=3

  build() {
    cd "${srcdir}/${pkgname}-${pkgver}"
    mkdir -p src/github.com/jangler/imp
-   mv filter src/github.com/jangler/imp
-   mv util src/github.com/jangler/imp
-   GOPATH="${srcdir}/${pkgname}-${pkgver}" go build -o ${pkgname}
+   cp -r filter src/github.com/jangler/imp/
+   cp -r util src/github.com/jangler/imp/
+   cp imp.go src/github.com/jangler/imp/
+   GO111MODULE=off GOPATH="${srcdir}/${pkgname}-${pkgver}" go build -o ${pkgname} github.com/jangler/imp
  }
```

## Installation
```bash
cd imp
makepkg -si
```

## Status
- Package builds successfully
- Installed and verified working at /usr/bin/imp
- Should be submitted upstream to AUR maintainer

## Date
2025-11-15
