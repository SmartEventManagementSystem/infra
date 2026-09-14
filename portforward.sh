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
    
    if ! kubectl get svc -n "$namespace" "$service" &>/dev/null; then
        echo "⚠️  Service $service not found"
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
    
    # ArgoCD
    forward argocd-server 18080 80 argocd
    
    # Spark
    forward spark-master 17080 8080 spark
    forward spark-master 17077 7077 spark
    
    # Data Platform
    forward elasticsearch 19200 9200 dataplatform
    forward kafka 19092 9092 dataplatform
    forward debezium-connect 18083 8083 dataplatform
    forward debezium-ui 18084 8080 dataplatform
    forward starrocks-fe 18030 8030 dataplatform
    forward starrocks-fe 19030 9030 dataplatform
    forward airflow-webserver 18081 8080 dataplatform
    forward flink-jobmanager 18082 8081 dataplatform
    forward kafka-ui 18085 8080 dataplatform
    
else
    case "$1" in
        argocd|argo)
            forward argocd-server 18080 80 argocd
            ;;
        spark)
            forward spark-master 17080 8080 spark
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
            forward debezium-ui 18084 8080 dataplatform
            ;;
        starrocks|sr)
            forward starrocks-fe 18030 8030 dataplatform
            forward starrocks-fe 19030 9030 dataplatform
            ;;
        airflow|af)
            forward airflow-webserver 18081 8080 dataplatform
            ;;
        flink)
            forward flink-jobmanager 18082 8081 dataplatform
            ;;
        kafka-ui)
            forward kafka-ui 18085 8080 dataplatform
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
echo "  spark          : localhost:17080, 17077"
echo "  elasticsearch  : localhost:19200"
echo "  kafka          : localhost:19092"
echo "  kafka-ui       : localhost:18085"
echo "  debezium       : localhost:18083"
echo "  debezium-ui    : localhost:18084"
echo "  starrocks      : localhost:18030 (UI), 19030 (SQL)"
echo "  airflow        : localhost:18081"
echo "  flink          : localhost:18082"
echo "=========================================="
echo ""
echo "Press Ctrl+C to stop all forwards"

wait
