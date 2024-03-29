
# A basic production planning model using disjunctive programming to model raw material contracts
# Tom H 
using JuMP
using GLPK
using HiGHS
using Gurobi
using DataFrames
using XLSX
using DisjunctiveProgramming
using Formatting

include("utility.jl")

print("------------READING INPUT DATA------------\n")

function run_model(input_file, output_file, vss_flag, scenario, no_contracts)
    data = xl_to_df(input_file)

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
    PC = df2param(data["Capacity"])
    L = df2param(data["LogisticCosts"])
    SC = df2param(data["StorageCosts"])
    ST = df2param(data["StorageCapacities"])
    PR = df2param(data["Prices"])
    Prb = df2param(data["Scenarios"])
    


    # Sets 
    A = unique(data["Contracts"].CONTRACTS)
    M = unique(data["PM"].MILL)
    PM = unique(data["PM"].PM)
    P = unique(data["CustomerDemand"].PRODUCT)
    R = unique(data["RawMaterialPrices"][!,"RAW MATERIAL"])
    C = unique(data["CustomerDemand"].CUSTOMER)
    T = unique(data["CustomerDemand"].CALMONTH)
    Scn = unique(data["Scenarios"].SCENARIO)

    if scenario != "All"
        for scn in Scn
            if scn == scenario
                Prb[scn] = 1
            else
                Prb[scn] = 0
            end
        end
    end


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
    calc_vss = vss_flag
    bigM = 100000
    mod = Model(Gurobi.Optimizer)
    set_optimizer_attribute(mod, "OutputFlag",0)
    set_optimizer_attribute(mod, "LogToConsole",0)


    # Decision Variables

    # Integer decision variables

    # Stage 1
    @variable(mod, z[A, R, T_fd_fix, M], Bin)
    @variable(mod, slack2_1[R,T_fd_fix,M], Bin)
    @variable(mod, slack3_1[R,T_fd_fix,M], Bin)
    @variable(mod, slack3_2[R,T_fd_fix,M], Bin)


    # Stage 2

    # Cont. decision variables
    @variable(mod,  RC[A, R, T_fd_fix, M, Scn] >= 0) #raw material purchased by mill M under contract A at time t
    # DACA contract ad-hoc variables

    @variable(mod,  daca[["d1","d2"],R, T, M, Scn] >= 0)  #how much raw material procured in each stage of contract. 
                                                #Here d1 means the higher price and then when we breach the limit d2 is amount received at lower price
    # BULK contract contract variable
    @variable(mod,  rcost_bulk[R, T, M, Scn] >= 0)
    # Fixed duration (FD) contract cost variable

    @variable(mod,  RI[T_lag_fix, R, M, Scn] >= 0) # raw material inventory
    @variable(mod, x[P, PM, T, C, Scn] >= 0)
    @variable(mod, d[T, PM, P, C, Scn] >= 0) #D[t,c,i,s]
    @variable(mod, I[P, M , T_lag_fix, C, Scn] >= 0)
    @variable(mod, demand_slack[P, PM, T, C, Scn] >=0)
    @variable(mod, fd_cost_tot>=0)
    @variable(mod, rcost_fd[R, T_fd_fix, M, Scn] >= 0)


    # Expressions
    @expression(mod, rcost_f, sum(RP[t,r,s]*RC["FIXED",r, t, m, s]*Prb[s] for r in R, t in T, m in M,s in Scn))
    @expression(mod, rcost_daca, sum((dacapr[t, "d1", r]*daca["d1", r, t,m, s] + dacapr[t, "d2", r]*daca["d2", r, t,m, s])*Prb[s] for r in R, t in T, m in M, s in Scn))
    @expression(mod, sales, sum(PR[t,i]*(D[t,c,i, s]-sum(demand_slack[i,p,t,c,s] for p in PM))*Prb[s] for i in P, t in T, c in C, s in Scn))
    @expression(mod, rcost, rcost_f + rcost_daca + sum(rcost_bulk[r,t,m, s]*Prb[s] for r in R, t in T, m in M, s in Scn) + sum(rcost_fd[r,t,m,s]*Prb[s] for r in R, t in T, s in Scn, m in M))
    @expression(mod, icost, sum(SC[m]*I[i,m,t,c, s]*Prb[s] for m in M, i in P, t in T, c in C, s in Scn) + sum(SC[m]*RI[t,r,m, s]*Prb[s] for t in T, r in R, m in M, s in Scn ))
    @expression(mod, lcost, sum(L[c,m]*x[i,p,t,c, s]*Prb[s] for i in P, p in PM, t in T, c in C, m in M, s in Scn))

    # Objective function
    @objective(mod, Max, sales - rcost - icost - lcost)

    # Constraints

    if calc_vss == true
        runid = replace(split(input_file, "_")[2], ".xlsx" => "")

        det_data = xl_to_df("RESULTS_"*runid*"_det.xlsx") #results of deterministic run, we need to extract first stage decisions
        contract = df2param(det_data["Contracts"])
        #fix the first stage decisions to be the contract decisions in the deterministic problem when averages are used for the stochastic
        @constraint(mod, [a in A, t in T, r in R, m in M], z[a, r,t, m] == contract[a, r, t, m]) 
    end

    if no_contracts == true
        @constraint(mod, [t in T, r in R, m in M], z["FIXED", r, t, m] == 1)
    end
    # Contract Constraints
    # Only one contract allowed
    @constraint(mod, [t in T, r in R, m in M], sum(z[a, r, t, m] for a in A) <= 1)
    # Only exercise active Contracts
    @constraint(mod, [a in A, r in R, t in T, m in M, s in Scn], RC[a, r, t, m, s] <= bigM*z[a, r, t, m] )



    # DACA
    @constraint(mod, [r in R, t in T,m in M, s in Scn], RC["DACA", r, t, m, s] == daca["d1", r, t, m, s] + daca["d2", r, t, m, s])
    @constraint(mod, daca1_1[r in R, t in T, m in M, s in Scn], daca["d1", r, t, m, s] <= dacalim[t,r])
    @constraint(mod, daca1_2[r in R, t in T, m in M, s in Scn], daca["d2", r, t, m, s] == 0)
    @constraint(mod, daca2_1[r in R, t in T, m in M, s in Scn], daca["d1", r, t, m, s] == dacalim[t,r])
    @constraint(mod, daca2_2[r in R, t in T, m in M, s in Scn], 0 <= daca["d2", r, t, m, s])

    # Add DACA contract disjunctions
    for s in Scn
        for r in R
            for t in T
                for m in M
                    local id = Symbol("daca_disjun_"*string(r)*string(t)*string(m))
                    add_disjunction!(mod, (daca1_1[r,t,m,s], daca1_2[r,t,m,s]), (daca2_1[r,t,m,s], daca2_2[r,t,m,s]), reformulation=:big_m, name=id, M=bigM)
                    @constraint(mod,  z["DACA", r, t, m] == mod[id][1] + mod[id][2])
                end
            end
        end
    end

    # BULK
    @constraint(mod, bulk1_1[r in R, t in T, m in M, s in Scn], rcost_bulk[r,t,m, s] == bulkpr[t, "b1", r]*RC["BULK", r, t,m, s])
    @constraint(mod, bulk1_2[r in R, t in T, m in M, s in Scn], 0 <= RC["BULK", r, t,m, s] <= bulklim[t, r] )
    @constraint(mod, bulk2_1[r in R, t in T, m in M, s in Scn], rcost_bulk[r,t,m, s ] == bulkpr[t, "b2", r]*RC["BULK", r, t,m, s ])
    @constraint(mod, bulk2_2[r in R, t in T, m in M, s in Scn], bulklim[t, r] <= RC["BULK", r, t, m, s] )

    # Add BULK contract disjunctions
    for s in Scn
        for r in R
            for t in T
                for m in M
                    local id = Symbol("bulk_disjun_"*string(r)*string(t)*string(m))
                    add_disjunction!(mod, (bulk1_1[r,t,m,s], bulk1_2[r,t,m,s]), (bulk2_1[r,t,m,s], bulk2_2[r,t,m,s]), reformulation=:big_m, name=id, M=bigM)
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
    #3 month
    @constraint(mod, fd3_1[r in R, t in T,m in M, s in Scn], rcost_fd[r,t,m,s] == fdpr[t,"l3",r]*RC["FD", r, t,m,s])
    @constraint(mod, fd3_2[r in R, t in T,m in M, s in Scn], rcost_fd[r,t+1,m,s] == fdpr[t,"l3",r]*RC["FD", r, t+1,m,s])
    @constraint(mod, fd3_3[r in R, t in T,m in M, s in Scn], rcost_fd[r,t+2,m,s] == fdpr[t,"l3",r]*RC["FD", r, t+2,m,s])
    @constraint(mod, fd3_4[r in R, t in T,m in M, s in Scn], fdlim[t,"l3",r] <= RC["FD", r, t,m,s])
    @constraint(mod, fd3_5[r in R, t in T,m in M, s in Scn], fdlim[t,"l3",r] <= RC["FD", r, t+1,m,s])
    @constraint(mod, fd3_6[r in R, t in T,m in M, s in Scn], fdlim[t,"l3",r] <= RC["FD", r, t+2,m,s])


    # If choose a 2 month or 3 month length contract, the contract type for the raw material is already decided for those months
    # E.g if at time t we choose a 3 month contract, then the contract type for t+1 and t+2 must be fixed as FD since we are locked into that contract by definition

    for s in Scn
        for r in R
            for t in T
                for m in M
                    local id = Symbol("fd_disjun_"*string(r)*string(t)*string(m))
                    add_disjunction!(mod, 
                    (fd1_1[r,t,m,s], fd1_2[r,t,m,s]),                                           #1 month 
                    (fd2_1[r,t,m,s], fd2_2[r,t,m,s], fd2_3[r,t,m,s], fd2_4[r,t,m,s]),                        #2 month
                    (fd3_1[r,t,m,s], fd3_2[r,t,m,s], fd3_3[r,t,m,s], fd3_4[r,t,m,s], fd3_5[r,t,m,s], fd3_6[r,t,m,s]), #3 month
                    reformulation=:big_m, name=id, M=bigM)
                    
                end
            end
        end
    end 

    @constraint(mod, [r in R, t in T, m in M],  z["FD", r, t, m] == slack2_1[r,t,m] + slack3_1[r,t,m] + slack3_2[r,t,m] + mod[Symbol("fd_disjun_"*string(r)*string(t)*string(m))][1] + mod[Symbol("fd_disjun_"*string(r)*string(t)*string(m))][2] + mod[Symbol("fd_disjun_"*string(r)*string(t)*string(m))][3] )

    @constraint(mod, [r in R, t in T[2:end], m in M], slack2_1[r,t,m] == mod[Symbol("fd_disjun_"*string(r)*string(t-1)*string(m))][2])
    @constraint(mod, [r in R, t in T[2:end], m in M], slack3_1[r,t,m] == mod[Symbol("fd_disjun_"*string(r)*string(t-1)*string(m))][3])
    @constraint(mod, [r in R, t in T[3:end], m in M], slack3_2[r,t,m] == mod[Symbol("fd_disjun_"*string(r)*string(t-2)*string(m))][3])

    @constraint(mod, [r in R, t in [202101, 202102, 202113, 202114, 202115], m in M], slack3_2[r,t,m] == 0)
    @constraint(mod, [r in R, t in [202101, 202113, 202114, 202115], m in M], slack3_1[r,t,m] == 0)
    @constraint(mod, [r in R, t in [202101, 202113, 202114, 202115], m in M], slack2_1[r,t,m] == 0)
    
    # Date fixes
    @constraint(mod, [i in P, m in M,c in C, s in Scn], I[i, m, 202100, c, s] == 0)
    @constraint(mod, [r in R, m in M, s in Scn], RI[202100, r, m, s] == 0)
    @constraint(mod, [r in R, t in [202113, 202114, 202115], m in M, s in Scn], RC["FD", r, t, m, s] == 0)

    # Demand allocation, total demand for product i is allocated to PMs
    @constraint(mod, [t in T, i in P, c in C, s in Scn], sum(d[t, p, i, c, s] for p in PM) == D[t,c,i,s])

    # Demand satisfaction, the demand slack indicates demand we could not fulfill. 
    @constraint(mod, [t in T, i in P, c in C, s in Scn, p in PM], x[i, p, t, c, s] + I[i, pm_mill[p], t-1 , c, s] + demand_slack[i, p, t, c, s] == d[t, p, i, c, s] + I[i, pm_mill[p], t, c, s] )

    # If we want to produce product i, with certain raw materials, we must have those on hand either by buying or in our raw material inventory 
    @constraint(mod, rbal[t in T, r in R, m in M, s in Scn], sum(RC[a,r,t,m,s] for a in A) + RI[t-1,r,m,s] == sum(a[i,r]*x[i, p, t, c, s] for c in C, i in P, p in mill_pm[m]) + RI[t,r,m,s] )

    # Bounded inventory
    @constraint(mod, [m in M, t in T, s in Scn], sum(I[i, m, t, c, s] for i in P, c in C) + sum(RI[t, r, m, s] for r in R, m in M) <= ST[m])

    # Bounded capacity 
    @constraint(mod, [t in T, p in PM, s in Scn], sum(x[i, p, t , c, s] for i in P, c in C) <= PC[p])

    print("------------DEFINING MODEL DONE------------\n")
    write_to_file(mod,"mylp.lp")
    print("------------OPT START------------\n")
    set_optimizer_attribute(mod, "MIPFocus", 2)
    set_optimizer_attribute(mod, "MIPGap", 0.0005)
    
    optimize!(mod)
    print("------------OPT DONE------------\n")
    x_df = convert_jump_container_to_df(x)
    rename!(x_df, [:Product, :PM, :Period, :Customer, :Scenario, :Amount])
    I_df = convert_jump_container_to_df(I)
    rename!(I_df, [:Product, :Mill, :Period, :Customer, :Scenario, :Amount])
    RI_df = convert_jump_container_to_df(RI)
    rename!(RI_df, [:Period, :RawMaterial, :Mill, :Scenario, :Amount])
    z_df = convert_jump_container_to_df(z)
    rename!(z_df, [:Contract, :RawMaterial, :Period, :Mill, :Used])
    rc_df = convert_jump_container_to_df(RC)
    rename!(rc_df, [:Contract, :RawMaterial, :Period, :Mill, :Scenario, :Amount])
    rcosts_fd_df = convert_jump_container_to_df(rcost_fd)
    rename!(rcosts_fd_df, [:RawMaterial, :Period, :Mill, :Scenario, :Amount])
    slack32_df = convert_jump_container_to_df(slack3_2)
    rename!(slack32_df, [:RawMaterial, :Period, :Mill, :Amount])
    slack31_df = convert_jump_container_to_df(slack3_1)
    rename!(slack31_df, [:RawMaterial, :Period, :Mill, :Amount])
    slack21_df = convert_jump_container_to_df(slack2_1)
    rename!(slack21_df, [:RawMaterial, :Period, :Mill, :Amount])

    
    print("------------RESULTS WRITING------------\n")

    

    if isfile(output_file) == true
        rm(output_file)
    end 

    XLSX.writetable(output_file, "Production" => x_df, 
                                    "Inventory" => I_df,
                                    "RawMaterialInventory" => RI_df,
                                    "Contracts" => z_df,
                                    "RawMaterialContract" => rc_df,
                                    "RawMaterialPrices" => data["RawMaterialPrices"],
                                    "FD_Costs" => rcosts_fd_df,
                                    "Slack32" => slack32_df,
                                    "Slack31" => slack31_df,
                                    "Slack21" => slack21_df
                                    )
    #write_to_file(mod,"mylp.lp")
    print("------------ALL DONE------------\n")
    return objective_value(mod), rc_df
