# Workaround: AWS ECR Long-Lived Auth Tokens

```
kubectl create secret generic aws-credentials \
  --from-literal=AWS_ACCESS_KEY_ID=****************** \
  --from-literal=AWS_SECRET_ACCESS_KEY=**************************
```

```
kubectl apply -f workaround.yaml
```
