# Copyright Materialize, Inc. All rights reserved.
#
# Use of this software is governed by the Business Source License
# included in the LICENSE file at the root of this repository.
#
# As of the Change Date specified in that file, in accordance with
# the Business Source License, use of this software will be governed
# by the Apache License, Version 2.0.

# Test that a dependency chain with multiple links is properly maintained
# across creation and deletion.

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
              {"name": "x", "type": "long"},
              {"name": "y", "type": "string"}
            ]
          },
          "null"
        ]
      },
      { "name": "after", "type": ["row", "null"] }
    ]
  }

> CREATE SOURCE s
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-data-${testdrive.seed}'
  FORMAT AVRO USING SCHEMA '${schema}'
  ENVELOPE DEBEZIUM

! CREATE SOURCE s
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-data-blah-${testdrive.seed}'
  FORMAT AVRO USING SCHEMA '${schema}'
  ENVELOPE DEBEZIUM
catalog item 's' already exists

> CREATE SOURCE IF NOT EXISTS s
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-data-blah-${testdrive.seed}'
  FORMAT AVRO USING SCHEMA '${schema}'
  ENVELOPE DEBEZIUM

> CREATE MATERIALIZED VIEW test1 AS SELECT 1;

> CREATE MATERIALIZED VIEW test2 AS SELECT * FROM test1;

> CREATE MATERIALIZED VIEW test3a AS SELECT * FROM test2;

> CREATE MATERIALIZED VIEW test3b AS SELECT * FROM test2;

! DROP VIEW test1;
cannot drop materialize.public.test1: still depended upon by catalog item 'materialize.public.test2'

! DROP VIEW test2;
cannot drop materialize.public.test2: still depended upon by catalog item 'materialize.public.test3a'

> DROP VIEW test3a;

! DROP VIEW test1;
cannot drop materialize.public.test1: still depended upon by catalog item 'materialize.public.test2'

! DROP VIEW test2;
cannot drop materialize.public.test2: still depended upon by catalog item 'materialize.public.test3b'

> DROP VIEW test3b;

! DROP VIEW test1;
cannot drop materialize.public.test1: still depended upon by catalog item 'materialize.public.test2'

> DROP VIEW test2;

> DROP VIEW test1;

# Test that CASCADE causes all dependent views to be dropped along with the
# named view.

> CREATE MATERIALIZED VIEW test1 AS SELECT 1;

> CREATE MATERIALIZED VIEW test2 AS SELECT * FROM test1;

> DROP VIEW test1 CASCADE;

# TODO(benesch): when we have a system stream that has the names of all
# available views, we can verify there that views are actually dropped,
# rather than verifying the drop by checking whether DROP VIEW fails.

! DROP VIEW test1;
unknown catalog item 'test1'

! DROP VIEW test2;
unknown catalog item 'test2'

# Test that DROP VIEW IF EXISTS succeeds even if the view does not exist.

> DROP VIEW IF EXISTS test1;

# Test that CASCADE causes all dependent views to be dropped along with the
# named source.

> CREATE MATERIALIZED VIEW test4 as SELECT * FROM s;

> DROP SOURCE s CASCADE;

! DROP VIEW test4;
unknown catalog item 'test4'

> CREATE SOURCE s
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-data-${testdrive.seed}'
  FORMAT AVRO USING SCHEMA '${schema}'
  ENVELOPE DEBEZIUM

> CREATE SINK s1 FROM s
  INTO KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'v'
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}'

! CREATE SINK s1 FROM s
  INTO KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'v'
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}'
catalog item 's1' already exists

> CREATE SINK IF NOT EXISTS s1 FROM s
  INTO KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'v2'
  FORMAT AVRO USING CONFLUENT SCHEMA REGISTRY '${testdrive.schema-registry-url}'

# Test that sinks cannot be depended upon.
! CREATE MATERIALIZED VIEW v2 AS SELECT * FROM s1;
catalog item 'materialize.public.s1' is a sink and so cannot be depended upon

> CREATE MATERIALIZED VIEW v2 AS SELECT X from s;

> CREATE MATERIALIZED VIEW v2a AS SELECT X+1 as X from v2;

> CREATE INDEX i1 ON v2(x);

# Test that indexes cannot be depended upon

! CREATE MATERIALIZED VIEW v3 as SELECT * FROM i1;
catalog item 'materialize.public.i1' is an index and so cannot be depended upon

