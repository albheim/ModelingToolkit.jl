using SymbolicUtils: istree

function nterms(t)
    if istree(t)
        return reduce(+, map(nterms, arguments(t)), init=0)
    else
        return 1
    end
end
# Soft pivoted
# Note: we call this function with a matrix of Union{SymbolicUtils.Symbolic, Any}
# It should work as-is with Operation type too.
function sym_lu(A)
    m, n = size(A)
    L = fill!(Array{Any}(undef, size(A)),0) # TODO: make sparse?
    for i=1:min(m, n)
        L[i,i] = 1
    end
    U = copy(A)
    p = BlasInt[1:m;]
    for k = 1:m-1
        _, i = findmin(map(ii->iszero(U[ii, k]) ? Inf : nterms(U[ii,k]), k:n))
        i += k - 1
        # swap
        U[k, k:end], U[i, k:end] = U[i, k:end], U[k, k:end]
        L[k, 1:k-1], L[i, 1:k-1] = L[i, 1:k-1], L[k, 1:k-1]
        p[k] = i

        for j = k+1:m
            L[j,k] = U[j, k] / U[k, k]
            U[j,k:m] .= U[j,k:m] .- simplifying_dot(L[j,k],  U[k,k:m])
        end
    end
    factors = copy(U)
    for j=1:m
        for i=j+1:n
            factors[i,j] = L[i,j]
        end
    end

    @pa p
    LU(factors, p, BlasInt(0))
end

# Given a vector of equations and a
# list of independent variables,
# return the coefficient matrix `A` and a
# vector of constants (possibly symbolic) `b` such that
# A \ b will solve the equations for the vars
function A_b(eqs, vars)
    exprs = rhss(eqs) .- lhss(eqs)
    for ex in exprs
        @assert islinear(ex, vars)
    end
    A = jacobian(exprs, vars)
    b = A * vars - exprs
    A, b
end

macro pa(x)
    n = string(x)
    quote
        println($n, " = ")
        Base.print_array(stdout, $(esc(x)))
        println()
    end
end
function solve_for(eqs, vars)
    @pa eqs
    @pa vars

    A, b = A_b(eqs, vars)
    A = SymbolicUtils.simplify.(to_symbolic.(A), polynorm=true)
    b = SymbolicUtils.simplify.(to_symbolic.(b), polynorm=true)
    @pa A
    @pa b
    map(to_mtk, SymbolicUtils.simplify.(ldiv(sym_lu(A), b)))
end

# ldiv below

_iszero(x::Number) = iszero(x)
_isone(x::Number) = isone(x)
_iszero(::Term) = false
_isone(::Term) = false

function simplifying_dot(x,y)
    isempty(x) && return 0
    muls = map(x,y) do xi,yi
        _isone(xi) ? yi : _isone(yi) ? xi : _iszero(xi) ? 0 : _iszero(yi) ? 0 : xi * yi
    end

    reduce(muls) do acc, x
        _iszero(acc) ? x : _iszero(x) ? acc : acc + x
    end
end

function ldiv(A::LU, b)
    # unit lower triangular solve first:
    L = A.L
    U = A.U
    m, n = size(L)
    x = Vector{Any}(undef, length(b))
    b = b[A.p]
    for i=1:n
        sub = simplifying_dot(b[1:i-1], L[i, 1:i-1])
        x[i] = _iszero(sub) ? b[i] : b[i] - sub
    end

    for i=n:-1:1
        sub = simplifying_dot(b[i+1:end], U[i,i+1:end])
        den = U[i,i]
        x[i] = _iszero(sub) ? x[i] : x[i] - sub
        x[i] = _isone(U[i,i]) ? x[i] : _isone(-U[i,i]) ? -x[i] : x[i] / U[i,i]
    end
    x
end
