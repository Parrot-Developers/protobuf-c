# Inspired by atom.mk from "protobuf"

LOCAL_PATH := $(call my-dir)

###############################################################################
include $(CLEAR_VARS)

LOCAL_HOST_MODULE := protobuf-c
LOCAL_DESCRIPTION := Protocol Buffers implementation in C
LOCAL_CATEGORY_PATH := libs

LOCAL_PUBLIC_LIBRARIES := host.protobuf

LOCAL_AUTOTOOLS_VERSION := 1.3.2
LOCAL_AUTOTOOLS_ARCHIVE := $(LOCAL_HOST_MODULE)-$(LOCAL_AUTOTOOLS_VERSION).tar.gz
LOCAL_AUTOTOOLS_SUBDIR := $(LOCAL_HOST_MODULE)-$(LOCAL_AUTOTOOLS_VERSION)
LOCAL_ARCHIVE_PATCHES := message_field_number.patch commit-3d2ed0d.patch

include $(BUILD_AUTOTOOLS)

###############################################################################
include $(CLEAR_VARS)

LOCAL_MODULE := protobuf-c
LOCAL_DESCRIPTION := Protocol Buffers implementation in C
LOCAL_CATEGORY_PATH := libs

LOCAL_DEPENDS_HOST_MODULES := host.protobuf-c

LOCAL_AUTOTOOLS_VERSION := 1.3.2
LOCAL_AUTOTOOLS_ARCHIVE := $(LOCAL_MODULE)-$(LOCAL_AUTOTOOLS_VERSION).tar.gz
LOCAL_AUTOTOOLS_SUBDIR := $(LOCAL_MODULE)-$(LOCAL_AUTOTOOLS_VERSION)
LOCAL_ARCHIVE_PATCHES := commit-3d2ed0d.patch

LOCAL_AUTOTOOLS_CONFIGURE_ARGS := --disable-protoc

LOCAL_EXPORT_LDLIBS := -lprotobuf-c

include $(BUILD_AUTOTOOLS)

###############################################################################
include $(CLEAR_VARS)

LOCAL_MODULE := libprotobuf-c-base

LOCAL_DESCRIPTION := Google Protocol Buffers basics in C
LOCAL_PUBLIC_LIBRARIES := protobuf-base protobuf-c
LOCAL_EXPORT_C_INCLUDES := $(call local-get-build-dir)/gen

# Can not use find here, files may not be present yet in staging directory
google_proto_path := $(TARGET_OUT_STAGING)/usr/share/protobuf/google/protobuf
google_proto_files := $(addprefix $(google_proto_path)/,any.proto empty.proto wrappers.proto descriptor.proto struct.proto)
$(google_proto_files): $(call module-get-stamp-file,protobuf-base,done)

$(foreach __f,$(google_proto_files), \
	$(eval LOCAL_CUSTOM_MACROS += protoc-c-macro:c,gen/google/protobuf,$(__f),$(google_proto_path)) \
)

include $(BUILD_LIBRARY)

###############################################################################
###############################################################################
## Custom macro that can be used in LOCAL_CUSTOM_MACROS of a module to
## create automatically rules to generate files from .proto.
## Note : in the context of the macro, LOCAL_XXX variables refer to the module
## that use the macro, not this module defining the macro.
## As the content of the macro is 'eval' after, most of variable ref shall be
## escaped (hence the $$). Only $1, $2... variables can be used directly.
## Note : no 'global' variable shall be used except the ones defined by
## alchemy (TARGET_XXX and HOST_XXX variables). Otherwise the macro will no
## work when integrated in a SDK (using local-register-custom-macro).
## Note : rules shoud NOT use any variables defined in the context of the
## macro (for the same reason PRIVATE_XXX variables shall be used in place of
## LOCAL_XXX variables).
## Note : if you need a script or a binary, please install it in host staging
## directory and execute it from there. This way it will also work in the
## context of a SDK.
###############################################################################

