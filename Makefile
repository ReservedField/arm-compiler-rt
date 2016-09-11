# Require make >= 3.81 (note that MAKE_VERSION is empty < 3.69).
ifneq ($(and $(MAKE_VERSION),$(firstword $(sort $(MAKE_VERSION) 3.81))),3.81)
$(error Make >= 3.81 required)
endif

# Detect compiler. CC_IS_CLANG is set to 1 for Clang, empty for GCC.
# Note that this doesn't error out straight away: it'll bail out when building
# the first object. This avoids useless errors for targets that don't build
# anything (e.g. clean, or dist when everything's already built).
CC_VERSION := $(shell $(CC) -v 2>&1)
CC_IS_CLANG := $(if $(findstring clang version,$(CC_VERSION)),1)
ifndef CC_IS_CLANG
	ifeq ($(findstring gcc version,$(CC_VERSION)),)
		CC_CHECK_ERROR := Unsupported compiler
	else ifeq ($(findstring Target: arm-none-eabi,$(CC_VERSION)),)
		CC_CHECK_ERROR := Your GCC doesn't target arm-none-eabi
	endif
endif

# Disable all builtin rules.
MAKEFLAGS += --no-builtin-rules
.SUFFIXES:

# Enable secondary expansion.
.SECONDEXPANSION:

# Output name.
TARGET := libclang_rt.builtins

# Distribution name.
DSTNAME := arm-compiler-rt

# Directories.
CRTDIR := compiler-rt
SRCDIR := $(CRTDIR)/lib/builtins
LSTDIR := list
OBJDIR := obj
LIBDIR := lib
DSTDIR := dist

# Toolchain binaries.
AR := arm-none-eabi-ar

# Include directories.
INCDIRS := include

# Common compiler flags.
# Pretty much one function per object, no need for -fdata/function-sections.
# Clang generates some harmless warnings for GCC-only attributes, silence them.
# Clang's stdint.h uses cascading redefinitions, but doesn't undef before
# redefining. Silence those macro-redefined warnings, too.
CFLAGS := \
	-std=gnu99 -fPIC -fno-builtin -fvisibility=hidden -fomit-frame-pointer \
	-ffreestanding \
	$(if $(CC_IS_CLANG),-Wno-unknown-attributes -Wno-macro-redefined) \
	$(foreach d,$(INCDIRS),-I$d)

# Gets the architectural compiler flags for a target.
# Argument 1: architecture name, in GCC's -march format. Suffix with :thumb to
#             only generate Thumb code.
# Argument 2: FPU. Optional, defaults to no FPU.
# Argument 3: float ABI (soft, softfp, hard). Optional, defaults to soft if no
#             FPU is specified or hard if it is.
target-cflags = \
	$(call __target-cflags-arch,$(subst :, ,$1)) \
	-mfloat-abi=$(or $3,$(if $2,hard,soft)) \
	$(if $(CC_IS_CLANG),-mfpu=$(or $2,none),$(if $2,-mfpu=$2))
__target-cflags-arch = $(call __target-cflags-arch-gen,$(word 1,$1),$(word 2,$1))
__target-cflags-arch-gen = \
	$(if $(CC_IS_CLANG),-target $(subst -,,$1)-none-eabi,-march=$1) \
	$(if $(filter thumb,$2),-mthumb)

# Reads the content of the specified lists in the list/prefix-name path.
# Argument 1: list prefix.
# Argument 2: list names.
read-list = $(and $1,$2,$(shell cat $(addprefix $(LSTDIR)/$1-,$2) | sed '/^\#/d'))
# Gets the sources from the specified source lists, excluding those in the
# specified blacklists.
# Argument 1: source list names.
# Argument 2: blacklist names.
get-srcs = $(filter-out $(call read-list,blacklist,$2),$(call read-list,srclist,$1))
# Gets the objects to build for the specified source lists, excluding those
# in the specified blacklists.
# Argument 1: source list names.
# Argument 2: blacklist names.
get-objs = $(addsuffix .o,$(basename $(call get-srcs,$1,$2)))
# Gets all the directories needed to create the specified relative paths
# from the specified base path. The output has no duplicates and no trailing
# slashes.
# Argument 1: base path.
# Argument 2: relative paths.
get-dirs = $(patsubst %/.,%,$(patsubst %/,%,$(addprefix $1/,$(sort $(dir $2)))))
# Prints an information message about what a recipe is doing.
# Argument 1: CPU target.
# Argument 2: command display name.
info-cmd = $(info [$1] $2 $@)

# Base object path for the specified CPU target.
# Argument 1: CPU target name.
objbase-tmpl = $(OBJDIR)/$1
# Base library path for the specified library subdirectory.
# Argument 1: subdirectory.
libbase-tmpl = $(LIBDIR)/$1
# Object pattern for the specified CPU target.
# Argument 1: CPU target name.
objpat-tmpl = $(call objbase-tmpl,$1)/%.o
# Object output paths for the specified CPU target.
# Argument 1: CPU target name.
# Argument 2: relative object paths.
objs-tmpl = $(addprefix $(call objbase-tmpl,$1)/,$2)
# Library output file for the specified library subdirectory.
# Argument 1: subdirectory.
lib-tmpl = $(call libbase-tmpl,$1)/$(TARGET).a
# All directories required for the build.
# Argument 1: CPU target name.
# Argument 2: library subdirectory.
# Argument 3: relative object paths.
build-dirs-tmpl = $(call get-dirs,$(call objbase-tmpl,$1),$3) $(call libbase-tmpl,$2)

