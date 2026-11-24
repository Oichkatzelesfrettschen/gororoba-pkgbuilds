# Comment to post on https://aur.archlinux.org/packages/joern-git

Two independent problems. The first is a packaging bug with a one-line fix; the
second is a host-toolchain interaction the maintainer may prefer to document
rather than encode.

---

## package() looks for an artifact name sbt no longer produces

`package()` unzips `target/joern-cli.zip`, but `sbt createDistribution` now emits
a platform-suffixed name. The build succeeds completely and then dies at the
packaging step:

```
[success] All package validations passed
[success] Total time: 9 s, completed Aug 30, 2026, 9:10:33 PM
...
unzip:  cannot find or open target/joern-cli.zip, target/joern-cli.zip.zip or target/joern-cli.zip.ZIP.
==> ERROR: A failure occurred in package().
```

What is actually in `target/` afterwards:

```
$ ls target/*.zip
target/joern-cli-linux-x86_64.zip
```

A glob tracks whatever suffix upstream settles on:

```diff
 package() {
 	cd "$_pkgname"
+	local _dist
+	_dist=$(find target -maxdepth 1 -name 'joern-cli*.zip' -print -quit)
+	[ -n "$_dist" ] || { echo "no joern-cli*.zip under target/" >&2; return 1; }
 	mkdir -p "$pkgdir/opt/joern"
-	unzip -qo -d "$pkgdir/opt/joern" 'target/joern-cli.zip'
+	unzip -qo -d "$pkgdir/opt/joern" "$_dist"
 	cd "$pkgdir/opt/joern/joern-cli/"
```

`querydb/target/querydb.zip` is unchanged and still resolves.

## Building under JDK 26 crashes the JVM

On a host where `archlinux-java` defaults to `java-26-openjdk`, `sbt stage`
aborts with a HotSpot crash rather than a compile error:

```
SIGSEGV (0xb) at pc=0x00007f59613fa89e, pid=300042, tid=300545
JRE version: OpenJDK Runtime Environment (26.0.2)
Problematic frame: V  [libjvm.so+0x5fa89e]
Current thread: JavaThread "C2 CompilerThread0" ... _thread_in_native
Current CompileTask: C2:199755 ... dotty.tools.scaladoc.translators.SignatureBuilder::list
siginfo: si_signo: 11 (SIGSEGV), si_code: 1 (SEGV_MAPERR), si_addr: 0x000000000000002c
```

The C2 JIT thread segfaults on a near-null address while compiling scaladoc's
dotty bytecode. This is a VM crash, not resource exhaustion: heap exhaustion
raises `java.lang.OutOfMemoryError` with a different report header, and
upstream's `.sbtopts` already grants `-Xms3G -Xmx4G` against 31 GiB of RAM.

Building under `java-21-openjdk` compiles the same sources clean. `depends` and
`makedepends` already permit it (`java-runtime>=19`, `java-environment>=19`), so
pinning costs nothing:

```diff
+_jdk=/usr/lib/jvm/java-21-openjdk
+
 build() {
 	cd "$_pkgname"
+	if [ -d "$_jdk" ]; then
+		export JAVA_HOME="$_jdk"
+		export PATH="$_jdk/bin:$PATH"
+	fi
 	sbt stage
```

If pinning an LTS in the PKGBUILD is unwelcome, a note in the package
description would still save the next person the crash-log dig.
