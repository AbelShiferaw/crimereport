from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import ELB, CloudFront as CF, NATGateway, InternetGateway
from diagrams.aws.compute import Fargate, Lambda
from diagrams.aws.database import Aurora, ElastiCache
from diagrams.aws.storage import S3
from diagrams.aws.integration import StepFunctions, Eventbridge
from diagrams.aws.ml import Rekognition
from diagrams.aws.media import ElementalMediaconvert
from diagrams.aws.security import WAF
from diagrams.aws.general import Client
from diagrams.onprem.client import User
import os

script_dir = os.path.dirname(os.path.abspath(__file__))

graph_attr = {
    "fontsize": "28",
    "bgcolor": "white",
    "pad": "1.0",
    "nodesep": "0.6",
    "ranksep": "1.0",
    "dpi": "150",
}

with Diagram(
    "API Request Flow (through VPC)",
    filename=os.path.join(script_dir, "request_flow_api"),
    show=False,
    direction="TB",
    graph_attr=graph_attr,
    outformat="png",
):
    user = User("Mobile App")

    with Cluster("1. Edge Layer", graph_attr={"style": "rounded", "bgcolor": "#FFEBEE"}):
        waf = WAF("WAF inspects\nrequest")

    with Cluster("2. Public Subnet (VPC)", graph_attr={"style": "rounded", "bgcolor": "#C8E6C9"}):
        igw = InternetGateway("Internet\nGateway")
        alb = ELB("ALB terminates\nSSL, routes\nto healthy target")

    with Cluster("3. Private Subnet (VPC)", graph_attr={"style": "rounded", "bgcolor": "#EDE7F6"}):
        fargate = Fargate("Fargate runs\nNode.js + Express\n+ Socket.io")
        aurora = Aurora("Query crime\nreports\n(PostGIS geo)")
        redis = ElastiCache("Check cache\nfirst, rate\nlimit check")

    with Cluster("4. Response", graph_attr={"style": "rounded", "bgcolor": "#E0F2F1"}):
        response = Client("JSON response\nback to app")

    user >> Edge(label="1. HTTPS GET\n/api/v1/reports?lat=X&lng=Y", color="darkgreen") >> waf
    waf >> Edge(label="2. Rate OK,\nno attacks", color="darkgreen") >> igw
    igw >> Edge(label="3. Route to\npublic subnet", color="blue") >> alb
    alb >> Edge(label="4. Forward to\nhealthy task\n(port 3000)", color="blue") >> fargate
    fargate >> Edge(label="5a. Cache\nhit?", color="red") >> redis
    fargate >> Edge(label="5b. Cache miss\n-> SQL query", color="purple") >> aurora
    fargate >> Edge(label="6. Return\nresults", color="darkcyan") >> response
    response >> Edge(label="7. IGW -> Internet\n-> User", color="darkcyan") >> user


with Diagram(
    "Media Upload Flow (bypasses VPC)",
    filename=os.path.join(script_dir, "request_flow_media"),
    show=False,
    direction="TB",
    graph_attr=graph_attr,
    outformat="png",
):
    app = User("Mobile App")

    with Cluster("Phase 1: Get Presigned URL\n(goes through VPC)", graph_attr={"style": "rounded", "bgcolor": "#E3F2FD"}):
        alb2 = ELB("ALB -> Fargate")

    with Cluster("Phase 2: Direct Upload\n(bypasses VPC entirely)", graph_attr={"style": "rounded", "bgcolor": "#FFF3E0"}):
        s3_upload = S3("S3 Uploads\nBucket\n(presigned URL)")

    with Cluster("Phase 3: Serverless Processing\n(outside VPC)", graph_attr={"style": "rounded", "bgcolor": "#FBE9E7"}):
        eb = Eventbridge("EventBridge\nObjectCreated")
        sfn = StepFunctions("Step Functions\nPipeline")
        rek = Rekognition("Rekognition\nModeration")
        lam = Lambda("Lambda\nJob Builder")
        mc = ElementalMediaconvert("MediaConvert\nTranscode")

    with Cluster("Phase 4: Delivery\n(outside VPC)", graph_attr={"style": "rounded", "bgcolor": "#E8F5E9"}):
        s3_media = S3("S3 Media\nBucket")
        cdn = CF("CloudFront\nCDN")

    app >> Edge(label="1. POST /api/reports\n(through VPC)", color="blue") >> alb2
    alb2 >> Edge(label="2. Returns\npresigned URL", color="blue", style="dashed") >> app
    app >> Edge(label="3. PUT file\ndirectly to S3\n(NO VPC)", color="orange") >> s3_upload
    s3_upload >> Edge(color="gray") >> eb
    eb >> Edge(color="gray") >> sfn
    sfn >> Edge(label="Moderate", color="gray") >> rek
    rek >> Edge(label="Safe", color="green") >> lam
    lam >> Edge(color="gray") >> mc
    mc >> Edge(color="gray") >> s3_media
    s3_media >> Edge(color="gray") >> cdn
    cdn >> Edge(label="4. Stream\nmedia", color="darkcyan") >> app
