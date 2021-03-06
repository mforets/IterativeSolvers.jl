export minres_iterable, minres, minres!

import Base.LinAlg: BLAS.axpy!, givensAlgorithm
import Base: start, next, done

mutable struct MINRESIterable{matT, solT, vecT <: DenseVector, smallVecT <: DenseVector, rotT <: Number, realT <: Real}
    A::matT
    skew_hermitian::Bool
    x::solT

    # Krylov basis vectors
    v_prev::vecT
    v_curr::vecT
    v_next::vecT

    # W = R * inv(V) is computed using 3-term recurrence
    w_prev::vecT
    w_curr::vecT
    w_next::vecT

    # Vector of size 4, holding the active column of the Hessenberg matrix
    # rhs is just two active values of the right-hand side.
    H::smallVecT
    rhs::smallVecT

    # Some Givens rotations
    c_prev::rotT
    s_prev::rotT
    c_curr::rotT
    s_curr::rotT

    # Bookkeeping
    mv_products::Int
    maxiter::Int
    tolerance::realT
    resnorm::realT
end

minres_iterable(A, b; kwargs...) = minres_iterable!(zerox(A, b), A, b; initially_zero = true, kwargs...)

function minres_iterable!(x, A, b; 
    initially_zero::Bool = false, 
    skew_hermitian::Bool = false, 
    tol = sqrt(eps(real(eltype(b)))), 
    maxiter = size(A, 1)
)
    T = eltype(x)
    HessenbergT = skew_hermitian ? T : real(T)

    v_prev = similar(x)
    v_curr = similar(x)
    copy!(v_curr, b)
    v_next = similar(x)
    w_prev = similar(x)
    w_curr = similar(x)
    w_next = similar(x)

    mv_products = 0

    # For nonzero x's, we must do an MV for the initial residual vec
    if !initially_zero
        # Use v_next to store Ax; v_next will soon be overwritten.
        A_mul_B!(v_next, A, x)
        axpy!(-one(T), v_next, v_curr)
        mv_products = 1
    end

    resnorm = norm(v_curr)
    reltol = resnorm * tol

    # Last active column of the Hessenberg matrix 
    # and last two entries of the right-hand side
    H = zeros(HessenbergT, 4)
    rhs = [resnorm; zero(HessenbergT)]

    # Normalize the first Krylov basis vector
    scale!(v_curr, inv(resnorm))

    # Givens rotations
    c_prev, s_prev = one(T), zero(T)
    c_curr, s_curr = one(T), zero(T)

    MINRESIterable(
        A, skew_hermitian, x,
        v_prev, v_curr, v_next,
        w_prev, w_curr, w_next,
        H, rhs,
        c_prev, s_prev, c_curr, s_curr,
        mv_products, maxiter, reltol, resnorm
    )
end

converged(m::MINRESIterable) = m.resnorm ≤ m.tolerance

start(::MINRESIterable) = 1

done(m::MINRESIterable, iteration::Int) = iteration > m.maxiter || converged(m)

