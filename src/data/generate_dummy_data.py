import pandas as pd
from sklearn.model_selection import train_test_split
import numpy as np
import os

# create fake dataset
X = np.random.randint(0, 5, size=(100, 5))
y = np.random.randint(0, 2, size=(100))

X_train, X_test, y_train, y_test = train_test_split(X, y, test_size=0.2)

os.makedirs("data/preprocessed", exist_ok=True)

pd.DataFrame(X_train).to_csv("data/preprocessed/X_train.csv", index=False)
pd.DataFrame(X_test).to_csv("data/preprocessed/X_test.csv", index=False)
pd.DataFrame(y_train).to_csv("data/preprocessed/y_train.csv", index=False)
pd.DataFrame(y_test).to_csv("data/preprocessed/y_test.csv", index=False)

print("Dummy dataset created successfully.")