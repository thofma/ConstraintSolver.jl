module ConstraintSolver

using MatrixNetworks

CS = ConstraintSolver

include("Variable.jl")

mutable struct CSInfo
    pre_backtrack_calls :: Int
    backtracked         :: Bool
    backtrack_counter   :: Int
    in_backtrack_calls  :: Int
end

function Base.show(io::IO, csinfo::CSInfo)
    println("Info: ")
    for name in fieldnames(CSInfo)
        println(io, "$name = $(getfield(csinfo, name))")
    end
end

mutable struct Constraint
    idx                 :: Int
    fct                 :: Function
    indices             :: Vector{Int}
    pvals               :: Vector{Int}
    rhs                 :: Int
end

mutable struct ConstraintOutput
    feasible            :: Bool
    idx_changed         :: Dict{Int, Bool}
    pruned              :: Vector{Int}
end

mutable struct BacktrackObj
    variable_idx        :: Int
    pval_idx            :: Int
    pvals               :: Vector{Int}
    constraint_idx      :: Vector{Int}
    pruned              :: Vector{Vector{Int}}

    BacktrackObj() = new()
end

mutable struct CoM
    search_space        :: Vector{Variable}
    subscription        :: Vector{Vector{Int}} 
    constraints         :: Vector{Constraint}
    bt_infeasible       :: Vector{Int}
    info                :: CSInfo
    
    CoM() = new()
end

include("all_different.jl")
include("eq_sum.jl")

function init()
    com = CoM()
    com.constraints         = Vector{Constraint}()
    com.subscription        = Vector{Vector{Int}}()
    com.search_space        = Vector{Variable}()
    com.bt_infeasible       = Vector{Int}()
    com.info                = CSInfo(0, false, 0, 0)
    return com
end

function addVar!(com::CS.CoM, from::Int, to::Int; fix=nothing)
    ind = length(com.search_space)+1
    var = Variable(ind, from, to, 1, to-from+1, from:to, 1:to-from+1, 1-from, from, to)
    if fix !== nothing
        fix!(var, fix)
    end
    push!(com.search_space, var)
    push!(com.subscription, Int[])
    push!(com.bt_infeasible, 0)
    return var
end

function fulfills_constraints(com::CS.CoM, index, value)
    constraints = com.constraints[com.subscription[index]]
    feasible = true
    for constraint in constraints
        feasible = constraint.fct(com, constraint, value, index)
        if !feasible
            break
        end
    end
    return feasible
end


"""
    fixed_vs_unfixed(search_space, indices)

Returns the fixed_vals as well as the unfixed_indices
"""
function fixed_vs_unfixed(search_space, indices)
    # get all values which are fixed
    fixed_vals = Int[]
    unfixed_indices = Int[]
    for (i,ind) in enumerate(indices)
        if isfixed(search_space[ind])
            push!(fixed_vals, value(search_space[ind]))
        else
            push!(unfixed_indices, i)
        end
    end
    return fixed_vals, unfixed_indices
end

"""
    add_constraint!(com::CS.CoM, fct, variables; rhs=0)

Add a constraint using a function name and the variables over which the constraint should hold
"""
function add_constraint!(com::CS.CoM, fct, variables; rhs=0)
    current_constraint_number = length(com.constraints)+1
    indices = vec([v.idx for v in variables])
    constraint = Constraint(current_constraint_number, fct, indices, Int[], rhs)
    push!(com.constraints, constraint)
    pvals_intervals = Vector{NamedTuple}()
    push!(pvals_intervals, (from = variables[1].from, to = variables[1].to))
    for (i,ind) in enumerate(indices)
        extra_from = variables[i].from
        extra_to   = variables[i].to
        comp_inside = false
        for cpvals in pvals_intervals
            if extra_from >= cpvals.from && extra_to <= cpvals.to
                # completely inside the interval already
                comp_inside = true
                break
            elseif extra_from >= cpvals.from && extra_from <= cpvals.to
                extra_from = cpvals.to+1
            elseif extra_to <= cpvals.to && extra_to >= cpvals.from
                extra_to = cpvals.from-1
            end
        end
        if !comp_inside && extra_to >= extra_from
            push!(pvals_intervals, (from = extra_from, to = extra_to))
        end
        push!(com.subscription[ind], current_constraint_number)
    end
    pvals = collect(pvals_intervals[1].from:pvals_intervals[1].to)
    for interval in pvals_intervals[2:end]
        pvals = vcat(pvals, collect(interval.from:interval.to))
    end
    constraint.pvals = pvals
