JULIA_SRC := $(subst \,/,$(BASE_JULIA_SRC))
JULIA_BIN := $(subst \,/,$(BASE_JULIA_BIN))

include Make.inc

LLVM_VER_MAJ:=$(word 1, $(subst ., ,$(LLVM_VER)))
LLVM_VER_MIN:=$(word 2, $(subst ., ,$(LLVM_VER)))
# define a "short" LLVM version for easy comparisons
ifeq ($(LLVM_VER),svn)
LLVM_VER_SHORT:=svn
else
LLVM_VER_SHORT:=$(LLVM_VER_MAJ).$(LLVM_VER_MIN)
endif
LLVM_VER_PATCH:=$(word 3, $(subst ., ,$(LLVM_VER)))
ifeq ($(LLVM_VER_PATCH),)
LLVM_VER_PATCH := 0
endif

ifeq ($(LLVM_VER_SHORT),$(filter $(LLVM_VER_SHORT),3.3 3.4 3.5 3.6 3.7 3.8))
LLVM_USE_CMAKE := 0
else
LLVM_USE_CMAKE := 1
endif

all: usr/lib/libcxxffi.$(SHLIB_EXT) build/clang_constants.jl

ifeq ($(OLD_CXX_ABI),1)
CXX_ABI_SETTING=-D_GLIBCXX_USE_CXX11_ABI=0
else
CXX_ABI_SETTING=-D_GLIBCXX_USE_CXX11_ABI=1
endif

CXXJL_CPPFLAGS = -I$(JULIA_SRC)/src/support -I$(BASE_JULIA_BIN)/../include

ifeq ($(JULIA_BINARY_BUILD),1)
LIBDIR := $(BASE_JULIA_BIN)/../lib/julia
else
LIBDIR := $(BASE_JULIA_BIN)/../lib
endif

CLANG_LIBS = clangFrontendTool clangBasic clangLex clangDriver clangFrontend clangParse \
        clangAST clangASTMatchers clangSema clangAnalysis clangEdit \
        clangRewriteFrontend clangRewrite clangSerialization clangStaticAnalyzerCheckers \
        clangStaticAnalyzerCore clangStaticAnalyzerFrontend clangTooling clangToolingCore \
        clangCodeGen clangARCMigrate clangFormat

# If clang is not built by base julia, build it ourselves
src:
	mkdir $@

LLVM_CONFIG = $(LLVM_BUILD)/tools/llvm-config
CLANG_CMAKE_DEP = $(LLVM_BUILD)/tools/llvm-config
CLANG_CMAKE_OPTS += -DLLVM_TABLEGEN_EXE=$(LLVM_BUILD)/tools/llvm-tblgen

build/clang-$(LLVM_VER)/Makefile: $(CLANG_SRC) $(CLANG_CMAKE_DEP)
	mkdir -p $(dir $@)
	cd $(dir $@) && \
		cmake -G "Unix Makefiles" \
			-DLLVM_BUILD_LLVM_DYLIB=ON -DCMAKE_BUILD_TYPE=Release \
			-DLLVM_LINK_LLVM_DYLIB=ON -DLLVM_ENABLE_THREADS=OFF \
                        -DCMAKE_CXX_COMPILER_ARG1="$(CXX_ABI_SETTING)" \
			-DLLVM_CONFIG=$(LLVM_CONFIG) $(CLANG_CMAKE_OPTS) $(CLANG_SRC)

build/clang-$(LLVM_VER)/lib/libclangCodeGen.a: build/clang-$(LLVM_VER)/Makefile
	cd build/clang-$(LLVM_VER) && $(MAKE)
LIB_DEPENDENCY += build/clang-$(LLVM_VER)/lib/libclangCodeGen.a
JULIA_LDFLAGS += -Lbuild/clang-$(LLVM_VER)/lib
CXXJL_CPPFLAGS += -I$(CLANG_SRC)/lib -Ibuild/clang-$(LLVM_VER)/include \
	-I-I$(CLANG_SRC)/include


LLVM_HEADER_DIRS = $(LLVM_SRC)/include $(LLVM_BUILD)/include
JULIA_LDFLAGS = -L$(BASE_JULIA_BIN)/../lib -L$(BASE_JULIA_BIN)/../lib/julia


CXX_LLVM_VER := $(LLVM_VER)
# ifeq ($(CXX_LLVM_VER),svn)
# CXX_LLVM_VER := $(shell $(BASE_JULIA_BIN)/../tools/llvm-config --version)
# endif

ifneq ($(LLVM_HEADER_DIRS),)
CXXJL_CPPFLAGS += $(addprefix -I,$(LLVM_HEADER_DIRS))
endif

FLAGS = -std=c++11 $(CPPFLAGS) $(CFLAGS) $(CXXJL_CPPFLAGS)

ifneq ($(USEMSVC), 1)
CPP_STDOUT := $(CPP) -P
else
CPP_STDOUT := $(CPP) -E
endif

ifeq ($(LLVM_USE_CMAKE),1)
LLVM_LIB_NAME := LLVM
else ifeq ($(LLVM_VER),svn)
LLVM_LIB_NAME := LLVM
else
LLVM_LIB_NAME := LLVM-$(CXX_LLVM_VER)
endif
LDFLAGS += -l$(LLVM_LIB_NAME)

LIB_DEPENDENCY += $(LIBDIR)/lib$(LLVM_LIB_NAME).$(SHLIB_EXT)


# $(info $$LLVM_USE_CMAKE is [${LLVM_USE_CMAKE}])

usr/lib:
	@mkdir -p $(CURDIR)/usr/lib/

build:
	@mkdir -p $(CURDIR)/build

LLVM_EXTRA_CPPFLAGS =
ifneq ($(LLVM_ASSERTIONS),1)
LLVM_EXTRA_CPPFLAGS += -DLLVM_NDEBUG
endif

build/bootstrap.o: ../src/bootstrap.cpp BuildBootstrap.Makefile $(LIB_DEPENDENCY) | build
	@$(call PRINT_CC, $(CXX) $(CXX_ABI_SETTING) -fno-rtti -DLIBRARY_EXPORTS -fPIC -O0 -g $(FLAGS) $(LLVM_EXTRA_CPPFLAGS) -c ../src/bootstrap.cpp -o $@)


LINKED_LIBS = $(addprefix -l,$(CLANG_LIBS))
ifeq ($(BUILD_LLDB),1)
LINKED_LIBS += $(LLDB_LIBS)
endif

ifneq (,$(wildcard $(BASE_JULIA_BIN)/../lib/libjulia.$(SHLIB_EXT)))
usr/lib/libcxxffi.$(SHLIB_EXT): build/bootstrap.o $(LIB_DEPENDENCY) | usr/lib
	@$(call PRINT_LINK, $(CXX) -shared -fPIC $(JULIA_LDFLAGS) -Lbuild/clang-6.0.0/lib -ljulia $(LDFLAGS) -o $@ $(WHOLE_ARCHIVE) $(LINKED_LIBS) $(NO_WHOLE_ARCHIVE) $< )
else
usr/lib/libcxxffi.$(SHLIB_EXT):
	@echo "Not building release library because corresponding julia RELEASE library does not exist."
	@echo "To build, simply run the build again once the library at"
	@echo $(build_libdir)/libjulia.$(SHLIB_EXT)
	@echo "has been built."
endif

build/clang_constants.jl: ../src/cenumvals.jl.h usr/lib/libcxxffi.$(SHLIB_EXT)
	@$(call PRINT_PERL, $(CPP_STDOUT) $(CXXJL_CPPFLAGS) -DJULIA ../src/cenumvals.jl.h > $@)
