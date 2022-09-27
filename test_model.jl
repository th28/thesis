
# Basic production model to build off
# Tom H 
using JuMP
using GLPK
using HiGHS
using Gurobi
using DataFrames
using XLSX
using DisjunctiveProgramming

include("utility.jl")

file = "deterministic_2cust_2mills.xlsx"

xf = XLSX.readxlsx(file)
sheet_names = XLSX.sheetnames(xf)
data = Dict()

for sheet in sheet_names 
    data[sheet] = DataFrame(XLSX.readtable(file, sheet)...)
end

# Parameters
fdlim = df2param(data["FD_limits"])
fdpr = df2param(data["FD_prices"])
dacalim = df2param(data["DACA_limits"])
dacapr = df2param(data["DACA_prices"])
bulklim = df2param(data["BULK_limits"])
bulkpr = df2param(data["BULK_prices"])
a = df2param(data["RawMaterialConversion"])
RP = df2param(data["RawMaterialPrices"]) #market rate prices used in fixed price contracts
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
T_fd_fix = vcat(T, [202213, 202214, 202215])
# Mappings



pm_mill = Dict(Pair.(data["PM"].PM, data["PM"].MILL))
prod_mat = Dict()
prod_en = Dict()

for product in unique(data["RawMaterialConversion"].PRODUCT)
    prod_mat[product] = unique(filter(:PRODUCT => ==(product), data["RawMaterialConversion"])[!,"RAW MATERIAL"])
end
for product in unique(data["EnergyCosts"].PRODUCT)
    prod_en[product] = unique(filter(:PRODUCT => ==(product), data["EnergyCosts"])[!,"ENERGY"])
end

# Model 
#big_m
bigM = 1000000
mod = Model(Gurobi.Optimizer)

# Decision Variables

# Integer decision variables
@variable(mod, z[A, R, T], Bin)
@variable(mod, y[PM], Bin)


# Cont. decision variables
@variable(mod, RC[A,R, T_fd_fix] >= 0)
# DACA contract ad-hoc variables
@variable(mod, daca[["d1","d2"],R, T] >= 0)  #how much raw material procured in each stage of contract. 
                                             #Here d1 means the higher price and then when we breach the limit d2 is amount received at lower price
# BULK contract contract variable
@variable(mod, rcost_bulk[R, T] >= 0)
# Fixed duration (FD) contract cost variable
@variable(mod, rcost_fd[R, T_fd_fix] >= 0)


@variable(mod, RB[T,R] >= 0) # raw material purchased at time T
@variable(mod, RI[T_lag_fix, R, M] >= 0) # raw material inventory
@variable(mod, x[P, PM, T, C] >= 0)
@variable(mod, I[P, M , T_lag_fix, C] >= 0)

@expression(mod, rcost_f, sum(RP[t,r]*RC["FIXED",r, t] for r in R, t in T))
@expression(mod, rcost_daca, sum(dacapr[t, "d1", r]*daca["d1", r, t] + dacapr[t, "d2", r]*daca["d2", r, t] for r in R, t in T))
@expression(mod, sales, sum(PR[t,i]*D[t,c,i] for i in P, t in T, c in C))
@expression(mod, rcost, rcost_f + rcost_daca + sum(rcost_bulk[r,t] for r in R, t in T) + sum(rcost_fd[r,t] for r in R, t in T))
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
#@constraint(mod,  z["FD", "R1", 202203] == 1)
#Only exercise active Contracts
@constraint(mod, [a in A, r in R, t in T], RC[a, r, t] <= bigM*z[a, r, t] )
#Aggregate raw material purchases
@constraint(mod, [t in T, r in R], RB[t,r] == sum(RC[a, r, t] for a in A))

#DACA
@constraint(mod, [r in R, t in T], RC["DACA", r, t] == daca["d1", r, t] + daca["d2", r, t])
@constraint(mod, daca1_1[r in R, t in T], daca["d1", r, t] <= dacalim[t,r])
@constraint(mod, daca1_2[r in R, t in T], daca["d2", r, t] == 0)
@constraint(mod, daca2_1[r in R, t in T], daca["d1", r, t] == dacalim[t,r])
@constraint(mod, daca2_2[r in R, t in T], 0 <= daca["d2", r, t])

#Add DACA contract disjunctions
for r in R
    for t in T
        local id = Symbol("daca_disjun_"*string(r)*string(t))
        add_disjunction!(mod, (daca1_1[r,t], daca1_2[r,t]), (daca2_1[r,t], daca2_2[r,t]), reformulation=:big_m, name=id, M = bigM)
        @constraint(mod,  z["DACA", r, t] == mod[id][1] + mod[id][2])
    end
end

#BULK
@constraint(mod, bulk1_1[r in R, t in T], rcost_bulk[r,t] == bulkpr[t, "b1", r]*RC["BULK", r, t])
@constraint(mod, bulk1_2[r in R, t in T], 0 <= RC["BULK", r, t] <= bulklim[t, r] )
@constraint(mod, bulk2_1[r in R, t in T], rcost_bulk[r,t] == bulkpr[t, "b2", r]*RC["BULK", r, t])
@constraint(mod, bulk2_2[r in R, t in T], bulklim[t, r] <= RC["BULK", r, t] )

