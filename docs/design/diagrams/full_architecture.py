from diagrams import Diagram, Cluster, Edge
from diagrams.aws.network import ELB, CloudFront as CF, VPC as VPCIcon, NATGateway, InternetGateway
from diagrams.aws.compute import Fargate, Lambda
from diagrams.aws.database import Aurora, ElastiCache
from diagrams.aws.storage import S3
from diagrams.aws.integration import SNS, SQS, StepFunctions, Eventbridge
from diagrams.aws.media import ElementalMediaconvert
from diagrams.aws.ml import Rekognition
from diagrams.aws.security import WAF
from diagrams.aws.general import Client
from diagrams.firebase.grow import Messaging as FCMIcon
from diagrams.onprem.client import User
from diagrams.custom import Custom
import urllib.request
import os

script_dir = os.path.dirname(os.path.abspath(__file__))
icons_dir = os.path.join(script_dir, "icons")
os.makedirs(icons_dir, exist_ok=True)

icons = {
    "flutter": ("https://storage.googleapis.com/cms-storage-bucket/4fd5520fe28ebf839571.png", "flutter.png"),
    "mapbox": ("https://upload.wikimedia.org/wikipedia/commons/thumb/1/1f/Mapbox_logo_2019.svg/512px-Mapbox_logo_2019.svg.png", "mapbox.png"),
}

for name, (url, filename) in icons.items():
    filepath = os.path.join(icons_dir, filename)
    if not os.path.exists(filepath):
        try:
            urllib.request.urlretrieve(url, filepath)
        except Exception:
            pass

flutter_icon = os.path.join(icons_dir, "flutter.png")
mapbox_icon = os.path.join(icons_dir, "mapbox.png")

graph_attr = {
    "fontsize": "32",
    "bgcolor": "white",
    "pad": "1.0",
    "nodesep": "0.6",
    "ranksep": "1.0",
    "dpi": "150",
}

