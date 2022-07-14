
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
ST = df2param(data["StorageCapacities"])
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
T_lag_fix = vcat([202200],T)

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

# Cont. decision variables
@variable(mod, x[P, PM, T, C] >= 0)
@variable(mod, I[P, M , T_lag_fix, C] >= 0)

# Objective components (linear expressions)
@expression(mod, sales, sum(PR[t,i]*x[i,p,t,c] for i in P, p in PM, t in T, c in C))
@expression(mod, pcost, sum(sum(WC[t,p,i,r] for r in prod_mat[i])*x[i,p,t,c] for i in P, p in PM, t in T, c in C))
@expression(mod, icost, sum(SC[m]*I[i,m,t,c] for m in M, i in P, t in T, c in C))
@expression(mod, lcost, sum(L[c,m]*x[i,p,t,c] for i in P, p in PM, t in T, c in C, m in M))
@expression(mod, ecost, sum(sum(EC[t,pm_mill[p],i,r] for r in prod_en[i])*x[i,p,t,c] for i in P, p in PM, t in T, c in C))

# Objective function
@objective(mod, Max, sales - pcost - icost - ecost - lcost)

# Constraints
@constraint(mod, [i in P, m in M,c in C], I[i,m,202200,c] == 0)
# Demand satisfaction
@constraint(mod, [t in T, i in P, c in C], sum(x[i,p,t,c] for p in PM) + sum(I[i,m,t-1,c] for m in M) == D[t,c,i] + sum(I[i,m,t,c] for m in M))

# Bounded inventory
@constraint(mod, [m in M, t in T], sum(I[i,m,t,c] for i in P, c in C) <= ST[m])

# Bounded capacity 
@constraint(mod, [t in T, p in PM], sum(x[i,p,t,c] for i in P, c in C) <= PC[p])

optimize!(mod)

x_df = convert_jump_container_to_df(x)
rename!(x_df, [:Product, :PM, :Period, :Customer, :Amount])
I_df = convert_jump_container_to_df(I)
rename!(I_df, [:Product, :Mill, :Period, :Customer, :Amount])
rm("results.xlsx")
XLSX.writetable("results.xlsx", "Production" => x_df, "Inventory" => I_df)