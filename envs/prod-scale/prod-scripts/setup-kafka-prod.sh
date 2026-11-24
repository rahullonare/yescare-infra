#!/usr/bin/env bash
# Deploy Kafka + topics to the PROD cluster (3-broker KRaft StatefulSet, RF=3).
# Prod-only. macOS/Linux portable. Needs 3 schedulable nodes (one broker per node).
set -euo pipefail
DIR="$(cd "$(dirname "$0")" && pwd)"
source "$DIR/prod.env"

echo "=== [PROD] Kafka setup on $PROD_CLUSTER ==="
doctl kubernetes cluster kubeconfig save "$PROD_CLUSTER" --set-current-context

kubectl --context "$PROD_CONTEXT" create namespace messaging --dry-run=client -o yaml | kubectl --context "$PROD_CONTEXT" apply -f -
kubectl --context "$PROD_CONTEXT" apply -f "$DIR/../kafka.yaml"
echo "Waiting for Kafka (3 brokers) to be ready..."
kubectl --context "$PROD_CONTEXT" rollout status statefulset/kafka -n messaging --timeout=360s
kubectl --context "$PROD_CONTEXT" wait --for=condition=ready pod -l app=kafka -n messaging --timeout=180s
sleep 10

echo "Creating topics (RF=3)..."
TOPICS="appointment.created appointment.updated consultation.started consultation.ended \
notification.send payment.processed doctor.onboarded user.signup consultation.completed \
consultation.cancel consultation.rejected consultation.prescribed doctor.force.logout \
doctor.display.ready consultation.assigned consultation.cancelled consultation.request \
consultation.accepted consultation.request.fcm doctor.presence.changed \
gateway.consultation.assign gateway.consultation.cancel gateway.consultation.complete \
gateway.consultation.in_progress user.notification auth.force-logout"

# Idempotent server-side loop; retry a few times (kubectl exec streams can drop mid-batch).
for attempt in 1 2 3 4; do
  cnt=$(kubectl --context "$PROD_CONTEXT" exec -n messaging kafka-0 -- \
        /opt/kafka/bin/kafka-topics.sh --list --bootstrap-server localhost:9092 2>/dev/null | grep -vcE '^$|__')
  echo "  attempt $attempt: $cnt topics"
  [ "$cnt" -ge 26 ] && break
  kubectl --context "$PROD_CONTEXT" exec -n messaging kafka-0 -- bash -c \
    "for t in $TOPICS; do /opt/kafka/bin/kafka-topics.sh --create --if-not-exists --bootstrap-server localhost:9092 --topic \$t --partitions 3 --replication-factor 3 >/dev/null 2>&1 || true; done" 2>/dev/null || true
done
echo "--- under-replicated partitions (want 0) ---"
kubectl --context "$PROD_CONTEXT" exec -n messaging kafka-0 -- \
  /opt/kafka/bin/kafka-topics.sh --describe --under-replicated-partitions --bootstrap-server localhost:9092

echo "=== [PROD] Kafka setup complete (3 brokers, RF=3) ==="
