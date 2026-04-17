import * as cdk from 'aws-cdk-lib';
import * as cloudfront from 'aws-cdk-lib/aws-cloudfront';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as route53 from 'aws-cdk-lib/aws-route53';
import * as targets from 'aws-cdk-lib/aws-route53-targets';
import { Construct } from 'constructs';
import { PROJECT_PREFIX, DOMAIN_NAME, API_SUBDOMAIN, CDN_SUBDOMAIN } from '../config/constants';

export interface DnsStackProps extends cdk.StackProps {
  /** The ALB to alias `api.reportcrime.app` to. */
  alb: elbv2.IApplicationLoadBalancer;
  /** The CloudFront distribution to alias `cdn.reportcrime.app` to. */
  distribution: cloudfront.IDistribution;
  /** Override domain name (useful for testing). Defaults to DOMAIN_NAME constant. */
  domainName?: string;
}

export class DnsStack extends cdk.Stack {
  public readonly hostedZone: route53.IHostedZone;
  public readonly apiRecord: route53.ARecord;
  public readonly cdnRecord: route53.ARecord;

  constructor(scope: Construct, id: string, props: DnsStackProps) {
    super(scope, id, props);

    const { alb, distribution } = props;
    const domainName = props.domainName ?? DOMAIN_NAME;

    this.hostedZone = new route53.HostedZone(this, 'HostedZone', {
      zoneName: domainName,
      comment: `${PROJECT_PREFIX} public hosted zone`,
    });

    this.apiRecord = new route53.ARecord(this, 'ApiAliasRecord', {
      zone: this.hostedZone,
      recordName: `${API_SUBDOMAIN}.${domainName}`,
      target: route53.RecordTarget.fromAlias(
        new targets.LoadBalancerTarget(alb),
      ),
      comment: 'API ALB alias',
    });

    this.cdnRecord = new route53.ARecord(this, 'CdnAliasRecord', {
      zone: this.hostedZone,
      recordName: `${CDN_SUBDOMAIN}.${domainName}`,
      target: route53.RecordTarget.fromAlias(
        new targets.CloudFrontTarget(distribution),
      ),
      comment: 'CDN CloudFront alias',
    });

    new cdk.CfnOutput(this, 'HostedZoneId', {
      value: this.hostedZone.hostedZoneId,
      description: 'Route 53 hosted zone ID',
    });

    new cdk.CfnOutput(this, 'ApiDomainName', {
      value: `${API_SUBDOMAIN}.${domainName}`,
      description: 'API domain name',
    });

    new cdk.CfnOutput(this, 'CdnDomainName', {
      value: `${CDN_SUBDOMAIN}.${domainName}`,
      description: 'CDN domain name',
    });
  }
}
