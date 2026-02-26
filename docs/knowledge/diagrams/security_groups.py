from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import ELB
from diagrams.aws.compute import Fargate
from diagrams.aws.database import Aurora, ElastiCache
from diagrams.aws.security import WAF
from diagrams.onprem.client import User
import os

script_dir = os.path.dirname(os.path.abspath(__file__))

graph_attr = {
    "fontsize": "28",
    "bgcolor": "white",
    "pad": "1.0",
    "nodesep": "0.8",
    "ranksep": "1.2",
    "dpi": "150",
}

with Diagram(
    "CrimeReport - Security Group Trust Chain",
    filename=os.path.join(script_dir, "security_groups"),
    show=False,
    direction="TB",
    graph_attr=graph_attr,
    outformat="png",
):
    attacker = User("Attacker /\nLegitimate User")

    waf = WAF("WAF WebACL\n(Layer 7 Filter)\n\nBlocks:\n- >2000 req/5min\n- SQL injection\n- XSS attacks\n- Known bad inputs")

    with Cluster("crimereport-alb-sg\n(ALB Security Group)", graph_attr={"style": "rounded", "bgcolor": "#C8E6C9", "fontsize": "16"}):
        alb = ELB("Application\nLoad Balancer\n\nIngress: 80, 443\nfrom 0.0.0.0/0\n(anyone)")

    with Cluster("crimereport-ecs-sg\n(ECS Security Group)", graph_attr={"style": "rounded", "bgcolor": "#BBDEFB", "fontsize": "16"}):
        fargate = Fargate("ECS Fargate\nAPI Service\n\nIngress: 3000\nfrom ALB SG ONLY")

    with Cluster("crimereport-db-sg\n(DB Security Group)", graph_attr={"style": "rounded", "bgcolor": "#E1BEE7", "fontsize": "16"}):
        aurora = Aurora("Aurora PostgreSQL\n\nIngress: 5432\nfrom ECS SG ONLY\nEgress: NONE")

    with Cluster("crimereport-redis-sg\n(Redis Security Group)", graph_attr={"style": "rounded", "bgcolor": "#FFCCBC", "fontsize": "16"}):
        redis = ElastiCache("ElastiCache Redis\n\nIngress: 6379\nfrom ECS SG ONLY\nEgress: NONE")

    attacker >> Edge(label="HTTP/HTTPS\nrequest", color="darkgreen") >> waf
    waf >> Edge(label="Passed\ninspection", color="darkgreen") >> alb
    alb >> Edge(label="Port 3000\n(SG reference)", color="blue") >> fargate
    fargate >> Edge(label="Port 5432\n(SG reference)", color="purple") >> aurora
    fargate >> Edge(label="Port 6379\n(SG reference)", color="red") >> redis