# $1: language (c).
# $2: output directory (Relative to build directory unless an absolute path is
#     given (ex LOCAL_PATH).
# $3: input .proto file
# $4: optional value for --proto_path, by default it is the directory of the
#     .proto file
define protoc-c-macro
# Setup some internal variables
protoc_c_in_file := $3
protoc_c_proto_path := $(call remove-trailing-slash,$(or $4,$(dir $3)))
# reproduce what -I/--proto_path does, so that we can have some sort of namespacing
protoc_c_out_subdir := $$(call remove-trailing-slash,\
				$$(patsubst $$(protoc_c_proto_path)/%,%,$(dir $3)))

protoc_c_module_build_dir := $(call local-get-build-dir)
protoc_c_out := $$(call remove-trailing-slash,$$(if $$(call is-path-absolute,$2),$2,$$(protoc_c_module_build_dir)/$2))
protoc_c_out_dir := $$(call remove-trailing-slash,$$(protoc_c_out)/$$(protoc_c_out_subdir))
protoc_c_dep_file := $$(protoc_c_module_build_dir)/$$(subst $(colon),_,$$(subst /,_,$$(call path-from-top,$$(protoc_c_in_file)))).$1.d
protoc_c_done_file := $$(protoc_c_module_build_dir)/$$(subst $(colon),_,$$(subst /,_,$$(call path-from-top,$$(protoc_c_in_file)))).$1.done

# Directory where to copy the input .proto file
protoc_c_out_cp_proto := $$(if $$(protoc_c_out_subdir), \
	$(TARGET_OUT_STAGING)/usr/share/protobuf/$$(protoc_c_out_subdir)/$(notdir $3), \
	$(TARGET_OUT_STAGING)/usr/share/protobuf/$(notdir $3) \
)

# The C generation case is handled here (endl is to force new line even if macro
# requires single line)
$(if $(call streq,$1,c), \
	protoc_c_src_files := $$(addprefix $$(protoc_c_out_dir)/,$$(patsubst %.proto,%.pb-c.c,$(notdir $3))) $(endl) \
	protoc_c_inc_files := $$(addprefix $$(protoc_c_out_dir)/,$$(patsubst %.proto,%.pb-c.h,$(notdir $3))) $(endl) \
	protoc_c_gen_files := $$(protoc_c_src_files) $$(protoc_c_inc_files) \
)

# Create a dependency between generated files and .done file with an empty
# command to make sure regeneration is correctly triggered to files
# depending on them
$$(protoc_c_gen_files): $$(protoc_c_done_file)
	$(empty)

# Actual generation rule
$$(protoc_c_done_file): PRIVATE_OUT_DIR := $$(protoc_c_out)
$$(protoc_c_done_file): PRIVATE_PROTO_PATH := $$(protoc_c_proto_path)
$$(protoc_c_done_file): PRIVATE_PROTO_SRC_FILES := $$(protoc_c_src_files)
$$(protoc_c_done_file): PRIVATE_PROTO_OUT_CP_PROTO := $$(protoc_c_out_cp_proto)
$$(protoc_c_done_file): PRIVATE_PROTO_DEP_FILE := $$(protoc_c_dep_file)
$$(protoc_c_done_file): PRIVATE_PROTOC_GEN_C_EXE := $(HOST_OUT_STAGING)/usr/bin/protoc-gen-c$(HOST_EXE_SUFFIX)
$$(protoc_c_done_file): PRIVATE_PROTOC_EXE := $(HOST_OUT_STAGING)/usr/bin/protoc$(HOST_EXE_SUFFIX)
$$(protoc_c_done_file): $$(protoc_c_in_file)
	$$(call print-banner1,"Generating",$$(call path-from-top,$$(PRIVATE_PROTO_SRC_FILES)),$$(call path-from-top,$3))
	@mkdir -p $$(PRIVATE_OUT_DIR)
	$(Q) $$(PRIVATE_PROTOC_EXE) --plugin=protoc-gen-c=$$(PRIVATE_PROTOC_GEN_C_EXE) \
		--$1_out=$$(PRIVATE_OUT_DIR) \
		--proto_path=$$(PRIVATE_PROTO_PATH) \
		--proto_path=$(TARGET_OUT_STAGING)/usr/share/protobuf \
		$(foreach __dir,$(TARGET_SDK_DIRS), \
			$(if $(wildcard $(__dir)/usr/share/protobuf), \
				--proto_path=$(__dir)/usr/share/protobuf \
			) \
		) \
		--dependency_out=$$(PRIVATE_PROTO_DEP_FILE) \
		$3

