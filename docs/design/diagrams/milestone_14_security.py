from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import ELB
from diagrams.aws.compute import Fargate
from diagrams.aws.database import Aurora, ElastiCache
from diagrams.aws.security import IAMRole, WAF
from diagrams.aws.management import Cloudwatch
from diagrams.aws.storage import S3
from diagrams.aws.integration import SNS

graph_attr = {
    "fontsize": "28",
    "bgcolor": "white",
    "pad": "0.8",
    "nodesep": "0.8",
    "ranksep": "1.0",
}

with Diagram(
    "CrimeReport - Security Groups & IAM Roles",
    filename="milestone_14_security",
    show=False,
    direction="LR",
    graph_attr=graph_attr,
    outformat="png",
):
    with Cluster("Security Groups", graph_attr={"style": "rounded", "bgcolor": "#FDECEA"}):
        with Cluster("WAF → ALB SG\nInbound: 80, 443 from 0.0.0.0/0"):
            waf = WAF("Web Application\nFirewall (WAF)")
            alb = ELB("API Gateway\nALB")

        with Cluster("ECS SG\nInbound: 3000 from ALB SG"):
            ecs = Fargate("Report API\nService\n(ECS Fargate)")

        with Cluster("DB SG\nInbound: 5432 from ECS SG"):
            db = Aurora("Crime Reports DB\n(Aurora Serverless v2)")

        with Cluster("Redis SG\nInbound: 6379 from ECS SG"):
            redis = ElastiCache("Feed Cache +\nSocket Adapter\n(ElastiCache Redis)")

    waf >> Edge(label="Filtered\nTraffic") >> alb
    alb >> Edge(label="TCP 3000", color="darkgreen") >> ecs
    ecs >> Edge(label="TCP 5432", color="blue") >> db
    ecs >> Edge(label="TCP 6379", color="red") >> redis

    with Cluster("IAM Roles", graph_attr={"style": "rounded", "bgcolor": "#E8F0FE"}):
        exec_role = IAMRole("ECS Execution\nRole")
        task_role = IAMRole("ECS Task\nRole")

    with Cluster("AWS Services", graph_attr={"style": "rounded", "bgcolor": "#F3E5F5"}):
        logs = Cloudwatch("CloudWatch\nLogs")
        s3 = S3("Processed Media\nS3 Bucket")
        sns = SNS("Notification\nDispatcher\n(SNS)")

    exec_role >> Edge(label="ECR Pull\n+ Logs", style="dashed") >> logs
    task_role >> Edge(label="Read/Write", style="dashed") >> s3
    task_role >> Edge(label="Publish", style="dashed") >> sns
