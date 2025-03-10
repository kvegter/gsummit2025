// 
// To execute this in the Neo4j Browser - copy and paste the contents into the execution box.
// 
// This script will add OperationalPoints, Sections and POIs
//
// NB. Running this script in it's entirety will erase your database first.
//

//
// WARNING!
// This drops all the GDS projections from your current database
//
// CALL gds.graph.list() YIELD graphName AS toDrop
// CALL gds.graph.drop(toDrop) YIELD graphName
// RETURN "Dropped " + graphName;

//
// WARNING! 
// This erases your database contents
//
MATCH (n)
DETACH DELETE n;

// 
// WARNING! 
// This DROPs all your indexes and constraints
//
CALL apoc.schema.assert({},{});

//
//CREATE a CONSTRAINT to ensure that the 'id' of an Operational Point is both there, and unique.
//
CREATE CONSTRAINT uc_OperationalPoint_id IF NOT EXISTS FOR (op:OperationalPoint) REQUIRE (op.id) IS UNIQUE;

//
// Create index for the Operation Point on Name
//
CREATE INDEX index_OperationalPoint_name IF NOT EXISTS FOR (op:OperationalPoint) ON (op.name);

//
// Loading Operational Points
//
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/kvegter/gsummit2025/refs/heads/main/data/OperationalPoint_All.csv" AS row
//This WITH is to ensure our data is as normalized as we can
WITH
    trim(row.id) AS id, //trim will remove and start and trailing spaces from an ID
    toFloat(row.latitude) AS latitude, //toFloat will 
    toFloat(row.longitude) AS longitude,
    trim(row.name) AS name,
    [] + trim(row.country) + trim(row.extralabel) AS labels,
    trim(row.country) AS country
MERGE (op:OperationalPoint {id: id})
ON CREATE SET
    op.geolocation = Point({latitude: latitude, longitude: longitude}),
    op.name = name
WITH op, labels, name, country
CALL apoc.create.addLabels( op, labels ) YIELD node
RETURN DISTINCT 'Complete';

//
// Load Section Length Data
//
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/kvegter/gsummit2025/refs/heads/main/data/SECTION_ALL_Length.csv" AS row
WITH
    trim(row.source) AS sourceId,
    trim(row.target) AS targetId,
    toFloat(row.sectionlength) AS length
MATCH (source:OperationalPoint WHERE source.id = sourceId)
MATCH (target:OperationalPoint WHERE target.id = targetId)
MERGE (source)-[s:SECTION]->(target)
SET s.sectionlength = length;

//
// Load Speed Data
//
LOAD CSV WITH HEADERS FROM "https://raw.githubusercontent.com/kvegter/gsummit2025/refs/heads/main/data/SECTION_ALL_Speed.csv" AS row
WITH
    trim(row.source) AS sourceId,
    trim(row.target) AS targetId,
    toFloat(row.sectionspeed) AS speed
MATCH (source:OperationalPoint WHERE source.id = sourceId)
MATCH (target:OperationalPoint WHERE target.id = targetId)
MERGE (source)-[s:SECTION]->(target)
SET s.speed = speed;

//
// Load Point of Interest data
//
LOAD CSV WITH HEADERS FROM 'https://raw.githubusercontent.com/kvegter/gsummit2025/refs/heads/main/data/POIs.csv' AS row
WITH 
    row.CITY AS city,
    row.POI_DESCRIPTION AS description,
    row.LINK_FOTO AS linkFoto,
    row.LINK_WEBSITE AS linkWeb,
    row.LAT AS lat,
    row.LONG AS long,
    row.SECRET AS secret
CREATE (po:POI {
    geolocation : point({latitude: toFloat(lat),longitude: toFloat(long)}),
    description : description,
    city : city,
    linkWebSite : linkWeb,
    linkFoto : linkFoto,
    long : toFloat(long),
    lat : toFloat(lat),
    secret : toBoolean(secret)
});

//
// Link POI to nearest OperationalPoint that is a Station or SmallStation
// by finding the closest distance between `geolocation` point of the POI and the next
// available station / passenger stop `geolocation` point
//
MATCH 
    (poi:POI), 
    (op:Station|SmallStation|PassengerTerminal) 
WITH 
    poi, op, 
    point.distance(poi.geolocation, op.geolocation) AS distance
ORDER BY distance
WITH poi, COLLECT(op)[0] AS closest
MERGE (closest)-[:IS_NEAR]->(poi);

//
//  Create the missing links and some properties
//
MATCH
    (uk:UK:BorderPoint),
    (france:France)
WITH
    uk, france,
    point.distance(france.geolocation, uk.geolocation) as distance
ORDER by distance LIMIT 1
MERGE (france)-[:SECTION {sectionlength: distance/1000.0, curated: true}]->(uk);

MATCH (s1:Station)-[s:SECTION]->(s2:Station)
WHERE
    NOT (s.speed IS NULL)
    AND NOT (s.sectionlength IS NULL )
WITH
    s1.name AS startName, s2.name AS endName,
    (s.sectionlength / s.speed) * 60 * 60 AS timeTakenInSeconds
    LIMIT 1
RETURN startName, endName, timeTakenInSeconds;

MATCH (:OperationalPoint)-[r:SECTION]->(:OperationalPoint)
WHERE
    r.speed IS NOT NULL
    AND r.sectionlength IS NOT NULL
SET r.traveltime = (r.sectionlength / r.speed) * 60 * 60;

// ==== DONE LOADING ====
