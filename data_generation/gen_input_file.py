#Generate optimization scenarios 
import warnings
warnings.simplefilter(action='ignore', category=FutureWarning)
import pandas as pd
import random 
import numpy as np
from arch.bootstrap import MovingBlockBootstrap
import os
import math
from pathlib import Path
import xlwings

def save_excel_file(file_path):
    excel_app = xlwings.App(visible=False)
    excel_book = excel_app.books.open(file_path)
    excel_book.save()
    excel_book.close()
    excel_app.quit()


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


#pulprice raw material data
pulp_prices = pd.read_excel(r'C:\Users\Tom\Documents\Thesis\dev\data_generation\pulp_prices.xls')
pulp_prices["date"] = pd.to_datetime(pulp_prices["date"])
pulp_prices.index = pulp_prices["date"]
pulp_prices = pulp_prices.drop(columns=["date"])

bs = MovingBlockBootstrap(3, pulp_prices)

#parameters

#pm_ct = 5
#mill_ct = pm_ct
#scn_ct = 6
#cust_ct = 4
#prod_ct = 3
#e_ct = 1
#raw_mat_ct = 3

pm_ct = 1
mill_ct = pm_ct
scn_ct = 1
cust_ct = 1
prod_ct = 1
e_ct = 1
raw_mat_ct = 1

raw_materials = ["R"+str(i) for i in range(raw_mat_ct)]
pms  = ["PM"+str(i) for i in range(pm_ct)]
customers = ["C"+str(i) for i in range(cust_ct)]
prods = ["P"+str(i) for i in range(prod_ct)]
calmonths = [i + 202101 for i in range(12)]
scns = ["S"+str(i) for i in range(scn_ct)]
mills = ["M"+str(i) for i in range(mill_ct)]
energy_comps = ["E"+str(i) for i in range(e_ct)]

input_file = {}

def gen_scenarios_tab(scn_ct):

    prb = 1.0/float(scn_ct)

    df = pd.DataFrame(columns=["SCENARIO","METRIC"])

    for i in range(scn_ct):
        row = {"SCENARIO": "S"+str(i), "METRIC": prb}
        df = df.append(row, ignore_index=True)

    return df

def gen_contracts():

    df = pd.DataFrame(["FIXED","DACA","BULK","FD"],columns=["CONTRACTS"])
    return df

def gen_limits(raw_materials):
    df = pd.DataFrame(columns=["CALMONTH", "RAW MATERIAL", "METRIC"])
    for r in raw_materials:
        for m in calmonths:
            lim = random.random()*100 + 1
            row  = {"CALMONTH":m, "RAW MATERIAL": r, "METRIC": lim}
            df = df.append(row, ignore_index=True)

    return df

def gen_prices(raw_materials, contract_stages, spot_prices):
    df = pd.DataFrame(columns=["CALMONTH", "TYPE", "RAW MATERIAL", "METRIC"])
    for r in raw_materials:
        for m in calmonths:
            for idx, c in enumerate(contract_stages):
                rates = [1.0,.9,.8]
                price = spot_prices.loc[(spot_prices['CALMONTH']==m) & (spot_prices['RAW MATERIAL']==r)][['METRIC']].values[0][0]
                if idx == 0:
                    discount_factor = random.uniform(0.75,0.9)
                    row  = {"CALMONTH":m, "TYPE": c, "RAW MATERIAL": r, "METRIC": price}
                    df = df.append(row, ignore_index=True)
                else:
                    
                    row  = {"CALMONTH":m, "TYPE": c, "RAW MATERIAL": r, "METRIC": rates[idx]*discount_factor*price}
                    df = df.append(row, ignore_index=True)

    return df


def gen_fd_limits(raw_materials, contract_stages):
    df = pd.DataFrame(columns=["CALMONTH", "TYPE", "RAW MATERIAL", "METRIC"])
    for r in raw_materials:
        for m in calmonths:
            for idx, c in enumerate(contract_stages):
                
                if idx == 0: minimum_buy = random.uniform(10,100)
                rates = [1,1.25,1.50]
                row  = {"CALMONTH":m, "TYPE": c, "RAW MATERIAL": r, "METRIC": rates[idx]*minimum_buy}
                df = df.append(row, ignore_index=True)

    return df

def gen_pms_tab(pm_ct):
    df = pd.DataFrame(columns=["MILL","PM"])
    for pm in range(pm_ct):
        row = {"MILL": "M"+str(pm), "PM":"PM"+str(pm)}
        df = df.append(row, ignore_index=True)
    
    return df

def gen_cust_dem_tab():
    df = pd.DataFrame(columns=["CALMONTH", "CUSTOMER", "PRODUCT", "SCENARIO", "METRIC"])
    s_rand = {}
    for s in scns:
        s_rand[s] = random.random()+1

    for c in customers:
        time_c = 5*random.random()
        for mid, m in enumerate(calmonths):
            for p in prods:
                prod_randomness = random.random()+1
                for s in scns:
                    demand = s_rand[s]*100*math.sin(prod_randomness*mid + time_c + s_rand[s]) + s_rand[s]*100 + random.random() #seasonal trend in demand

                    row = {"CALMONTH": m, "CUSTOMER":c, "PRODUCT":p, "SCENARIO":s, "METRIC": demand}
                    df = df.append(row, ignore_index=True)
    
    return df

def gen_fixed_costs():
    df = pd.DataFrame(columns=["PM","METRIC"])
    for p in pms:
        row = {"PM": p, "METRIC": 0}
        df = df.append(row, ignore_index=True)
    
    return df