#Add BULK contract disjunctions
for r in R
    for t in T
        local id = Symbol("bulk_disjun_"*string(r)*string(t))
        add_disjunction!(mod, (bulk1_1[r,t], bulk1_2[r,t]), (bulk2_1[r,t], bulk2_2[r,t]), reformulation=:big_m, name=id, M = bigM)
        @constraint(mod,  z["BULK", r, t] == mod[id][1] + mod[id][2])
    end
end

#FD
#1 month
@constraint(mod, fd1_1[r in R, t in T], rcost_fd[r,t] == fdpr[t,"l1",r]*RC["FD", r, t])
@constraint(mod, fd1_2[r in R, t in T], fdlim[t,"l1",r] <= RC["FD", r, t])
#2 month
@constraint(mod, fd2_1[r in R, t in T], rcost_fd[r,t] == fdpr[t,"l2", r]*RC["FD", r, t])
@constraint(mod, fd2_2[r in R, t in T], rcost_fd[r,t+1] == fdpr[t,"l2", r]*RC["FD", r, t+1])
@constraint(mod, fd2_3[r in R, t in T], fdlim[t,"l2", r] <= RC["FD", r, t] )
@constraint(mod, fd2_4[r in R, t in T], fdlim[t,"l2", r] <= RC["FD", r, t+1] )
# month
@constraint(mod, fd3_1[r in R, t in T], rcost_fd[r,t] == fdpr[t,"l3",r]*RC["FD", r, t])
@constraint(mod, fd3_2[r in R, t in T], rcost_fd[r,t+1] == fdpr[t,"l3",r]*RC["FD", r, t+1])
@constraint(mod, fd3_3[r in R, t in T], rcost_fd[r,t+2] == fdpr[t,"l3",r]*RC["FD", r, t+2])
@constraint(mod, fd3_4[r in R, t in T], fdlim[t,"l3",r] <= RC["FD", r, t])
@constraint(mod, fd3_5[r in R, t in T], fdlim[t,"l3",r] <= RC["FD", r, t+1])
@constraint(mod, fd3_6[r in R, t in T], fdlim[t,"l3",r] <= RC["FD", r, t+2])

for r in R
    for t in T
        local id = Symbol("fd_disjun_"*string(r)*string(t))
        add_disjunction!(mod, 
        (fd1_1[r,t], fd1_2[r,t]),                                           #1 month 
        (fd2_1[r,t], fd2_2[r,t], fd2_3[r,t], fd2_4),                        #2 month
        (fd3_1[r,t], fd3_2[r,t], fd3_3[r,t], fd3_4[r,t], fd3_5[r,t], fd3_6[r,t]), #3 month
        reformulation=:big_m, name=id, M = bigM)
        @constraint(mod,  z["FD", r, t] == mod[id][1] + mod[id][2] + mod[id][3] )
    end
end



#Date fixes
@constraint(mod, [i in P, m in M,c in C], I[i, m, 202200, c] == 0)
@constraint(mod, [r in R, m in M], RI[202200, r, m] == 0)
@constraint(mod, [r in R, t in [202213, 202214, 202215]], RC["FD", r, t] == 0)

# Demand satisfaction
@constraint(mod, [t in T, i in P, c in C], sum(x[i, p, t, c] for p in PM) + sum(I[i,m,t-1,c] for m in M) == D[t,c,i] + sum(I[i,m,t,c] for m in M))

# Raw material balance
@constraint(mod, [t in T, i in P, r in R], RB[t,r] + sum(RI[t-1, r, m] for m in M) 
                        == sum(a[i,r]*x[i,p,t,c] for c in C, p in PM) + sum(RI[t,r,m] for m in M))

# Bounded inventory       
@constraint(mod, [m in M, t in T], sum(I[i, m, t, c] for i in P, c in C) + sum(RI[t, r, m] for t in T, r in R, m in M) <= ST[m])

# Bounded capacity 
@constraint(mod, [t in T, p in PM], sum(x[i, p, t , c] for i in P, c in C) <= PC[p]*y[p])

print("------------OPT START------------\n")
optimize!(mod)
print("------------OPT END------------\n")
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
z_df = convert_jump_container_to_df(z)
rename!(z_df, [:Contract, :RawMaterial, :Period, :Used])
rc_df = convert_jump_container_to_df(RC)
rename!(rc_df, [:Contract, :RawMaterial, :Period, :Amount])
rcost_fd_df = convert_jump_container_to_df(rcost_fd)
rename!(rcost_fd_df, [:RawMaterial, :Period, :Amount])

rm("results.xlsx")
XLSX.writetable("results.xlsx", "Production" => x_df, 
                                "Inventory" => I_df,
                                "RawMaterial" => RB_df,
                                "RawMaterialInventory" => RI_df,
                                "PMRunning" => y_df,
                                "Contracts" => z_df,
                                "RawMaterialContract" => rc_df,
                                "RawMaterialPrices" => data["RawMaterialPrices"],
                                "RawMaterialCosts_FD" => rcost_fd_df)

print("------------DONE------------\n")