############################
# Networking
############################
output "vpc_id" {
  value = module.vpc.id
}

output "vpc_ip_range" {
  value = var.vpc_ip_range
}

############################
# Kubernetes
############################
output "kubernetes_cluster_id" {
  value = module.kubernetes.cluster_id
}

output "kubernetes_endpoint" {
  value = module.kubernetes.endpoint
}

output "kubeconfig" {
  value       = module.kubernetes.kubeconfig_raw
  sensitive   = true
  description = "terraform output -raw kubeconfig > kubeconfig-prod-scale.yaml"
}

output "kubeconfig_command" {
  value = "terraform output -raw kubeconfig > kubeconfig-prod-scale.yaml && export KUBECONFIG=$PWD/kubeconfig-prod-scale.yaml"
}

############################
# PostgreSQL
############################
output "database_host" {
  value = module.postgres.database_host
}

output "database_port" {
  value = module.postgres.database_port
}

output "database_name" {
  value = module.postgres.database_name
}

output "database_user" {
  value = module.postgres.database_user
}

output "database_password" {
  value     = module.postgres.database_password
  sensitive = true
}

output "database_url_template" {
  value       = "postgresql://${module.postgres.database_user}:PASSWORD@${module.postgres.database_host}:${module.postgres.database_port}/${module.postgres.database_name}?sslmode=require"
  description = "Substitute PASSWORD from the database_password output (sensitive)"
}

############################
# Redis (managed)
############################
output "redis_host" {
  value = module.redis.host
}

output "redis_port" {
  value = module.redis.port
}

output "redis_password" {
  value     = module.redis.password
  sensitive = true
}

############################
# Spaces
############################
output "spaces_app_bucket" {
  value = try(module.spaces[0].app_bucket_name, null)
}

output "spaces_logs_bucket" {
  value = try(module.spaces[0].logs_bucket_name, null)
}

output "spaces_endpoint" {
  value       = "https://${var.spaces_region}.digitaloceanspaces.com"
  description = "AWS_S3_ENDPOINT / spring.cloud.aws.s3.endpoint"
}

output "spaces_region" {
  value = var.spaces_region
}

############################
# Container Registry
############################
output "registry_endpoint" {
  value = try(module.registry[0].endpoint, "registry not managed by this stack — using shared yescare registry")
}

output "registry_ci_credentials" {
  value     = try(module.registry[0].ci_docker_credentials, null)
  sensitive = true
}

############################
# Kafka (in-cluster, KRaft combined)
############################
output "kafka_bootstrap_servers" {
  value       = "kafka.messaging.svc.cluster.local:9092"
  description = "Spring Kafka: spring.kafka.bootstrap-servers"
}

output "kafka_topics" {
  value = var.kafka_topics
}

output "kafka_replica_count" {
  value = var.kafka_replica_count
}

############################
# Ingress / TLS / DNS
############################
output "load_balancer_ip_command" {
  value = "kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}

output "certificate_id" {
  value = try(module.domain[0].certificate_id, "domain not configured")
}

output "domain_fqdn" {
  value = try(module.domain[0].apex_record_fqdn, "domain not configured")
}

############################
# Firewall
############################
output "firewall_id" {
  value = module.firewall.id
}

############################
# Scaling cheat-sheet (echoed for visibility)
############################
output "scale_phase_hints" {
  value = <<EOT
Phase 1 (10K users, current defaults): ~$210-320/mo
Phase 2 (100K): bump k8s_node_size=s-4vcpu-8gb, k8s_min_nodes=3 max=10, db_size=db-s-4vcpu-8gb, db_node_count=2, kafka_replica_count=5, kafka_storage_size=50Gi
Phase 3 (1M): k8s_node_size=s-8vcpu-16gb, db_size larger + add read replica, redis_size=db-s-2vcpu-4gb HA, dedicated kafka node pool
Phase 4 (10M): multi-pool DOKS, consider managed Kafka, CDN/WAF mandatory
See: digitalocean/envs/prod-scale/README.md
EOT
}

# Per-service DB users and passwords
output "hospital_db_password" {
  value     = module.postgres.hospital_user_password
  sensitive = true
}
output "payment_db_password" {
  value     = module.postgres.payment_user_password
  sensitive = true
}
output "notification_db_password" {
  value     = module.postgres.notification_user_password
  sensitive = true
}
