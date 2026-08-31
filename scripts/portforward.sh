#!/bin/bash
# EMS Platform - Port Forward Script
# Usage: ./scripts/portforward.sh [service]
# Without arguments: starts all port-forwards

set -e

NAMESPACE="${NAMESPACE:-dataplatform}"
BG="${BG:-true}"

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m'

log() { echo -e "${GREEN}[$(date +%H:%M:%S)]${NC} $1"; }
info() { echo -e "${BLUE}[INFO]${NC} $1"; }

port_forward() {
    local name=$1
    local target=$2
    local local_port=$3
    local namespace=$4

    if [ "$BG" = "true" ]; then
        kubectl port-forward -n "$namespace" svc/"$target" $local_port:$local_port > /dev/null 2>&1 &
        echo $! > /tmp/pf-$name.pid
        log "Started: $name (http://localhost:$local_port)"
    else
        kubectl port-forward -n "$namespace" svc/"$target" $local_port:$local_port
    fi
}

stop_all() {
    info "Stopping all port-forwards..."
    for f in /tmp/pf-*.pid; do
        if [ -f "$f" ]; then
            name=$(basename "$f" .pid | sed 's/pf-//')
            pid=$(cat "$f")
            if kill -0 "$pid" 2>/dev/null; then
                kill "$pid" 2>/dev/null || true
                info "Stopped: $name"
            fi
            rm -f "$f"
        fi
    done
}

# Parse arguments
case "${1:-all}" in
    all)
        log "Starting all port-forwards..."

        # ArgoCD
        port_forward argocd argocd-server 8080 argocd
        port_forward argocd-redis argocd-redis 6379 argocd

        # Data Platform
        port_forward kafka kafka-headless 9092 dataplatform
        port_forward airflow airflow-webserver 8080 dataplatform
        port_forward flink flink-jobmanager 8081 dataplatform
        port_forward spark spark-history-server 18080 dataplatform
        port_forward openmetadata openmetadata 8585 dataplatform
        port_forward starrocks starrocks-fe 9030 dataplatform
        port_forward minio minio 9000 dataplatform

        echo ""
        info "All port-forwards started!"
        info "Press Ctrl+C to stop all"
        info ""
        echo -e "${YELLOW}Available services:${NC}"
        echo "  ArgoCD UI:        http://localhost:8080"
        echo "  ArgoCD Redis:     localhost:6379"
        echo "  Kafka:            localhost:9092"
        echo "  Airflow:          http://localhost:8080"
        echo "  Flink UI:         http://localhost:8081"
        echo "  Spark History:    http://localhost:18080"
        echo "  OpenMetadata:      http://localhost:8585"
        echo "  StarRocks FE:     localhost:9030"
        echo "  MinIO Console:    http://localhost:9001 (API: localhost:9000)"
        echo ""
        echo -e "${YELLOW}Default credentials:${NC}"
        echo "  ArgoCD: admin / (check kubectl get secret argocd-initial-admin-secret -n argocd)"
        echo "  MinIO: minioadmin / minioadmin"
        echo ""
        echo "Waiting... (Ctrl+C to stop)"
        wait
        ;;
    stop)
        stop_all
        ;;
    status)
        info "Port-forward status:"
        for f in /tmp/pf-*.pid; do
            if [ -f "$f" ]; then
                name=$(basename "$f" .pid | sed 's/pf-//')
                pid=$(cat "$f")
                if kill -0 "$pid" 2>/dev/null; then
                    echo -e "  ${GREEN}✓${NC} $name (PID: $pid)"
                else
                    echo -e "  ${YELLOW}✗${NC} $name (not running)"
                fi
            fi
        done
        ;;
    kafka|broker)
        port_forward kafka kafka-headless 9092 dataplatform
        wait
        ;;
    airflow|webserver)
        port_forward airflow airflow-webserver 8080 dataplatform
        wait
        ;;
    flink|jm)
        port_forward flink flink-jobmanager 8081 dataplatform
        wait
        ;;
    spark|history)
        port_forward spark spark-history-server 18080 dataplatform
        wait
        ;;
    openmetadata|om)
        port_forward openmetadata openmetadata 8585 dataplatform
        wait
        ;;
    starrocks|sr)
        port_forward starrocks starrocks-fe 9030 dataplatform
        wait
        ;;
    minio)
        port_forward minio minio 9000 dataplatform
        wait
        ;;
    argocd|argo)
        port_forward argocd argocd-server 8080 argocd
        wait
        ;;
    *)
        echo "Usage: $0 [all|stop|status|kafka|airflow|flink|spark|openmetadata|starrocks|minio|argocd]"
        echo ""
        echo "  all         - Start all port-forwards (default)"
        echo "  stop        - Stop all port-forwards"
        echo "  status      - Show status of all port-forwards"
        echo "  kafka       - Port forward Kafka broker"
        echo "  airflow     - Port forward Airflow webserver"
        echo "  flink       - Port forward Flink JobManager UI"
        echo "  spark       - Port forward Spark History Server"
        echo "  openmetadata - Port forward OpenMetadata"
        echo "  starrocks   - Port forward StarRocks FE"
        echo "  minio       - Port forward MinIO"
        echo "  argocd      - Port forward ArgoCD"
        exit 1
        ;;
esac
