import * as cdk from 'aws-cdk-lib';
import * as ssm from 'aws-cdk-lib/aws-ssm';
import { Construct } from 'constructs';
import { PROJECT_PREFIX } from '../config/constants';

/**
 * SNS Platform Applications for push notifications must be created via AWS CLI
 * or Console because they require out-of-band credentials (FCM service account,
 * APNs certs). This stack reads their ARNs from SSM Parameter Store so the
 * compute stack can reference them as environment variables.
 *
 * Before deploying, create the SSM parameters:
 *   aws ssm put-parameter --name /crimereport/sns-android-platform-arn --value <arn> --type String
 *   aws ssm put-parameter --name /crimereport/sns-ios-platform-arn --value <arn> --type String
 */
export class SnsStack extends cdk.Stack {
  public readonly androidPlatformArn: string;
  public readonly iosPlatformArn: string;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    this.androidPlatformArn = ssm.StringParameter.valueForStringParameter(
      this,
      `/${PROJECT_PREFIX}/sns-android-platform-arn`,
    );

    this.iosPlatformArn = ssm.StringParameter.valueForStringParameter(
      this,
      `/${PROJECT_PREFIX}/sns-ios-platform-arn`,
    );

    new cdk.CfnOutput(this, 'AndroidPlatformArn', { value: this.androidPlatformArn });
    new cdk.CfnOutput(this, 'IosPlatformArn', { value: this.iosPlatformArn });
  }
}
