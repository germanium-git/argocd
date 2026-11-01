

## K8s Operator
https://github.com/k8sgpt-ai/charts



helm repo add k8sgpt https://charts.k8sgpt.ai
helm repo update
helm upgrade -i k8sgpt-operator k8sgpt/k8sgpt-operator --version 0.2.24 -n k8sgpt-operator-system --create-namespace



create secret


kubectl create secret generic k8sgpt-sample-secret --from-literal=openai-api-key=$OPENAI_TOKEN -n k8sgpt-operator-system


## Client CLI

https://github.com/k8sgpt-ai/k8sgpt