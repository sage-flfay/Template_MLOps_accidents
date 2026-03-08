import joblib
import numpy as np


def test_model_prediction():

    model = joblib.load("src/models/trained_model.joblib")

    sample = np.zeros((1, 5))

    prediction = model.predict(sample)

    assert prediction is not None