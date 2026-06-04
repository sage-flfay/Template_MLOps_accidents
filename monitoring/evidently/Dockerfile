FROM python:3.9-slim
WORKDIR /app
RUN pip install --no-cache-dir --upgrade pip
COPY requirements.txt ./requirements.txt
RUN pip install --no-cache-dir -r requirements.txt
COPY monitor.py ./monitor.py
COPY X_train.csv ./X_train.csv
CMD ["python", "monitor.py"]
