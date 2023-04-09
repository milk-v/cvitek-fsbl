#
# Copyright (c) 2015-2017, ARM Limited and Contributors. All rights reserved.
#
# SPDX-License-Identifier: BSD-3-Clause
#

EXTRA_DEPS = Makefile ${PLAT_MAKEFILE_FULL}

define print_target
	@printf '\033[1;34;40m  TARGET $@ \033[0m\n'
endef

define print_var
    $(info $(shell printf '\033[1;34;40m  [VAR] $1=%s \033[0m\n' '${$1}'))
endef

# Report an error if the eval make function is not available.
$(eval eval_available := T)
ifneq (${eval_available},T)
    $(error This makefile only works with a Make program that supports $$(eval))
endif

# Some utility macros for manipulating awkward (whitespace) characters.
blank			:=
space			:=${blank} ${blank}

# A user defined function to recursively search for a filename below a directory
#    $1 is the directory root of the recursive search (blank for current directory).
#    $2 is the file name to search for.
define rwildcard
$(strip $(foreach d,$(wildcard ${1}*),$(call rwildcard,${d}/,${2}) $(filter $(subst *,%,%${2}),${d})))
endef

# This table is used in converting lower case to upper case.
uppercase_table:=a,A b,B c,C d,D e,E f,F g,G h,H i,I j,J k,K l,L m,M n,N o,O p,P q,Q r,R s,S t,T u,U v,V w,W x,X y,Y z,Z

# Internal macro used for converting lower case to upper case.
#   $(1) = upper case table
#   $(2) = String to convert
define uppercase_internal
$(if $(1),$$(subst $(firstword $(1)),$(call uppercase_internal,$(wordlist 2,$(words $(1)),$(1)),$(2))),$(2))
endef

# A macro for converting a string to upper case
#   $(1) = String to convert
define uppercase
$(eval uppercase_result:=$(call uppercase_internal,$(uppercase_table),$(1)))$(uppercase_result)
endef

define yn10
$(if $(filter y m 1,${1}),1,0)
endef

define if_enabled
$(if $(filter y m 1,${1}),1)
endef

# Convenience function for adding build definitions
# $(eval $(call add_define,FOO)) will have:
# -DFOO if $(FOO) is empty; -DFOO=$(FOO) otherwise
define add_define
    DEFINES			+=	-D$(1)$(if $(value $(1)),=$(value $(1)),)
endef

define add_define_if_enabled
    $(if $(call if_enabled,$(value ${1})),DEFINES += -D${1})
endef

# Convenience function for adding build definitions
# $(eval $(call add_define_val,FOO,BAR)) will have:
# -DFOO=BAR
define add_define_val
    DEFINES			+=	-D$(1)=$(2)
endef

# Convenience function for verifying option has a boolean value
# $(eval $(call assert_boolean,FOO)) will assert FOO is 0 or 1
define assert_boolean
    $(if $(filter-out 0 1,$($1)),$(error $1 must be boolean))
endef

0-9 := 0 1 2 3 4 5 6 7 8 9

# Function to verify that a given option $(1) contains a numeric value
define assert_numeric
$(if $($(1)),,$(error $(1) must not be empty))
$(eval __numeric := $($(1)))
$(foreach d,$(0-9),$(eval __numeric := $(subst $(d),,$(__numeric))))
$(if $(__numeric),$(error $(1) must be numeric))
endef

# IMG_LINKERFILE defines the linker script corresponding to a BL stage
#   $(1) = BL stage (2, 30, 31, 32, 33)
define IMG_LINKERFILE
    ${BUILD_DIR}/bl$(1).ld
endef

# IMG_MAPFILE defines the output file describing the memory map corresponding
# to a BL stage
#   $(1) = BL stage (2, 30, 31, 32, 33)
define IMG_MAPFILE
    ${BUILD_DIR}/bl$(1).map
endef

# IMG_ELF defines the elf file corresponding to a BL stage
#   $(1) = BL stage (2, 30, 31, 32, 33)
define IMG_ELF
    ${BUILD_DIR}/bl$(1).elf
