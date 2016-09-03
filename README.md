[![Build Status](https://travis-ci.org/ReservedField/arm-compiler-rt.svg?branch=master)](https://travis-ci.org/ReservedField/arm-compiler-rt)

This is an experiment to make building `compiler-rt` for bare metal ARM targets
easy. It bypasses the CMake build system and is much quicker to setup.

# Dependencies

 * `arm-none-eabi` binutils
 * `arm-none-eabi` GCC
 * `arm-none-eabi` libc (e.g. newlib)
 * GNU make >= 3.81

# Cloning

`compiler-rt` is provided as a submodule:
```
git clone https://github.com/ReservedField/arm-compiler-rt
cd arm-compiler-rt
git submodule init
git submodule update
```

# Building

To build everything, you can just issue `make`. To clean your whole build, use
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

# License

You're allowed to use this project under the terms of the MIT license. See the
`LICENSE` file for the full text.
