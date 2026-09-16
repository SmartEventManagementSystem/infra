#!/bin/bash

# Cleanup
cleanup() {
    echo "Stopping port forwards..."
    pkill -f "kubectl port-forward" 2>/dev/null
    exit 0
}
trap cleanup SIGINT SIGTERM

echo "=========================================="
echo "  EMS Platform Port Forward"
echo "=========================================="

# Start all port forwards
kubectl port-forward -n argocd svc/argocd-server 18080:80 > /dev/null 2>&1 &
kubectl port-forward -n dataplatform svc/elasticsearch 19200:9200 > /dev/null 2>&1 &
kubectl port-forward -n dataplatform svc/kafka 19092:9092 > /dev/null 2>&1 &
kubectl port-forward -n dataplatform svc/debezium-connect 18083:8083 > /dev/null 2>&1 &
kubectl port-forward -n dataplatform svc/debezium-ui 18084:8080 > /dev/null 2>&1 &
kubectl port-forward -n dataplatform svc/kafka-ui 18085:8080 > /dev/null 2>&1 &
kubectl port-forward -n dataplatform svc/airflow-webserver 18081:8080 > /dev/null 2>&1 &
kubectl port-forward -n dataplatform svc/flink-jobmanager 18082:8081 > /dev/null 2>&1 &
kubectl port-forward -n spark svc/spark-master 17080:8080 > /dev/null 2>&1 &
kubectl port-forward -n dataplatform svc/mysql 13306:3306 > /dev/null 2>&1 &
kubectl port-forward -n dataplatform svc/postgres 15432:5432 > /dev/null 2>&1 &

sleep 3

echo ""
echo "=========================================="
echo "Available endpoints:"
echo "  argocd         : localhost:18080"
echo "  elasticsearch  : localhost:19200"
echo "  kafka          : localhost:19092"
echo "  kafka-ui       : localhost:18085"
echo "  debezium       : localhost:18083"
echo "  debezium-ui    : localhost:18084"
echo "  airflow        : localhost:18081"
echo "  flink          : localhost:18082"
echo "  spark          : localhost:17080"
echo "  mysql          : localhost:13306"
echo "  postgres       : localhost:15432"
echo "=========================================="
echo ""
echo "Press Ctrl+C to stop all forwards"
echo ""

wait
