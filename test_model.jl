
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

#file = "stochastic_2cust_2mills.xlsx"

print("------------READING INPUT DATA------------\n")

file = "INPUT.xlsx"

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
Prb = df2param(data["Scenarios"])

# Sets 
A = unique(data["Contracts"].CONTRACTS)
M = unique(data["PM"].MILL)
PM = unique(data["PM"].PM)
P = unique(data["CustomerDemand"].PRODUCT)
R = unique(data["RawMaterialPrices"][!,"RAW MATERIAL"])
E = unique(data["EnergyCosts"].ENERGY)
C = unique(data["CustomerDemand"].CUSTOMER)
T = unique(data["CustomerDemand"].CALMONTH)
Scn = unique(data["Scenarios"].SCENARIO)
T_lag_fix = vcat([202100],T)
T_fd_fix = vcat(T, [202113, 202114, 202115])
# Mappings

Scn_no = length(Scn)
pm_mill = Dict(Pair.(data["PM"].PM, data["PM"].MILL))
mill_pm = invert_dict(pm_mill)
prod_mat = Dict()
prod_en = Dict()

for product in unique(data["RawMaterialConversion"].PRODUCT)
    prod_mat[product] = unique(filter(:PRODUCT => ==(product), data["RawMaterialConversion"])[!,"RAW MATERIAL"])
end
for product in unique(data["EnergyCosts"].PRODUCT)
    prod_en[product] = unique(filter(:PRODUCT => ==(product), data["EnergyCosts"])[!,"ENERGY"])
end
  

print("------------INPUT DATA READ DONE------------\n")

print("------------DEFINING MODEL------------\n")

# Model 
#big_m
bigM = 1000000
mod = Model(Gurobi.Optimizer)

# Decision Variables

# Integer decision variables

# Stage 1
@variable(mod, z[A, R, T, M], Bin)


# Stage 2
@variable(mod, y[PM, Scn], Bin)


# Cont. decision variables
@variable(mod, RC[A, R, T_fd_fix, M, Scn] >= 0) #raw material purchased by mill M under contract A at time t
# DACA contract ad-hoc variables
  
@variable(mod, daca[["d1","d2"],R, T, M, Scn] >= 0)  #how much raw material procured in each stage of contract. 
                                            #Here d1 means the higher price and then when we breach the limit d2 is amount received at lower price
# BULK contract contract variable
@variable(mod, rcost_bulk[R, T, M, Scn] >= 0)
# Fixed duration (FD) contract cost variable
@variable(mod, rcost_fd[R, T_fd_fix, M, Scn] >= 0)
@variable(mod, RI[T_lag_fix, R, M, Scn] >= 0) # raw material inventory
@variable(mod, x[P, PM, T, C, Scn] >= 0)
@variable(mod, I[P, M , T_lag_fix, C, Scn] >= 0)
@variable(mod, demand_slack[P, PM, T, C, Scn] >=0)

# Expressions
@expression(mod, rcost_f, sum(RP[t,r,s]*RC["FIXED",r, t, m, s]*Prb[s] for r in R, t in T, m in M,s in Scn))
@expression(mod, rcost_daca, sum((dacapr[t, "d1", r]*daca["d1", r, t,m, s] + dacapr[t, "d2", r]*daca["d2", r, t,m, s])*Prb[s] for r in R, t in T, m in M, s in Scn))
@expression(mod, sales, sum(PR[t,i]*(D[t,c,i, s]-sum(demand_slack[i,p,t,c,s] for p in PM))*Prb[s] for i in P, t in T, c in C, s in Scn))
@expression(mod, rcost, rcost_f + rcost_daca + sum(rcost_bulk[r,t,m, s]*Prb[s] for r in R, t in T, m in M, s in Scn) + sum(rcost_fd[r,t,m,s]*Prb[s] for r in R, t in T, s in Scn, m in M))
@expression(mod, icost, sum(SC[m]*I[i,m,t,c, s]*Prb[s] for m in M, i in P, t in T, c in C, s in Scn) + sum(SC[m]*RI[t,r,m, s]*Prb[s] for t in T, r in R, m in M, s in Scn ))
@expression(mod, lcost, sum(L[c,m]*x[i,p,t,c, s]*Prb[s] for i in P, p in PM, t in T, c in C, m in M, s in Scn))
@expression(mod, ecost, sum(sum(EC[t,pm_mill[p],i,r] for r in prod_en[i])*x[i,p,t,c,s]*Prb[s] for i in P, p in PM, t in T, c in C, s in Scn))
@expression(mod, onoff, sum((F[p]*y[p,s] + S[p]*(1-y[p,s]))*Prb[s] for p in PM, s in Scn))
@expression(mod, demand_penality,  sum(demand_slack[i,p,t,c, s]*Prb[s] for i in P, p in PM, t in T, c in C, m in M, s in Scn))

