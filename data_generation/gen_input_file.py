#Generate optimization scenarios 
import warnings
warnings.simplefilter(action='ignore', category=FutureWarning)
import pandas as pd
import random 
import time

sheets = [
    'FixedCosts',
    'RawMaterialConversion',
    'RawMaterialPrices',
    'ShutdownCosts',
    'Capacity',
    'LogisitcCosts',
    'StorageCapacities',
    'StorageCosts',
    'Prices',
    'EnergyCosts'
]

#parameters
pm_ct = 4
mill_ct = pm_ct
scn_ct = 3
cust_ct = 10
prod_ct = 4
e_ct = 4
raw_mat_ct = 5
raw_materials = ["R"+str(i) for i in range(raw_mat_ct)]
pms  = ["PM"+str(i) for i in range(pm_ct)]
customers = ["C"+str(i) for i in range(cust_ct)]
prods = ["P"+str(i) for i in range(prod_ct)]
calmonths = [i + 202201 for i in range(12)]
scns = ["S"+str(i) for i in range(scn_ct)]
mills = ["M"+str(i) for i in range(mill_ct)]
energy_comps = ["E"+str(i) for i in range(e_ct)]

input_file = {}

def gen_scenarios_tab(scn_ct):

    prb = 1.0/float(scn_ct)

    df = pd.DataFrame(columns=["SCENARIO","METRIC"])

    for i in range(scn_ct):
        row = {"SCENARIO": "S"+str(i+1), "METRIC": prb}
        df = df.append(row, ignore_index=True)

    return df

#print(gen_scenarios_tab(40))

def gen_contracts():

    df = pd.DataFrame(["FIXED","DACA","BULK","FD"],columns=["CONTRACTS"])
    return df

#print(gen_contracts())

def gen_limits_prices(raw_materials, contract_stages):
    if contract_stages == "no_stages":
        df = pd.DataFrame(columns=["CALMONTH", "RAW MATERIAL", "METRIC"])
        for r in raw_materials:
            for m in calmonths:
                lim = random.random()*100 + 1
                row  = {"CALMONTH":m, "RAW MATERIAL": r, "METRIC": lim}
                df = df.append(row, ignore_index=True)

        return df
    else:
        df = pd.DataFrame(columns=["CALMONTH", "TYPE", "RAW MATERIAL", "METRIC"])
        for r in raw_materials:
            for c in contract_stages:
                for m in calmonths:
                    lim = random.random()*100 + 1
                    row  = {"CALMONTH":m, "TYPE": c, "RAW MATERIAL": r, "METRIC": lim}
                    df = df.append(row, ignore_index=True)

        return df
    
#print(gen_limits_prices(raw_materials, contract_stages = "no_stages"))

def gen_pms_tab(pm_ct):
    df = pd.DataFrame(columns=["MILL","PM"])
    for pm in range(pm_ct):
        row = {"MILL": "M"+str(pm), "PM":"PM"+str(pm)}
        df = df.append(row, ignore_index=True)
    
    return df

#print(gen_pms_tab(pm_ct))

def gen_cust_dem_tab():
    df = pd.DataFrame(columns=["CALMONTH", "CUSTOMER", "PRODUCT", "SCENARIO", "METRIC"])
    for c in customers:
        for m in calmonths:
            for p in prods:
                for s in scns:
                    demand = random.random()*100 + 1
                    row = {"CALMONTH": m, "CUSTOMER":c, "PRODUCT":p, "SCENARIO":s, "METRIC": demand}
                    df = df.append(row, ignore_index=True)
    
    return df

#print(gen_cust_dem_tab())

def gen_fixed_costs():
    df = pd.DataFrame(columns=["PM","METRIC"])
    for p in pms:
        row = {"PM": p, "METRIC": 500*random.random()+10000.0}
        df = df.append(row, ignore_index=True)
    
    return df

#print(gen_fixed_costs())

def gen_raw_mat_conv():
    df = pd.DataFrame(columns=["PRODUCT", "RAW MATERIAL", "METRIC"])
    for p in prods:
        for r in raw_materials:
            row = {"PRODUCT": p, "RAW MATERIAL": r, "METRIC": random.random()}
            df = df.append(row, ignore_index=True)

    return df


