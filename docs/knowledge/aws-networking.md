# AWS Networking - Knowledge Base

Personal reference notes for understanding the AWS networking layer in the CrimeReport project.

---

## VPC (Virtual Private Cloud)

A VPC is your own isolated section of AWS's cloud. Think of it as your private data center inside AWS. Nothing gets in or out unless you explicitly allow it.

**Key properties:**
- Every AWS account comes with a "default VPC" per region, but best practice is to create your own
- A VPC is region-scoped (e.g., our VPC is in `us-east-1`)
- You define an IP address range using **CIDR notation**

### CIDR Notation

CIDR (Classless Inter-Domain Routing) defines a block of IP addresses.

```
10.0.0.0/16
│        │
│        └── /16 means the first 16 bits are fixed
│            This gives us 65,536 IP addresses (10.0.0.0 - 10.0.255.255)
│
└── The base IP address
```

Common CIDR sizes:
- `/16` = 65,536 IPs (typical VPC size, what we use)
- `/24` = 256 IPs (typical subnet size, what we use)
- `/32` = 1 IP (a single host)

The smaller the number after `/`, the more IPs you get.

### Our VPC Config

```
VPC CIDR: 10.0.0.0/16 (65,536 addresses)
Region:   us-east-1
AZs:      2 (us-east-1a, us-east-1b)
```

---

## Availability Zones (AZs)

An AZ is a physically separate data center within an AWS region. Each region has 3-6 AZs. They have independent power, cooling, and networking but are connected via low-latency fiber.

**Why use multiple AZs?**
- If one data center goes down (fire, power outage, flood), your app stays running in the other
- This is called **high availability (HA)**
- AWS best practice: always deploy across at least 2 AZs

**Our setup: 2 AZs**
```
us-east-1 Region
├── us-east-1a  ──  Public Subnet (10.0.0.0/24) + Private Subnet (10.0.2.0/24)
└── us-east-1b  ──  Public Subnet (10.0.1.0/24) + Private Subnet (10.0.3.0/24)
```

We use 2 AZs (not 3) to keep costs manageable for MVP while still having HA.

---

## Subnets

A subnet is a partition of the VPC's IP range. Each subnet lives in exactly one AZ. Subnets are where you actually place your resources (servers, databases, etc.).

### Subnet Types

**Public Subnet** (`SubnetType.PUBLIC`)
- Has a route to the **Internet Gateway**
- Resources here CAN be reached from the internet (if security groups allow)
- Resources here CAN reach the internet directly
- Instances get public IP addresses (`mapPublicIpOnLaunch: true`)
- Used for: **ALB (load balancer)**, NAT Gateway

**Private Subnet with Egress** (`SubnetType.PRIVATE_WITH_EGRESS`)
- Has NO direct route from the internet (no one outside can reach these)
- CAN reach the internet outbound via a **NAT Gateway** (for downloading updates, calling APIs, etc.)
- Resources do NOT get public IPs
- Used for: **ECS Fargate tasks, Aurora database, ElastiCache Redis**

