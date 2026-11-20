# Cert Manager

The certification manager instructs the provider Let's Encrypt to issue certificates. The DNS01 challenge is used to prove ownership of the domain operating in CloudFlare.

## Installation
1. Let argo install the helm chart
2. Configure K8s secret holding the CloudFlare token
3. Configure Issuer
4. Try to create a test certificate


### Helm

https://artifacthub.io/packages/helm/cert-manager/cert-manager


### Values.yaml
https://github.com/cert-manager/cert-manager/blob/master/deploy/charts/cert-manager/values.yaml


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

## Certificates

`addons/germanium-certificate-prod.yaml` issues the wildcard certificate for *germanium.cz* and **.germanium.cz* (secret `default/germanium-cz-prod-tls`).
The Traefik gateways `traefik-gateway-tls` and `traefik-gateway-tls-tunnel` use it for every HTTPS route, so apps don't need certificates of their own.

The staging and `*.local.germanium.cz` certificates, and the per-app certificates, were removed in 2026-11 because nothing used them.
