from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import (
    ELB, VPC as VPCIcon, NATGateway, InternetGateway,
    RouteTable, Route53
)
from diagrams.aws.compute import Fargate
from diagrams.aws.database import Aurora, ElastiCache
from diagrams.aws.security import WAF
from diagrams.aws.general import Client
from diagrams.onprem.client import User
import os

script_dir = os.path.dirname(os.path.abspath(__file__))

graph_attr = {
    "fontsize": "28",
    "bgcolor": "white",
    "pad": "1.0",
    "nodesep": "0.5",
    "ranksep": "0.8",
    "dpi": "150",
}

with Diagram(
    "CrimeReport VPC - Network Topology",
    filename=os.path.join(script_dir, "vpc_topology"),
    show=False,
    direction="TB",
    graph_attr=graph_attr,
    outformat="png",
):
    internet = User("Internet\nUsers")

    with Cluster("AWS Region: us-east-1", graph_attr={"style": "rounded", "bgcolor": "#FFF8E1"}):

        waf = WAF("WAF\nRate Limit: 2000/5min\nCommon Rules\nBad Input Rules")

        with Cluster("VPC: 10.0.0.0/16", graph_attr={"style": "rounded", "bgcolor": "#E8EAF6", "fontsize": "20"}):

            with Cluster("Public Subnets", graph_attr={"style": "rounded", "bgcolor": "#C8E6C9"}):

                with Cluster("Public-A (us-east-1a)\n10.0.0.0/24", graph_attr={"style": "dashed", "bgcolor": "#E8F5E9"}):
                    igw = InternetGateway("Internet\nGateway")
                    alb_a = ELB("ALB\n(port 80/443)")
                    nat = NATGateway("NAT Gateway\n~$32/mo")

                with Cluster("Public-B (us-east-1b)\n10.0.1.0/24", graph_attr={"style": "dashed", "bgcolor": "#E8F5E9"}):
                    alb_b = ELB("ALB\n(2nd AZ)")

            with Cluster("Private Subnets (PRIVATE_WITH_EGRESS)", graph_attr={"style": "rounded", "bgcolor": "#EDE7F6"}):

                with Cluster("Private-A (us-east-1a)\n10.0.2.0/24", graph_attr={"style": "dashed", "bgcolor": "#F3E5F5"}):
                    fargate_a = Fargate("ECS Fargate\nAPI Task\n0.25 vCPU / 0.5 GB")
                    aurora_w = Aurora("Aurora Writer\nPostgreSQL + PostGIS")
                    redis = ElastiCache("Redis\ncache.t4g.micro")

                with Cluster("Private-B (us-east-1b)\n10.0.3.0/24", graph_attr={"style": "dashed", "bgcolor": "#F3E5F5"}):
                    fargate_b = Fargate("ECS Fargate\nAPI Task\n(scale target)")
                    aurora_r = Aurora("Aurora\n(failover AZ)")

    internet >> Edge(label="HTTPS", color="darkgreen") >> waf
    waf >> Edge(label="Allowed\ntraffic", color="darkgreen") >> igw
    igw >> alb_a
    igw >> alb_b

    alb_a >> Edge(label="port 3000", color="blue") >> fargate_a
    alb_b >> Edge(label="port 3000", color="blue") >> fargate_b

    fargate_a >> Edge(label="port 5432", color="purple") >> aurora_w
    fargate_a >> Edge(label="port 6379", color="red") >> redis
    fargate_b >> Edge(label="port 5432", color="purple") >> aurora_w
    fargate_b >> Edge(label="port 6379", color="red") >> redis

    fargate_a >> Edge(label="Outbound\n(pull images, APIs)", style="dashed", color="gray") >> nat
    fargate_b >> Edge(label="Outbound", style="dashed", color="gray") >> nat
