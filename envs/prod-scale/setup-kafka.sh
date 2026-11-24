#!/bin/bash
set -e

echo "=== Setting up Kafka ==="
#doctl kubernetes cluster kubeconfig save yescare-preprod-scale-k8s --set-current-context
doctl kubernetes cluster kubeconfig save yescare-pre-prod-scale-k8s --set-current-context
kubectl create namespace messaging --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -f "$(dirname "$0")/kafka.yaml"
echo "Waiting for Kafka pod to be ready..."
kubectl rollout status deployment/kafka -n messaging --timeout=180s
echo "Waiting 15s for K8s API to stabilize..."
sleep 15
echo "Creating Kafka topics..."
kubectl exec -n messaging deployment/kafka -- bash -c "
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic appointment.created --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic appointment.updated --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic consultation.started --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic consultation.ended --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic notification.send --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic payment.processed --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic doctor.onboarded --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic user.signup --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic consultation.completed --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic consultation.cancel --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic consultation.rejected --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic consultation.prescribed --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic doctor.force.logout --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic doctor.display.ready --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic consultation.assigned --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic consultation.cancelled --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic consultation.request --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic consultation.accepted --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic consultation.request.fcm --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic doctor.presence.changed --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic gateway.consultation.assign --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic gateway.consultation.cancel --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic gateway.consultation.complete --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic gateway.consultation.in_progress --partitions 3 --replication-factor 1
/opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092
"
echo "=== Kafka setup complete ==="
