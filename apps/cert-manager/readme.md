# Cert Manager

## Installation
1. Let argo install the helm chart
2. Configure K8s secret holding the CloudFlare token
3. Configure Issuer
4. Try to create a test certificate


## Sealed Secret

Create a token in CloudFlare UI with the permission to edit the DNS zone germanium.cz.

```
kubectl create secret generic cloudflare-token-secret -n cert-manager \
    --from-literal=cloudflare-token=xxxx-yyyyyyyyyy-zzzzzzzzzzzz \
    --dry-run=client -o yaml | kubeseal --format=yaml > sealedsecrets-cloudflare.yaml
```

Check the secret
```
kubectl get secret --namespace cert-manager cloudflare-token-secret -o jsonpath="{.data.cloudflare-token}" | base64 -d
```

The secret is used as apiTokenSecretRef in dns01 challenge in the issuer definition and it proves that you own the DNS for your domain name by putting a specific value in a TXT record.

## Issuers

Create two ClusterIssures for having the certificates signed by Let's Encrypt stage and prod.

`cluster-issuer-prod.yaml`
`cluster-issuer-staging.yaml`

## Cerrtificates

Try to create a certificates for **.germanium.cz* and **.local.germanium.cz*. by using the following manifests.

- germanium-certificate-prod.yaml
- germanium-certificate-staging.yaml
- local-certificate-prod.yaml
- local-certificate-staging.yaml
