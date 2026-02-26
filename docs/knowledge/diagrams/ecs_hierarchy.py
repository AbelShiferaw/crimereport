from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import ECS, Fargate, ECR
from diagrams.aws.network import ELB
from diagrams.aws.management import Cloudwatch
import os

script_dir = os.path.dirname(os.path.abspath(__file__))

graph_attr = {
    "fontsize": "28",
    "bgcolor": "white",
    "pad": "1.0",
    "nodesep": "0.8",
    "ranksep": "1.0",
    "splines": "ortho",
}

cluster_attr = {
    "fontsize": "20",
    "style": "rounded",
    "bgcolor": "#f0f4ff",
}

with Diagram(
    "ECS Hierarchy",
    filename=os.path.join(script_dir, "ecs_hierarchy"),
    show=False,
    direction="TB",
    graph_attr=graph_attr,
):
    ecr = ECR("ECR\ncrimereport-api")
    logs = Cloudwatch("CloudWatch\nLog Group")

    with Cluster("ECS Cluster: crimereport-cluster", graph_attr=cluster_attr):
        with Cluster(
            "Service: crimereport-api\ndesiredCount=1, auto-scaling 1-10",
            graph_attr={**cluster_attr, "bgcolor": "#e8f5e9"},
        ):
            with Cluster(
                "Task 1 — IP: 10.0.128.47\n0.25 vCPU / 512 MB",
                graph_attr={**cluster_attr, "bgcolor": "#fff3e0"},
            ):
                task1 = Fargate("Container: api\nport 3000")

            with Cluster(
                "Task 2 — IP: 10.0.129.15\n0.25 vCPU / 512 MB",
                graph_attr={**cluster_attr, "bgcolor": "#fff3e0"},
            ):
                task2 = Fargate("Container: api\nport 3000")

            with Cluster(
                "Task 3 — IP: 10.0.128.102\n0.25 vCPU / 512 MB",
                graph_attr={**cluster_attr, "bgcolor": "#fff3e0"},
            ):
                task3 = Fargate("Container: api\nport 3000")

    alb = ELB("ALB\ncrimereport-alb")

    ecr >> Edge(label="image pull", style="dashed") >> task1
    alb >> Edge(label=":3000") >> task1
    alb >> Edge(label=":3000") >> task2
    alb >> Edge(label=":3000") >> task3
    task1 >> Edge(label="stdout/stderr", style="dashed") >> logs
