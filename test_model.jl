
# Basic production model to build off
# Tom H 
using JuMP
using GLPK
using HiGHS
using DataFrames
using XLSX

include("utility.jl")

# Data structures

struct Arc
    c::String
    m::String
end

file = "deterministic_2cust_2mills.xlsx"

xf = XLSX.readxlsx(file)
sheet_names = XLSX.sheetnames(xf)
data = Dict()

for sheet in sheet_names 
    data[sheet] = DataFrame(XLSX.readtable(file, sheet)...)
end

# Parameters

D = df2param(data["CustomerDemand"])
F = df2param(data["FixedCosts"])
S = df2param(data["ShutdownCosts"])
PC = df2param(data["Capacity"])
L = df2param(data["LogisticCosts"])
SC = df2param(data["StorageCosts"])
PR = df2param(data["Prices"])
WC = df2param(data["RawMaterialCosts"])
EC = df2param(data["EnergyCosts"])

# Sets 

M = unique(data["PM"].MILL)
PM = unique(data["PM"].PM)
P = unique(data["CustomerDemand"].PRODUCT)
R = unique(data["RawMaterialCosts"][!,"RAW MATERIAL"])
E = unique(data["EnergyCosts"].ENERGY)
C = unique(data["CustomerDemand"].CUSTOMER)
T = unique(data["CustomerDemand"].CALMONTH)
L_arcs = Arc.(data["LogisticCosts"][!,1], data["LogisticCosts"][!,2]) #create an arc for each customer mill route available

# Mappings

pm_mill = Dict(Pair.(data["PM"].PM, data["PM"].MILL))
prod_mat = Dict()
prod_en = Dict()

for product in unique(data["RawMaterialCosts"].PRODUCT)
    prod_mat[product] = unique(filter(:PRODUCT => ==(product), data["RawMaterialCosts"])[!,"RAW MATERIAL"])
end
for product in unique(data["EnergyCosts"].PRODUCT)
    prod_en[product] = unique(filter(:PRODUCT => ==(product), data["EnergyCosts"])[!,"ENERGY"])
end

# Model 

mod = Model(HiGHS.Optimizer)

# Decision Variables

# Integer decision variables
@variable(mod, y[PM], Bin)
T_lag_fix = vcat([202200],T)

# Cont. decision variables
@variable(mod, u[L_arcs, P,T] >= 0)
@variable(mod, x[P,PM, T] >= 0)
@variable(mod, I[P,M,T_lag_fix] >= 0)

# Objective components (linear expressions)
@expression(mod, sales, sum(PR[t,i]*x[i,p,t] for i in P, p in PM, t in T))
@expression(mod, pcost, sum(sum(WC[t,p,i,r] for r in prod_mat[i])*x[i,p,t] for i in P, p in PM, t in T))
@expression(mod, icost, sum(SC[m]*I[p,m,t] for m in M, p in P, t in T))
@expression(mod, lcost, sum(L[arc.c, arc.m]*u[arc,i,t] for i in P, t in T, arc in L_arcs))
@expression(mod, ecost, sum(sum(EC[t,pm_mill[p],i,r] for r in prod_en[i])*x[i,p,t] for i in P, p in PM, t in T))

# Objective function

@objective(mod, Max, sales - pcost - icost - ecost - lcost)

# Constraints

@constraint(mod, [i in P, m in M], I[i,m,202200] == 0)
# Demand satisfaction
@constraint(mod, [t in T, i in P], sum(x[i,p,t] for p in PM) + sum(I[i,m,t-1] for m in M) == sum(D[t,c,i] for c in C) + sum(I[i,m,t] for m in M))

# Distribution balance
#@constraint(mod, [m in M, t in T], sum(x[i,p,t] for i in P, p in [p for p in PM if pm_mill[p] == m]) == sum(u[c,m,i,t] for c in C, i in P))
@constraint(mod, [l in L_arcs, t in T], sum(x[i,p,t] for i in P, p in [p for p in PM if pm_mill[p] == l.m]) == sum(u[l,i,t] for i in P))

# Customer-level demand satisfaction
#@constraint(mod, [c in C, i in P, t in T], sum(u[c,m,i,t] for m in M) >= D[t,c,i])
@constraint(mod, [l in L_arcs, i in P, t in T], u[l,i,t] >= D[t,l.c,i])

# Bounded inventory
@constraint(mod, [m in M, t in T], sum(I[i,m,t] for i in P) <= 100)

# Bounded capacity 
@constraint(mod, [t in T, p in PM], sum(x[i,p,t] for i in P) <= PC[p])

optimize!(mod)


# Print model
for i in P
    for p in PM
        for t in T
            println("x[" , i , "," , p , "," , t , "]" , " = " , value(x[i,p,t]))
        end
    end
end

u_df = convert_jump_container_to_df(u)
insertcols!(u_df, 1, :Customer => getfield.(u_df[!,"dim1"], :c)) #XLSX cant export structs
insertcols!(u_df, 2, :Mill => getfield.(u_df[!,"dim1"], :m))
select!(u_df, Not(:dim1))
x_df = convert_jump_container_to_df(x)
I_df = convert_jump_container_to_df(I)

XLSX.writetable("results.xlsx", "Logistics" => u_df ,"Production" => x_df, "Inventory" => I_df)