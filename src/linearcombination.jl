function Base.:+(x::Variable, y::Variable)
    return LinearCombination([x.idx, y.idx], [1, 1])
end

function Base.:-(x::Variable, y::Variable)
    return LinearCombination([x.idx, y.idx], [1, -1])
end

function Base.:-(x::LinearCombination)
    return LinearCombination(x.indices, -x.coeffs)
end

function Base.:+(x::LinearCombination, y::Variable)
    lv = LinearCombination(x.indices, x.coeffs)
    push!(lv.indices, y.idx)
    push!(lv.coeffs, 1)
    return lv
end

function Base.:-(x::LinearCombination, y::Variable)
    lv = LinearCombination(x.indices, x.coeffs)
    push!(lv.indices, y.idx)
    push!(lv.coeffs, -1)
    return lv
end

function Base.:+(x::Variable, y::Int)
    return LinearCombination([x.idx], [1]) + y
end

function Base.:+(x::LinearCombination, y::Int)
    lv = LinearCombination(x.indices, x.coeffs)
    push!(lv.indices, 0)
    push!(lv.coeffs, y)
    return lv
end

function Base.:-(x::Variable, y::Int)
    return LinearCombination([x.idx], [1]) - y
end

function Base.:-(x::LinearCombination, y::Int)
    return x + (-y)
end

function Base.:+(x::Variable, y::LinearCombination)
    return y + x # commutative
end

function Base.:+(x::LinearCombination, y::LinearCombination)
    return LinearCombination(vcat(x.indices, y.indices), vcat(x.coeffs, y.coeffs))
end

function Base.:-(x::LinearCombination, y::LinearCombination)
    return LinearCombination(vcat(x.indices, y.indices), vcat(x.coeffs, -y.coeffs))
end

function Base.:*(x::Int, y::Variable)
    return LinearCombination([y.idx], [x])
end

function Base.:*(y::Variable, x::Int)
    return LinearCombination([y.idx], [x])
end


function simplify(x::LinearCombination)
    set_indices = Set(x.indices)
    # if unique
    if length(set_indices) == length(x.indices)
        if 0 in set_indices
            indices = Int[]
            coeffs = Int[]
            lhs = 0
            for i = 1:length(x.indices)
                if x.indices[i] == 0
                    lhs = x.coeffs[i]
                else
                    push!(indices, x.indices[i])
                    push!(coeffs, x.coeffs[i])
                end
            end
            return indices, coeffs, lhs
        else
            return x.indices, x.coeffs, 0
        end
    end

    perm = sortperm(x.indices)
    x.indices = x.indices[perm]
    x.coeffs = x.coeffs[perm]
    indices = Int[x.indices[1]]
    coeffs = Int[x.coeffs[1]]

    last_idx = x.indices[1]

    for i = 2:length(x.indices)
        if x.indices[i] == last_idx
            coeffs[end] += x.coeffs[i]
        else
            last_idx = x.indices[i]
            push!(indices, x.indices[i])
            push!(coeffs, x.coeffs[i])
        end
    end

    lhs = 0
    if indices[1] == 0
        lhs = coeffs[1]
        indices = indices[2:end]
        coeffs = coeffs[2:end]
    end

    return indices, coeffs, lhs
end
