llvm_ver = "6.0.0"

# include("download.jl")

using Libdl

BASE_JULIA_BIN = get(ENV, "BASE_JULIA_BIN", Sys.BINDIR)
BASE_JULIA_SRC = get(ENV, "BASE_JULIA_SRC", joinpath(@__DIR__, "juliasrc", "julia"))

#write a simple include file with that path
println("writing path.jl file")
s = """
const BASE_JULIA_BIN=$(sprint(show, BASE_JULIA_BIN))
export BASE_JULIA_BIN

const BASE_JULIA_SRC=$(sprint(show, BASE_JULIA_SRC))
export BASE_JULIA_SRC
"""
f = open(joinpath(dirname(@__FILE__),"path.jl"), "w")
write(f, s)
close(f)

println("Tuning for julia installation at $BASE_JULIA_BIN with sources possibly at $BASE_JULIA_SRC")

# Try to autodetect C++ ABI in use
# llvm_path = (Sys.isapple() && VersionNumber(Base.libllvm_version) >= v"3.8") ? "libLLVM" : "libLLVM-$(Base.libllvm_version)"
#
# llvm_lib_path = Libdl.dlpath(llvm_path)
# old_cxx_abi = findfirst("_ZN4llvm3sys16getProcessTripleEv", String(open(read, llvm_lib_path))) !== nothing
# old_cxx_abi && (ENV["OLD_CXX_ABI"] = "1")

# llvm_config_path = joinpath(BASE_JULIA_BIN,"..","tools","llvm-config")

@info "Building julia binary build"
ENV["LLVM_VER"] = llvm_ver
ENV["JULIA_BINARY_BUILD"] = "1"
ENV["PATH"] = string(Sys.BINDIR,":",ENV["PATH"])
ENV["LLVM_SRC"] = joinpath(@__DIR__, "llvmsrc", "llvm-$(llvm_ver).src")
ENV["LLVM_BUILD"] = joinpath(@__DIR__, "usr")
ENV["CLANG_SRC"] = joinpath(@__DIR__, "clangsrc", "cfe-$(llvm_ver).src")

make = Sys.isbsd() && !Sys.isapple() ? `gmake` : `make`
run(`$make -j$(Sys.CPU_THREADS) -f BuildBootstrap.Makefile BASE_JULIA_BIN=$BASE_JULIA_BIN BASE_JULIA_SRC=$BASE_JULIA_SRC`)
