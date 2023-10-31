#!/bin/bash

CONSUL_K8S_PRIMARY="0.49.8"
CONSUL_K8S_SECONDARY="0.49.8"

multipass delete --purge k3s-primary k3s-secondary1 k3s-secondary2
sleep 1

set -e

multipass launch -n k3s-primary -m 6G -c 2 --cloud-init ./base-image.yaml
multipass launch -n k3s-secondary1 -m 6G -c 2 --cloud-init ./base-image-secondary1.yaml
multipass launch -n k3s-secondary2 -m 6G -c 2 --cloud-init ./base-image-secondary1.yaml

multipass exec k3s-primary helm repo add hashicorp https://helm.releases.hashicorp.com
multipass exec k3s-secondary1 helm repo add hashicorp https://helm.releases.hashicorp.com
multipass exec k3s-secondary2 helm repo add hashicorp https://helm.releases.hashicorp.com

multipass transfer values-primary.yaml k3s-primary:values.yaml
export SECONDARY1_IP=$(multipass info k3s-secondary1 --format json | jq -r '.info[].ipv4[0]')
export SECONDARY2_IP=$(multipass info k3s-secondary2 --format json | jq -r '.info[].ipv4[0]')
envsubst < values-secondary1.yaml | multipass transfer - k3s-secondary1:values.yaml
envsubst < values-secondary2.yaml | multipass transfer - k3s-secondary2:values.yaml

multipass exec k3s-primary -- KUBECONFIG=/home/ubuntu/.kube/config kubectl create ns consul
multipass exec k3s-secondary1 -- KUBECONFIG=/home/ubuntu/.kube/config kubectl create ns consul
multipass exec k3s-secondary2 -- KUBECONFIG=/home/ubuntu/.kube/config kubectl create ns consul

multipass exec k3s-primary -- KUBECONFIG=/home/ubuntu/.kube/config helm install consul hashicorp/consul -n consul -f values.yaml --version ${CONSUL_K8S_PRIMARY} --wait
sleep 10
multipass exec k3s-primary -- sh -c 'KUBECONFIG=/home/ubuntu/.kube/config kubectl -n consul get secret consul-federation --output yaml > consul-federation-secret.yaml'

multipass transfer k3s-primary:consul-federation-secret.yaml - | multipass transfer - k3s-secondary1:consul-federation-secret.yaml
multipass transfer k3s-primary:consul-federation-secret.yaml - | multipass transfer - k3s-secondary2:consul-federation-secret.yaml

multipass exec k3s-secondary1 -- KUBECONFIG=/home/ubuntu/.kube/config kubectl apply -n consul -f consul-federation-secret.yaml
multipass exec k3s-secondary2 -- KUBECONFIG=/home/ubuntu/.kube/config kubectl apply -n consul -f consul-federation-secret.yaml

sleep 60
multipass exec k3s-secondary1 -- helm install consul hashicorp/consul -n consul -f values.yaml --version ${CONSUL_K8S_SECONDARY} --wait
sleep 120
multipass exec k3s-secondary2 -- helm install consul hashicorp/consul -n consul -f values.yaml --version ${CONSUL_K8S_SECONDARY} --wait
