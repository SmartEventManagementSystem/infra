#!/bin/bash

# DataPlatform Port Forward Script
# Usage: ./portforward.sh [service]
# Without arguments, forwards all services

cleanup() {
    echo ""
    echo "Stopping all port forwards..."
    for pid in "${PIDS[@]}"; do
        kill $pid 2>/dev/null || true
    done
    exit 0
}

trap cleanup SIGINT SIGTERM

PIDS=()

forward() {
    local service=$1
    local port=$2
    local namespace=${3:-dataplatform}
    echo "Forwarding $service:$port (namespace: $namespace)..."
    kubectl port-forward -n "$namespace" svc/"$service" $port &
    PIDS+=($!)
}

echo "=========================================="
echo "  EMS Platform Port Forward"
echo "=========================================="
echo ""

if [ -z "$1" ] || [ "$1" == "all" ]; then
    echo "Forwarding ALL services..."
    echo ""
    
    # ArgoCD
    forward argocd-server 8080 argocd
    forward argocd-server 443 argocd-https
    
    # Spark
    forward spark-master 8080 spark
    forward spark-master 7077 spark
    
    # Data Platform
    forward elasticsearch 9200
    forward kafka 9092
    forward debezium-connect 8083
    forward starrocks-fe 9030
    forward starrocks-fe 8030
    forward airflow-webserver 8080
    forward flink-jobmanager 8081
    
    # Ingress
    forward ingress-nginx-controller 80 ingress-nginx
    forward ingress-nginx-controller 443 ingress-nginx
    
else
    case "$1" in
        argocd|argo)
            forward argocd-server 8080 argocd
            ;;
        spark)
            forward spark-master 8080 spark
            forward spark-master 7077 spark
            ;;
        elasticsearch|es)
            forward elasticsearch 9200
            ;;
        kafka)
            forward kafka 9092
            ;;
        debezium|cdc)
            forward debezium-connect 8083
            ;;
        starrocks|sr)
            forward starrocks-fe 9030
            forward starrocks-fe 8030
            ;;
        airflow|af)
            forward airflow-webserver 8080
            ;;
        flink)
            forward flink-jobmanager 8081
            ;;
        ingress|nginx)
            forward ingress-nginx-controller 80 ingress-nginx
            forward ingress-nginx-controller 443 ingress-nginx
            ;;
        *)
            echo "Unknown service: $1"
            echo ""
            echo "Available services:"
            echo "  argocd          - ArgoCD Server (8080)"
            echo "  spark           - Spark Master (8080, 7077)"
            echo "  elasticsearch   - Elasticsearch (9200)"
            echo "  kafka           - Kafka (9092)"
            echo "  debezium       - Debezium CDC (8083)"
            echo "  starrocks       - StarRocks FE (9030, 8030)"
            echo "  airflow         - Airflow Webserver (8080)"
            echo "  flink           - Flink JobManager (8081)"
            echo "  ingress         - Ingress Nginx (80, 443)"
            echo "  all             - Forward all services"
            exit 1
            ;;
    esac
fi

echo ""
echo "=========================================="
echo "Ports:"
echo "  argocd         : localhost:8080"
echo "  spark          : localhost:8080, 7077"
echo "  elasticsearch  : localhost:9200"
echo "  kafka          : localhost:9092"
echo "  debezium       : localhost:8083"
echo "  starrocks      : localhost:9030, 8030"
echo "  airflow        : localhost:8080"
echo "  flink          : localhost:8081"
echo "  ingress        : localhost:80, 443"
echo "=========================================="
echo ""
echo "Press Ctrl+C to stop all forwards"

# Wait for all processes
wait
