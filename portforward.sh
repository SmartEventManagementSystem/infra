#!/bin/bash

# EMS Platform Port Forward Script
# Usage: ./portforward.sh [service]

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
    local local_port=$2
    local svc_port=$3
    local namespace=${4:-dataplatform}
    
    # Check if service exists first
    if ! kubectl get svc -n "$namespace" "$service" &>/dev/null; then
        echo "⚠️  Service $service not found in namespace $namespace"
        return 1
    fi
    
    echo "Forwarding $service -> localhost:$local_port..."
    kubectl port-forward -n "$namespace" svc/"$service" ${local_port}:${svc_port} &
    PIDS+=($!)
}

echo "=========================================="
echo "  EMS Platform Port Forward"
echo "=========================================="
echo ""

if [ -z "$1" ] || [ "$1" == "all" ]; then
    echo "Forwarding ALL services..."
    echo ""
    
    # ArgoCD - dùng port 18080 trên local
    forward argocd-server 18080 80 argocd
    
    # Spark - dùng port 18080 và 17077
    forward spark-master 18080 80 spark
    forward spark-master 17077 7077 spark
    
    # Data Platform - dùng port khác để tránh conflict
    forward elasticsearch 19200 9200 dataplatform
    forward kafka 19092 9092 dataplatform
    forward debezium-connect 18083 8083 dataplatform
    forward starrocks-fe 19030 9030 dataplatform
    forward starrocks-fe 18030 8030 dataplatform
    forward airflow-webserver 18080 8080 dataplatform
    forward flink-jobmanager 18081 8081 dataplatform
    
else
    case "$1" in
        argocd|argo)
            forward argocd-server 18080 80 argocd
            ;;
        spark)
            forward spark-master 18080 80 spark
            forward spark-master 17077 7077 spark
            ;;
        elasticsearch|es)
            forward elasticsearch 19200 9200 dataplatform
            ;;
        kafka)
            forward kafka 19092 9092 dataplatform
            ;;
        debezium|cdc)
            forward debezium-connect 18083 8083 dataplatform
            ;;
        starrocks|sr)
            forward starrocks-fe 19030 9030 dataplatform
            forward starrocks-fe 18030 8030 dataplatform
            ;;
        airflow|af)
            forward airflow-webserver 18080 8080 dataplatform
            ;;
        flink)
            forward flink-jobmanager 18081 8081 dataplatform
            ;;
        *)
            echo "Unknown service: $1"
            exit 1
            ;;
    esac
fi

echo ""
echo "=========================================="
echo "Available endpoints:"
echo "  argocd         : localhost:18080"
echo "  spark          : localhost:18080, 17077"
echo "  elasticsearch  : localhost:19200"
echo "  kafka          : localhost:19092"
echo "  debezium       : localhost:18083"
echo "  starrocks      : localhost:19030, 18030"
echo "  airflow        : localhost:18080"
echo "  flink          : localhost:18081"
echo "=========================================="
echo ""
echo "Press Ctrl+C to stop all forwards"

wait
