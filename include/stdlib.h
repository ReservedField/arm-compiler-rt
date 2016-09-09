/**
 * Custom libc-agnostic stdlib.h.
 */

#ifndef ARM_COMPILER_RT_STDLIB_H
#define ARM_COMPILER_RT_STDLIB_H

/* Needed by: int_util.c */
extern void abort(void) __attribute__((noreturn));

#endif
