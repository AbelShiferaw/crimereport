import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { IamStack } from '../../lib/iam/iam-stack';
import { PROJECT_PREFIX } from '../../lib/config/constants';

describe('IamStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const stack = new IamStack(app, 'TestIam', {
      env: { account: '123456789012', region: 'us-east-1' },
    });
    template = Template.fromStack(stack);
  });

  test('ECS task role assumes ecs-tasks.amazonaws.com', () => {
    template.hasResourceProperties('AWS::IAM::Role', {
      RoleName: `${PROJECT_PREFIX}-ecs-task`,
      AssumeRolePolicyDocument: {
        Statement: Match.arrayWith([
          Match.objectLike({
            Action: 'sts:AssumeRole',
            Effect: 'Allow',
            Principal: { Service: 'ecs-tasks.amazonaws.com' },
          }),
        ]),
      },
    });
  });

  test('task role has S3 permissions scoped to crimereport-*', () => {
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: {
        Statement: Match.arrayWith([
          Match.objectLike({
            Sid: 'S3MediaAccess',
            Effect: 'Allow',
            Action: Match.arrayWith(['s3:GetObject', 's3:PutObject']),
            Resource: Match.arrayWith([
              `arn:aws:s3:::${PROJECT_PREFIX}-*`,
              `arn:aws:s3:::${PROJECT_PREFIX}-*/*`,
            ]),
          }),
        ]),
      },
    });
  });

  test('task role has Rekognition DetectModerationLabels permission', () => {
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: {
        Statement: Match.arrayWith([
          Match.objectLike({
            Sid: 'RekognitionModeration',
            Effect: 'Allow',
            Action: 'rekognition:DetectModerationLabels',
            Resource: '*',
          }),
        ]),
      },
    });
  });

  test('task role has SSM parameter read scoped to crimereport/*', () => {
    template.hasResourceProperties('AWS::IAM::Policy', {
      PolicyDocument: {
        Statement: Match.arrayWith([
          Match.objectLike({
            Sid: 'SSMParameterRead',
            Effect: 'Allow',
            Action: Match.arrayWith(['ssm:GetParameter']),
          }),
        ]),
      },
    });
  });
});
