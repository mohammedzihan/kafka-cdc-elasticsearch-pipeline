= Streaming ETL POC
Techncologoes Used: MySQL, Kafka, kSQLDB, ElasticSearch

image:images/ksql-debezium-es.png[Kafka Connect / ksqlDB / Elasticsearch]

This is designed to be run as a step-by-step demo. The `ksqldb-statements.sql` should match those run in this doc end-to-end and in theory you can just run the file, but I have not tested it. PRs welcome for a one-click script that just demonstrates the end-to-end running demo :)

== Pre-Flight Setup

Start the environment

## [source,bash]

## docker-compose up -d

## [source,bash]

bash -c ' \
echo -e "\n\n=============\nWaiting for Kafka Connect to start listening on localhost ⏳\n=============\n"
while [ $(curl -s -o /dev/null -w %{http_code} http://localhost:8083/connectors) -ne 200 ] ; do
echo -e "\t" $(date) " Kafka Connect listener HTTP state: " $(curl -s -o /dev/null -w %{http_code} http://localhost:8083/connectors) " (waiting for 200)"
sleep 5  
done
echo -e $(date) "\n\n--------------\n\o/ Kafka Connect is ready! Listener HTTP state: " $(curl -s -o /dev/null -w %{http_code} http://localhost:8083/connectors) "\n--------------\n"
'

---

The Elasticsearch, Debezium, and DataGen connectors should be available:

## [source,bash]

## curl -s localhost:8083/connector-plugins|jq '.[].class'|egrep 'DatagenConnector|MySqlConnector|ElasticsearchSinkConnector'

Expect:

## [source,bash]

"io.confluent.connect.elasticsearch.ElasticsearchSinkConnector"
"io.confluent.kafka.connect.datagen.DatagenConnector"
"io.debezium.connector.mysql.MySqlConnector"

---

=== Run ksqlDB CLI and MySQL CLI

Optionally, use something like `screen` or `tmux` to have these both easily to hand. Or multiple Terminal tabs. Whatever works for you :)

- ksqlDB CLI:

* ## [source,bash]
  ## docker exec -it ksqldb bash -c 'echo -e "\n\n⏳ Waiting for ksqlDB to be available before launching CLI\n"; while : ; do curl_status=$(curl -s -o /dev/null -w %{http_code} http://ksqldb:8088/info) ; echo -e $(date) " ksqlDB server listener HTTP state: " $curl_status " (waiting for 200)" ; if [ $curl_status -eq 200 ] ; then break ; fi ; sleep 5 ; done ; ksql http://ksqldb:8088'

== Pre-flight checklist

- Load http://localhost:5601/app/kibana#/dashboard/mysql-ksql-kafka-es[Kibana ratings dashboard]

== Demo

image:images/ksql-debezium-es.png[Kafka Connect / ksqlDB / Elasticsearch]

== Part 00 - Kafka Connect for streaming data to other systems

## [source,sql]

## SHOW TOPICS;

## [source,sql]

## PRINT ratings;

## [source,sql]

CREATE SINK CONNECTOR SINK_ES_RATINGS WITH (
'connector.class' = 'io.confluent.connect.elasticsearch.ElasticsearchSinkConnector',
'topics' = 'ratings',
'connection.url' = 'http://elasticsearch:9200',
'type.name' = '\_doc',
'key.ignore' = 'false',
'schema.ignore' = 'true',
'transforms'= 'ExtractTimestamp',
'transforms.ExtractTimestamp.type'= 'org.apache.kafka.connect.transforms.InsertField$Value',
'transforms.ExtractTimestamp.timestamp.field' = 'RATING_TS'
);

---

- **Show in Kibana** (http://localhost:5601/app/management/kibana/indexPatterns)

== Part 01 - ksqlDB for filtering streams

=== Inspect topics

## [source,sql]

## SHOW TOPICS;

## [source,bash]

ksql> SHOW TOPICS;

## Kafka Topic | Partitions | Partition Replicas

confluent_rmoff_02ksql_processing_log | 1 | 1
ratings | 1 | 1

---

---

=== Inspect ratings & define stream

## [source,sql]

## CREATE STREAM RATINGS WITH (KAFKA_TOPIC='ratings',VALUE_FORMAT='AVRO');

=== Select columns from live stream of data

## [source,sql]

## SELECT USER_ID, STARS, CHANNEL, MESSAGE FROM RATINGS EMIT CHANGES;

=== Filter live stream of data

## [source,sql]

## SELECT USER_ID, STARS, CHANNEL, MESSAGE FROM RATINGS WHERE LCASE(CHANNEL) NOT LIKE '%test%' EMIT CHANGES;

=== Create a derived stream

## [source,sql]

CREATE STREAM RATINGS_LIVE AS
SELECT \* FROM RATINGS WHERE LCASE(CHANNEL) NOT LIKE '%test%' EMIT CHANGES;

CREATE STREAM RATINGS_TEST AS
SELECT \* FROM RATINGS WHERE LCASE(CHANNEL) LIKE '%test%' EMIT CHANGES;

---

## [source,sql]

SELECT _ FROM RATINGS_LIVE EMIT CHANGES LIMIT 5;
SELECT _ FROM RATINGS_TEST EMIT CHANGES LIMIT 5;

---

## [source,sql]

## DESCRIBE RATINGS_LIVE EXTENDED;

== Part 02 - ingesting state from a database as an event stream

=== Show MySQL table + contents

Launch the MySQL CLI:

## [source,bash]

## docker exec -it mysql bash -c 'mysql -u $MYSQL_USER -p$MYSQL_PASSWORD demo'

## [source,sql]

## SHOW TABLES;

## [source,sql]

+----------------+
| Tables_in_demo |
+----------------+
| CUSTOMERS |
+----------------+
1 row in set (0.00 sec)

---

## [source,sql]

## SELECT ID, FIRST_NAME, LAST_NAME, EMAIL, CLUB_STATUS FROM CUSTOMERS LIMIT 5;

## [source,sql]

+----+-------------+------------+------------------------+-------------+
| ID | FIRST_NAME | LAST_NAME | EMAIL | CLUB_STATUS |
+----+-------------+------------+------------------------+-------------+
| 1 | Rica | Blaisdell | rblaisdell0@rambler.ru | bronze |
| 2 | Ruthie | Brockherst | rbrockherst1@ow.ly | platinum |
| 3 | Mariejeanne | Cocci | mcocci2@techcrunch.com | bronze |
| 4 | Hashim | Rumke | hrumke3@sohu.com | platinum |
| 5 | Hansiain | Coda | hcoda4@senate.gov | platinum |
+----+-------------+------------+------------------------+-------------+
5 rows in set (0.00 sec)

---

=== Ingest the data (plus any new changes) into Kafka

In ksqlDB:

## [source,sql]

CREATE SOURCE CONNECTOR SOURCE_MYSQL_01 WITH (
'connector.class' = 'io.debezium.connector.mysql.MySqlConnector',
'database.hostname' = 'mysql',
'database.port' = '3306',
'database.user' = 'debezium',
'database.password' = 'dbz',
'database.server.id' = '42',
'database.server.name' = 'asgard',
'table.whitelist' = 'demo.customers',
'database.history.kafka.bootstrap.servers' = 'kafka:29092',
'database.history.kafka.topic' = 'dbhistory.demo' ,
'include.schema.changes' = 'false',
'transforms'= 'unwrap,extractkey',
'transforms.unwrap.type'= 'io.debezium.transforms.ExtractNewRecordState',
'transforms.extractkey.type'= 'org.apache.kafka.connect.transforms.ExtractField$Key',
'transforms.extractkey.field'= 'id',
'key.converter'= 'org.apache.kafka.connect.storage.StringConverter',
'value.converter'= 'io.confluent.connect.avro.AvroConverter',
'value.converter.schema.registry.url'= 'http://schema-registry:8081'
);

---

Check that it's running:

## [source,sql]

ksql> SHOW CONNECTORS;

## Connector Name | Type | Class | Status

source-datagen-01 | SOURCE | io.confluent.kafka.connect.datagen.DatagenConnector | RUNNING (1/1 tasks RUNNING)
SOURCE_MYSQL_01 | SOURCE | io.debezium.connector.mysql.MySqlConnector | RUNNING (1/1 tasks RUNNING)

---

---

=== Show Kafka topic has been created & populated

## [source,sql]

## SHOW TOPICS;

## [source,sql]

ksql> SHOW TOPICS;

## Kafka Topic | Partitions | Partition Replicas

RATINGS_LIVE | 1 | 1
asgard.demo.CUSTOMERS | 1 | 1
confluent_rmoff_02ksql_processing_log | 1 | 1
dbhistory.demo | 1 | 1
ratings | 1 | 1

---

---

Show topic contents

## [source,sql]

## PRINT 'asgard.demo.CUSTOMERS' FROM BEGINNING;

## [source,sql]

Key format: JSON or KAFKA_STRING
Value format: AVRO or KAFKA_STRING
rowtime: 2021/09/08 08:28:47.103 Z, key: 1, value: {"id": 1, "first_name": "Rica", "last_name": "Blaisdell", "email": "rblaisdell0@rambler.ru", "gender": "Female", "club_status": "bronze","comments": "Universal optimal hierarchy", "create_ts": "2021-09-08T08:03:24Z", "update_ts": "2021-09-08T08:03:24Z"}, partition: 0
rowtime: 2021/09/08 08:28:47.125 Z, key: 2, value: {"id": 2, "first_name": "Ruthie", "last_name": "Brockherst", "email": "rbrockherst1@ow.ly", "gender": "Female", "club_status": "platinum", "comments": "Reverse-engineered tangible interface", "create_ts": "2021-09-08T08:03:24Z", "update_ts": "2021-09-08T08:03:24Z"}, partition: 0
…

---

Create ksqlDB stream and table

## [source,sql]

CREATE TABLE CUSTOMERS (CUSTOMER_ID VARCHAR PRIMARY KEY)
WITH (KAFKA_TOPIC='asgard.demo.CUSTOMERS', VALUE_FORMAT='AVRO');

---

Query the ksqlDB table:

## [source,sql]

SET 'auto.offset.reset' = 'earliest';
SELECT CUSTOMER_ID, FIRST_NAME, LAST_NAME, EMAIL, CLUB_STATUS FROM CUSTOMERS EMIT CHANGES LIMIT 5;

---

==== Make changes in MySQL, observe it in Kafka

MySQL terminal:

## [source,sql]

## INSERT INTO CUSTOMERS (ID,FIRST_NAME,LAST_NAME) VALUES (42,'Rick','Astley');

## [source,sql]

## UPDATE CUSTOMERS SET EMAIL = 'rick@example.com' where ID=42;

## [source,sql]

## UPDATE CUSTOMERS SET CLUB_STATUS = 'bronze' where ID=42;

## [source,sql]

## UPDATE CUSTOMERS SET CLUB_STATUS = 'platinum' where ID=42;

==== [Optional] Demonstrate Stream / Table difference

Check the data in ksqlDB:

Here's the table - the latest value for a given key
[source,sql]

---

SELECT TIMESTAMPTOSTRING(ROWTIME, 'HH:mm:ss') AS EVENT_TS,
CUSTOMER_ID,
FIRST_NAME,
LAST_NAME,
EMAIL,
CLUB_STATUS
FROM CUSTOMERS WHERE ID=42
EMIT CHANGES;

---

## [source,sql]

+-----------+-------------+-----------+----------+-----------------+------------+
|EVENT_TS |CUSTOMER_ID |FIRST_NAME |LAST_NAME |EMAIL |CLUB_STATUS |
+-----------+-------------+-----------+----------+-----------------+------------+
|09:20:15 |42 |Rick |Astley |rick@example.com |platinum |
^CQuery terminated

---

Here's the stream - every event, which in this context is every change event on the source database:

## [source,sql]

CREATE STREAM CUSTOMERS_STREAM (CUSTOMER_ID VARCHAR KEY) WITH (KAFKA_TOPIC='asgard.demo.CUSTOMERS', VALUE_FORMAT='AVRO');

SET 'auto.offset.reset' = 'earliest';

SELECT TIMESTAMPTOSTRING(ROWTIME, 'HH:mm:ss') AS EVENT_TS,
CUSTOMER_ID,
FIRST_NAME,
LAST_NAME,
EMAIL,
CLUB_STATUS
FROM CUSTOMERS_STREAM WHERE ID=42
EMIT CHANGES;

---

## [source,sql]

+----------+------------+-----------+----------+-----------------+------------+
|EVENT_TS |CUSTOMER_ID |FIRST_NAME |LAST_NAME |EMAIL |CLUB_STATUS |
+----------+------------+-----------+----------+-----------------+------------+
|09:20:07 |42 |Rick |Astley |null |null |
|09:20:10 |42 |Rick |Astley |rick@example.com |null |
|09:20:13 |42 |Rick |Astley |rick@example.com |bronze |
|09:20:15 |42 |Rick |Astley |rick@example.com |platinum |
^CQuery terminated
ksql>

---

== Part 03 - ksqlDB for joining streams

=== Join live stream of ratings to customer data

## [source,sql]

SELECT R.RATING_ID, R.MESSAGE, R.CHANNEL,
C.CUSTOMER_ID, C.FIRST_NAME + ' ' + C.LAST_NAME AS FULL_NAME,
C.CLUB_STATUS
FROM RATINGS_LIVE R
LEFT JOIN CUSTOMERS C
ON CAST(R.USER_ID AS STRING) = C.CUSTOMER_ID  
WHERE C.FIRST_NAME IS NOT NULL
EMIT CHANGES;

---

## [source,sql]

+------------+-----------------------------------+------------+--------------------+-------------+
|RATING_ID |MESSAGE |CUSTOMER_ID |FULL_NAME |CLUB_STATUS |
+------------+-----------------------------------+------------+--------------------+-------------+
|1 |more peanuts please |9 |Even Tinham |silver |
|2 |Exceeded all my expectations. Thank|8 |Patti Rosten |silver |
| | you ! | | | |
|3 |meh |17 |Brianna Paradise |bronze |
|4 |is this as good as it gets? really |14 |Isabelita Talboy |gold |
| |? | | | |
|5 |why is it so difficult to keep the |19 |Josiah Brockett |gold |
| |bathrooms clean ? | | | |
…

---

Persist this stream of data

## [source,sql]

SET 'auto.offset.reset' = 'earliest';
CREATE STREAM RATINGS_WITH_CUSTOMER_DATA
WITH (KAFKA_TOPIC='ratings-enriched')
AS
SELECT R.RATING_ID, R.MESSAGE, R.STARS, R.CHANNEL,
C.CUSTOMER_ID, C.FIRST_NAME + ' ' + C.LAST_NAME AS FULL_NAME,
C.CLUB_STATUS, C.EMAIL
FROM RATINGS_LIVE R
LEFT JOIN CUSTOMERS C
ON CAST(R.USER_ID AS STRING) = C.CUSTOMER_ID  
WHERE C.FIRST_NAME IS NOT NULL
EMIT CHANGES;

---

=== [Optional] Examine changing reference data

CUSTOMERS is a ksqlDB _table_, which means that we have the latest value for a given key.

Check out the ratings for customer id 2 only:
[source,sql]

---

SELECT TIMESTAMPTOSTRING(ROWTIME, 'HH:mm:ss') AS EVENT_TS,
FULL_NAME, CLUB_STATUS, STARS, MESSAGE, CHANNEL
FROM RATINGS_WITH_CUSTOMER_DATA
WHERE CAST(CUSTOMER_ID AS INT)=2
EMIT CHANGES;

---

In mysql, make a change to ID 2

## [source,sql]

## UPDATE CUSTOMERS SET CLUB_STATUS = 'bronze' WHERE ID=2;

Observe in the continuous ksqlDB query that the customer name has now changed.

=== Create stream of unhappy VIPs

## [source,sql]

CREATE STREAM UNHAPPY_PLATINUM_CUSTOMERS AS
SELECT FULL_NAME, CLUB_STATUS, EMAIL, STARS, MESSAGE
FROM RATINGS_WITH_CUSTOMER_DATA
WHERE STARS < 3
AND CLUB_STATUS = 'platinum'
PARTITION BY FULL_NAME;

---

== Stream to Elasticsearch

## [source,sql]

CREATE SINK CONNECTOR SINK_ELASTIC_01 WITH (
'connector.class' = 'io.confluent.connect.elasticsearch.ElasticsearchSinkConnector',
'connection.url' = 'http://elasticsearch:9200',
'type.name' = '',
'behavior.on.malformed.documents' = 'warn',
'errors.tolerance' = 'all',
'errors.log.enable' = 'true',
'errors.log.include.messages' = 'true',
'topics' = 'ratings-enriched,UNHAPPY_PLATINUM_CUSTOMERS',
'key.ignore' = 'true',
'schema.ignore' = 'true',
'key.converter' = 'org.apache.kafka.connect.storage.StringConverter',
'transforms'= 'ExtractTimestamp',
'transforms.ExtractTimestamp.type'= 'org.apache.kafka.connect.transforms.InsertField$Value',
'transforms.ExtractTimestamp.timestamp.field' = 'EXTRACT_TS'
);

---

Check status

## [source,sql]

ksql> SHOW CONNECTORS;

## Connector Name | Type | Class | Status

source-datagen-01 | SOURCE | io.confluent.kafka.connect.datagen.DatagenConnector | RUNNING (1/1 tasks RUNNING)
SOURCE_MYSQL_01 | SOURCE | io.debezium.connector.mysql.MySqlConnector | RUNNING (1/1 tasks RUNNING)
SINK_ELASTIC_00 | SINK | io.confluent.connect.elasticsearch.ElasticsearchSinkConnector | RUNNING (1/1 tasks RUNNING)

---

---

Check data in Elasticsearch:

## [source,bash]

## docker exec elasticsearch curl -s "http://localhost:9200/\_cat/indices/\*?h=idx,docsCount"

## [source,bash]

unhappy_platinum_customers 1
.kibana_task_manager_1 2
.apm-agent-configuration 0
kafka-ratings-enriched-2018-08 1
.kibana_1 11
ratings-enriched 3699

---

=== View in Kibana

Tested on Elasticsearch 7.5.0

http://localhost:5601/app/kibana#/dashboard/mysql-ksql-kafka-es

image:images/es02.png[Kibana]

image:images/es03.png[Kibana]

== Aggregations

Simple aggregation - count of ratings per person, per 15 minutes:

## [source,sql]

CREATE TABLE RATINGS_PER_CUSTOMER_PER_15MINUTE AS
SELECT FULL_NAME,COUNT(\*) AS RATINGS_COUNT, COLLECT_LIST(STARS) AS RATINGS
FROM RATINGS_WITH_CUSTOMER_DATA
WINDOW TUMBLING (SIZE 15 MINUTE)
GROUP BY FULL_NAME
EMIT CHANGES;

---

==== Push Query

## [source,sql]

SELECT TIMESTAMPTOSTRING(WINDOWSTART, 'yyyy-MM-dd HH:mm:ss') AS WINDOW_START_TS,
FULL_NAME,
RATINGS_COUNT,
RATINGS
FROM RATINGS_PER_CUSTOMER_PER_15MINUTE
WHERE FULL_NAME='Rica Blaisdell'
EMIT CHANGES;

---

==== Pull Query

## [source,sql]

SELECT TIMESTAMPTOSTRING(WINDOWSTART, 'yyyy-MM-dd HH:mm:ss') AS WINDOW_START_TS,
FULL_NAME,
RATINGS_COUNT,
RATINGS
FROM RATINGS_PER_CUSTOMER_PER_15MINUTE
WHERE FULL_NAME='Rica Blaisdell'
AND WINDOWSTART > '2020-07-06T15:30:00.000';

---

Show REST API with link:ksqlDB.postman_collection.json[Postman] or bash:

## [source,bash]

## docker exec -it ksqldb bash

Copy and paste:

## [source,bash]

# Store the epoch (milliseconds) fifteen minutes ago

PREDICATE=$(date --date '-15 min' +%s)000

# Pull from ksqlDB the aggregate-by-minute for the last five minutes for a given user:

curl -X "POST" "http://ksqldb:8088/query" \
 -H "Content-Type: application/vnd.ksql.v1+json; charset=utf-8" \
 -d '{"ksql":"SELECT TIMESTAMPTOSTRING(WINDOWSTART, '\''yyyy-MM-dd HH:mm:ss'\'') AS WINDOW_START_TS, FULL_NAME, RATINGS_COUNT, RATINGS FROM RATINGS_PER_CUSTOMER_PER_15MINUTE WHERE FULL_NAME='\''Rica Blaisdell'\'' AND WINDOWSTART > '$PREDICATE';"}'

---

Press Ctrl-D to exit the Docker container

== Appendix - compare filtered vs unfiltered data

Bring up a second ksqlDB prompt and show live ratings / live filtered ratings:

## [source,sql]

-- Live stream of ratings data
SET 'auto.offset.reset' = 'latest';
PRINT 'ratings';

-- You can use SELECT too, but PRINT makes it clearer that it's coming from a topic
SELECT TIMESTAMPTOSTRING(ROWTIME, 'yyyy-MM-dd HH:mm:ss') AS RATING_TIMESTAMP, STARS, CHANNEL FROM RATINGS EMIT CHANGES;

---

## [source,sql]

-- Just the ratings not from a test channel:
SET 'auto.offset.reset' = 'latest';
PRINT 'RATINGS_LIVE';

-- You can use SELECT too, but PRINT makes it clearer that it's coming from a topic
SELECT TIMESTAMPTOSTRING(ROWTIME, 'yyyy-MM-dd HH:mm:ss') AS RATING_TIMESTAMP, STARS, CHANNEL FROM RATINGS_LIVE EMIT CHANGES;

---
