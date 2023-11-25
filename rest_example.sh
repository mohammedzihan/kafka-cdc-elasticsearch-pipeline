

#!/usr/bin/env bash
chmod u+r+x rest_example.sh
chmod +x rest_example.sh


echo "Deploying ..."
#
# Ref: https://docs.ksqldb.io/en/latest/developer-guide/ksqldb-rest-api/ksql-endpoint/
#
# This works but is really horrid to look at, because the whole of the `ksql` value has to be a single line. WORKING!!
curl -s -XPOST "http://localhost:8083/connectors" -H  "Content-Type:application/json" -d '{
    "name": "SINK_ES_RATINGS",
    "config": {
        "connector.class" : "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
         "topics"          : "ratings",
"connection.url"  : "http://elasticsearch:9200",
    "type.name"       : "_doc",
    "key.ignore"      : "false",
    "schema.ignore"   : "true",
    "transforms": "ExtractTimestamp",
    "transforms.ExtractTimestamp.type": "org.apache.kafka.connect.transforms.InsertField$Value",
    "transforms.ExtractTimestamp.timestamp.field" : "RATING_TS"
    }
}'

sleep 10

curl --http1.1 \
     -X "POST" "http://localhost:8088/ksql" \
     -H "Accept: application/vnd.ksql.v1+json" \
     -H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
     -d '{"ksql":"CREATE STREAM RATINGS WITH (KAFKA_TOPIC='\''ratings'\'',VALUE_FORMAT='\''AVRO'\'');"}'

sleep 5

# # Splitting each command into a separate call makes more sense: 
curl --http1.1 \
-X "POST" "http://localhost:8088/ksql" \
-H "Accept: application/vnd.ksql.v1+json" \
-H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
-d '{"ksql":"CREATE STREAM RATINGS_LIVE AS SELECT * FROM RATINGS WHERE LCASE(CHANNEL) NOT LIKE '\''%test%'\'' EMIT CHANGES;"}'

sleep 5


curl --http1.1 \
     -X "POST" "http://localhost:8088/ksql" \
     -H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
     -d '{"ksql":"CREATE STREAM RATINGS_TEST AS SELECT * FROM RATINGS WHERE LCASE(CHANNEL) LIKE '\''%test%'\'' EMIT CHANGES;"}'

sleep 5


curl -s -XPUT "http://localhost:8083/connectors/register-mysql/config" -H  "Content-Type:application/json" -d '{
    "connector.class":"io.debezium.connector.mysql.MySqlConnector",
    "database.hostname":"mysql",
    "database.port":"3306",
    "database.user":"debezium",
    "database.password":"dbz",
    "database.server.id":"42",
    "database.server.name":"asgard",
    "table.whitelist":"demo.customers",
    "database.history.kafka.bootstrap.servers":"kafka:29092",
    "database.history.kafka.topic":"dbhistory.demo" ,
    "include.schema.changes":"false",
    "transforms": "unwrap,extractkey",
    "transforms.unwrap.type": "io.debezium.transforms.ExtractNewRecordState",
    "transforms.extractkey.type": "org.apache.kafka.connect.transforms.ExtractField$Key",
    "transforms.extractkey.field": "id",
    "key.converter": "org.apache.kafka.connect.storage.StringConverter",
    "value.converter": "io.confluent.connect.avro.AvroConverter",
    "value.converter.schema.registry.url": "http://schema-registry:8081"
 }'
 
sleep 10

curl --http1.1 \
-X "POST" "http://localhost:8088/ksql" \
-H "Accept: application/vnd.ksql.v1+json" \
-H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
-d '{"ksql":"CREATE TABLE CUSTOMERS (CUSTOMER_ID VARCHAR PRIMARY KEY) WITH (KAFKA_TOPIC='\''asgard.demo.CUSTOMERS'\'', VALUE_FORMAT='\''AVRO'\'');"}'

sleep 5

     # # Splitting each command into a separate call makes more sense: 
curl --http1.1 \
-X "POST" "http://localhost:8088/ksql" \
-H "Accept: application/vnd.ksql.v1+json" \
-H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
-d '{"ksql":"CREATE STREAM RATINGS_WITH_CUSTOMER_DATA WITH (KAFKA_TOPIC='\''ratings-enriched'\'') AS SELECT R.RATING_ID, R.MESSAGE, R.STARS, R.CHANNEL, C.CUSTOMER_ID, C.FIRST_NAME + '\'' '\'' + C.LAST_NAME AS FULL_NAME, C.CLUB_STATUS, C.EMAIL FROM RATINGS_LIVE R LEFT JOIN CUSTOMERS C ON CAST(R.USER_ID AS STRING) = C.CUSTOMER_ID WHERE C.FIRST_NAME IS NOT NULL EMIT CHANGES;"}'
sleep 5


curl -s -XPOST "http://localhost:8088/ksql" -H "Content-Type: application/vnd.ksql.v1+json" -d '{
"ksql": "CREATE STREAM UNHAPPY_PLATINUM_CUSTOMERS AS SELECT FULL_NAME, CLUB_STATUS, EMAIL, STARS, MESSAGE FROM RATINGS_WITH_CUSTOMER_DATA WHERE STARS < 3 AND CLUB_STATUS = '''platinum''' PARTITION BY FULL_NAME;",
"streamsProperties": {}
}'
sleep 5

curl -s -XPOST "http://localhost:8083/connectors" -H  "Content-Type:application/json" -d '{
    "name": "elastic-search",
    "config": {
        "connector.class" : "io.confluent.connect.elasticsearch.ElasticsearchSinkConnector",
        "connection.url" : "http://elasticsearch:9200",
        "type.name" : "",
        "behavior.on.malformed.documents" : "warn",
        "errors.tolerance" : "all",
        "errors.log.enable" : "true",
        "errors.log.include.messages" : "true",
        "topics" : "ratings-enriched,UNHAPPY_PLATINUM_CUSTOMERS",
        "key.ignore" : "true",
        "schema.ignore" : "true",
        "key.converter" : "org.apache.kafka.connect.storage.StringConverter",
        "transforms": "ExtractTimestamp",
        "transforms.ExtractTimestamp.type": "org.apache.kafka.connect.transforms.InsertField$Value",
        "transforms.ExtractTimestamp.timestamp.field" : "EXTRACT_TS"
    }
}'




 echo "Done !!"


