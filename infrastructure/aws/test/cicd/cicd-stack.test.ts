import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { CicdStack } from '../../lib/cicd/cicd-stack';
import { PROJECT_PREFIX, GITHUB_REPO } from '../../lib/config/constants';

describe('CicdStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const stack = new CicdStack(app, 'TestCicd', {
      env: { account: '123456789012', region: 'us-east-1' },
    });
    template = Template.fromStack(stack);
  });

  test('creates OIDC provider for GitHub Actions', () => {
    template.hasResourceProperties('Custom::AWSCDKOpenIdConnectProvider', {
      Url: 'https://token.actions.githubusercontent.com',
      ClientIDList: ['sts.amazonaws.com'],
    });
  });

  test('creates deploy role with correct trust policy', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      RoleName: `${PROJECT_PREFIX}-github-deploy`,
      AssumeRolePolicyDocument: {
        Statement: Match.arrayWith([
          Match.objectLike({
            Action: 'sts:AssumeRoleWithWebIdentity',
            Effect: 'Allow',
            Condition: {
              StringEquals: {
                'token.actions.githubusercontent.com:aud': 'sts.amazonaws.com',
              },
              StringLike: {
                'token.actions.githubusercontent.com:sub': `repo:${GITHUB_REPO}:*`,
              },
            },
          }),
        ]),
      },
    });
  });

  test('deploy role has AdministratorAccess', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      RoleName: `${PROJECT_PREFIX}-github-deploy`,
      ManagedPolicyArns: Match.arrayWith([
        Match.objectLike({
          'Fn::Join': Match.arrayWith([
            '',
            Match.arrayWith([
              Match.stringLikeRegexp('.*AdministratorAccess'),
            ]),
          ]),
        }),
      ]),
    });
  });

  test('exports deploy role ARN', () => {
    template.hasOutput('DeployRoleArn', {
      Value: Match.anyValue(),
    });
  });
});