function next(m::MINRESIterable, iteration::Int)
    # v_next = A * v_curr - H[2] * v_prev
    A_mul_B!(m.v_next, m.A, m.v_curr)

    iteration > 1 && axpy!(-m.H[2], m.v_prev, m.v_next)
    
    # Orthogonalize w.r.t. v_curr
    proj = dot(m.v_curr, m.v_next)
    m.H[3] = m.skew_hermitian ? proj : real(proj)
    axpy!(-proj, m.v_curr, m.v_next)

    # Normalize
    m.H[4] = norm(m.v_next)
    scale!(m.v_next, inv(m.H[4]))

    # Rotation on H[1] and H[2]. Note that H[1] = 0 initially
    if iteration > 2
        m.H[1] = m.s_prev * m.H[2]
        m.H[2] = m.c_prev * m.H[2]
    end

    # Rotation on H[2] and H[3]
    if iteration > 1
        tmp = -conj(m.s_curr) * m.H[2] + m.c_curr * m.H[3]
        m.H[2] = m.c_curr * m.H[2] + m.s_curr * m.H[3]
        m.H[3] = tmp
    end

    # Next rotation
    c, s, m.H[3] = givensAlgorithm(m.H[3], m.H[4])

    # Apply as well to the right-hand side
    m.rhs[2] = -conj(s) * m.rhs[1]
    m.rhs[1] = c * m.rhs[1]

    # Update W = V * inv(R). Two axpy's can maybe be one MV.
    copy!(m.w_next, m.v_curr)
    iteration > 1 && axpy!(-m.H[2], m.w_curr, m.w_next)
    iteration > 2 && axpy!(-m.H[1], m.w_prev, m.w_next)
    scale!(m.w_next, inv(m.H[3]))

    # Update solution x
    axpy!(m.rhs[1], m.w_next, m.x)

    # Move on: next -> curr, curr -> prev
    m.v_prev, m.v_curr, m.v_next = m.v_curr, m.v_next, m.v_prev
    m.w_prev, m.w_curr, m.w_next = m.w_curr, m.w_next, m.w_prev
    m.c_prev, m.s_prev, m.c_curr, m.s_curr = m.c_curr, m.s_curr, c, s
    m.rhs[1] = m.rhs[2]

    # Due to symmetry of the tri-diagonal matrix
    m.H[2] = m.skew_hermitian ? -m.H[4] : m.H[4]

    # The approximate residual is cheaply available
    m.resnorm = abs(m.rhs[2])

    m.resnorm, iteration + 1
end

"""
    minres!(x, A, b; kwargs...) -> x, [history]

Solve Ax = b for (skew-)Hermitian matrices A using MINRES.

# Arguments

- `x`: initial guess, will be updated in-place;
- `A`: linear operator;
- `b`: right-hand side.

## Keywords

- `initially_zero::Bool = false`: if `true` assumes that `iszero(x)` so that one 
  matrix-vector product can be saved when computing the initial 
  residual vector;
- `skew_hermitian::Bool = false`: if `true` assumes that `A` is skew-symmetric or skew-Hermitian;
- `tol`: tolerance for stopping condition `|r_k| / |r_0| ≤ tol`. Note that the residual is computed only approximately;
- `maxiter::Int`: maximum number of inner iterations of GMRES;
- `Pl`: left preconditioner;
- `Pr`: right preconditioner;
- `log::Bool = false`: keep track of the residual norm in each iteration;
- `verbose::Bool = false`: print convergence information during the iterations.

# Return values

**if `log` is `false`**

- `x`: approximate solution.

**if `log` is `true`**

- `x`: approximate solution;
- `history`: convergence history.
"""
function minres!(x, A, b; 
    skew_hermitian::Bool = false,
    verbose::Bool = false,
    log::Bool = false,
    tol = sqrt(eps(real(eltype(b)))),
    maxiter::Int = min(30, size(A, 1)),
    initially_zero::Bool = false
)
    history = ConvergenceHistory(partial = !log)
    history[:tol] = tol
    log && reserve!(history, :resnorm, maxiter)
    
    iterable = minres_iterable!(x, A, b; 
        skew_hermitian = skew_hermitian, 
        tol = tol, 
        maxiter = maxiter,
        initially_zero = initially_zero
    )
    
    if log
        history.mvps = iterable.mv_products
    end

    for (iteration, resnorm) = enumerate(iterable)
        if log
            nextiter!(history, mvps = 1)
            push!(history, :resnorm, resnorm)
        end
        verbose && @printf("%3d\t%1.2e\n", iteration, resnorm)
    end
    
    verbose && println()
    log && setconv(history, converged(iterable))
    log && shrink!(history)
    
    log ? (iterable.x, history) : iterable.x
end

"""
    minres(A, b; kwargs...) -> x, [history]

Same as [`minres!`](@ref), but allocates a solution vector `x` initialized with zeros.
"""
minres(A, b; kwargs...) = minres!(zerox(A, b), A, b; initially_zero = true, kwargs...)
