import * as cdk from 'aws-cdk-lib';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { SecurityStack } from '../../lib/network/security-stack';
import { API_PORT, DB_PORT, REDIS_PORT } from '../../lib/config/constants';

function createStack(): Template {
  const app = new cdk.App();
  const vpcStack = new cdk.Stack(app, 'VpcStack', {
    env: { account: '123456789012', region: 'us-east-1' },
  });
  const vpc = new ec2.Vpc(vpcStack, 'TestVpc', { maxAzs: 2 });

  const stack = new SecurityStack(app, 'TestSecurity', {
    env: { account: '123456789012', region: 'us-east-1' },
    vpc,
  });
  return Template.fromStack(stack);
}

describe('SecurityStack', () => {
  let template: Template;

  beforeAll(() => {
    template = createStack();
  });

  test('creates exactly 4 security groups', () => {
    template.resourceCountIs('AWS::EC2::SecurityGroup', 4);
  });

  test('ALB SG allows inbound HTTPS from IPv4', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupDescription: Match.stringLikeRegexp('API Gateway ALB'),
      SecurityGroupIngress: Match.arrayWith([
        Match.objectLike({
          IpProtocol: 'tcp',
          FromPort: 443,
          ToPort: 443,
          CidrIp: '0.0.0.0/0',
        }),
      ]),
    });
  });

  test('ALB SG allows inbound HTTPS from IPv6', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroup', {
      GroupDescription: Match.stringLikeRegexp('API Gateway ALB'),
      SecurityGroupIngress: Match.arrayWith([
        Match.objectLike({
          IpProtocol: 'tcp',
          FromPort: 443,
          ToPort: 443,
          CidrIpv6: '::/0',
        }),
      ]),
    });
  });

  test('ECS SG allows inbound on API port from ALB SG only', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroupIngress', {
      IpProtocol: 'tcp',
      FromPort: API_PORT,
      ToPort: API_PORT,
      Description: 'API traffic from ALB',
    });
  });

  test('DB SG allows inbound on DB port from ECS SG only', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroupIngress', {
      IpProtocol: 'tcp',
      FromPort: DB_PORT,
      ToPort: DB_PORT,
      Description: 'PostgreSQL from ECS tasks',
    });
  });

  test('Redis SG allows inbound on Redis port from ECS SG only', () => {
    template.hasResourceProperties('AWS::EC2::SecurityGroupIngress', {
      IpProtocol: 'tcp',
      FromPort: REDIS_PORT,
      ToPort: REDIS_PORT,
      Description: 'Redis from ECS tasks',
    });
  });

  test('DB and Redis SGs block all outbound', () => {
    const sgs = template.findResources('AWS::EC2::SecurityGroup');
    const restrictedSgs = Object.values(sgs).filter(
      (sg: any) =>
        sg.Properties.GroupDescription?.includes('Crime Reports DB') ||
        sg.Properties.GroupDescription?.includes('Feed Cache'),
    );
    for (const sg of restrictedSgs) {
      const egress = (sg as any).Properties.SecurityGroupEgress;
      expect(egress).toBeDefined();
      expect(egress).toEqual(
        expect.arrayContaining([
          expect.objectContaining({
            CidrIp: '255.255.255.255/32',
            Description: 'Disallow all traffic',
            IpProtocol: 'icmp',
            FromPort: 252,
            ToPort: 86,
          }),
        ]),
      );
    }
  });
});
