macro register(expr, Ts = [Num, Symbolic, Number])
    @assert expr.head == :call

    f = expr.args[1]
    args = expr.args[2:end]

    symbolic_args = findall(x->x isa Symbol, args)

    types = vec(collect(Iterators.product(ntuple(_->Ts, length(symbolic_args))...)))

    # remove Number Number Number methods
    filter!(Ts->!all(T->T == Number, Ts), types)

    annotype(name,T) = :($name :: $T)
    setinds(xs, idx, vs) = (xs=copy(xs); xs[idx] .= map(annotype, xs[idx], vs); xs)
    name(x::Symbol) = :($value($x))
    name(x::Expr) = ((@assert x.head == :(::)); :($value($(x.args[1]))))

    Expr(:block,
         [:($f($(setinds(args, symbolic_args, ts)...)) = Term{Number}($f, [$(map(name, args)...)]))
         for ts in types]...) |> esc
end

# Ensure that Operations that get @registered from outside the ModelingToolkit
# module can work without having to bring in the associated function into the
# ModelingToolkit namespace. We basically store information about functions
# registered at runtime in a ModelingToolkit variable,
# `registered_external_functions`. It's not pretty, but we are limited by the
# way GeneralizedGenerated builds a function (adding "ModelingToolkit" to every
# function call).
# ---
const registered_external_functions = Dict{Symbol,Module}()
function inject_registered_module_functions(expr)
    MacroTools.postwalk(expr) do x
        # Find all function calls in the expression and extract the function
        # name and calling module.
        MacroTools.@capture(x, f_module_.f_name_(xs__))
        if isnothing(f_module)
            MacroTools.@capture(x, f_name_(xs__))
        end

        if !isnothing(f_name)
            # Set the calling module to the module that registered it.
            mod = get(registered_external_functions, f_name, f_module)
            if !isnothing(mod) && mod != Base
                x.args[1] = :($mod.$f_name)
            end
        end

        return x
    end
end