def gen_raw_mat_conv():
    df = pd.DataFrame(columns=["PRODUCT", "RAW MATERIAL", "METRIC"])
    for p in prods:
        nums = [random.random() for r in raw_materials]
        total = sum(nums)
        nums = [num*(1/total) for num in nums] 

        for ct, r in enumerate(raw_materials):
            row = {"PRODUCT": p, "RAW MATERIAL": r, "METRIC": nums[ct]}
            df = df.append(row, ignore_index=True)
    
    return df


def gen_raw_mat_series(start='2021-01-01', end='2021-12-01'):
    sample = None
    for data in bs.bootstrap(1):
        model_data = data[0][0]
        model_data.index = pulp_prices.index
        sample = model_data[(model_data.index >= start) & (model_data.index <= end) ]
    
    return sample

def gen_raw_mat_prices():
    df = pd.DataFrame(columns=["CALMONTH", "RAW MATERIAL", "SCENARIO",  "METRIC"])
    
    for s in scns:
        for r in raw_materials:
            sample = gen_raw_mat_series() #bootstrap sampling 
            for c in calmonths:
                sample_value = sample[sample.index == str(c)[:4]+'-'+ str(c)[4:]+'-01']['pulp_price'].values[0]
                row = {"CALMONTH": c, "RAW MATERIAL": r, "SCENARIO": s, "METRIC": sample_value}
                df = df.append(row, ignore_index=True)

   
    

    return df

def gen_logistic_costs():
    df = pd.DataFrame(columns=["CUSTOMER", "MILL", "METRIC"])
    for c in customers:
        for m in mills:
            row = {"CUSTOMER": c, "MILL": m, "METRIC": random.random()}
            df = df.append(row, ignore_index=True)

    return df

def gen_storage_caps():
    df = pd.DataFrame(columns=["MILL", "METRIC"])
    for m in mills:
        row = {"MILL": m, "METRIC": 100000}
        df = df.append(row, ignore_index=True)

    return df

def gen_storage_costs():
    df = pd.DataFrame(columns=["MILL", "METRIC"])
    for m in mills:
        row = {"MILL": m, "METRIC": 0}
        df = df.append(row, ignore_index=True)

    return df

def gen_caps():
    df = pd.DataFrame(columns=["PM", "METRIC"])
    for pm in pms:
        row = {"PM": pm, "METRIC": 100000}
        df = df.append(row, ignore_index=True)

    return df

def gen_prod_prices():
    df = pd.DataFrame(columns=["CALMONTH", "PRODUCT", "METRIC"])
    for c in calmonths:
        for p in prods:
            row = {"CALMONTH":c, "PRODUCT": p, "METRIC": 1000}
            df = df.append(row, ignore_index=True)
    
    return df

def gen_energy_costs():
    df = pd.DataFrame(columns=["CALMONTH", "MILL", "PRODUCT", "ENERGY", "METRIC"])
    for c in calmonths:
        for m in mills:
            for p in prods:
                for e in energy_comps:
                    row = {"CALMONTH":c, "MILL": m, "PRODUCT": p, "ENERGY": e, "METRIC": random.random()}
                    df = df.append(row, ignore_index=True)
    return df

def gen_periods():
    return pd.DataFrame(data=calmonths, columns=["Period"])

def gen_custs():
    return pd.DataFrame(data=customers, columns=["Customer"])

def gen_mat():
    return pd.DataFrame(data=raw_materials, columns=["RawMaterials"])


fd_stages = ["l1","l2","l3"]
bulk_stages = ["b1","b2"]
daca_stages = ["d1","d2"]

input_file["Scenarios"] = gen_scenarios_tab(scn_ct)
input_file["Contracts"] = gen_contracts()

input_file["PM"] = gen_pms_tab(pm_ct=pm_ct)
input_file["CustomerDemand"] = gen_cust_dem_tab() 
input_file["FixedCosts"] = gen_fixed_costs()
input_file["RawMaterialConversion"] = gen_raw_mat_conv()
raw_mat_prices = gen_raw_mat_prices()
raw_mat_prices_avgs = raw_mat_prices[['CALMONTH','RAW MATERIAL', 'METRIC']].groupby(['CALMONTH', 'RAW MATERIAL']).mean().reset_index()
input_file["RawMaterialPrices"] = raw_mat_prices 

input_file["FD_limits"] = gen_fd_limits(raw_materials=raw_materials, contract_stages=fd_stages)
input_file["BULK_limits"] = gen_limits(raw_materials=raw_materials)
input_file["DACA_limits"] = gen_limits(raw_materials=raw_materials)

input_file["DACA_prices"] = gen_prices(raw_materials=raw_materials, contract_stages=daca_stages, spot_prices=raw_mat_prices_avgs)
input_file["FD_prices"] = gen_prices(raw_materials=raw_materials, contract_stages=fd_stages, spot_prices=raw_mat_prices_avgs)
input_file["BULK_prices"] = gen_prices(raw_materials=raw_materials, contract_stages=bulk_stages, spot_prices=raw_mat_prices_avgs)

input_file["ShutdownCosts"] = gen_fixed_costs()
input_file["Capacity"] = gen_caps()
input_file["LogisticCosts"] = gen_logistic_costs()
input_file["StorageCapacities"] = gen_storage_caps()
input_file["StorageCosts"] = gen_storage_costs()
input_file["Prices"] = gen_prod_prices()
input_file["EnergyCosts"] = gen_energy_costs()
input_file["Periods"] = gen_periods()
input_file["Customers"] = gen_custs()
input_file["RawMaterials"] = gen_mat()

input_path = Path('C:\\Users\\Tom\\Documents\\Thesis\\dev\\INPUT.xlsx')
try:
    os.remove(input_path)
except OSError:
    pass

writer = pd.ExcelWriter(input_path, engine='openpyxl') 

for sheet_name, df in input_file.items():
    df.to_excel(writer, sheet_name=sheet_name, index=False)


writer.save()

