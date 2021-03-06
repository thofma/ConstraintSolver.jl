Variable(idx) = Variable(
    idx,
    0,
    0,
    0,
    0,
    [],
    [],
    [],
    [],
    0,
    0,
    0,
    Vector{Vector{Tuple{Symbol,Int,Int,Int}}}(),
    false,
    false,
    false,
    false,
)

MatchingInit() = MatchingInit(0, Int[], Int[], Int[], Int[], Int[], Int[], Bool[], Bool[])

function ConstraintInternals(idx::Int, fct, set, indices::Vector{Int})
    return ConstraintInternals(
        idx, fct, set, indices, Int[], ImplementedConstraintFunctions(), nothing, zero(UInt64)
    )
end

function ImplementedConstraintFunctions()
   return ImplementedConstraintFunctions([false for f in fieldnames(ImplementedConstraintFunctions)]...)
end

function LinearConstraint(
    fct::MOI.ScalarAffineFunction,
    set::MOI.AbstractScalarSet,
    indices::Vector{Int},
)
    # get common type for rhs and coeffs
    # use the first value (can be .upper, .lower, .value) and subtract left constant
    rhs = -fct.constant
    if isa(set, Union{MOI.EqualTo, CS.NotEqualTo})
        rhs += set.value
    elseif isa(set, MOI.LessThan)
        rhs += set.upper
    end
    coeffs = [t.coefficient for t in fct.terms]
    promote_T = promote_type(typeof(rhs), eltype(coeffs))
    if promote_T != eltype(coeffs)
        coeffs = convert.(promote_T, coeffs)
    end
    if promote_T != typeof(rhs)
        rhs = convert(promote_T, rhs)
    end
    maxs = zeros(promote_T, length(indices))
    mins = zeros(promote_T, length(indices))
    pre_maxs = zeros(promote_T, length(indices))
    pre_mins = zeros(promote_T, length(indices))
    # this can be changed later in `set_in_all_different!` but needs to be initialized with false
    in_all_different = false

    internals = ConstraintInternals(0, fct, set, indices)
    lc = LinearConstraint(
        internals,
        in_all_different,
        mins,
        maxs,
        pre_mins,
        pre_maxs,
    )
    return lc
end

"""
    ConstraintSolverModel(T::DataType=Float64)

Create the constraint model object and specify the type of the solution
"""
function ConstraintSolverModel(::Type{T} = Float64) where {T<:Real}
    ConstraintSolverModel(
        nothing, # lp_model
        Vector{VariableRef}(), # lp_x
        Vector{Variable}(), # init_search_space
        Vector{Variable}(), # search_space
        Vector{Tuple{Int,Int}}(), # init_fixes
        Vector{Vector{Int}}(), # subscription
        Vector{Constraint}(), # constraints
        Vector{Int}(), # bt_infeasible
        1, # c_backtrack_idx
        Vector{BacktrackObj{T}}(), # backtrack_vec
        MOI.FEASIBILITY_SENSE, #
        NoObjective(), #
        get_traverse_strategy(), 
        get_branch_split(),
        zero(T), # best_sol,
        zero(T), # best_bound
        Vector{Solution}(), # all solution objects
        Vector{Int}(), # save backtrack id to solution
        CSInfo(0, false, 0, 0, 0, NumberConstraintTypes()), # info
        Dict{Symbol,Any}(), # input
        Vector{TreeLogNode{T}}(), # logs
        SolverOptions(), # options,
        -1.0, # solve start time
        -1.0, # solve time will be overwritten
    )
end

@deprecate init() ConstraintSolverModel()

function NumberConstraintTypes()
    return NumberConstraintTypes(zeros(Int, length(fieldnames(NumberConstraintTypes)))...)
end

function BacktrackObj(com::CS.CoM)
    return BacktrackObj(
        1, # idx
        0, # parent_idx
        0, # depth
        :Closed, # status
        0, # variable_idx
        0, # lb and ub only take effect if variable_idx != 0 
        0, # ub
        com.sense == MOI.MIN_SENSE ? typemax(com.best_bound) : typemin(com.best_bound),
        zeros(length(com.search_space)),
        zeros(length(com.search_space))
    )
end