# Objective function
@objective(mod, Max, sales - rcost - icost - ecost - lcost - onoff - 100000*demand_penality)


# Constraints
#Contract Constraints
#Only one contract allowed
@constraint(mod, [t in T, r in R, m in M], sum(z[a, r, t, m] for a in A) <= 1)

#Only exercise active Contracts
@constraint(mod, [a in A, r in R, t in T, m in M, s in Scn], RC[a, r, t, m, s] <= bigM*z[a, r, t, m] )

#DACA
@constraint(mod, [r in R, t in T,m in M, s in Scn], RC["DACA", r, t, m, s] == daca["d1", r, t, m, s] + daca["d2", r, t, m, s])
@constraint(mod, daca1_1[r in R, t in T, m in M, s in Scn], daca["d1", r, t, m, s] <= dacalim[t,r])
@constraint(mod, daca1_2[r in R, t in T, m in M, s in Scn], daca["d2", r, t, m, s] == 0)
@constraint(mod, daca2_1[r in R, t in T, m in M, s in Scn], daca["d1", r, t, m, s] == dacalim[t,r])
@constraint(mod, daca2_2[r in R, t in T, m in M, s in Scn], 0 <= daca["d2", r, t, m, s])

#Add DACA contract disjunctions
for s in Scn
    for r in R
        for t in T
            for m in M
                local id = Symbol("daca_disjun_"*string(r)*string(t)*string(m))
                add_disjunction!(mod, (daca1_1[r,t,m,s], daca1_2[r,t,m,s]), (daca2_1[r,t,m,s], daca2_2[r,t,m,s]), reformulation=:big_m, name=id, M = bigM)
                @constraint(mod,  z["DACA", r, t, m] == mod[id][1] + mod[id][2])
            end
        end
    end
end

#BULK
@constraint(mod, bulk1_1[r in R, t in T, m in M, s in Scn], rcost_bulk[r,t,m, s] == bulkpr[t, "b1", r]*RC["BULK", r, t,m, s])
@constraint(mod, bulk1_2[r in R, t in T, m in M, s in Scn], 0 <= RC["BULK", r, t,m, s] <= bulklim[t, r] )
@constraint(mod, bulk2_1[r in R, t in T, m in M, s in Scn], rcost_bulk[r,t,m, s ] == bulkpr[t, "b2", r]*RC["BULK", r, t,m, s ])
@constraint(mod, bulk2_2[r in R, t in T, m in M, s in Scn], bulklim[t, r] <= RC["BULK", r, t, m, s] )

#Add BULK contract disjunctions
for s in Scn
    for r in R
        for t in T
            for m in M
                local id = Symbol("bulk_disjun_"*string(r)*string(t)*string(m))
                add_disjunction!(mod, (bulk1_1[r,t,m,s], bulk1_2[r,t,m,s]), (bulk2_1[r,t,m,s], bulk2_2[r,t,m,s]), reformulation=:big_m, name=id, M = bigM)
                @constraint(mod,  z["BULK", r, t, m] == mod[id][1] + mod[id][2])
            end
        end
    end
end

#FD
#1 month
@constraint(mod, fd1_1[r in R, t in T,m in M, s in Scn], rcost_fd[r,t,m,s] == fdpr[t,"l1",r]*RC["FD", r, t,m,s])
@constraint(mod, fd1_2[r in R, t in T,m in M, s in Scn], fdlim[t,"l1",r] <= RC["FD", r, t,m, s])
#2 month
@constraint(mod, fd2_1[r in R, t in T,m in M, s in Scn], rcost_fd[r,t,m,s] == fdpr[t,"l2", r]*RC["FD", r, t,m,s])
@constraint(mod, fd2_2[r in R, t in T,m in M, s in Scn], rcost_fd[r,t+1,m,s] == fdpr[t,"l2", r]*RC["FD", r, t+1,m,s])
@constraint(mod, fd2_3[r in R, t in T,m in M, s in Scn], fdlim[t,"l2", r] <= RC["FD", r, t,m, s] )
@constraint(mod, fd2_4[r in R, t in T,m in M, s in Scn], fdlim[t,"l2", r] <= RC["FD", r, t+1,m, s] )
# month
@constraint(mod, fd3_1[r in R, t in T,m in M, s in Scn], rcost_fd[r,t,m,s] == fdpr[t,"l3",r]*RC["FD", r, t,m,s])
@constraint(mod, fd3_2[r in R, t in T,m in M, s in Scn], rcost_fd[r,t+1,m,s] == fdpr[t,"l3",r]*RC["FD", r, t+1,m,s])
@constraint(mod, fd3_3[r in R, t in T,m in M, s in Scn], rcost_fd[r,t+2,m,s] == fdpr[t,"l3",r]*RC["FD", r, t+2,m,s])
@constraint(mod, fd3_4[r in R, t in T,m in M, s in Scn], fdlim[t,"l3",r] <= RC["FD", r, t,m,s])
@constraint(mod, fd3_5[r in R, t in T,m in M, s in Scn], fdlim[t,"l3",r] <= RC["FD", r, t+1,m,s])
@constraint(mod, fd3_6[r in R, t in T,m in M, s in Scn], fdlim[t,"l3",r] <= RC["FD", r, t+2,m,s])

