import sklearn
import pandas as pd
from sklearn import ensemble
from sklearn.metrics import classification_report, accuracy_score
import joblib
import numpy as np

print(joblib.__version__)

# Load data
X_train = pd.read_csv('data/preprocessed/X_train.csv')
X_test = pd.read_csv('data/preprocessed/X_test.csv')
y_train = pd.read_csv('data/preprocessed/y_train.csv')
y_test = pd.read_csv('data/preprocessed/y_test.csv')

y_train = np.ravel(y_train)
y_test = np.ravel(y_test)

# Create model
rf_classifier = ensemble.RandomForestClassifier(n_jobs=-1)

# Train model
rf_classifier.fit(X_train, y_train)

# Evaluate model
predictions = rf_classifier.predict(X_test)

print("\nModel evaluation:")
print("Accuracy:", accuracy_score(y_test, predictions))
print(classification_report(y_test, predictions))

# Save model
model_filename = './src/models/trained_model.joblib'
joblib.dump(rf_classifier, model_filename)

print("Model trained and saved successfully.")