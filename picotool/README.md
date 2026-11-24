# picotool

Tracks the upstream release rather than the AUR package, which sat at 2.3.0.

## Why this package exists

`picotool` 2.3.0 aborts on every RP2040 device. `info`, `load`, `save`,
`verify`, and `bdev` all die before producing output:

```
/usr/include/c++/16/bits/shared_ptr_base.h:1424: _Tp* std::__shared_ptr_deref(_Tp*)
[with _Tp = tuple<resident_partition_t, shared_ptr<vector<partition_details, ...> > >]:
Assertion '__p != nullptr' failed.
```

`get_partition_info` returns `nullptr` when the connected model reports
`supports_partition_table()` false, which every RP2040 does, because partition
tables are an RP2350 feature. `get_partitions` at main.cpp:4673 dereferenced
that pointer with no null test. Arch and CachyOS compile C++ with
`-Wp,-D_GLIBCXX_ASSERTIONS`, so the defect surfaces as a clean abort; without
the define it is an unchecked null dereference rather than a working build.

Upstream fixed it in 2.3.1, released 2026-09-05, at main.cpp:4678:

```cpp
std::shared_ptr<vector<partition_details>> get_partitions(picoboot::connection &con) {
    auto pi = get_partition_info(con);
    return pi ? std::get<1>(*pi) : nullptr;
}
```

So this package carries no patch. It is the AUR PKGBUILD at 2.3.1, plus
`arch=('x86_64')` in place of the upstream `arch=('any')`, which misdeclares a
compiled binary as architecture-independent.

## Verification

2.3.1 builds against pico-sdk 2.3.0 and reports a Raspberry Pi Pico correctly
where 2.3.0 aborted:

```
$ picotool info -d
Device Information
 type:      RP2040
 revision:  B2
```

`namcap` reports three `ELF file outside of a valid path` errors for
`usr/share/picotool/*.elf`. Those are Arm Cortex-M payloads picotool embeds
into user images, and they are inherent to what upstream ships.

Drop this package once the AUR moves to 2.3.1 or later, keeping the `arch`
correction in mind.
