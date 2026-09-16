#!/bin/bash

# ============================================
# EMS Platform Port Forward Script
# ============================================
#
# CREDENTIALS & ACCESS INFO:
#
# ARGOCD
#   URL: http://localhost:18080
#   Username: admin
#   Password: YJ5zTqFY8QdZX1uP
#
# AIRFLOW
#   URL: http://localhost:18081
#   Username: admin
#   Password: admin123
#
# ELASTICSEARCH
#   URL: http://localhost:19200
#   No authentication required
#
# KAFKA
#   URL: localhost:19092
#   Use Kafka UI (localhost:18085) or Kafka CLI
#
# KAFKA UI
#   URL: http://localhost:18085
#   No authentication required
#
# DEBEZIUM CONNECT
#   URL: http://localhost:18083
#   REST API for CDC connectors
#
# DEBEZIUM UI
#   URL: http://localhost:18084
#   No authentication required
#
# FLINK
#   URL: http://localhost:18082
#   No authentication required
#
# SPARK
#   URL: http://localhost:17080
#   No authentication required
#
# MYSQL
#   Host: localhost:13306
#   Username: root
#   Password: mysqlroot123
#   Database: ems
#   Connect: mysql -h localhost -P 13306 -u root -p
#
# POSTGRESQL
#   Host: localhost:15432
#   Username: postgres
#   Password: postgres123
#   Database: ems
#   Connect: psql -h localhost -p 15432 -U postgres -d ems
#
# GCP BIGQUERY
#   Project: project-5ca79767-316d-4e68-a56
#   Region: asia-southeast1
#   Dataset: ems_analytics
#
# GCP BIGTABLE
#   Instance: ems-nosql
#   Cluster: ems-nosql-cluster
#   Zone: asia-southeast1-b
#
# ============================================

# Cleanup on exit
cleanup() {
    echo ""
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
