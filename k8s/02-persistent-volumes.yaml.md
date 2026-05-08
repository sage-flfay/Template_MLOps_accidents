# k3s inclut nativement "local-path" : stockage dans
# /var/lib/rancher/k3s/storage/ — aucune config supplémentaire
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: postgres-db-pvc
  namespace: accidents-severity
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 2Gi
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: mlflow-artifacts-pvc
  namespace: accidents-severity
spec:
  accessModes:
    - ReadWriteOnce
  storageClassName: local-path
  resources:
    requests:
      storage: 5Gi