#	Add a license file for generated code
	@echo "Generated code." > $$(PRIVATE_OUT_DIR)/.MODULE_LICENSE_BSD

#	Input file is in the form
#		a.cc a.h: c.proto d.proto ...
#	With potentially lines split with continuation lines '\'
#	We need to get the list of files after the ':' to generated a line of
#	this form for each dependency
#		c.proto:
#		d.proto:
#		....
#
#	Sed will see a single '$' for each '$$$$'.
#
#	The hard part is to be compatible with macos...
#
#	1: remove continuation lines and concatenates lines
#	2: remove everithinh before the ':'
#	3: split files one per line (the folowing sed fails on macos: 's/ */"\n"/g')
#	4: strip spaces on lines
#	5: remove empty lines
#	6: add ':' at the end of lines
	$(Q) sed -e ':x' -e '/\\$$$$/{N;bx' -e '}' -e 's/\\\n//g' \
		-e 's/.*://' \
		$$(PRIVATE_PROTO_DEP_FILE) \
		| fmt -1 \
		| sed -e 's/^ *//' \
		-e '/^$$$$/d' \
		-e 's/$$$$/:/' \
		> $$(PRIVATE_PROTO_DEP_FILE).tmp

#	Add contents at the end of original file (with a new line before)
	@( \
		echo ""; \
		cat $$(PRIVATE_PROTO_DEP_FILE).tmp \
	) >> $$(PRIVATE_PROTO_DEP_FILE)
	@rm $$(PRIVATE_PROTO_DEP_FILE).tmp

#	The copy of .proto file is done via a temp copy and move to ensure atomicity
#	of copy in case of parallel copy of the same file
#	Use flock when possible to avoid race conditions in some mv implementations
	@if [ $$(PRIVATE_MODULE) != libprotobuf-c-base ]; then \
		mkdir -p $$(dir $$(PRIVATE_PROTO_OUT_CP_PROTO)); \
	fi
ifeq ("$(HOST_OS)","darwin")
	@if [ $$(PRIVATE_MODULE) != libprotobuf-c-base ]; then \
		tmpfile=`mktemp $$(PRIVATE_BUILD_DIR)/tmp.XXXXXXXX`; \
		cp -af $3 $$$${tmpfile}; \
		mv -f $$$${tmpfile} $$(PRIVATE_PROTO_OUT_CP_PROTO); \
	fi
else
	@if [ $$(PRIVATE_MODULE) != libprotobuf-c-base ]; then \
		flock --wait 60 $$(dir $$(PRIVATE_PROTO_OUT_CP_PROTO)) \
			cp -af $3 $$(PRIVATE_PROTO_OUT_CP_PROTO); \
	fi
endif

	@mkdir -p $$(dir $$@)
	@touch $$@

-include $$(protoc_c_dep_file)

# Update either LOCAL_SRC_FILES or LOCAL_GENERATED_SRC_FILES
$(if $(call is-path-absolute,$2), \
	LOCAL_SRC_FILES += $$(patsubst $$(LOCAL_PATH)/%,%,$$(protoc_c_src_files)) \
	, \
	LOCAL_GENERATED_SRC_FILES += $$(patsubst $$(protoc_c_module_build_dir)/%,%,$$(protoc_c_src_files)) \
)

# Update alchemy variables for the module
LOCAL_CLEAN_FILES += $$(protoc_c_done_file) $$(protoc_c_out_cp_proto) $$(protoc_dep_file)
LOCAL_EXPORT_PREREQUISITES += $$(protoc_c_gen_files) $$(protoc_c_done_file)
LOCAL_DEPENDS_HOST_MODULES += host.protobuf-c

endef

# Register the macro in alchemy so it will be integrated in generated sdk
$(call local-register-custom-macro,protoc-c-macro)