> CREATE INDEX i2 ON v2a(x*2);

> SHOW INDEX in v2a;
Source_or_view           Key_name                             Column_name Expression     Null   Seq_in_index
------------------------------------------------------------------------------------------------------------
materialize.public.v2a   materialize.public.i2                <null>      "\"x\" * 2"    false  1
materialize.public.v2a   materialize.public.v2a_primary_idx   x           <null>         false  1

> SHOW INDEX in v2;
Source_or_view         Key_name                              Column_name Expression Null   Seq_in_index
-------------------------------------------------------------------------------------------------------
materialize.public.v2  materialize.public.i1                 x           <null>     false  1
materialize.public.v2  materialize.public.v2_primary_idx     x           <null>     false  1

# Test that dependent indexes do not prevent view deletion when restrict is specified
# but do not cause deletion of dependent views
> DROP VIEW v2a;

! DROP VIEW v2a;
unknown catalog item 'v2a'

> SHOW INDEX in v2;
Source_or_view           Key_name                              Column_name Expression Null  Seq_in_index
------------------------------------------------------------------------------------------------------
materialize.public.v2    materialize.public.i1                 x           <null>     false 1
materialize.public.v2    materialize.public.v2_primary_idx     x           <null>     false 1

! DROP INDEX i2;
unknown catalog item 'i2'

> CREATE MATERIALIZED VIEW v4 AS SELECT x, y from s;

> CREATE MATERIALIZED VIEW v4a AS SELECT y from v4;

> CREATE INDEX i3 ON v4a(y);

> SHOW INDEX in v4a;
Source_or_view           Key_name                               Column_name Expression Null  Seq_in_index
-------------------------------------------------------------------------------------------------------
materialize.public.v4a   materialize.public.i3                  y           <null>     false 1
materialize.public.v4a   materialize.public.v4a_primary_idx     y           <null>     false 1

> CREATE INDEX i4 ON v4(x);

> SHOW INDEX in v4;
Source_or_view          Key_name                           Column_name Expression Null  Seq_in_index
------------------------------------------------------------------------------------------------
materialize.public.v4   materialize.public.i4              x           <null>     false 1
materialize.public.v4   materialize.public.v4_primary_idx  x           <null>     false 1
materialize.public.v4   materialize.public.v4_primary_idx  y           <null>     false 2

# Test cascade deletes associated indexes as well
> DROP VIEW v4a CASCADE;

! DROP VIEW v4a;
unknown catalog item 'v4a'

! DROP INDEX i3;
unknown catalog item 'i3'

> SHOW INDEX in v4;
Source_or_view          Key_name                              Column_name Expression Null  Seq_in_index
-----------------------------------------------------------------------------------------------------
materialize.public.v4   materialize.public.i4                  x           <null>     false 1
materialize.public.v4   materialize.public.v4_primary_idx      x           <null>     false 1
materialize.public.v4   materialize.public.v4_primary_idx      y           <null>     false 2

> CREATE MATERIALIZED VIEW v5 AS SELECT substr(y, 3, 2) as substr from v4;

> CREATE INDEX i5 ON v5(substr);

> SHOW INDEX in v5;
Source_or_view               Key_name                            Column_name Expression Null  Seq_in_index
-----------------------------------------------------------------------------------------------------
materialize.public.v5   materialize.public.i5               substr      <null>     true  1
materialize.public.v5   materialize.public.v5_primary_idx   substr      <null>     true  1

> CREATE VIEW multicol AS SELECT 'a' AS a, 'b', 'c', 'd' AS d
> CREATE INDEX i6 ON multicol (2, a, 4)
> SHOW INDEX IN multicol
Source_or_view               Key_name               Column_name  Expression   Null    Seq_in_index
-----------------------------------------------------------------------------------------------------
materialize.public.multicol  materialize.public.i6  a            <null>       false   2
materialize.public.multicol  materialize.public.i6  @2           <null>       false   1
materialize.public.multicol  materialize.public.i6  d            <null>       false   3

# Test cascade deletes all indexes associated with cascaded views
> DROP VIEW v4 CASCADE;

! DROP VIEW v4;
unknown catalog item 'v4'

! DROP INDEX i5;
unknown catalog item 'i5'

! DROP VIEW v5;
unknown catalog item 'v5'

! DROP INDEX i4;
unknown catalog item 'i4'

# Test that dropping indexes even with cascade does not cause the underlying view to be dropped

