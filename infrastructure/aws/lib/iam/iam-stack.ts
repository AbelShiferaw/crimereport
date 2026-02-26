import * as cdk from 'aws-cdk-lib';
import * as iam from 'aws-cdk-lib/aws-iam';
import { Construct } from 'constructs';
import { PROJECT_PREFIX } from '../config/constants';

export class IamStack extends cdk.Stack {
  public readonly ecsTaskRole: iam.Role;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const ecsPrincipal = new iam.ServicePrincipal('ecs-tasks.amazonaws.com');

    this.ecsTaskRole = new iam.Role(this, 'EcsTaskRole', {
      roleName: `${PROJECT_PREFIX}-ecs-task`,
      assumedBy: ecsPrincipal,
      description: 'ECS task role - app-level permissions for S3, SNS, Rekognition, SSM',
    });

    this.ecsTaskRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'S3MediaAccess',
        effect: iam.Effect.ALLOW,
        actions: [
          's3:GetObject',
          's3:PutObject',
          's3:DeleteObject',
          's3:ListBucket',
        ],
        resources: [
          `arn:aws:s3:::${PROJECT_PREFIX}-*`,
          `arn:aws:s3:::${PROJECT_PREFIX}-*/*`,
        ],
      }),
    );

    this.ecsTaskRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'SNSPublish',
        effect: iam.Effect.ALLOW,
        actions: ['sns:Publish'],
        resources: [`arn:aws:sns:${this.region}:${this.account}:${PROJECT_PREFIX}-*`],
      }),
    );

    this.ecsTaskRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'RekognitionModeration',
        effect: iam.Effect.ALLOW,
        actions: ['rekognition:DetectModerationLabels'],
        resources: ['*'],
      }),
    );

    this.ecsTaskRole.addToPolicy(
      new iam.PolicyStatement({
        sid: 'SSMParameterRead',
        effect: iam.Effect.ALLOW,
        actions: [
          'ssm:GetParameter',
          'ssm:GetParameters',
          'ssm:GetParametersByPath',
        ],
        resources: [
          `arn:aws:ssm:${this.region}:${this.account}:parameter/${PROJECT_PREFIX}/*`,
        ],
      }),
    );

    new cdk.CfnOutput(this, 'EcsTaskRoleArn', {
      value: this.ecsTaskRole.roleArn,
      description: 'ECS Task Role ARN',
    });
  }
}