end

function get_weak_ind(com::CS.CoM)
    lowest_num_pvals = typemax(Int)
    biggest_inf = -1
    best_ind = -1
    biggest_dependent = typemax(Int)
    found = false

    for ind in 1:length(com.search_space)
        if !isfixed(com.search_space[ind])
            num_pvals = nvalues(com.search_space[ind])
            inf = com.bt_infeasible[ind]
            if inf >= biggest_inf
                if inf > biggest_inf || num_pvals < lowest_num_pvals
                    lowest_num_pvals = num_pvals
                    biggest_inf = inf
                    best_ind = ind
                    found = true
                end
            end
        end
    end
    return found, best_ind
end

"""
    prune!(com, constraints, constraint_outputs)

Prune based on previous constraint_outputs.
Add new constraints and constraint outputs to the corresponding inputs.
Returns feasible, constraints, constraint_outputs
"""
function prune!(com, constraints, constraint_outputs; pre_backtrack=false)
    feasible = true
    co_idx = 1
    constraint_idxs_dict = Dict{Int, Bool}()
    # get all constraints which need to be called (only once)
    for co_idx=1:length(constraint_outputs)
        constraint_output = constraint_outputs[co_idx]
        for changed_idx in keys(constraint_output.idx_changed)
            inner_constraints = com.constraints[com.subscription[changed_idx]]
            for constraint in inner_constraints
                constraint_idxs_dict[constraint.idx] = true
            end
        end
        co_idx += 1
    end
    constraint_idxs = collect(keys(constraint_idxs_dict))
    con_counter = 0
    # while we haven't called every constraint
    while length(constraint_idxs_dict) > 0
        con_counter += 1
        constraint = com.constraints[constraint_idxs[con_counter]]
        delete!(constraint_idxs_dict, constraint.idx)
        if all(v->isfixed(v), com.search_space[constraint.indices])
            continue
        end
        constraint_output = constraint.fct(com, constraint; logs = false)
        if !pre_backtrack
            com.info.in_backtrack_calls += 1
            push!(constraint_outputs, constraint_output)
            push!(constraints, constraint)
        else
            com.info.pre_backtrack_calls += 1
        end
        
        if !constraint_output.feasible
            feasible = false
            break
        end

        # if we fixed another value => add the corresponding constraint to the list
        # iff the constraint will not be called anyway in the list 
        for ind in keys(constraint_output.idx_changed)
            for constraint in com.constraints[com.subscription[ind]]
                if !haskey(constraint_idxs_dict, constraint.idx)
                    constraint_idxs_dict[constraint.idx] = true
                    push!(constraint_idxs, constraint.idx)
                end
            end
        end
    end
    return feasible, constraints, constraint_outputs
end

function single_reverse_pruning!(search_space, index::Int, prune_int::Int)
    if prune_int > 0
        var = search_space[index]
        l_ptr = max(1,var.last_ptr)
        new_l_ptr = var.last_ptr + prune_int
        @views min_val = minimum(var.values[l_ptr:new_l_ptr])
        @views max_val = maximum(var.values[l_ptr:new_l_ptr])
        if min_val < var.min
            var.min = min_val
        end
        if max_val > var.max
            var.max = max_val
        end
        var.last_ptr = new_l_ptr
    end
end

"""
    reverse_pruning!(com, constraints, constraint_outputs)

Reverse the changes made by constraints using their ConstraintOutputs
"""
function reverse_pruning!(com::CS.CoM, constraints, constraint_outputs)
    search_space = com.search_space
    for cidx = 1:length(constraint_outputs)
        constraint = constraints[cidx]
        constraint_output = constraint_outputs[cidx]
        for (i,local_ind) in enumerate(constraint.indices)
            single_reverse_pruning!(search_space, local_ind, constraint_output.pruned[i])
        end
    end
end

function reverse_pruning!(com::CS.CoM, backtrack_obj::CS.BacktrackObj)
    search_space = com.search_space
    for (i,constraint_idx) in enumerate(backtrack_obj.constraint_idx)
        constraint = com.constraints[constraint_idx]
        for (j,local_ind) in enumerate(constraint.indices)
            single_reverse_pruning!(search_space, local_ind, backtrack_obj.pruned[i][j])
        end
    end
    empty!(backtrack_obj.constraint_idx)
    empty!(backtrack_obj.pruned)
