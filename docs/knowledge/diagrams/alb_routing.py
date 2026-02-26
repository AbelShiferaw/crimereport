from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import Fargate
from diagrams.aws.network import ELB, ALB
from diagrams.aws.security import WAF
from diagrams.onprem.client import User
import os

script_dir = os.path.dirname(os.path.abspath(__file__))

graph_attr = {
    "fontsize": "28",
    "bgcolor": "white",
    "pad": "1.0",
    "nodesep": "0.6",
    "ranksep": "0.9",
}

cluster_attr = {
    "fontsize": "20",
    "style": "rounded",
    "bgcolor": "#f0f4ff",
}

with Diagram(
    "ALB Routing to Fargate",
    filename=os.path.join(script_dir, "alb_routing"),
    show=False,
    direction="TB",
    graph_attr=graph_attr,
):
    user = User("Mobile App\nGET /health")
    waf = WAF("WAF\nRate limit + rules")

    with Cluster("Public Subnet", graph_attr={**cluster_attr, "bgcolor": "#e3f2fd"}):
        alb = ELB("ALB\ncrimereport-alb\nDNS: crimereport-alb-xxx.elb.amazonaws.com")

        with Cluster(
            "Listener: port 80 (HTTP)\nDefault rule → target group",
            graph_attr={**cluster_attr, "bgcolor": "#bbdefb"},
        ):
            listener = ALB("HTTP Listener\nport 80")

    with Cluster(
        "Target Group: crimereport-api-tg\nProtocol: HTTP | Port: 3000\nHealth check: GET /health",
        graph_attr={**cluster_attr, "bgcolor": "#c8e6c9"},
    ):
        with Cluster("Private Subnet", graph_attr={**cluster_attr, "bgcolor": "#e8f5e9"}):
            task1 = Fargate("Task 1\n10.0.128.47:3000\n✓ healthy")
            task2 = Fargate("Task 2\n10.0.129.15:3000\n✓ healthy")
            task3 = Fargate("Task 3\n10.0.128.102:3000\n✗ unhealthy")

    user >> Edge(label="HTTP request") >> waf
    waf >> Edge(label="passes rules") >> alb
    alb >> listener
    listener >> Edge(label="forward to\nhealthy targets", color="green") >> task1
    listener >> Edge(label="forward", color="green") >> task2
    listener >> Edge(label="skip", style="dashed", color="red") >> task3
