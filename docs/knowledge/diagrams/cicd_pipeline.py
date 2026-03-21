from diagrams import Diagram, Cluster, Edge
from diagrams.aws.compute import ECR, ECS, Fargate
from diagrams.aws.network import ELB
from diagrams.aws.security import IAMRole
from diagrams.aws.management import Cloudformation
from diagrams.programming.language import Typescript
from diagrams.programming.framework import Flutter
from diagrams.onprem.vcs import Github
from diagrams.onprem.ci import GithubActions
from diagrams.onprem.container import Docker
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

# --- Diagram 1: PR Workflow ---

with Diagram(
    "CI/CD - Pull Request Workflow",
    filename=os.path.join(script_dir, "cicd_pr_workflow"),
    show=False,
    direction="LR",
    graph_attr=graph_attr,
    outformat="png",
):
    dev = User("Developer")
    pr = Github("Open PR\nto main")

    with Cluster("GitHub Actions Runner", graph_attr={"style": "rounded", "bgcolor": "#E3F2FD"}):
        with Cluster("Parallel Test Jobs", graph_attr={"style": "rounded", "bgcolor": "#BBDEFB"}):
            backend_test = Typescript("Backend Tests\nnpm test\n(Jest)")
            cdk_test = Typescript("CDK Tests\nnpm test\n(Jest)")
            flutter_test = Flutter("Flutter\nanalyze + test")

    with Cluster("AWS (read-only via OIDC)", graph_attr={"style": "rounded", "bgcolor": "#F3E5F5"}):
        oidc = IAMRole("OIDC\nAssumeRole")
        cfn_diff = Cloudformation("cdk diff\npreview changes")

    comment = Github("PR Comment\ninfra diff output")

    dev >> Edge(label="1. push branch", color="darkgreen") >> pr
    pr >> Edge(label="2. triggers", color="blue") >> backend_test
    pr >> Edge(color="blue") >> cdk_test
    pr >> Edge(color="blue") >> flutter_test
    backend_test >> Edge(label="3. all pass", color="green") >> oidc
    oidc >> Edge(label="4. temp creds", color="purple") >> cfn_diff
    cfn_diff >> Edge(label="5. post diff", color="darkcyan") >> comment


# --- Diagram 2: Deploy Workflow ---

with Diagram(
    "CI/CD - Deploy on Merge to Main",
    filename=os.path.join(script_dir, "cicd_deploy_workflow"),
    show=False,
    direction="TB",
    graph_attr=graph_attr,
    outformat="png",
):
    merge = Github("PR Merged\nto main")

    with Cluster("1. Test Gate (GitHub Actions)", graph_attr={"style": "rounded", "bgcolor": "#E3F2FD"}):
        tests = GithubActions("All Tests\nMust Pass")

    with Cluster("2. Authenticate (OIDC)", graph_attr={"style": "rounded", "bgcolor": "#F3E5F5"}):
        oidc2 = IAMRole("AssumeRole\n(15-min creds)")

    with Cluster("3. CDK Deploy", graph_attr={"style": "rounded", "bgcolor": "#FFF3E0"}):
        synth = Cloudformation("cdk synth\n(generate CFN)")
        deploy = Cloudformation("cdk deploy --all\n(10 stacks)")

    with Cluster("4. Container Pipeline (automatic)", graph_attr={"style": "rounded", "bgcolor": "#E8F5E9"}):
        docker = Docker("Docker Build\nvia CDK")
        ecr = ECR("Push to ECR")
        ecs = ECS("ECS Rolling\nUpdate")
        fargate = Fargate("New Tasks\nLaunched")

    with Cluster("5. Verify", graph_attr={"style": "rounded", "bgcolor": "#E0F2F1"}):
        alb = ELB("ALB Health\nCheck")

    merge >> Edge(label="triggers", color="darkgreen") >> tests
    tests >> Edge(label="all green", color="green") >> oidc2
    oidc2 >> Edge(label="temp AWS creds", color="purple") >> synth
    synth >> Edge(color="blue") >> deploy
    deploy >> Edge(label="builds image", color="orange") >> docker
    docker >> Edge(color="orange") >> ecr
    ecr >> Edge(label="new image", color="blue") >> ecs
    ecs >> Edge(color="blue") >> fargate
    fargate >> Edge(label="curl /health", color="darkcyan") >> alb


# --- Diagram 3: OIDC Authentication Flow ---

with Diagram(
    "GitHub Actions OIDC Authentication",
    filename=os.path.join(script_dir, "cicd_oidc_flow"),
    show=False,
    direction="LR",
    graph_attr=graph_attr,
    outformat="png",
):
    with Cluster("GitHub", graph_attr={"style": "rounded", "bgcolor": "#E3F2FD"}):
        action = GithubActions("Workflow Run")
        jwt = Github("OIDC JWT\n(short-lived)")

    with Cluster("AWS IAM", graph_attr={"style": "rounded", "bgcolor": "#F3E5F5"}):
        provider = IAMRole("OIDC Provider\ntrusts\ntoken.actions.\ngithubusercontent.com")
        role = IAMRole("Deploy Role\ncrimereport-\ngithub-deploy")
        sts = IAMRole("STS Credentials\n(15 min TTL)")

    action >> Edge(label="1. request\nOIDC token", color="blue") >> jwt
    jwt >> Edge(label="2. present JWT", color="purple") >> provider
    provider >> Edge(label="3. verify issuer\n& claims", color="purple") >> role
    role >> Edge(label="4. AssumeRole\nWithWebIdentity", color="orange") >> sts
    sts >> Edge(label="5. temp access key\n+ secret + token", color="green", style="dashed") >> action
