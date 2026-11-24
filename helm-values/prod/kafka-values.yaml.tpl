global:
  security:
    allowInsecureImages: true

image:
  registry: registry-1.docker.io
  repository: bitnamicharts/kafka
  tag: 32.4.3

broker:
  replicaCount: 0

controller:
  replicaCount: ${replica_count}
  persistence:
    enabled: true
    size: ${storage_size}
  resources:
    requests:
      cpu: ${cpu_request}
      memory: ${memory_request}
    limits:
      memory: ${memory_limit}
  pdb:
    create: false

listeners:
  client:
    protocol: PLAINTEXT
  controller:
    protocol: PLAINTEXT
  interbroker:
    protocol: PLAINTEXT

externalAccess:
  enabled: false

provisioning:
  enabled: true
  numPartitions: ${topic_partitions}
  replicationFactor: ${topic_replication_factor}
  topics:
%{ for t in topics ~}
    - name: ${t}
      partitions: ${topic_partitions}
      replicationFactor: ${topic_replication_factor}
      config:
        retention.ms: "604800000"
        min.insync.replicas: "2"
%{ endfor ~}

metrics:
  jmx:
    enabled: false
  kafka:
    enabled: false
