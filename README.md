[![Build Status](https://travis-ci.org/ReservedField/arm-compiler-rt.svg?branch=master)](https://travis-ci.org/ReservedField/arm-compiler-rt)

This is an experiment to make building `compiler-rt` for bare metal ARM targets
easy. It bypasses the CMake build system and is much quicker to setup.

## Prebuilts

You can grab prebuilt packages from the [Releases](https://github.com/ReservedField/arm-compiler-rt/releases)
page. Those are deployed from Travis for tagged commits that I deem stable, so
you'll usually be fine with the latest one.

They are built using `binutils-arm-none-eabi`, `gcc-arm-none-eabi` and
`libnewlib-arm-none-eabi` from Ubuntu Trusty repositories. Note that newlib is
only used for headers, so the prebuilts should work even if you link against a
different libc.

## Building from source

### Dependencies

Those are all required:

 * `arm-none-eabi` binutils
 * `arm-none-eabi` libc (e.g. newlib)
 * GNU make >= 3.81

One of those compilers is required:

 * `arm-none-eabi` GCC
 * Clang >= 3.9.0

### Cloning

`compiler-rt` is provided as a submodule:
```
git clone https://github.com/ReservedField/arm-compiler-rt
cd arm-compiler-rt
git submodule init
git submodule update
```

### Preparation

You need to properly set `CC` for `make` to point to your cross compiler.

You also need to check that your `arm-none-eabi` libc headers are in your
compiler search path. It can be done with `CC -v -x c /dev/null` (replace `CC`
with your actual compiler).

The most common situation is that you've installed your software from repos,
which usually means that `arm-none-eabi-gcc` will have the libc headers set up
but Clang won't. If you need to add include paths you can specify a
space-separated list with the `INCDIRS` variable.

A typical GCC build looks like:
```
CC=arm-none-eabi-gcc make
```

A typical Clang build looks like:
```
CC=clang INCDIRS=/usr/arm-none-eabi/include make
```

Please make sure you've set those correctly - don't build against the system
libc headers. Note that builds might succeed even without explicit headers and
without libc being in the search path because the compiler is pulling them from
the system. You don't want that! Check your include paths.

You'll need to specify those options everytime you're building something, even
though for brevity it's not explicited in the Building section. The exceptions
are of course `clean(-target)`, `distclean` and `dist` (for the latter, only if
everything's already built).

### Building

To build everything just issue `make`. To clean the whole build use
`make clean`.

You can also build and clean single targets using `make target` and
`make clean-target`. Supported targets:

 * `armv6m`: ARMv6-M (e.g. Cortex-M0/M0+/M1). Outputs to `lib/armv6-m`.
 * `armv7m`: ARMv7-M (e.g. Cortex-M3). Outputs to `lib/armv7-m`.
 * `armv7em-sf`: ARMv7E-M, soft float ABI (e.g. Cortex-M4/M7).
   Outputs to `lib/armv7e-m`.
 * `armv7em-hf`: ARMv7E-M, hard VFPv4 float ABI (e.g. Cortex-M4F/M7F).
   Outputs to `lib/armv7e-m/fpu`.
 * `armv7em-hf-dp`: ARMv7E-M, hard double-precision VFPv4 float ABI
   (e.g. Cortex-M7F with DP FPU). Outputs to `lib/armv7e-m/fpu-dp`.
 * `armv7em`: all ARMv7E-M targets.

Parallel make (`-j` option) is supported.

To create a distributable package use `make dist` (will output to the `dist`
directory). To clean everything, including distribs, use `make distclean`.

## Known bugs

 * Nested functions are not supported (we need bare-metal implementations for
   trampoline builtins).
 * ARMv7E-M with double-precision FPU should be built for VFPv5, but GCC
   doesn't like it. Worked around by building for VFPv4.

## License

You're allowed to use this project under the terms of the MIT license. See the
`LICENSE` file for the full text.

## Hacking

A note on nested functions: they require trampolines, which means we need to
provide bare-metal implementations for `enable_execute_stack.c` and
`clear_cache.c`. Those are trivial if no OS is present. People using an RTOS
and nested functions will have to write implementations themselves.

I'd like to expand on building this compiler-rt with Clang, since it will also
expose some issues you might encounter if you start getting your hands dirty
and some shortcomings on ARMv6-M.

First off, we're compiling the `release_39` branch of compiler-rt, so it's
pretty logical to use Clang >= 3.9.0. In particular, the build will fail with
older versions because they [lack ARM EHABI exceptions support](https://reviews.llvm.org/D15781)
in `unwind.h`, causing compile errors in the `gcc_personality_v0.c` shipped
with compiler-rt `release_39` (which supports them).

Another problem with older Clang versions is that [`__ELF__` is not defined](https://reviews.llvm.org/D19225)
for `arm-none-eabi` targets, resulting in `compiler-rt/lib/builtins/assembly.h`
generating incorrect assembler directives for the `SYMBOL_IS_FUNC` macro. This
can of course be worked around by passing `-D__ELF__` to the compiler.

Another thing you should be aware of is that [relocation for 16-bit ARM branches](https://github.com/llvm-mirror/llvm/commit/af86df2b0f3f987981877fad1c0854fc915e2474)
was only recently added (it's not even available in 3.9.0). This is relevant
because some handwritten assembly `__aeabi` functions do branches to global
symbols. On ARMv7(E)-M you'll get 32-bit branches with 24-bit relocations. On
ARMv6-M there's no 32-bit branch, so you'll get a 16-bit branches with 11-bit
relocations. Clang didn't implement this relocation (GCC did), so it produced
an `unsupported relocation on symbol` for those branches. Now, I [removed](https://github.com/ReservedField/arm-compiler-rt/commit/9a05715d1429ea48a937bad6cedacd22436cb1f5)
those `__aeabi` functions from ARMv6-M targets in our compiler-rt for a couple
reasons. First, the compiler-rt CMake lists don't compile them for ARMv6-M.
Second, they'd require (at the time of writing) a bleeding-edge version of
Clang just to support ARMv6-M targets. That being said, this is not yet
satisfactory, because even if their absence won't be a problem for Clang (it
doesn't seem to emit calls to them) they're required by the ARM RTABI. The
catch here is that simply compiling them for ARMv6-M (resulting in 16-bit
branches) is *not* a good idea even if Clang can generate the 11-bit
relocation, because the ELF for ARM specification doesn't require linkers to
generate veeners for 16-bit branches (while it does for 32-bit ones). Hitting
an out-of-range branch at link time is never nice. The real solution is an
ARMv6-M forwarding for those functions (using `BL`, as its 32-bit form is
supported, or a litpool).

By the way, it seems that libc isn't actually needed when building with Clang,
because it falls back to freestanding headers. I haven't tested this well
enough, so for now I've kept the libc requirement.
