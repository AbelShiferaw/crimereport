import * as cdk from 'aws-cdk-lib';
import { Template, Match } from 'aws-cdk-lib/assertions';
import { WafStack } from '../../lib/network/waf-stack';
import { WAF_RATE_LIMIT } from '../../lib/config/constants';

describe('WafStack', () => {
  let template: Template;

  beforeAll(() => {
    const app = new cdk.App();
    const stack = new WafStack(app, 'TestWaf', {
      env: { account: '123456789012', region: 'us-east-1' },
    });
    template = Template.fromStack(stack);
  });

  test('creates WebACL with REGIONAL scope and Allow default action', () => {
    template.hasResourceProperties('AWS::WAFv2::WebACL', {
      Scope: 'REGIONAL',
      DefaultAction: { Allow: {} },
    });
  });

  test('has rate-limiting rule with correct limit', () => {
    template.hasResourceProperties('AWS::WAFv2::WebACL', {
      Rules: Match.arrayWith([
        Match.objectLike({
          Name: 'RateLimitPerIP',
          Statement: {
            RateBasedStatement: {
              Limit: WAF_RATE_LIMIT,
              AggregateKeyType: 'IP',
            },
          },
          Action: { Block: {} },
        }),
      ]),
    });
  });

  test('has AWSManagedRulesCommonRuleSet attached', () => {
    template.hasResourceProperties('AWS::WAFv2::WebACL', {
      Rules: Match.arrayWith([
        Match.objectLike({
          Name: 'AWSManagedRulesCommonRuleSet',
          Statement: {
            ManagedRuleGroupStatement: {
              VendorName: 'AWS',
              Name: 'AWSManagedRulesCommonRuleSet',
            },
          },
        }),
      ]),
    });
  });

  test('has AWSManagedRulesKnownBadInputsRuleSet attached', () => {
    template.hasResourceProperties('AWS::WAFv2::WebACL', {
      Rules: Match.arrayWith([
        Match.objectLike({
          Name: 'AWSManagedRulesKnownBadInputs',
          Statement: {
            ManagedRuleGroupStatement: {
              VendorName: 'AWS',
              Name: 'AWSManagedRulesKnownBadInputsRuleSet',
            },
          },
        }),
      ]),
    });
  });
});