end


stoc = false
det_basic = true

if stoc == true
    columnnames = ["Instance", "RP","EV", "VSS","VSS Pct. Chg","EVPI","EVPI Pct. Chg"]
    stats = DataFrame([name => [] for name in columnnames])
    for i in 0:9

        

        print("Solving determinstic case \n")

        run_model("INPUT_"*string(i)*"_det.xlsx", "RESULTS_"*string(i)*"_det.xlsx", false, "All", false)

        print("Solving expected value problem (EV) \n")

        ev, _ = run_model("INPUT_"*string(i)*".xlsx", "RESULTS_"*string(i)*".xlsx", true, "All", false)

        print("Solving stochastic problem (RP)\n")

        rp, _ = run_model("INPUT_"*string(i)*".xlsx", "RESULTS_"*string(i)*".xlsx", false, "All", false)

        print("EVPI calculation")

        data = xl_to_df("INPUT_"*string(i)*".xlsx")
        Scn = unique(data["Scenarios"].SCENARIO)

        objs = []
        for scn in Scn
            obj, _ = run_model("INPUT_"*string(i)*".xlsx", "RESULTS_"*string(i)*".xlsx", false, scn, false)
            push!(objs, obj)
        end

        objs_pr = objs .* (1/length(objs))
        evpi_ev = sum(objs_pr)
        EVPI = evpi_ev - rp

        print("\n")
        print("-----------STATS----------\n")
        print("\n")
        print("RP: "*string(round(rp,digits=2))*"\n")
        print("EV: "*string(round(ev,digits=2))*"\n")
        print("VSS: "*string(round(rp - ev,digits=2))*"\n")
        pct_chg = ((rp - ev)/ev)*100
        print("Percentage change: "*string(round(pct_chg,digits=2))*" %"*"\n")
        print("EVPI: "*string(round(EVPI,digits=2))*"\n")
        print("Percentage change: "*string(round(EVPI/evpi_ev,digits=2))*" %"*"\n")
        print("Objectives:\n"*string(objs))


        row = (i, round(rp,digits=2), round(ev,digits=2), round(rp - ev,digits=2), round(pct_chg,digits=2), round(EVPI,digits=2), round(EVPI/evpi_ev,digits=2))
        push!(stats, row)
    end

    if isfile("STATS_stoc.xlsx") == true
        rm("STATS_stoc.xlsx")
    end 

    XLSX.writetable("STATS_stoc.xlsx", "STATS"=> stats)