def gen_raw_mat_prices():
    df = pd.DataFrame(columns=["CALMONTH", "RAW MATERIAL", "METRIC"])
    for r in raw_materials:
        for c in calmonths:
            row = {"CALMONTH": c, "RAW MATERIAL": r, "METRIC": random.random()}
            df = df.append(row, ignore_index=True)
    return df

#print(gen_raw_mat_prices())

#shutdown costs same as fixed cost
#capacity same as fixed costs

def gen_logistic_costs():
    df = pd.DataFrame(columns=["CUSTOMER", "MILL", "METRIC"])
    for c in customers:
        for m in mills:
            row = {"CUSTOMER": c, "MILL": m, "METRIC": random.random()}
            df = df.append(row, ignore_index=True)

    return df

#print(gen_logistic_costs())

def gen_storage_caps():
    df = pd.DataFrame(columns=["MILL", "METRIC"])
    for m in mills:
        row = {"MILL": m, "METRIC": random.random()}
        df = df.append(row, ignore_index=True)

    return df

def gen_caps():
    df = pd.DataFrame(columns=["PM", "METRIC"])
    for pm in pms:
        row = {"PM": pm, "METRIC": random.random()}
        df = df.append(row, ignore_index=True)

    return df
#print(gen_storage_caps())


#storage costs use storage caps function

def gen_prod_prices():
    df = pd.DataFrame(columns=["CALMONTH", "PRODUCT", "METRIC"])
    for c in calmonths:
        for p in prods:
            row = {"CALMONTH":c, "PRODUCT": p, "METRIC": random.random()}
            df = df.append(row, ignore_index=True)
    
    return df

#print(gen_prod_prices())

def gen_energy_costs():
    df = pd.DataFrame(columns=["CALMONTH", "MILL", "PRODUCT", "ENERGY", "METRIC"])
    for c in calmonths:
        for m in mills:
            for p in prods:
                for e in energy_comps:
                    row = {"CALMONTH":c, "MILL": m, "PRODUCT": p, "ENERGY": e, "METRIC": random.random()}
                    df = df.append(row, ignore_index=True)
    return df


fd_stages = ["l1","l2","l3"]
bulk_stages = ["b1","b2"]
daca_stages = ["d1","d2"]

input_file["Scenarios"] = gen_scenarios_tab(scn_ct)
input_file["Contracts"] = gen_contracts()
input_file["FD_limits"] = gen_limits_prices(raw_materials=raw_materials, contract_stages=fd_stages)
input_file["FD_prices"] = gen_limits_prices(raw_materials=raw_materials, contract_stages=fd_stages)
input_file["BULK_prices"] = gen_limits_prices(raw_materials=raw_materials, contract_stages=bulk_stages)
input_file["BULK_limits"] = gen_limits_prices(raw_materials=raw_materials, contract_stages="no_stages")
input_file["DACA_limits"] = gen_limits_prices(raw_materials=raw_materials, contract_stages="no_stages")
input_file["DACA_prices"] = gen_limits_prices(raw_materials=raw_materials, contract_stages=daca_stages)
input_file["PM"] = gen_pms_tab(pm_ct=pm_ct)
input_file["CustomerDemand"] = gen_cust_dem_tab()
input_file["FixedCosts"] = gen_fixed_costs()
input_file["RawMaterialConversion"] = gen_raw_mat_conv()
input_file["RawMaterialPrices"] = gen_raw_mat_prices()
input_file["ShutdownCosts"] = gen_fixed_costs()
input_file["Capacity"] = gen_caps()
input_file["LogisticCosts"] = gen_logistic_costs()
input_file["StorageCapacities"] = gen_storage_caps()
input_file["StorageCosts"] = gen_storage_caps()
input_file["Prices"] = gen_prod_prices()
input_file["EnergyCosts"] = gen_energy_costs()

writer = pd.ExcelWriter('scenarios/input_file'+str(time.time())+'.xlsx', engine='openpyxl') 

for sheet_name, df in input_file.items():
    df.to_excel(writer, sheet_name=sheet_name, index=False)

writer.save()
writer.close()

