#!/bin/bash
echo "=== YesCare Preprod Verification ==="

echo ""
echo "--- K8s Nodes ---"
kubectl get nodes

echo ""
echo "--- Kafka Pod ---"
kubectl get pods -n messaging

echo ""
echo "--- Kafka Topics ---"
kubectl exec -n messaging deployment/kafka -- bash -c "/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092"

echo ""
echo "--- PostgreSQL DBs ---"
doctl databases db list $(doctl databases list --no-header --format ID,Name | grep "yescare-pre-prod-scale-pg" | awk '{print $1}')

echo ""
echo "--- PostgreSQL Users ---"
doctl databases user list $(doctl databases list --no-header --format ID,Name | grep "yescare-pre-prod-scale-pg" | awk '{print $1}')

echo ""
echo "--- Redis ---"
doctl databases list | grep redis

echo ""
echo "--- LB IP ---"
kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}'

echo ""
echo "=== All Done! Preprod Infra Ready ==="

# Update DNS to new LB IP
echo ""
echo "--- Updating DNS ---"
LB_IP=$(kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}')
doctl compute domain records update yescare.co.in --record-id 1821333975 --record-data "$LB_IP"
doctl compute domain records update yescare.co.in --record-id 1822440970 --record-data "$LB_IP"
echo "DNS updated to: $LB_IP"
