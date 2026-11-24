# ingress-nginx — prod-scale Phase 1
# Templated by Terraform: digitalocean/envs/prod-scale/main.tf

controller:
  replicaCount: ${replica_count}

  service:
    type: LoadBalancer
    annotations:
      # Use proxy protocol if you need real client IPs (requires app awareness)
      # service.beta.kubernetes.io/do-loadbalancer-enable-proxy-protocol: "true"
      service.beta.kubernetes.io/do-loadbalancer-protocol: "https"
      service.beta.kubernetes.io/do-loadbalancer-redirect-http-to-https: "true"
      service.beta.kubernetes.io/do-loadbalancer-tls-ports: "443"
      service.beta.kubernetes.io/do-loadbalancer-size-unit: "1"  # bump to 2-5 at Phase 2+

  resources:
    requests:
      cpu: 100m
      memory: 256Mi
    limits:
      memory: 512Mi

  # Force pods onto separate nodes
  affinity:
    podAntiAffinity:
      preferredDuringSchedulingIgnoredDuringExecution:
        - weight: 100
          podAffinityTerm:
            labelSelector:
              matchLabels:
                app.kubernetes.io/name: ingress-nginx
                app.kubernetes.io/component: controller
            topologyKey: kubernetes.io/hostname

  metrics:
    enabled: true
    serviceMonitor:
      enabled: false  # flip true once Prometheus Operator is installed

  config:
    # Hardening
    use-forwarded-headers: "true"
    enable-real-ip: "true"
    proxy-body-size: "20m"
    keep-alive: "75"
    keep-alive-requests: "1000"
    allow-snippet-annotations: "true"

  autoscaling:
    enabled: false  # enable at Phase 2 — HPA scales 2-6 based on CPU
    minReplicas: ${replica_count}
    maxReplicas: 6
    targetCPUUtilizationPercentage: 70