end

function backtrack!(com::CS.CoM)
    found, ind = get_weak_ind(com)
    if !found 
        return :Solved
    end
    com.info.backtrack_counter += 1

    pvals = values(com.search_space[ind])
    backtrack_obj = BacktrackObj()
    backtrack_obj.variable_idx = ind
    backtrack_obj.pval_idx = 0
    backtrack_obj.pvals = pvals
    backtrack_vec = BacktrackObj[backtrack_obj]
    finished = false
    while length(backtrack_vec) > 0 && !finished
        backtrack_obj = backtrack_vec[end]
        backtrack_obj.pval_idx += 1
        ind = backtrack_obj.variable_idx
        
        if isdefined(backtrack_obj, :pruned)
            reverse_pruning!(com, backtrack_obj)
        end

        # checked every value => remove from backtrack
        if backtrack_obj.pval_idx > length(backtrack_obj.pvals)
            com.search_space[ind].last_ptr = length(backtrack_obj.pvals)
            com.search_space[ind].first_ptr = 1
            com.search_space[ind].min = minimum(backtrack_obj.pvals)
            com.search_space[ind].max = maximum(backtrack_obj.pvals)
            pop!(backtrack_vec)
            continue
        end
        pval = backtrack_obj.pvals[backtrack_obj.pval_idx]

        # check if this value is still possible
        constraints = com.constraints[com.subscription[ind]]
        feasible = true
        for constraint in constraints
            feasible = constraint.fct(com, constraint, pval, ind)
            if !feasible
                break
            end
        end
        if !feasible
            continue
        end
        # value is still possible => set it
        fix!(com.search_space[ind], pval)
        constraint_outputs = ConstraintOutput[]
        for constraint in constraints
            constraint_output = constraint.fct(com, constraint; logs = false)
            push!(constraint_outputs, constraint_output)
            if !constraint_output.feasible
                feasible = false
                break
            end
        end
        if !feasible
            reverse_pruning!(com, constraints, constraint_outputs)
            continue
        end

        # prune on fixed vals
        feasible, constraints, constraint_outputs = prune!(com, constraints, constraint_outputs)
         
        if !feasible
            reverse_pruning!(com, constraints, constraint_outputs)
            continue
        end

        found, ind = get_weak_ind(com)
        if !found 
            return :Solved
        end
        com.info.backtrack_counter += 1

        backtrack_obj.constraint_idx = zeros(Int, length(constraint_outputs))
        backtrack_obj.pruned = Vector{Vector{Int}}(undef, length(constraint_outputs))
        for cidx = 1:length(constraint_outputs)
            constraint = constraints[cidx]
            constraint_output = constraint_outputs[cidx]
            backtrack_obj.constraint_idx[cidx] = constraint.idx
            backtrack_obj.pruned[cidx] = constraint_outputs[cidx].pruned
        end

        pvals = values(com.search_space[ind])
        backtrack_obj = BacktrackObj()
        backtrack_obj.variable_idx = ind
        backtrack_obj.pval_idx = 0
        backtrack_obj.pvals = pvals
        push!(backtrack_vec, backtrack_obj)
    end
    return :Infeasible
end

function solve!(com::CS.CoM; backtrack=true)
    if all(v->isfixed(v), com.search_space)
        return :Solved
    end

    changed = Dict{Int, Bool}()
    feasible = true
    constraint_outputs = ConstraintOutput[]
    for constraint in com.constraints
        com.info.pre_backtrack_calls += 1
        constraint_output = constraint.fct(com, constraint)
        push!(constraint_outputs, constraint_output)
        merge!(changed, constraint_output.idx_changed)
        if !constraint_output.feasible
            feasible = false
            break
        end
    end

    if !feasible
        return :Infeasible
    end

    if all(v->isfixed(v), com.search_space)
        return :Solved
    end

    feasible, constraints, constraint_outputs = prune!(com, com.constraints, constraint_outputs
                                                        ;pre_backtrack=true)


    if !feasible 
        return :Infeasible
    end
    
    if all(v->isfixed(v), com.search_space)
        return :Solved
    end
    if backtrack
        com.info.backtracked = true
        return backtrack!(com)
    else
        @info "Backtracking is turned off."
        return :NotSolved
    end
end

end # module
