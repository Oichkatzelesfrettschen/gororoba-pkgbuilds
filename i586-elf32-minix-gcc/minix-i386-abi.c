/* Binds a compiler's i386 MINIX type model to the sysroot headers that libc
   was built against. Every check is a compile-time assertion, so the probe
   discriminates before any code links or runs: a compiler whose SIZE_TYPE,
   PTRDIFF_TYPE, WCHAR_TYPE, or WINT_TYPE disagrees with <machine/ansi.h>
   produces objects whose libc calls take the wrong argument widths, and this
   translation unit refuses to compile rather than producing them.

   Compile against the target sysroot's headers, for example
     $CC -std=c99 -Wall -Wextra -Werror -c minix-i386-abi.c
   with the compiler's own --with-sysroot in effect. The paired fault
   injection lives in inject-minix-i386-abi.sh, so this file carries no path
   that can weaken an assertion. */

#include <limits.h>
#include <stddef.h>
#include <sys/types.h>
#include <wchar.h>

/* A false condition gives the array a negative size, which C99 rejects at
   translation time; the tag names the assertion in the diagnostic. */
#define ABI_ASSERT(name, cond) typedef char abi_assert_##name[(cond) ? 1 : -1]

/* Scalar widths of the 32-bit MINIX ELF ABI. */
ABI_ASSERT(char_bit, CHAR_BIT == 8);
ABI_ASSERT(short_size, sizeof(short) == 2);
ABI_ASSERT(int_size, sizeof(int) == 4);
ABI_ASSERT(long_size, sizeof(long) == 4);
ABI_ASSERT(long_long_size, sizeof(long long) == 8);
ABI_ASSERT(pointer_size, sizeof(void *) == 4);
ABI_ASSERT(float_size, sizeof(float) == 4);
ABI_ASSERT(double_size, sizeof(double) == 8);

/* The x87 80-bit format occupies twelve bytes at four-byte alignment in the
   i386 System V ABI, which is what the sysroot's libm and libc were built
   against. */
ABI_ASSERT(long_double_size, sizeof(long double) == 12);

/* machine/ansi.h defines _BSD_SIZE_T_ as unsigned int and _BSD_PTRDIFF_T_ as
   int, and GCC and clang each publish their own choice as __SIZE_TYPE__ and
   __PTRDIFF_TYPE__. Comparing widths and signedness catches the case where a
   compiler's target header disagrees with the headers libc was compiled
   against. */
ABI_ASSERT(size_t_width, sizeof(size_t) == 4);
ABI_ASSERT(size_t_unsigned, (size_t)-1 > (size_t)0);
ABI_ASSERT(ptrdiff_t_width, sizeof(ptrdiff_t) == 4);
ABI_ASSERT(ptrdiff_t_signed, (ptrdiff_t)-1 < (ptrdiff_t)0);
ABI_ASSERT(size_t_matches_builtin, sizeof(size_t) == sizeof(__SIZE_TYPE__));
ABI_ASSERT(ptrdiff_t_matches_builtin,
           sizeof(ptrdiff_t) == sizeof(__PTRDIFF_TYPE__));

/* minix.h sets WCHAR_TYPE and WINT_TYPE to int and WCHAR_TYPE_SIZE to 32, and
   the sysroot's _BSD_WCHAR_T_ and _BSD_WINT_T_ agree. */
ABI_ASSERT(wchar_t_width, sizeof(wchar_t) == 4);
ABI_ASSERT(wchar_t_signed, (wchar_t)-1 < (wchar_t)0);
ABI_ASSERT(wint_t_width, sizeof(wint_t) == 4);

/* Structure layout the calling convention depends on: no tail padding beyond
   natural alignment, and bitfields packed into the declared storage unit. */
struct abi_pair { char c; int i; };
struct abi_three { char a; char b; char c; };
struct abi_bits { unsigned int lo : 3; unsigned int hi : 5; };

ABI_ASSERT(pair_size, sizeof(struct abi_pair) == 8);
ABI_ASSERT(pair_alignment, offsetof(struct abi_pair, i) == 4);
ABI_ASSERT(three_size, sizeof(struct abi_three) == 3);
ABI_ASSERT(bitfield_unit, sizeof(struct abi_bits) == 4);

/* The struct sizes the return convention is measured at; DEFAULT_PCC_STRUCT_RETURN
   sends every one of them back through memory, which the generated code shows
   rather than this file. */
struct abi_ret1 { char a[1]; };
struct abi_ret2 { char a[2]; };
struct abi_ret4 { char a[4]; };
struct abi_ret8 { char a[8]; };
struct abi_ret12 { char a[12]; };
struct abi_ret16 { char a[16]; };

ABI_ASSERT(ret1_size, sizeof(struct abi_ret1) == 1);
ABI_ASSERT(ret2_size, sizeof(struct abi_ret2) == 2);
ABI_ASSERT(ret4_size, sizeof(struct abi_ret4) == 4);
ABI_ASSERT(ret8_size, sizeof(struct abi_ret8) == 8);
ABI_ASSERT(ret12_size, sizeof(struct abi_ret12) == 12);
ABI_ASSERT(ret16_size, sizeof(struct abi_ret16) == 16);

struct abi_ret1 abi_return1(void) { struct abi_ret1 v; v.a[0] = 1; return v; }
struct abi_ret2 abi_return2(void) { struct abi_ret2 v; v.a[0] = 2; return v; }
struct abi_ret4 abi_return4(void) { struct abi_ret4 v; v.a[0] = 4; return v; }
struct abi_ret8 abi_return8(void) { struct abi_ret8 v; v.a[0] = 8; return v; }
struct abi_ret12 abi_return12(void) { struct abi_ret12 v; v.a[0] = 12; return v; }
struct abi_ret16 abi_return16(void) { struct abi_ret16 v; v.a[0] = 16; return v; }

/* The predefined macros the MINIX target promises its sources. Clang's
   MinixTargetInfo::getOSDefines states the release in all three spellings, so
   source testing the release rather than the name reads 3 from either
   compiler front end. */
#ifndef __minix
#error "the target defines no __minix"
#endif
#ifndef __minix__
#error "the target defines no __minix__"
#endif
#ifndef __Minix__
#error "the target defines no __Minix__"
#endif
#if __minix != 3 || __minix__ != 3 || __Minix__ != 3
#error "the MINIX release macros disagree with the accepted compiler's value"
#endif
#ifndef __unix__
#error "the target defines no __unix__"
#endif
#ifndef __ELF__
#error "the target defines no __ELF__"
#endif
#ifdef __NetBSD__
#error "the MINIX target defines __NetBSD__, which its headers key on separately"
#endif