elseif det_basic == true
    # Define the column names
    columnnames = ["Instance", "Obj. value","Runtime (min)", "BULK","DACA","FD","FIXED"]
    stats = DataFrame([name => [] for name in columnnames])

    for i in 0:9
        print("Solving instance: "*string(i)*"\n")
        t1 = time_ns()
        obj, rc_df = run_model("INPUT_"*string(i)*".xlsx", "RESULTS_"*string(i)*".xlsx", false, "All", false)
        t2 = time_ns()
        rt = string(round((1/60.0)*(t2-t1)/1000000000,digits=2))
        print("Objective function: "*string(format(round(obj,digits=2)))*"\n")
        print("Runtime: "*rt*"\n")

        result = combine(groupby(rc_df, :Contract), :Amount => (col -> sum(col) / sum(rc_df."Amount") * 100) => :PERCENTAGE)
        sort!(result, :Contract)
        pcts = result."PERCENTAGE"

        row = (i, obj, rt, pcts...)
        push!(stats, row)

        println(result)

    end

    if isfile("STATS.xlsx") == true
        rm("STATS.xlsx")
    end 

    XLSX.writetable("STATS.xlsx", "STATS"=> stats)

else
    # Define the column names
    columnnames = ["Instance", "Obj. value (contracts)", "Obj. value (no contracts)", "Pct. chg" ]
    stats = DataFrame([name => [] for name in columnnames])

    for i in 0:9
        print("Solving instance: "*string(i)*"\n")
     
        obj, rc_df = run_model("INPUT_"*string(i)*".xlsx", "RESULTS_"*string(i)*".xlsx", false, "All", false)
        obj_f, rc_df = run_model("INPUT_"*string(i)*".xlsx", "RESULTS_"*string(i)*".xlsx", false, "All", true)

        print("Objective function: "*string(format(round(obj,digits=2)))*"\n")

        chg = round(((obj - obj_f)/obj_f)*100,digits=1)
        print("Pct chg: "*string(chg)*" %\n")
        row = (i, obj, obj_f, chg)
        push!(stats, row)

       

    end

    if isfile("STATS_impact.xlsx") == true
        rm("STATS_impact.xlsx")
    end 

    XLSX.writetable("STATS.xlsx", "STATS"=> stats)

end




