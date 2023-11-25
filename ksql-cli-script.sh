#!/bin/bash

# while : ; do
#     curl_status=$(curl -s -o /dev/null -w %{http_code} http://ksqldb:8088/info)
#     echo -e $(date) " ksqlDB server listener HTTP state: " $curl_status " (waiting for 200)"
#     if [ $curl_status -eq 200 ] ; then
#         break
#     fi
#     sleep 5
# done



docker exec ksqldb ksql http://ksql:8088 <<EOF 

CREATE SINK CONNECTOR SINK_ES_RATINGS WITH (
    'connector.class' = 'io.confluent.connect.elasticsearch.ElasticsearchSinkConnector',
    'topics'          = 'ratings',
    'connection.url'  = 'http://elasticsearch:9200',
    'type.name'       = '_doc',
    'key.ignore'      = 'false',
    'schema.ignore'   = 'true',
    'transforms'= 'ExtractTimestamp',
    'transforms.ExtractTimestamp.type'= 'org.apache.kafka.connect.transforms.InsertField$Value',
    'transforms.ExtractTimestamp.timestamp.field' = 'RATING_TS'
);
EOF
CREATE SOURCE CONNECTOR SOURCE_MYSQL_01 WITH (
    "connector.class" = "io.debezium.connector.mysql.MySqlConnector",
    "database.hostname" = "mysql",
    "database.port" = "3306",
    "database.user" = "debezium",
    "database.password" = "dbz",
    "database.server.id" = "42",
    "database.server.name" = "asgard",
    "table.whitelist" = "demo.customers",
    "database.history.kafka.bootstrap.servers" = "kafka:29092",
    "database.history.kafka.topic" = "dbhistory.demo" ,
    "include.schema.changes" = "false",
    "transforms"= "unwrap,extractkey",
    "transforms.unwrap.type"= "io.debezium.transforms.ExtractNewRecordState",
    "transforms.extractkey.type"= "org.apache.kafka.connect.transforms.ExtractField$Key",
    "transforms.extractkey.field"= "id",
    "key.converter"= "org.apache.kafka.connect.storage.StringConverter",
    "value.converter"= "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url"= "http://schema-registry:8081"
    );

CREATE STREAM RATINGS WITH (KAFKA_TOPIC='ratings',VALUE_FORMAT='AVRO');
CREATE STREAM RATINGS WITH (KAFKA_TOPIC='ratingssssss',VALUE_FORMAT='AVRO');

SELECT USER_ID, STARS, CHANNEL, MESSAGE FROM RATINGS WHERE LCASE(CHANNEL) NOT LIKE '%test%' EMIT CHANGES;

CREATE STREAM RATINGS_LIVE AS
SELECT * FROM RATINGS WHERE LCASE(CHANNEL) NOT LIKE '%test%' EMIT CHANGES;

CREATE STREAM RATINGS_TEST AS
SELECT * FROM RATINGS WHERE LCASE(CHANNEL) LIKE '%test%' EMIT CHANGES;

SELECT * FROM RATINGS_LIVE EMIT CHANGES LIMIT 5;
SELECT * FROM RATINGS_TEST EMIT CHANGES LIMIT 5;



CREATE TABLE CUSTOMERS (CUSTOMER_ID VARCHAR PRIMARY KEY)
  WITH (KAFKA_TOPIC='asgard.demo.CUSTOMERS', VALUE_FORMAT='AVRO');

EOF