**Isolated Subnet** (`SubnetType.PRIVATE_ISOLATED`)
- No internet access at all, inbound or outbound
- Completely cut off from the internet
- Used for: ultra-sensitive databases (we don't use this type)

### Why Private Subnets?

This is the **defense-in-depth** principle. Even if an attacker compromises the ALB, they can't directly reach the database because it's in a private subnet with a security group that only allows connections from the ECS security group.

```
Internet
    │
    ▼
┌─────────────────── Public Subnet ───────────────────┐
│  Internet Gateway ──── ALB (load balancer)          │
│                        NAT Gateway                   │
└──────────────────────────│───────────────────────────┘
                           │ (only port 3000 from ALB SG)
┌─────────────────── Private Subnet ──────────────────┐
│  ECS Fargate (API)                                   │
│       │                    │                         │
│       │ (port 5432)        │ (port 6379)             │
│       ▼                    ▼                         │
│  Aurora DB            ElastiCache Redis              │
└──────────────────────────────────────────────────────┘
```

### Our Subnet Layout

Each subnet gets a `/24` CIDR block (256 IPs). AWS reserves 5 IPs per subnet, so each has 251 usable:

| Subnet | AZ | CIDR | Type | What's In It |
|--------|----|------|------|-------------|
| Public-A | us-east-1a | 10.0.0.0/24 | PUBLIC | ALB, NAT Gateway |
| Public-B | us-east-1b | 10.0.1.0/24 | PUBLIC | ALB (second AZ) |
| Private-A | us-east-1a | 10.0.2.0/24 | PRIVATE_WITH_EGRESS | ECS, Aurora, Redis |
| Private-B | us-east-1b | 10.0.3.0/24 | PRIVATE_WITH_EGRESS | ECS, Aurora (failover) |

---

## Internet Gateway (IGW)

An Internet Gateway is what connects your VPC to the public internet. Without it, nothing in your VPC can talk to the outside world.

- Attached to the VPC (one per VPC)
- Public subnets have a route table entry pointing `0.0.0.0/0` (all traffic) to the IGW
- Free (no hourly charge)
- Horizontally scaled, redundant, no bandwidth constraints

**Flow:** Internet user -> IGW -> Public Subnet -> ALB

---

## NAT Gateway

A NAT (Network Address Translation) Gateway lets resources in **private subnets** access the internet **outbound only**. The internet cannot initiate connections back in.

**Why we need it:**
- ECS Fargate tasks in private subnets need to pull Docker images from ECR
- Lambda functions may need to call external APIs
- Software updates, SDK calls to AWS services

**How it works:**
1. Fargate task in private subnet sends request to `api.example.com`
2. Private subnet route table sends it to the NAT Gateway (which sits in the public subnet)
3. NAT Gateway translates the private IP to its own public IP
4. Response comes back to NAT Gateway, which forwards it to the Fargate task
5. The external server never sees the Fargate task's private IP

**Cost:** ~$32/month (fixed) + data transfer charges. This is one of the most expensive "hidden" costs in AWS.

**Our config:** 1 NAT Gateway (not 2). For HA you'd put one in each AZ, but for MVP one is fine. If the AZ with the NAT Gateway goes down, private resources lose outbound internet temporarily, but the app still functions for cached/local operations.

```
Private Subnet                Public Subnet              Internet
┌──────────┐    route table    ┌─────────────┐            ┌────────┐
│ Fargate  │ ──────────────>  │ NAT Gateway │ ────────>  │ ECR    │
│ 10.0.2.x │    0.0.0.0/0    │ 10.0.0.x    │            │ APIs   │
└──────────┘    -> nat-gw     └─────────────┘            └────────┘
                                    │
                              Uses IGW to reach internet
```

---

## Route Tables

Every subnet has a route table that determines where network traffic goes. Think of it as a GPS for packets.

**Public Subnet Route Table:**
| Destination | Target | Meaning |
|-------------|--------|---------|
| 10.0.0.0/16 | local | Traffic within the VPC stays in the VPC |
| 0.0.0.0/0 | igw-xxx | Everything else goes to the Internet Gateway |

**Private Subnet Route Table:**
| Destination | Target | Meaning |
|-------------|--------|---------|
| 10.0.0.0/16 | local | Traffic within the VPC stays in the VPC |
| 0.0.0.0/0 | nat-xxx | Everything else goes to the NAT Gateway |

The `local` route is automatic and ensures resources within the VPC can always talk to each other (e.g., Fargate to Aurora on private IPs) without going through any gateway.

---

## Security Groups

A security group is a virtual firewall for individual resources. It controls what traffic can flow **in** (ingress) and **out** (egress).

Key properties:
- **Stateful**: if you allow traffic in, the response is automatically allowed out (and vice versa)
- **Default deny**: if you don't add a rule, the traffic is blocked
- You can reference other security groups as the source (not just IPs), which is how you create trust chains

### Our Security Groups

We have 4 security groups, each for a specific layer. The rules create a chain of trust:

**1. ALB Security Group** (`crimereport-alb-sg`)
```
Ingress:
  - Port 80  from 0.0.0.0/0 (any IPv4)     ← HTTP from internet
  - Port 80  from ::/0 (any IPv6)            ← HTTP from internet
  - Port 443 from 0.0.0.0/0 (any IPv4)      ← HTTPS from internet
  - Port 443 from ::/0 (any IPv6)            ← HTTPS from internet
Egress:
  - All traffic (default)                     ← ALB needs to reach ECS
```

**2. ECS Security Group** (`crimereport-ecs-sg`)
```
Ingress:
  - Port 3000 from ALB Security Group ONLY   ← Only ALB can talk to containers
Egress:
  - All traffic (default)                     ← Containers reach DB, Redis, internet (via NAT)
```

**3. Database Security Group** (`crimereport-db-sg`)
```
Ingress:
  - Port 5432 from ECS Security Group ONLY   ← Only Fargate tasks can connect
Egress:
  - None (allowAllOutbound: false)            ← DB doesn't need to call out
```

**4. Redis Security Group** (`crimereport-redis-sg`)
```
Ingress:
  - Port 6379 from ECS Security Group ONLY   ← Only Fargate tasks can connect
Egress:
  - None (allowAllOutbound: false)            ← Redis doesn't need to call out
```

### The Trust Chain

```
Internet ──(80/443)──> ALB SG ──(3000)──> ECS SG ──(5432)──> DB SG
                                              │
                                              └──(6379)──> Redis SG
```

Each layer only accepts traffic from the layer directly above it. An attacker would need to compromise each layer sequentially to reach the database. This is **defense-in-depth**.

### Security Group vs. NACL

| Feature | Security Group | Network ACL (NACL) |
|---------|---------------|-------------------|
| Level | Instance/resource | Subnet |
| Stateful | Yes (return traffic auto-allowed) | No (must allow both directions) |
| Rules | Allow only | Allow AND deny |
| Default | Deny all ingress, allow all egress | Allow all |
| Use case | Primary firewall | Extra subnet-level protection |

We use security groups only. NACLs add complexity and are usually only needed for compliance requirements.

---

## WAF (Web Application Firewall)

WAF sits in front of the ALB and inspects HTTP requests before they reach your application. It protects against application-layer attacks.

**Our WAF rules:**
1. **Rate limiting** (2000 requests per 5 minutes per IP) - prevents DDoS and brute force
2. **AWS Common Rule Set** - blocks known attack patterns (XSS, SQLi, etc.)
3. **Known Bad Inputs** - blocks requests with known malicious payloads

WAF is **regional** (not global like CloudFront WAF). It's associated directly with the ALB.

```
Internet → WAF (inspect/block) → ALB → ECS
                │
                └── Blocked: rate limit exceeded, SQL injection, XSS
```

---

## How It All Connects - Full Request Flow

### API Request (user fetches crime reports)

```
1. User's phone sends HTTPS request to our API
2. Request hits the Internet Gateway (enters the VPC)
3. WAF inspects the request (rate limit, attack patterns)
   └── If suspicious → blocked, 403 returned
4. ALB receives the request (public subnet)
   └── ALB terminates SSL, routes based on rules
   └── Health checks ensure only healthy targets receive traffic
5. ALB forwards to a Fargate task (private subnet, port 3000)
6. Fargate task queries Aurora DB (private subnet, port 5432)
   └── Security group allows: ECS SG → DB SG
7. Fargate task checks Redis cache (private subnet, port 6379)
   └── Security group allows: ECS SG → Redis SG
8. Response flows back: Fargate → ALB → IGW → User
```

### Media Upload (user uploads a video)

```
1. App calls API: POST /api/reports → gets presigned S3 URL
   └── This goes through the API flow above
2. App uploads directly to S3 via presigned URL
   └── This does NOT go through the VPC (S3 is a public AWS service)
   └── Presigned URL authenticates the upload
3. S3 emits ObjectCreated event → EventBridge → Step Functions
   └── Step Functions is also outside the VPC (serverless)
4. Step Functions calls Rekognition (AWS service, no VPC needed)
5. If safe: copy to media bucket (images) or Lambda triggers MediaConvert (videos)
6. CloudFront CDN serves processed media to the app
```

### Key Insight: Not Everything Lives in the VPC

| Inside VPC | Outside VPC |
|------------|-------------|
| ALB | S3 buckets |
| ECS Fargate | CloudFront CDN |
| Aurora database | Step Functions |
| ElastiCache Redis | Lambda |
| NAT Gateway | EventBridge |
| Internet Gateway | Rekognition |
|  | MediaConvert |
|  | WAF (attached to ALB but managed outside) |
|  | SQS |
|  | SNS |

Serverless/managed services (S3, Lambda, Step Functions, etc.) run on AWS's shared infrastructure and are accessed via AWS APIs over the internet (or via VPC Endpoints for private access).

VPC resources are things you "place" into a subnet: servers, databases, caches.

---

## Subnet Groups

Some AWS services require a **subnet group** -- a named collection of subnets (usually in different AZs) where the service can place its resources.

### Database Subnet Group

Aurora needs to know which subnets to place database instances in. CDK creates this automatically when you pass `vpcSubnets`:

```typescript
// From database-stack.ts
vpc,
vpcSubnets: { subnetType: ec2.SubnetType.PRIVATE_WITH_EGRESS },
```

This tells Aurora: "place my instances in private subnets across the available AZs." Aurora creates one writer in AZ-a and can failover to AZ-b.

### Redis Subnet Group

ElastiCache requires an explicit subnet group. We create one manually:

```typescript
// From cache-stack.ts
const subnetGroup = new elasticache.CfnSubnetGroup(this, 'RedisSubnetGroup', {
  cacheSubnetGroupName: `${PROJECT_PREFIX}-redis-subnet`,
  description: 'CrimeReport Redis subnet group (private subnets)',
  subnetIds: vpc.privateSubnets.map(s => s.subnetId),
});
```

This says: "Redis can be placed in any of the private subnets." We run 1 node (MVP), but if we enable Multi-AZ later, ElastiCache can place replicas in the other AZ's subnet.

### Why Subnet Groups Exist

They decouple "where can this service run?" from "where is it running right now." If you add a third AZ later, you just update the subnet group -- you don't reconfigure each service individually.

---

## Cost Breakdown of Networking Components

| Component | Cost | Notes |
|-----------|------|-------|
| VPC | Free | No charge for the VPC itself |
| Subnets | Free | No charge for subnets |
| Internet Gateway | Free | No charge |
| NAT Gateway | ~$32/month | Fixed hourly + $0.045/GB data processed |
| Security Groups | Free | No charge |
| Route Tables | Free | No charge |
| WAF | ~$6/month | $5/WebACL + $1/rule + $0.60/million requests |
| ALB | ~$20/month | $0.0225/hour + LCU charges |

The NAT Gateway is the biggest "hidden" networking cost. For production, you'd want one per AZ (~$64/month for 2), but for MVP one is enough.

---

## Common Gotchas

1. **Fargate tasks can't pull images without NAT**: If your private subnets don't have a route to a NAT Gateway, Fargate can't pull Docker images from ECR and tasks will fail to start.

2. **Security group changes are immediate**: Unlike NACLs which have rule ordering, security groups apply all rules at once and changes take effect immediately.

3. **You can't change a VPC's CIDR after creation**: Choose a large enough range up front. `/16` is the standard choice.

4. **Subnet IPs are not all usable**: AWS reserves 5 IPs per subnet (first 4 + last 1). A `/24` subnet has 251 usable IPs, not 256.

5. **Cross-AZ data transfer costs money**: Traffic between AZs (e.g., Fargate in AZ-a talking to Redis in AZ-b) costs $0.01/GB. This is minimal but adds up at scale.

6. **ALB must span at least 2 AZs**: AWS requires ALBs to be in at least 2 AZs for availability. This is why we have 2 public subnets.