with Diagram(
    "CrimeReport - Full System Architecture",
    filename=os.path.join(script_dir, "full_architecture"),
    show=False,
    direction="TB",
    graph_attr=graph_attr,
    outformat="png",
):
    user = User("Anonymous\nReporter")

    with Cluster("Flutter Mobile App", graph_attr={"style": "rounded", "bgcolor": "#E3F2FD"}):
        if os.path.exists(flutter_icon):
            app = Custom("CrimeReport\nApp", flutter_icon)
        else:
            app = Client("CrimeReport\nApp")
        rest_client = Client("Report API\nClient")
        ws_client = Client("Live Updates\nClient")

    with Cluster("AWS Cloud", graph_attr={"style": "rounded", "bgcolor": "#FFF8E1"}):

        with Cluster("Edge Protection", graph_attr={"style": "rounded", "bgcolor": "#FFEBEE"}):
            waf = WAF("Web Application\nFirewall (WAF)")

        with Cluster("VPC: 10.0.0.0/16", graph_attr={"style": "rounded", "bgcolor": "#E8EAF6"}):

            with Cluster("Public Subnets (10.0.0.0/24, 10.0.1.0/24)", graph_attr={"style": "rounded", "bgcolor": "#C8E6C9"}):
                igw = InternetGateway("Internet\nGateway")
                with Cluster("crimereport-alb-sg\n(80/443 from internet)", graph_attr={"style": "dashed", "bgcolor": "#A5D6A7", "pencolor": "#2E7D32"}):
                    alb = ELB("API Gateway\nALB")
                nat = NATGateway("NAT\nGateway")

            with Cluster("Private Subnets (10.0.2.0/24, 10.0.3.0/24)", graph_attr={"style": "rounded", "bgcolor": "#F3E5F5"}):
                with Cluster("crimereport-ecs-sg\n(3000 from ALB SG only)", graph_attr={"style": "dashed", "bgcolor": "#CE93D8", "pencolor": "#6A1B9A"}):
                    fargate = Fargate("Report API\nService\n(ECS Fargate)\n0.25 vCPU / 0.5 GB")
                with Cluster("crimereport-db-sg\n(5432 from ECS SG only)", graph_attr={"style": "dashed", "bgcolor": "#CE93D8", "pencolor": "#6A1B9A"}):
                    aurora = Aurora("Crime Reports DB\n(Aurora Serverless v2\n+ PostGIS)")
                with Cluster("crimereport-redis-sg\n(6379 from ECS SG only)", graph_attr={"style": "dashed", "bgcolor": "#CE93D8", "pencolor": "#6A1B9A"}):
                    redis = ElastiCache("Feed Cache +\nSocket Adapter\n(ElastiCache Redis)\ncache.t4g.micro")

        with Cluster("Media Pipeline", graph_attr={"style": "rounded", "bgcolor": "#FBE9E7"}):
            s3_raw = S3("Evidence Upload\nS3 Bucket")
            eb = Eventbridge("Upload Event\n(EventBridge)")
            sfn = StepFunctions("Media Processing\nPipeline\n(Step Functions)")
            rekognition = Rekognition("Content\nModeration\n(Rekognition)")
            lam = Lambda("MediaConvert\nJob Builder\n(Lambda)")
            dlq = SQS("Failed Jobs\nDead Letter Queue\n(SQS)")
            media_convert = ElementalMediaconvert("Evidence\nTranscoder\n(MediaConvert)")
            s3_processed = S3("Processed Media\nS3 Bucket")
            cloudfront = CF("Media Delivery\nCDN\n(CloudFront)")

        with Cluster("Notifications", graph_attr={"style": "rounded", "bgcolor": "#E0F2F1"}):
            sns = SNS("Notification\nDispatcher\n(SNS)")

    with Cluster("External Services", graph_attr={"style": "rounded", "bgcolor": "#ECEFF1"}):
        fcm = FCMIcon("Push Delivery\nService (FCM)")
        if os.path.exists(mapbox_icon):
            mapbox = Custom("Crime Map\nTiles (Mapbox)", mapbox_icon)
        else:
            mapbox = Client("Crime Map\nTiles (Mapbox)")
        recaptcha = Client("reCAPTCHA v3\n(Google)")

    user >> app

    app >> Edge(label="Verify before\nsubmit", style="dashed", color="gray") >> recaptcha
    rest_client >> Edge(label="HTTP/REST\n/v1/*", color="darkgreen") >> waf
    ws_client >> Edge(label="WebSocket", color="purple") >> waf
    waf >> Edge(label="Rate-limited\ntraffic", color="darkgreen") >> igw
    igw >> alb
    alb >> fargate

    fargate >> Edge(label="SQL", color="blue") >> aurora
    fargate >> Edge(label="Cache +\nPub/Sub", color="red") >> redis
    fargate >> Edge(label="Outbound\nvia NAT", style="dashed", color="gray") >> nat

    app >> Edge(label="Upload\n(presigned URL)", color="orange") >> s3_raw
    s3_raw >> Edge(label="ObjectCreated", color="gray") >> eb
    eb >> Edge(label="Trigger", color="gray") >> sfn
    sfn >> Edge(label="On failure", color="crimson", style="dashed") >> dlq
    sfn >> Edge(label="Image: sync\nVideo: async", color="gray") >> rekognition
    rekognition >> Edge(label="Safe\nvideo only", color="green") >> lam
    lam >> Edge(label="Submit Job", color="gray") >> media_convert
    media_convert >> Edge(label="MP4 + Thumb\n+ GIF", color="gray") >> s3_processed
    rekognition >> Edge(label="Safe\nimage: copy", color="green", style="dashed") >> s3_processed
    s3_processed >> cloudfront
    cloudfront >> Edge(label="Stream\nMedia", color="darkcyan") >> app

    fargate >> Edge(label="Publish", color="teal") >> sns
    sns >> Edge(color="orange") >> fcm
    fcm >> Edge(label="Push\nNotification", color="orange") >> app

    app >> Edge(label="Map Tiles", style="dashed", color="gray") >> mapbox
