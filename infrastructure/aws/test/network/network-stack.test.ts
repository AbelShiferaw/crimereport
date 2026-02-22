import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import { NetworkStack } from '../../lib/network/network-stack';
import { VPC_CIDR } from '../../lib/config/constants';

describe('NetworkStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const stack = new NetworkStack(app, 'TestNetwork', {
      env: { account: '123456789012', region: 'us-east-1' },
    });
    template = Template.fromStack(stack);
  });

  test('creates VPC with correct CIDR', () => {
    template.hasResourceProperties('AWS::EC2::VPC', {
      CidrBlock: VPC_CIDR,
      EnableDnsHostnames: true,
      EnableDnsSupport: true,
    });
  });

  test('creates exactly 2 public subnets with public IPs', () => {
    const subnets = template.findResources('AWS::EC2::Subnet', {
      Properties: {
        MapPublicIpOnLaunch: true,
      },
    });
    expect(Object.keys(subnets).length).toBe(2);
  });

  test('creates exactly 2 private subnets', () => {
    const allSubnets = template.findResources('AWS::EC2::Subnet');
    const publicSubnets = template.findResources('AWS::EC2::Subnet', {
      Properties: { MapPublicIpOnLaunch: true },
    });
    const privateCount = Object.keys(allSubnets).length - Object.keys(publicSubnets).length;
    expect(privateCount).toBe(2);
  });

  test('creates exactly 1 NAT Gateway', () => {
    template.resourceCountIs('AWS::EC2::NatGateway', 1);
  });

  test('creates and attaches Internet Gateway', () => {
    template.resourceCountIs('AWS::EC2::InternetGateway', 1);
    template.resourceCountIs('AWS::EC2::VPCGatewayAttachment', 1);
  });
});