# To be eval'ed. Requires secondary expansion. Expands to:
#  - compilation rules to build the objects;
#  - library rule to build the library;
#  - directory rules to create the needed paths;
#  - build and clean phony rules;
#  - build prerequisite for the 'all' target.
# Argument 1: CPU target name.
# Argument 2: library subdirectory.
# Argument 3: CPU-specific compiler flags.
# Argument 4: relative object path(s).
define build-rules
ifdef CC_CHECK_ERROR
$(call objpat-tmpl,$1):
	$$(error $(CC_CHECK_ERROR))
else
$(call objpat-tmpl,$1): $(SRCDIR)/%.c | $$$$(@D)
	$$(call info-cmd,$1,CC)
	@$(CC) $3 $(CFLAGS) -c $$< -o $$@
$(call objpat-tmpl,$1): $(SRCDIR)/%.S | $$$$(@D)
	$$(call info-cmd,$1,AS)
	@$(CC) $3 $(CFLAGS) -c $$< -o $$@
endif
$(call lib-tmpl,$2): $(call objs-tmpl,$1,$4) | $$$$(@D)
	$$(call info-cmd,$1,AR)
	@$(AR) -rc $$@ $$^
$(call build-dirs-tmpl,$1,$2,$4):
	@mkdir -p $$@
$1: $(call lib-tmpl,$2)
clean-$1:
	rm -rf $(call objbase-tmpl,$1) $(call lib-tmpl,$2)
all: $1
.PHONY: $1 clean-$1
endef

# To be eval'ed. Expands to build and clean rules for a target group.
# Argument 1: target group name.
# Argument 2: target names to group.
# Argument 3: common library subdirectory for clean (optional).
define group-rules
$1: $2
clean-$1: $(addprefix clean-,$2)
	$(if $3,rm -rf $(call libbase-tmpl,$3))
.PHONY: $1 clean-$1
endef

# Adds a new CPU target.
# Argument 1: CPU target name.
# Argument 2: library subdirectory.
# Argument 3: CPU-specific compiler flags.
# Argument 4: source list names.
# Argument 5: blacklist names.
add-target = $(eval $(call build-rules,$1,$2,$3,$(call get-objs,$4,$5)))
# Adds a new target group.
# Argument 1: target group name.
# Argument 2: target names to group.
# Argument 3: common library subdirectory for clean (optional).
add-group = $(eval $(call group-rules,$1,$2,$3))

# all: default, build everything (prereqs set by add-target).
.DEFAULT_GOAL := all

# clean: clean everything, excluding distribution.
clean:
	rm -rf $(OBJDIR) $(LIBDIR)

# dist: build everything and package for distribution.
dist: all
	mkdir -p $(DSTDIR)
	mkdir $(TMPDIR)/$(DSTVER)
	$(call dist-symlink,README.dist,README)
	$(call dist-symlink,$(CRTDIR)/CREDITS.TXT)
	$(call dist-symlink,$(CRTDIR)/LICENSE.TXT)
	$(call dist-symlink,$(LIBDIR))
	rm -rf $(DSTDIR)/$(DSTVER).tar.gz
	tar -C $(TMPDIR) -zchf $(DSTDIR)/$(DSTVER).tar.gz $(DSTVER)
dist: DSTVER := $(DSTNAME)-$(or $(shell git describe --abbrev --dirty --always --tags 2> /dev/null),unknown)
dist: TMPDIR := $(shell mktemp -d)
dist-symlink = ln -s $(abspath $1) $(TMPDIR)/$(DSTVER)/$(or $2,$(notdir $1))

# distclean: clean everything, including distribution.
distclean: clean
	rm -rf $(DSTDIR)

.PHONY: all clean dist distclean

# TODO: we're compiling a little too much stuff. This isn't a problem since
# unused objects won't get linked into the final binary, but it makes the build
# noisier and slower. The macho_embedded lists are a good starting point to
# tweak our owns, but we have to make sure they're not too Xcode-specific.

# armv6m: ARMv6-M.
CPUFLAGS_ARMV6M := $(call target-cflags,armv6-m:thumb)
$(call add-target,armv6m,armv6-m,$(CPUFLAGS_ARMV6M),generic,thumb)

# armv7m: ARMv7-M.
CPUFLAGS_ARMV7M := $(call target-cflags,armv7-m:thumb) $(if $(CC_IS_CLANG),,-mfix-cortex-m3-ldrd)
$(call add-target,armv7m,armv7-m,$(CPUFLAGS_ARMV7M),generic arm,thumb)

# armv7em-sf: ARMv7E-M, soft float ABI.
CPUFLAGS_ARMV7EM_SF := $(call target-cflags,armv7e-m:thumb)
$(call add-target,armv7em-sf,armv7e-m,$(CPUFLAGS_ARMV7EM_SF),generic arm,thumb)

# armv7em-hf: ARMv7E-M, hard float ABI, single-precision VFPv4.
CPUFLAGS_ARMV7EM_HF := $(call target-cflags,armv7e-m:thumb,fpv4-sp-d16)
$(call add-target,armv7em-hf,armv7e-m/fpu,$(CPUFLAGS_ARMV7EM_HF),generic arm arm-fpu,thumb)

# armv7em-hf-dp: ARMv7E-M, hard float ABI, double-precision VFPv5.
CPUFLAGS_ARMV7EM_HF_DP := $(call target-cflags,armv7e-m:thumb,fpv5-d16)
$(call add-target,armv7em-hf-dp,armv7e-m/fpu-dp,$(CPUFLAGS_ARMV7EM_HF_DP),generic arm arm-fpu arm-fpu-dp,thumb)

# armv7em: group of all ARMv7E-M targets.
$(call add-group,armv7em,armv7em-sf armv7em-hf armv7em-hf-dp,armv7e-m)