for s in Scn
    for r in R
        for t in T
            for m in M
                local id = Symbol("fd_disjun_"*string(r)*string(t)*string(m))
                add_disjunction!(mod, 
                (fd1_1[r,t,m,s], fd1_2[r,t,m,s]),                                           #1 month 
                (fd2_1[r,t,m,s], fd2_2[r,t,m,s], fd2_3[r,t,m,s], fd2_4[r,t,m,s]),                        #2 month
                (fd3_1[r,t,m,s], fd3_2[r,t,m,s], fd3_3[r,t,m,s], fd3_4[r,t,m,s], fd3_5[r,t,m,s], fd3_6[r,t,m,s]), #3 month
                reformulation=:big_m, name=id, M = bigM)
                @constraint(mod,  z["FD", r, t, m] == mod[id][1] + mod[id][2] + mod[id][3] )
            end
        end
    end
end 


#Date fixes
@constraint(mod, [i in P, m in M,c in C, s in Scn], I[i, m, 202100, c, s] == 0)
@constraint(mod, [r in R, m in M, s in Scn], RI[202100, r, m, s] == 0)
@constraint(mod, [r in R, t in [202113, 202114, 202115], m in M, s in Scn], RC["FD", r, t, m, s] == 0)

# Demand satisfaction
@constraint(mod, [t in T, i in P, c in C, s in Scn], sum(x[i, p, t, c, s] for p in PM) + sum(I[i,m,t-1,c,s] for m in M) + sum(demand_slack[i,p,t,c,s] for p in PM) == D[t,c,i,s] + sum(I[i,m,t,c,s] for m in M) )

# Raw material balance
@constraint(mod, [t in T, i in P, r in R, m in M, s in Scn], sum(RC[a,r,t,m,s] for a in A) + RI[t-1, r, m, s] == a[i, r]*sum(x[i, p, t, c, s] for c in C, p in mill_pm[m]) + RI[t, r, m, s])

# Bounded inventory       
@constraint(mod, [m in M, t in T, s in Scn], sum(I[i, m, t, c, s] for i in P, c in C) + sum(RI[t, r, m, s] for r in R, m in M) <= ST[m])

# Bounded capacity 
@constraint(mod, [t in T, p in PM, s in Scn], sum(x[i, p, t , c, s] for i in P, c in C) <= PC[p]*y[p,s])

print("------------DEFINING MODEL DONE------------\n")

print("------------OPT START------------\n")
optimize!(mod)
print("------------OPT DONE------------\n")
x_df = convert_jump_container_to_df(x)
#rename!(x_df, [:Product, :PM, :Period, :Customer, :Amount])
I_df = convert_jump_container_to_df(I)
#rename!(I_df, [:Product, :Mill, :Period, :Customer, :Amount])
RI_df = convert_jump_container_to_df(RI)
#rename!(RI_df, [:Period, :RawMaterial, :Mill, :Amount])
y_df = convert_jump_container_to_df(y)
#rename!(y_df, [:PM, :Running])
z_df = convert_jump_container_to_df(z)
#rename!(z_df, [:Contract, :RawMaterial, :Period, :Used])
rc_df = convert_jump_container_to_df(RC)
#rename!(rc_df, [:Contract, :RawMaterial, :Period, :Amount])
rcost_fd_df = convert_jump_container_to_df(rcost_fd)
#rename!(rcost_fd_df, [:RawMaterial, :Period, :Amount])
demand_slack_df = convert_jump_container_to_df(demand_slack)


print("------------RESULTS WRITING------------\n")

rm("RESULTS.xlsx")
XLSX.writetable("RESULTS.xlsx", "Production" => x_df, 
                                "Inventory" => I_df,
                                "RawMaterialInventory" => RI_df,
                                "PMRunning" => y_df,
                                "Contracts" => z_df,
                                "RawMaterialContract" => rc_df,
                                "RawMaterialPrices" => data["RawMaterialPrices"],
                                "RawMaterialCosts_FD" => rcost_fd_df,
                                "DemandSlack" => demand_slack_df,
                                )

print("------------ALL DONE------------\n")