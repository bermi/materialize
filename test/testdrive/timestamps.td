# Copyright Materialize, Inc. All rights reserved.
#
# Use of this software is governed by the Business Source License
# included in the LICENSE file at the root of this repository.
#
# As of the Change Date specified in that file, in accordance with
# the Business Source License, use of this software will be governed
# by the Apache License, Version 2.0.

$ set schema={
    "type": "record",
    "name": "envelope",
    "fields": [
      {
        "name": "before",
        "type": [
          {
            "name": "row",
            "type": "record",
            "fields": [
              {"name": "a", "type": "long"},
              {"name": "b", "type": "long"}
            ]
          },
          "null"
        ]
      },
      { "name": "after", "type": ["row", "null"] }
    ]
  }

$ kafka-create-topic topic=data-consistency

$ kafka-ingest format=bytes topic=data-consistency timestamp=1
dummy,1,0,0,0

$ kafka-create-topic topic=data

$ kafka-ingest format=avro topic=data schema=${schema} timestamp=1
{"before": null, "after": {"a": 1, "b": 1}}
{"before": null, "after": {"a": 2, "b": 1}}
{"before": null, "after": {"a": 3, "b": 1}}
{"before": null, "after": {"a": 1, "b": 2}}

$ kafka-create-topic topic=data2

$ kafka-ingest format=avro topic=data2 schema=${schema} timestamp=1
{"before": null, "after": {"a": 1, "b": 1}}
{"before": null, "after": {"a": 2, "b": 1}}
{"before": null, "after": {"a": 3, "b": 1}}
{"before": null, "after": {"a": 1, "b": 2}}

> CREATE MATERIALIZED SOURCE data_byo
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-data-${testdrive.seed}'
    WITH (consistency = 'testdrive-data-consistency-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${schema}'
  ENVELOPE DEBEZIUM

> CREATE MATERIALIZED SOURCE data2_byo
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-data2-${testdrive.seed}'
    WITH (consistency = 'testdrive-data-consistency-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${schema}'
  ENVELOPE DEBEZIUM

> CREATE MATERIALIZED SOURCE data3_byo
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-data3-${testdrive.seed}'
      WITH (consistency = 'testdrive-data-consistency-${testdrive.seed}')
  FORMAT AVRO USING SCHEMA '${schema}'
  ENVELOPE DEBEZIUM

> CREATE MATERIALIZED SOURCE data_rt
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-data-${testdrive.seed}'
  FORMAT AVRO USING SCHEMA '${schema}'
  ENVELOPE DEBEZIUM

> CREATE MATERIALIZED SOURCE data2_rt
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-data2-${testdrive.seed}'
  FORMAT AVRO USING SCHEMA '${schema}'
  ENVELOPE DEBEZIUM

> CREATE MATERIALIZED VIEW view_byo AS SELECT b, sum(a) FROM data_byo GROUP BY b

> CREATE MATERIALIZED VIEW view2_byo AS SELECT b, sum(a) FROM data2_byo GROUP BY b

> CREATE MATERIALIZED VIEW view_empty AS SELECT data2_byo.a,data3_byo.a FROM data2_byo,data3_byo WHERE data2_byo.b=data3_byo.b

> CREATE MATERIALIZED VIEW view_rt AS SELECT b, sum(a) FROM data_rt GROUP BY b

> CREATE MATERIALIZED VIEW view2_rt AS SELECT b, sum(a) FROM data2_rt GROUP BY b

! SELECT * FROM view_byo;
At least one input has no complete timestamps yet.

$ kafka-ingest format=bytes topic=data-consistency timestamp=1
testdrive-data-${testdrive.seed},1,0,1,1
testdrive-data2-${testdrive.seed},1,0,1,4

> SELECT * FROM view_byo
b  sum
------
1 1

> SELECT * FROM view2_byo
b  sum
------
1  6
2  1

$ kafka-ingest format=bytes topic=data-consistency timestamp=2
testdrive-data-${testdrive.seed},1,0,2,4

> SELECT * FROM view2_byo
b  sum
------
1  6
2  1

!SELECT * FROM view_empty
At least one input has no complete timestamps yet.

$ kafka-ingest format=bytes topic=data-consistency timestamp=2
testdrive-data3-${testdrive.seed},1,0,10,0

> SELECT * FROM view_empty
a a
------

> SELECT * FROM view_rt
b  sum
------
1  6
2  1

> SELECT * FROM view2_rt
b  sum
------
1  6
2  1
