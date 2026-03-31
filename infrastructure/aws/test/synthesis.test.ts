import * as path from 'path';
import * as cdk from 'aws-cdk-lib';
import { NetworkStack } from '../lib/network/network-stack';
import { WafStack } from '../lib/network/waf-stack';
import { SecurityStack } from '../lib/network/security-stack';
import { IamStack } from '../lib/iam/iam-stack';
import { DatabaseStack } from '../lib/data/database-stack';
import { CacheStack } from '../lib/data/cache-stack';
import { MediaStack } from '../lib/media/media-stack';
import { ComputeStack } from '../lib/compute/compute-stack';
import { MonitoringStack } from '../lib/monitoring/monitoring-stack';
import { SnsStack } from '../lib/notifications/sns-stack';
import { CicdStack } from '../lib/cicd/cicd-stack';
import { PROJECT_PREFIX } from '../lib/config/constants';

describe('Full CDK synthesis smoke test', () => {
  let app: cdk.App;

  beforeAll(() => { app = new cdk.App(); });

  test('synthesizes all stacks without circular dependency errors', () => {
    const env = { account: '123456789012', region: 'us-east-1' };
    const networkStack = new NetworkStack(app, 'Test-Network', { env });
    const wafStack = new WafStack(app, 'Test-Waf', { env });
    const securityStack = new SecurityStack(app, 'Test-Security', { env, vpc: networkStack.vpc });
    securityStack.addDependency(networkStack);
    const iamStack = new IamStack(app, 'Test-Iam', { env });
    const databaseStack = new DatabaseStack(app, 'Test-Database', { env, vpc: networkStack.vpc, securityGroup: securityStack.dbSecurityGroup });
    databaseStack.addDependency(networkStack); databaseStack.addDependency(securityStack);
    const cacheStack = new CacheStack(app, 'Test-Cache', { env, vpc: networkStack.vpc, securityGroup: securityStack.redisSecurityGroup });
    cacheStack.addDependency(networkStack); cacheStack.addDependency(securityStack);
    const mediaStack = new MediaStack(app, 'Test-Media', { env });
    const snsStack = new SnsStack(app, 'Test-Sns', { env });
    const computeStack = new ComputeStack(app, 'Test-Compute', {
      env, vpc: networkStack.vpc, albSecurityGroup: securityStack.albSecurityGroup,
      ecsSecurityGroup: securityStack.ecsSecurityGroup, taskRole: iamStack.ecsTaskRole,
      dbSecret: databaseStack.cluster.secret!, redisEndpoint: cacheStack.redisEndpoint,
      redisPort: cacheStack.redisPort, wafAclArn: wafStack.webAclArn,
      dockerDir: path.join(__dirname, '..', '..', '..', 'backend', 'api'),
      s3UploadsBucket: mediaStack.uploadsBucket.bucketName, s3MediaBucket: mediaStack.mediaBucket.bucketName,
      cdnDomain: mediaStack.distribution.distributionDomainName,
      snsAndroidPlatformArn: snsStack.androidPlatformArn, snsIosPlatformArn: snsStack.iosPlatformArn,
    });
    computeStack.addDependency(networkStack); computeStack.addDependency(securityStack);
    computeStack.addDependency(iamStack); computeStack.addDependency(databaseStack);
    computeStack.addDependency(cacheStack); computeStack.addDependency(wafStack);
    computeStack.addDependency(mediaStack); computeStack.addDependency(snsStack);
    new CicdStack(app, 'Test-Cicd', { env });
    const monitoringStack = new MonitoringStack(app, 'Test-Monitoring', {
      env, dbCluster: databaseStack.cluster, redisReplicationGroupId: `${PROJECT_PREFIX}-redis`,
      ecsCluster: computeStack.cluster, ecsService: computeStack.service, alb: computeStack.alb,
    });
    monitoringStack.addDependency(databaseStack); monitoringStack.addDependency(cacheStack);
    monitoringStack.addDependency(computeStack);
    expect(() => app.synth()).not.toThrow();
  });

  test('synthesis produces the expected number of stacks', () => {
    const assembly = app.synth();
    expect(assembly.stacks.length).toBeGreaterThanOrEqual(10);
    const names = assembly.stacks.map((s) => s.stackName);
    expect(names).toContain('Test-Network');
    expect(names).toContain('Test-Compute');
    expect(names).toContain('Test-Media');
    expect(names).toContain('Test-Monitoring');
  });
});
