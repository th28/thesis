using JuMP
using GLPK
using HiGHS
using DataFrames
using XLSX
#Credit to jd-foster from the julia discourse post: https://discourse.julialang.org/t/extracting-jump-results/51429/4
function convert_jump_container_to_df(var::JuMP.Containers.DenseAxisArray;
    dim_names::Vector{Symbol}=Vector{Symbol}(),
    value_col::Symbol=:Value)

    if isempty(var)
        return DataFrame()
    end

    if length(dim_names) == 0
        dim_names = [Symbol("dim$i") for i in 1:length(var.axes)]
    end

    if length(dim_names) != length(var.axes)
        throw(ArgumentError("Length of given name list does not fit the number of variable dimensions"))
    end

    tup_dim = (dim_names...,)

    # With a product over all axis sets of size M, form an Mx1 Array of all indices to the JuMP container `var`
    ind = reshape([collect(k[i] for i in 1:length(dim_names)) for k in Base.Iterators.product(var.axes...)],:,1)

    var_val  = value.(var)

    df = DataFrame([merge(NamedTuple{tup_dim}(ind[i]), NamedTuple{(value_col,)}(var_val[(ind[i]...,)...])) for i in 1:length(ind)])

    return df
end

function df2param(df)
    d = Dict() 
    num_cols = length(names(df))
    for row in eachrow(df)
        if num_cols == 2
            d[Tuple(row[1:num_cols-1])[1]] = row[num_cols]
        else    
            d[Tuple(row[1:num_cols-1])] = row[num_cols]
        end
    end
    return d
end



function invert_dict(dict, warning::Bool = false)
    vals = collect(values(dict))
    dict_length = length(unique(vals))

  

    linked_list = Array[]

    for i in vals 
        push!(linked_list,[])
    end 

    new_dict = Dict(zip(vals, linked_list))

    for (key,val) in dict 
        push!(new_dict[val],key)
    end
    

    return new_dict
end


function xl_to_df(file_name)
    file = file_name

    xf = XLSX.readxlsx(file)
    sheet_names = XLSX.sheetnames(xf)
    data = Dict()

    for sheet in sheet_names 
        data[sheet] = DataFrame(XLSX.readtable(file, sheet)...)
    end

    return data
end