endef

# IMG_DUMP defines the symbols dump file corresponding to a BL stage
#   $(1) = BL stage (2, 30, 31, 32, 33)
define IMG_DUMP
    ${BUILD_DIR}/bl$(1).dis
endef

define IMG_SYM
    ${BUILD_DIR}/bl$(1).sym
endef

# IMG_BIN defines the default image file corresponding to a BL stage
#   $(1) = BL stage (2, 30, 31, 32, 33)
define IMG_BIN
    ${BUILD_PLAT}/bl$(1).bin
endef

################################################################################
# Auxiliary macros to build TF images from sources
################################################################################

MAKE_DEP = -Wp,-MD,$(DEP) -MT $$@ -MP

# MAKE_C builds a C source file and generates the dependency file
#   $(1) = output directory
#   $(2) = source file (%.c)
#   $(3) = BL stage (2, 2u, 30, 31, 32, 33)
define MAKE_C

$(eval OBJ := $(1)/$(patsubst %.c,%.o,$(notdir $(2))))
$(eval DEP := $(patsubst %.o,%.d,$(OBJ)))
$(eval IMAGE := IMAGE_BL$(call uppercase,$(3)))

$(OBJ): ${EXTRA_DEPS}
$(OBJ): $(2) | bl$(3)_dirs
	@echo "  CC      $$<"
	$$(Q)$$(CC) $$(TF_CFLAGS) $$(CFLAGS) -D$(IMAGE) $(MAKE_DEP) -c $$< -o $$@

-include $(DEP)

endef


# MAKE_S builds an assembly source file and generates the dependency file
#   $(1) = output directory
#   $(2) = assembly file (%.S)
#   $(3) = BL stage (2, 2u, 30, 31, 32, 33)
define MAKE_S

$(eval OBJ := $(1)/$(patsubst %.S,%.o,$(notdir $(2))))
$(eval DEP := $(patsubst %.o,%.d,$(OBJ)))
$(eval IMAGE := IMAGE_BL$(call uppercase,$(3)))

$(OBJ): ${EXTRA_DEPS}
$(OBJ): $(2) | bl$(3)_dirs
	@echo "  AS      $$<"
	$$(Q)$$(AS) $$(ASFLAGS) -D$(IMAGE) $(MAKE_DEP) -c $$< -o $$@

-include $(DEP)

endef


# MAKE_LD generate the linker script using the C preprocessor
#   $(1) = output linker script
#   $(2) = input template
#   $(3) = BL stage (2, 2u, 30, 31, 32, 33)
define MAKE_LD

$(eval DEP := $(1).d)

$(1): $(2) | bl$(3)_dirs
	@echo "  PP      $$<"
	$$(Q)$$(CPP) $$(CPPFLAGS) -P -D__ASSEMBLY__ -D__LINKER__ $(MAKE_DEP) -o $$@ $$<

-include $(DEP)

endef


# MAKE_OBJS builds both C and assembly source files
#   $(1) = output directory
#   $(2) = list of source files (both C and assembly)
#   $(3) = BL stage (2, 30, 31, 32, 33)
define MAKE_OBJS
        $(eval C_OBJS := $(filter %.c,$(2)))
        $(eval REMAIN := $(filter-out %.c,$(2)))
        $(eval $(foreach obj,$(C_OBJS),$(call MAKE_C,$(1),$(obj),$(3))))

        $(eval S_OBJS := $(filter %.S,$(REMAIN)))
        $(eval REMAIN := $(filter-out %.S,$(REMAIN)))
        $(eval $(foreach obj,$(S_OBJS),$(call MAKE_S,$(1),$(obj),$(3))))

        $(and $(REMAIN),$(error Unexpected source files present: $(REMAIN)))
endef


# NOTE: The line continuation '\' is required in the next define otherwise we
# end up with a line-feed characer at the end of the last c filename.
# Also bear this issue in mind if extending the list of supported filetypes.
define SOURCES_TO_OBJS
        $(notdir $(patsubst %.c,%.o,$(filter %.c,$(1)))) \
        $(notdir $(patsubst %.S,%.o,$(filter %.S,$(1))))
