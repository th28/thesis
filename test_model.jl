
# Basic production model to build off
# Tom H 
using JuMP
using GLPK
using HiGHS
using DataFrames
using XLSX
using DisjunctiveProgramming

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
dacalim = df2param(data["DACA_limits"])
dacapr = df2param(data["DACA_prices"])
a = df2param(data["RawMaterialConversion"])
RP = df2param(data["RawMaterialPrices"])
D = df2param(data["CustomerDemand"])
F = df2param(data["FixedCosts"])
S = df2param(data["ShutdownCosts"])
PC = df2param(data["Capacity"])
L = df2param(data["LogisticCosts"])
SC = df2param(data["StorageCosts"])
ST = df2param(data["StorageCapacities"])
PR = df2param(data["Prices"])
EC = df2param(data["EnergyCosts"])

# Sets 
A = unique(data["Contracts"].CONTRACT)
M = unique(data["PM"].MILL)
PM = unique(data["PM"].PM)
P = unique(data["CustomerDemand"].PRODUCT)
R = unique(data["RawMaterialPrices"][!,"RAW MATERIAL"])
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

mod = Model(GLPK.Optimizer)

# Decision Variables

# Integer decision variables
@variable(mod, z[A, R, T], Bin)
@variable(mod, y[PM], Bin)


# Cont. decision variables
@variable(mod, RC[A,R,T] >= 0)
# DACA contract ad-hoc variables
@variable(mod, daca[["d1","d2"],R, T] >= 0)  #contract stage, raw mater. time period



@variable(mod, RB[T,R] >= 0) # raw material purchased at time T
@variable(mod, RI[T_lag_fix, R, M] >= 0) # raw material inventory
@variable(mod, x[P, PM, T, C] >= 0)
@variable(mod, I[P, M , T_lag_fix, C] >= 0)

@expression(mod, rcost_f, sum(RP[t,r]*RC["FIXED",r, t] for r in R, t in T))
@expression(mod, rcost_daca, sum(dacapr[t, "d1", r]*daca["d1", r, t] + dacapr[t, "d2", r]*daca["d1", r, t] for r in R, t in T))
# Objective components (linear expressions)
@expression(mod, sales, sum(PR[t,i]*x[i,p,t,c] for i in P, p in PM, t in T, c in C))
#@expression(mod, rcost, sum(RP[t,r]*RB[t,r] for t in T, r in R))
@expression(mod, rcost, rcost_f + rcost_daca)
@expression(mod, icost, sum(SC[m]*I[i,m,t,c] for m in M, i in P, t in T, c in C) + sum(SC[m]*RI[t,r,m] for t in T, r in R, m in M))
@expression(mod, lcost, sum(L[c,m]*x[i,p,t,c] for i in P, p in PM, t in T, c in C, m in M))
@expression(mod, ecost, sum(sum(EC[t,pm_mill[p],i,r] for r in prod_en[i])*x[i,p,t,c] for i in P, p in PM, t in T, c in C))
@expression(mod, onoff, sum(F[p]*y[p] + S[p]*(1-y[p]) for p in PM))

# Objective function
@objective(mod, Max, sales - rcost - icost - ecost - lcost - onoff)

# Constraints
#Contract Constraints
#Only one contract allowed
@constraint(mod, [t in T, r in R], sum(z[a, r, t] for a in A) <= 1)
#Only exercise active Contracts
@constraint(mod, [a in A, r in R, t in T], RC[a, r, t] <= 100000000*z[a, r, t] )
#Aggregate raw material purchases
@constraint(mod, [t in T, r in R], RB[t,r] == sum(RC[a, r, t] for a in A))
#DACA
@constraint(mod, [r in R, t in T], RC["DACA", r, t] == daca["d1", r, t] + daca["d2", r, t])





@constraint(mod, [i in P, m in M,c in C], I[i, m, 202200, c] == 0)
@constraint(mod, [r in R, m in M], RI[202200, r, m] == 0)

# Demand satisfaction
@constraint(mod, [t in T, i in P, c in C], sum(x[i, p, t, c] for p in PM) + sum(I[i,m,t-1,c] for m in M) == D[t,c,i] + sum(I[i,m,t,c] for m in M))

# Raw material balance
@constraint(mod, [t in T, i in P, r in R], RB[t,r] + sum(RI[t-1, r, m] for m in M) 
                        == sum(a[i,r]*x[i,p,t,c] for c in C, p in PM) + sum(RI[t,r,m] for m in M))

# Bounded inventory       
@constraint(mod, [m in M, t in T], sum(I[i, m, t, c] for i in P, c in C) + sum(RI[t, r, m] for t in T, r in R, m in M) <= ST[m])

# Bounded capacity 
@constraint(mod, [t in T, p in PM], sum(x[i, p, t , c] for i in P, c in C) <= PC[p]*y[p])

optimize!(mod)

x_df = convert_jump_container_to_df(x)
rename!(x_df, [:Product, :PM, :Period, :Customer, :Amount])
I_df = convert_jump_container_to_df(I)
rename!(I_df, [:Product, :Mill, :Period, :Customer, :Amount])
RB_df = convert_jump_container_to_df(RB)
rename!(RB_df, [:Period, :RawMaterial, :Amount])
RI_df = convert_jump_container_to_df(RI)
rename!(RI_df, [:Period, :RawMaterial, :Mill, :Amount])
y_df = convert_jump_container_to_df(y)
rename!(y_df, [:PM, :Running])

rm("results.xlsx")
XLSX.writetable("results.xlsx", "Production" => x_df, 
                                "Inventory" => I_df,
                                "RawMaterial" => RB_df,
                                "RawMaterialInventory" => RI_df,
                                "PMRunning" => y_df)