> DROP INDEX i1 CASCADE;

> DROP VIEW v2;

# Materialized source tests

> CREATE MATERIALIZED SOURCE s3
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-data-${testdrive.seed}'
  FORMAT AVRO USING SCHEMA '${schema}'
  ENVELOPE DEBEZIUM

# Test that dependent indexes do not prevent source deletion when restrict is specified
> CREATE INDEX j1 on s3(ascii(y))

> SHOW INDEX in s3;
Source_or_view          Key_name                              Column_name Expression     Null  Seq_in_index
----------------------------------------------------------------------------------------------------
materialize.public.s3   materialize.public.j1                 <null>      "ascii(\"y\")" false 1
materialize.public.s3   materialize.public.s3_primary_idx     x           <null>         false 1
materialize.public.s3   materialize.public.s3_primary_idx     y           <null>         false 2

> DROP SOURCE s3;

! DROP SOURCE s3;
unknown catalog item 's3'

! DROP INDEX j1;
unknown catalog item 'j1'

# Test cascade deletes all indexes associated with cascaded sources and views

> CREATE MATERIALIZED SOURCE s4
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-data-${testdrive.seed}'
  FORMAT AVRO USING SCHEMA '${schema}'
  ENVELOPE DEBEZIUM

> CREATE INDEX j2 on s4(x+2);

> CREATE VIEW w as SELECT y, x + 2 as z from s4;

> CREATE INDEX j3 on w(z);

> SHOW INDEX in s4;
Source_or_view          Key_name                              Column_name Expression  Null  Seq_in_index
----------------------------------------------------------------------------------------------------
materialize.public.s4   materialize.public.j2                 <null>      "\"x\" + 2" false 1
materialize.public.s4   materialize.public.s4_primary_idx     x           <null>      false 1
materialize.public.s4   materialize.public.s4_primary_idx     y           <null>      false 2

> SHOW INDEX in w;
Source_or_view         Key_name                            Column_name Expression Null  Seq_in_index
----------------------------------------------------------------------------------------------------
materialize.public.w   materialize.public.j3               z           <null>     false 1

> DROP SOURCE s4 CASCADE;

! DROP VIEW w;
unknown catalog item 'w'

! DROP INDEX j3;
unknown catalog item 'j3'

! DROP SOURCE s4;
unknown catalog item 's4'

! DROP INDEX j2;
unknown catalog item 'j2'

# Test that dropping indexes even with cascade does not cause the underlying source to be dropped

> CREATE MATERIALIZED SOURCE s5
  FROM KAFKA BROKER '${testdrive.kafka-addr}' TOPIC 'testdrive-data-${testdrive.seed}'
  FORMAT AVRO USING SCHEMA '${schema}'
  ENVELOPE DEBEZIUM

> DROP INDEX s5_primary_idx CASCADE;

> DROP SOURCE s5;

#cleanup
> DROP SINK s1;

> DROP SOURCE s;

# Test CREATE OR REPLACE view.

> CREATE OR REPLACE MATERIALIZED VIEW v3 AS SELECT 1
> SELECT * FROM v3
1

> CREATE OR REPLACE MATERIALIZED VIEW v3 AS SELECT 2
> SELECT * FROM v3
2

> CREATE OR REPLACE MATERIALIZED VIEW v4 AS SELECT * FROM v3
> SELECT * FROM v4
2

! CREATE OR REPLACE MATERIALIZED VIEW v3 AS SELECT 3
cannot drop materialize.public.v3: still depended upon by catalog item 'materialize.public.v4'

> CREATE OR REPLACE MATERIALIZED VIEW v4 AS SELECT 3
> SELECT * FROM v4
3

> SELECT * FROM v3
2

> CREATE OR REPLACE MATERIALIZED VIEW v3 AS SELECT 4
> SELECT * FROM v3
4

# Test CREATE VIEW IF NOT EXISTS

> CREATE MATERIALIZED VIEW test1 AS SELECT 1;

> CREATE MATERIALIZED VIEW test2 AS SELECT * FROM test1;

! DROP VIEW test1;
cannot drop materialize.public.test1: still depended upon by catalog item 'materialize.public.test2'

# Succeeds even though it's dependent on.
> CREATE MATERIALIZED VIEW IF NOT EXISTS test1 AS SELECT 2 as b;

> SELECT * FROM test1;
?column?
-----------
1

> DROP VIEW test2;

> DROP VIEW test1;