endef

# Allow overriding the timestamp, for example for reproducible builds, or to
# synchronize timestamps across multiple projects.
# This must be set to a C string (including quotes where applicable).
BUILD_MESSAGE_TIMESTAMP := "$(shell date -Is)"

# MAKE_BL macro defines the targets and options to build each BL image.
# Arguments:
#   $(1) = BL stage (2, 2u, 30, 31, 32, 33)
#   $(2) = FIP command line option (if empty, image will not be included in the FIP)
define MAKE_BL
        $(eval BUILD_DIR  := ${BUILD_PLAT}/bl$(1))
        $(eval BL_SOURCES := $(BL$(call uppercase,$(1))_SOURCES))
        $(eval SOURCES    := $(BL_SOURCES))
        $(eval OBJS       := $(addprefix $(BUILD_DIR)/,$(call SOURCES_TO_OBJS,$(SOURCES))))
        $(eval LINKERFILE := $(call IMG_LINKERFILE,$(1)))
        $(eval MAPFILE    := $(call IMG_MAPFILE,$(1)))
        $(eval ELF        := $(call IMG_ELF,$(1)))
        $(eval SYM        := $(call IMG_SYM,$(1)))
        $(eval DUMP       := $(call IMG_DUMP,$(1)))
        $(eval BIN        := $(call IMG_BIN,$(1)))
        $(eval BL_LINKERFILE := $(BL$(call uppercase,$(1))_LINKERFILE))
        # We use sort only to get a list of unique object directory names.
        # ordering is not relevant but sort removes duplicates.
        $(eval TEMP_OBJ_DIRS := $(sort $(dir ${OBJS} ${LINKERFILE})))
        # The $(dir ) function leaves a trailing / on the directory names
        # Rip off the / to match directory names with make rule targets.
        $(eval OBJ_DIRS   := $(patsubst %/,%,$(TEMP_OBJ_DIRS)))

# Create generators for object directory structure

$(eval $(call MAKE_PREREQ_DIR,${BUILD_DIR},))

$(eval $(foreach objd,${OBJ_DIRS},$(call MAKE_PREREQ_DIR,${objd},${BUILD_DIR})))

.PHONY : bl${1}_dirs

# We use order-only prerequisites to ensure that directories are created,
# but do not cause re-builds every time a file is written.
bl${1}_dirs: | ${OBJ_DIRS}

$(eval $(call MAKE_OBJS,$(BUILD_DIR),$(SOURCES),$(1)))
$(eval $(call MAKE_LD,$(LINKERFILE),$(BL_LINKERFILE),$(1)))

$(ELF): $(OBJS) $(LINKERFILE) | bl$(1)_dirs
	@echo "  LD      $$@"
	@echo 'const char build_message[] = $(BUILD_MESSAGE_TIMESTAMP); \
	       const char version_string[] = "${VERSION_STRING}";' | \
		$$(CC) $$(TF_CFLAGS) $$(CFLAGS) -xc -c - -o $(BUILD_DIR)/build_message.o
	$$(Q)$$(LD) -o $$@ $$(TF_LDFLAGS) $$(LDFLAGS) -Map=$(MAPFILE) \
		--script $(LINKERFILE) $(BUILD_DIR)/build_message.o ${BL2_RLS_OBJS} $(OBJS) $(LDLIBS)

$(SYM): $(ELF)
	@echo "  SYM     $$@"
	$$(Q)$$(READELF) -s $$< | sort -b -r -g -k 3 > $$@

$(DUMP): $(ELF)
	@echo "  OD      $$@"
	$${Q}$${OD} -dx $$< > $$@

$(BIN): $(ELF)
	@echo "  BIN     $$@"
	$$(Q)$$(OC) -O binary $$< $$@
	@${ECHO_BLANK_LINE}
	@echo "Built $$@ successfully"
	@${ECHO_BLANK_LINE}

.PHONY: bl$(1)
bl$(1): $(BIN) $(SYM) $(DUMP)
	$$(print_target)

bl-build: bl$(1)

endef

