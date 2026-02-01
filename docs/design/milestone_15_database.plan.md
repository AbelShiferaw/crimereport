# Milestone 15: Database Layer

## Goal
Set up Aurora PostgreSQL with PostGIS extension and ElastiCache Redis cluster.

## Dependencies
Requires **Milestone 14** complete (VPC and security groups).

## Implementation

### 1. Aurora PostgreSQL Cluster
```hcl
# infrastructure/database.tf

resource "aws_db_subnet_group" "main" {
  name       = "reportcrime-db-subnet"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

resource "aws_rds_cluster" "main" {
  cluster_identifier     = "reportcrime-db"
  engine                 = "aurora-postgresql"
  engine_version         = "15.4"
  database_name          = "reportcrime"
  master_username        = "admin"
  master_password        = var.db_password  # From secrets
  
  db_subnet_group_name   = aws_db_subnet_group.main.name
  vpc_security_group_ids = [aws_security_group.db.id]
  
  serverlessv2_scaling_configuration {
    min_capacity = 0.5
    max_capacity = 4
  }
  
  skip_final_snapshot = true  # Change for production
}

resource "aws_rds_cluster_instance" "main" {
  cluster_identifier   = aws_rds_cluster.main.id
  instance_class       = "db.serverless"
  engine               = "aurora-postgresql"
  publicly_accessible  = false
}
```

### 2. Database Schema
```sql
-- migrations/001_initial_schema.sql

-- Enable PostGIS
CREATE EXTENSION IF NOT EXISTS postgis;

-- Reports table
CREATE TABLE reports (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    device_id VARCHAR(64) NOT NULL,
    type VARCHAR(50) NOT NULL,
    description TEXT,
    location GEOGRAPHY(POINT, 4326) NOT NULL,
    address VARCHAR(255),
    status VARCHAR(20) DEFAULT 'pending',
    upvotes INTEGER DEFAULT 0,
    comment_count INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    updated_at TIMESTAMPTZ DEFAULT NOW()
);

-- Spatial index for nearby queries
CREATE INDEX idx_reports_location ON reports USING GIST(location);
CREATE INDEX idx_reports_created_at ON reports(created_at DESC);
CREATE INDEX idx_reports_device_id ON reports(device_id);

-- Media table
CREATE TABLE media (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id UUID REFERENCES reports(id) ON DELETE CASCADE,
    type VARCHAR(10) NOT NULL,  -- 'video' or 'image'
    url VARCHAR(500) NOT NULL,
    thumbnail_url VARCHAR(500),
    duration_ms INTEGER,
    width INTEGER,
    height INTEGER,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_media_report_id ON media(report_id);

-- Comments table
CREATE TABLE comments (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    report_id UUID REFERENCES reports(id) ON DELETE CASCADE,
    device_id VARCHAR(64) NOT NULL,
    content TEXT NOT NULL,
    upvotes INTEGER DEFAULT 0,
    created_at TIMESTAMPTZ DEFAULT NOW()
);

CREATE INDEX idx_comments_report_id ON comments(report_id);

-- Upvotes tracking (prevent duplicates)
CREATE TABLE report_upvotes (
    report_id UUID REFERENCES reports(id) ON DELETE CASCADE,
    device_id VARCHAR(64) NOT NULL,
    created_at TIMESTAMPTZ DEFAULT NOW(),
    PRIMARY KEY (report_id, device_id)
);

-- Device rate limiting
CREATE TABLE device_activity (
    device_id VARCHAR(64) PRIMARY KEY,
    report_count_today INTEGER DEFAULT 0,
    last_report_at TIMESTAMPTZ,
    flagged BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMPTZ DEFAULT NOW()
);
```

### 3. ElastiCache Redis
```hcl
# infrastructure/redis.tf

resource "aws_elasticache_subnet_group" "main" {
  name       = "reportcrime-redis-subnet"
  subnet_ids = [aws_subnet.private_a.id, aws_subnet.private_b.id]
}

resource "aws_elasticache_replication_group" "main" {
  replication_group_id = "reportcrime-redis"
  description          = "ReportCrime Redis cluster"
  
  node_type            = "cache.t4g.micro"  # Start small
  num_cache_clusters   = 2  # Multi-AZ
  
  engine               = "redis"
  engine_version       = "7.0"
  port                 = 6379
  
  subnet_group_name    = aws_elasticache_subnet_group.main.name
  security_group_ids   = [aws_security_group.redis.id]
  
  automatic_failover_enabled = true
  multi_az_enabled          = true
  
  at_rest_encryption_enabled = true
  transit_encryption_enabled = true
}
```

### 4. Secrets Manager
```hcl
# infrastructure/secrets.tf

resource "aws_secretsmanager_secret" "db_password" {
  name = "reportcrime/db-password"
}

resource "aws_secretsmanager_secret_version" "db_password" {
  secret_id     = aws_secretsmanager_secret.db_password.id
  secret_string = var.db_password
}
```

### 5. Test Connection Script
```bash
#!/bin/bash
# scripts/test_db_connection.sh

# Get DB endpoint
DB_ENDPOINT=$(aws rds describe-db-clusters \
  --db-cluster-identifier reportcrime-db \
  --query 'DBClusters[0].Endpoint' --output text)

# Test connection (requires bastion or VPN)
psql "postgresql://admin:${DB_PASSWORD}@${DB_ENDPOINT}:5432/reportcrime" \
  -c "SELECT PostGIS_Version();"
```

## Geospatial Query Examples
```sql
-- Find reports within 5km of a point
SELECT * FROM reports
WHERE ST_DWithin(
    location,
    ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326)::geography,
    5000  -- meters
)
ORDER BY created_at DESC
LIMIT 50;

-- Get distance from user to report
SELECT 
    id,
    ST_Distance(
        location,
        ST_SetSRID(ST_MakePoint(-122.4194, 37.7749), 4326)::geography
    ) as distance_meters
FROM reports;
```

## Deliverable Checklist
- [ ] Aurora PostgreSQL cluster created
- [ ] PostGIS extension enabled
- [ ] All tables created with indexes
- [ ] Spatial index working for geo queries
- [ ] ElastiCache Redis cluster running
- [ ] Multi-AZ enabled for both
- [ ] Secrets stored in Secrets Manager
- [ ] Can connect from local (via bastion/VPN)
- [ ] Test geo query returns results

## Files (5 total)
1. `infrastructure/database.tf` - Aurora config
2. `infrastructure/redis.tf` - ElastiCache config
3. `infrastructure/secrets.tf` - Secrets Manager
4. `migrations/001_initial_schema.sql` - Database schema
5. `scripts/test_db_connection.sh` - Connection test
