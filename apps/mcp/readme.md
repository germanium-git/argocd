# MCP

https://artifacthub.io/packages/helm/cowboysysop/kubernetes-mcp

https://skywork.ai/blog/how-to-deploy-operate-mcp-server-kubernetes-helm-guide/

## DEV
helm upgrade -i mcp cowboysysop/kubernetes-mcp -n chatmcp -f values.dev.yaml --create-namespace


Enable port forwarding
```bash
export POD_NAME=$(kubectl get pods --namespace "chatmcp" -l "app.kubernetes.io/name=kubernetes-mcp,app.kubernetes.io/instance=mcp" -o jsonpath="{.items[0].metadata.name}")
echo "Visit http://127.0.0.1:8080/ to use your application"
kubectl --namespace "chatmcp" port-forward $POD_NAME 8080:8080
```

Check if MCP responds after port forwarding is enabled
```bash
curl -sS http://localhost:8080/mcp \
    -H "Content-Type: application/json" \
    -X POST \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```

## PROD

helm upgrade -i mcp cowboysysop/kubernetes-mcp -n chatmcp -f values.prod.yaml --create-namespace



```bash
curl -sS http://mcp.germanium.cz/mcp \
    -H "Content-Type: application/json" \
    -X POST \
    -d '{"jsonrpc":"2.0","id":1,"method":"tools/list","params":{}}'
```