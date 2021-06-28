#!/bin/bash

set -e

export EXPERIMENT=hybrid-exp

# create cluster
minikube start --cpus 8 --memory 12288 --kubernetes-version=v1.17.11

# platform setup
echo "Setting up platform"
$ITER8/samples/kfserving/quickstart/iter8setup.sh
$ITER8/samples/kfserving/quickstart/platformsetup.sh

echo "Create app/ML model versions"
kubectl apply -f $ITER8/samples/kfserving/quickstart/baseline.yaml
kubectl apply -f $ITER8/samples/kfserving/quickstart/candidate.yaml
kubectl apply -f $ITER8/samples/kfserving/quickstart/routing-rule.yaml
kubectl wait --for=condition=Ready isvc/flowers -n ns-baseline --timeout=600s       
kubectl wait --for=condition=Ready isvc/flowers -n ns-candidate --timeout=600s

echo "Define metrics"
kubectl apply -f $ITER8/samples/kfserving/hybrid/metrics.yaml

echo "Launch experiment"
kubectl apply -f $ITER8/samples/kfserving/hybrid/experiment.yaml

echo "Generate requests"

URL_VALUE="http://$(kubectl -n istio-system get svc istio-ingressgateway -o jsonpath='{.spec.clusterIP}'):80/productpage"

# Port-forward Istio ingress
INGRESS_GATEWAY_SERVICE=$(kubectl get svc -n istio-system --selector="app=istio-ingressgateway" --output jsonpath='{.items[0].metadata.name}')
kubectl port-forward -n istio-system svc/${INGRESS_GATEWAY_SERVICE} 8080:80 &
sleep 5.0

# Get the prediction payload
curl -o /tmp/input.json https://raw.githubusercontent.com/kubeflow/kfserving/master/docs/samples/v1beta1/rollout/input.json

# Send prediction requests... this step requires fortio
fortio load -t 360s -qps 4.0 -H "Host: example.com" -payload-file /tmp/input.json -json /tmp/fortiooutput.json http://localhost:8080/v1/models/flowers:predict

# Wait
kubectl wait experiment $EXPERIMENT --for=condition=Completed --timeout=300s

# Log final experiment
kubectl get experiment $EXPERIMENT -o yaml

# Check
source $ITER8/samples/kfserving/quickstart/check.sh

kubectl delete -f $ITER8/samples/kfserving/hybrid/experiment.yaml
kubectl delete -f $ITER8/samples/kfserving/hybrid/metrics.yaml
# Cleanup .. delete inference services (and its ns takes forever)...
# so skipping this for now... need to be fixed later;
# possibly by bringing this up with KFServing

# kubectl delete -f $ITER8/samples/kfserving/quickstart/baseline.yaml
# kubectl delete -f $ITER8/samples/kfserving/quickstart/candidate.yaml

# delete cluster
minikube delete

set +e

echo -e "\033[0;32mSUCCESS:\033[0m $0"
