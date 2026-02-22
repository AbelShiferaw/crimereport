from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import VPC, PublicSubnet, PrivateSubnet, NATGateway, InternetGateway, ELB, Route53
from diagrams.aws.compute import Fargate
from diagrams.aws.database import Aurora, ElastiCache
from diagrams.aws.security import WAF

graph_attr = {
    "fontsize": "28",
    "bgcolor": "white",
    "pad": "0.8",
    "nodesep": "0.8",
    "ranksep": "1.2",
    "splines": "ortho",
}

with Diagram(
    "CrimeReport - Milestone 14: VPC & Network Architecture",
    filename="milestone_14_vpc_architecture",
    show=False,
    direction="TB",
    graph_attr=graph_attr,
    outformat="png",
):
    internet = Route53("Internet\nTraffic")

    with Cluster("VPC - 10.0.0.0/16", graph_attr={"style": "rounded", "bgcolor": "#E8F4FD"}):
        igw = InternetGateway("Internet\nGateway")

        with Cluster("Edge Protection", graph_attr={"style": "rounded", "bgcolor": "#FFEBEE"}):
            waf = WAF("Web Application\nFirewall (WAF)")

        with Cluster("Public Subnets", graph_attr={"style": "rounded", "bgcolor": "#D4EDDA"}):
            pub_a = PublicSubnet("Public A\n10.0.0.0/24\nus-east-1a")
            pub_b = PublicSubnet("Public B\n10.0.64.0/24\nus-east-1b")
            alb = ELB("API Gateway\nALB")
            nat = NATGateway("NAT\nGateway")

        with Cluster("Private Subnets", graph_attr={"style": "rounded", "bgcolor": "#FFF3CD"}):
            priv_a = PrivateSubnet("Private A\n10.0.128.0/24\nus-east-1a")
            priv_b = PrivateSubnet("Private B\n10.0.192.0/24\nus-east-1b")

            with Cluster("Report API Service (ECS Fargate)\n0.25 vCPU / 0.5 GB"):
                ecs_a = Fargate("Report API\nTask AZ-a")
                ecs_b = Fargate("Report API\nTask AZ-b")

            with Cluster("Data Layer"):
                db = Aurora("Crime Reports DB\n(Aurora Serverless v2)\nPort 5432")
                cache = ElastiCache("Feed Cache +\nSocket Adapter\n(ElastiCache Redis\ncache.t4g.micro)\nPort 6379")

    internet >> igw
    igw >> waf
    waf >> alb
    alb >> Edge(label="Port 3000") >> ecs_a
    alb >> Edge(label="Port 3000") >> ecs_b
    ecs_a >> db
    ecs_a >> cache
    ecs_b >> db
    ecs_b >> cache
    nat >> Edge(label="Outbound\nInternet") >> igw
