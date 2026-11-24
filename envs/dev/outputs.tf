output "vpc_id" {
  description = "DigitalOcean VPC UUID"
  value       = module.vpc.id
}

output "public_subnets" {
  description = "Not applicable on DO VPC — empty list"
  value       = []
}

output "private_subnets" {
  description = "Not applicable on DO VPC — empty list"
  value       = []
}

output "k3s_public_ip" {
  description = "Use ingress LoadBalancer IP after do-dev-stack-install.sh (kubectl get svc -n ingress-nginx)"
  value       = null
}

output "k3s_instance_id" {
  value = null
}

output "nat_instance_id" {
  value = null
}

output "kubernetes_cluster_id" {
  value = module.kubernetes.cluster_id
}

output "kubernetes_endpoint" {
  value = module.kubernetes.endpoint
}

output "kubeconfig" {
  value       = module.kubernetes.kubeconfig_raw
  sensitive   = true
  description = "terraform output -raw kubeconfig > kubeconfig-dev.yaml"
}

output "kubeconfig_command" {
  value = "terraform output -raw kubeconfig > kubeconfig-dev.yaml && export KUBECONFIG=\"$PWD/kubeconfig-dev.yaml\""
}

output "ssm_connect_command" {
  value = "N/A on DigitalOcean — use kubeconfig output above"
}

output "rds_endpoint" {
  description = "PostgreSQL host (DEV_DB_HOST)"
  value       = module.postgres.database_host
}

output "rds_endpoint_port" {
  value = module.postgres.database_port
}

output "rds_identifier" {
  value = module.postgres.database_cluster_name
}

output "database_name" {
  value = module.postgres.database_name
}

output "database_user" {
  value = module.postgres.database_user
}

output "database_password" {
  value       = module.postgres.database_password
  sensitive   = true
}

############################
# Spaces (S3-compatible) — replace AWS S3
############################
output "s3_app_bucket" {
  description = "Bucket name for DEV_S3_BUCKET / spring.cloud.aws.s3.bucket"
  value       = try(module.spaces[0].app_bucket_name, null)
}

output "s3_logs_bucket" {
  value = try(module.spaces[0].logs_bucket_name, null)
}

output "spaces_s3_endpoint" {
  description = "S3 API endpoint for AWS SDK / Spring (virtual-hosted style)"
  value       = var.enable_spaces ? "https://${var.region}.digitaloceanspaces.com" : null
}

output "spaces_region" {
  description = "Same as var.region for client config"
  value       = var.region
}

############################
# In-cluster messaging (after do-dev-stack-install.sh) — replace SQS / MSK
############################
output "redis_connection" {
  value = "redis-master.default.svc.cluster.local:6379"
}

output "rabbitmq_host" {
  description = "Spring AMQP: spring.rabbitmq.host"
  value       = "rabbitmq.default.svc.cluster.local"
}

output "rabbitmq_port" {
  value = 5672
}

output "rabbitmq_user" {
  value = "yescare"
}

output "rabbitmq_management_url" {
  description = "kubectl port-forward svc/rabbitmq 15672:15672 — open http://127.0.0.1:15672"
  value       = "http://rabbitmq.default.svc.cluster.local:15672 (cluster-internal)"
}

output "kafka_bootstrap_servers" {
  description = "Spring Kafka: spring.kafka.bootstrap-servers"
  value       = "kafka.default.svc.cluster.local:9092"
}

output "kafka_topics_suggested" {
  description = "Topics created by helm values (align consumers with these names)"
  value       = ["dev-events", "dev-notifications", "dev-jobs"]
}

output "github_repo_url" {
  value = var.github_repo_url
}

output "runner_secret_name" {
  value = var.runner_secret_name
}

output "rds_secret_name" {
  value = var.rds_secret_name
}

output "deploy_runbook" {
  value = "DEPLOY_STEPS_DEV_DO.md"
}

output "app_env_migration" {
  value = "DO_APPLICATION_ENV_VARS.md"
}

############################
# Container Registry
############################
output "registry_endpoint" {
  description = "Image prefix: registry.digitalocean.com/<name>"
  value       = try(module.registry[0].endpoint, "registry not created — set create_registry=true")
}

output "registry_ci_credentials" {
  value     = try(module.registry[0].ci_docker_credentials, null)
  sensitive = true
}

############################
# Firewall
############################
output "firewall_id" {
  value = module.firewall.id
}

############################
# ingress-nginx LB IP (available after apply + LB provisioned)
############################
output "load_balancer_ip_command" {
  value = "kubectl get svc ingress-nginx-controller -n ingress-nginx -o jsonpath='{.status.loadBalancer.ingress[0].ip}'"
}
