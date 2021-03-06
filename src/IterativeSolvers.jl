__precompile__(true)
"""
Main module for `IterativeSolvers.jl` -- a Julia package for solving linear systems,
eigensystems, and singular value problems.
"""
module IterativeSolvers

using SugarBLAS

include("common.jl")
include("orthogonalize.jl")
include("history.jl")

#Specialized factorizations
include("factorization.jl")
include("hessenberg.jl")

#Linear solvers
include("stationary.jl")
include("stationary_sparse.jl")
include("cg.jl")
include("minres.jl")
include("bicgstabl.jl")
include("gmres.jl")
include("chebyshev.jl")
include("idrs.jl")

#Eigensolvers
include("simple.jl")

#SVD solvers
include("svdl.jl")

#Least-squares
include("lsqr.jl")
include("lsmr.jl")

#Randomized algorithms
include("rlinalg.jl")
include("rsvd.jl")
include("rsvd_fnkz.jl")

end
