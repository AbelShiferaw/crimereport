import * as cdk from 'aws-cdk-lib';
import * as wafv2 from 'aws-cdk-lib/aws-wafv2';
import { Construct } from 'constructs';
import { PROJECT_PREFIX, WAF_RATE_LIMIT } from '../config/constants';

export class WafStack extends cdk.Stack {
  public readonly webAclArn: string;

  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    const webAcl = new wafv2.CfnWebACL(this, 'CrimeReportWaf', {
      name: `${PROJECT_PREFIX}-waf`,
      scope: 'REGIONAL',
      defaultAction: { allow: {} },
      visibilityConfig: {
        cloudWatchMetricsEnabled: true,
        metricName: `${PROJECT_PREFIX}-waf`,
        sampledRequestsEnabled: true,
      },
      rules: [
        {
          name: 'RateLimitPerIP',
          priority: 1,
          action: { block: {} },
          visibilityConfig: {
            cloudWatchMetricsEnabled: true,
            metricName: `${PROJECT_PREFIX}-rate-limit`,
            sampledRequestsEnabled: true,
          },
          statement: {
            rateBasedStatement: {
              limit: WAF_RATE_LIMIT,
              aggregateKeyType: 'IP',
            },
          },
        },
        {
          name: 'AWSManagedRulesCommonRuleSet',
          priority: 2,
          overrideAction: { none: {} },
          visibilityConfig: {
            cloudWatchMetricsEnabled: true,
            metricName: `${PROJECT_PREFIX}-common-rules`,
            sampledRequestsEnabled: true,
          },
          statement: {
            managedRuleGroupStatement: {
              vendorName: 'AWS',
              name: 'AWSManagedRulesCommonRuleSet',
            },
          },
        },
        {
          name: 'AWSManagedRulesKnownBadInputs',
          priority: 3,
          overrideAction: { none: {} },
          visibilityConfig: {
            cloudWatchMetricsEnabled: true,
            metricName: `${PROJECT_PREFIX}-bad-inputs`,
            sampledRequestsEnabled: true,
          },
          statement: {
            managedRuleGroupStatement: {
              vendorName: 'AWS',
              name: 'AWSManagedRulesKnownBadInputsRuleSet',
            },
          },
        },
      ],
    });

    this.webAclArn = webAcl.attrArn;

    new cdk.CfnOutput(this, 'WebAclArn', {
      value: webAcl.attrArn,
      description: 'WAF WebACL ARN (attach to ALB in Milestone 17)',
    });
  }
}
