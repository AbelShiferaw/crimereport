from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import ECR, ECS, Fargate
from diagrams.aws.network import ELB
from diagrams.aws.security import SecretsManager, WAF
from diagrams.aws.management import Cloudwatch
from diagrams.onprem.container import Docker
from diagrams.programming.language import Typescript, Nodejs
from diagrams.onprem.client import User
import os

script_dir = os.path.dirname(os.path.abspath(__file__))

graph_attr = {
    "fontsize": "28",
    "bgcolor": "white",
    "pad": "1.0",
    "nodesep": "0.6",
    "ranksep": "1.0",
}

cluster_attr = {
    "fontsize": "20",
    "style": "rounded",
    "bgcolor": "#f0f4ff",
}

with Diagram(
    "Code to Fargate Pipeline",
    filename=os.path.join(script_dir, "code_to_fargate"),
    show=False,
    direction="LR",
    graph_attr=graph_attr,
):
    with Cluster("Local Development", graph_attr={**cluster_attr, "bgcolor": "#e3f2fd"}):
        ts_code = Typescript("src/index.ts\n(TypeScript)")
        js_code = Nodejs("dist/index.js\n(compiled JS)")
        docker = Docker("docker build\n(Dockerfile)")

    ts_code >> Edge(label="tsc compile") >> js_code
    js_code >> Edge(label="COPY into image") >> docker

    with Cluster("AWS Cloud", graph_attr={**cluster_attr, "bgcolor": "#f3e5f5"}):
        ecr = ECR("ECR\ncrimereport-api")
        secrets = SecretsManager("Secrets Manager\nDATABASE_URL")

        with Cluster("ECS / Fargate", graph_attr={**cluster_attr, "bgcolor": "#e8f5e9"}):
            ecs = ECS("ECS Service\ncrimereport-api")
            fargate = Fargate("Fargate Task\nnode dist/index.js")

        logs = Cloudwatch("CloudWatch\nLogs")
        waf = WAF("WAF")
        alb = ELB("ALB\nport 80")

    docker >> Edge(label="docker push") >> ecr
    ecr >> Edge(label="image pull") >> ecs
    ecs >> Edge(label="launch task") >> fargate
    secrets >> Edge(label="inject secret", style="dashed") >> fargate
    fargate >> Edge(label="stdout", style="dashed") >> logs

    user = User("Mobile App")
    user >> waf >> alb >> Edge(label=":3000") >> fargate
