 
import pandas as pd
import numpy as np
import random

def random_walk(df, start_value=0, threshold=0.5, step_size=1, min_value=-np.inf, max_value=np.inf):
    previous_value = start_value
    for index, row in df.iterrows():
        if previous_value < min_value:
            previous_value = min_value
        if previous_value > max_value:
            previous_value = max_value
        probability = random.random()
        if probability >= threshold:
            df.loc[index, 'value'] = previous_value + step_size
        else:
            df.loc[index, 'value'] = previous_value - step_size
        previous_value = df.loc[index, 'value']
    return df

scale = 10

products = ['P'+str(i) for i in range(scale)]
customer = ['C'+str(i) for i in range(scale)]

df_all_scn = pd.DataFrame()

for p in products:
    for c in customer:
        scn = pd.DataFrame(index=[i for i in range(12)])
        scn = random_walk(scn)
        scn.insert(0, column="Customer", value=c)
        scn.insert(0, column="Product", value=p)

        df_all_scn.append(scn)

        print(scn)

print(df_all_scn)