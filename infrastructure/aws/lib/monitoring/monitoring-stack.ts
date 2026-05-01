import * as cdk from 'aws-cdk-lib';
import * as cloudwatch from 'aws-cdk-lib/aws-cloudwatch';
import * as cw_actions from 'aws-cdk-lib/aws-cloudwatch-actions';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as elbv2 from 'aws-cdk-lib/aws-elasticloadbalancingv2';
import * as rds from 'aws-cdk-lib/aws-rds';
import * as sns from 'aws-cdk-lib/aws-sns';
import * as subscriptions from 'aws-cdk-lib/aws-sns-subscriptions';
import { Construct } from 'constructs';
import { PROJECT_PREFIX, ALARM_EMAIL } from '../config/constants';

export interface MonitoringStackProps extends cdk.StackProps {
  dbCluster: rds.IDatabaseCluster;
  redisReplicationGroupId: string;
  ecsCluster: ecs.ICluster;
  ecsService: ecs.FargateService;
  alb: elbv2.IApplicationLoadBalancer;
}

export class MonitoringStack extends cdk.Stack {
  public readonly dashboard: cloudwatch.Dashboard;
  public readonly alarmTopic: sns.Topic;

  constructor(scope: Construct, id: string, props: MonitoringStackProps) {
    super(scope, id, props);

    const { dbCluster, redisReplicationGroupId, ecsService, alb } = props;

    // ── SNS Alarm Topic ──────────────────────────────────────

    this.alarmTopic = new sns.Topic(this, 'AlarmTopic', {
      topicName: `${PROJECT_PREFIX}-alarms`,
      displayName: 'CrimeReport Operations Alarms',
    });

    this.alarmTopic.addSubscription(
      new subscriptions.EmailSubscription(ALARM_EMAIL),
    );

    const snsAction = new cw_actions.SnsAction(this.alarmTopic);

    // ── Database Metrics ─────────────────────────────────────

    const dbCpuMetric = dbCluster.metricCPUUtilization({ period: cdk.Duration.minutes(5) });
    const dbConnectionsMetric = dbCluster.metricDatabaseConnections({ period: cdk.Duration.minutes(5) });
    const dbFreeMemMetric = dbCluster.metric('FreeableMemory', {
      statistic: 'Average',
      period: cdk.Duration.minutes(5),
    });

    const dbCpuAlarm = new cloudwatch.Alarm(this, 'DbCpuAlarm', {
      alarmName: `${PROJECT_PREFIX}-db-cpu-high`,
      alarmDescription: 'Aurora CPU utilization exceeded 80%',
      metric: dbCpuMetric,
      threshold: 80,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    dbCpuAlarm.addAlarmAction(snsAction);
    dbCpuAlarm.addOkAction(snsAction);

    const dbConnectionsAlarm = new cloudwatch.Alarm(this, 'DbConnectionsAlarm', {
      alarmName: `${PROJECT_PREFIX}-db-connections-high`,
      alarmDescription: 'Aurora connection count exceeded 50',
      metric: dbConnectionsMetric,
      threshold: 50,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    dbConnectionsAlarm.addAlarmAction(snsAction);
    dbConnectionsAlarm.addOkAction(snsAction);

    const dbMemoryAlarm = new cloudwatch.Alarm(this, 'DbMemoryAlarm', {
      alarmName: `${PROJECT_PREFIX}-db-memory-low`,
      alarmDescription: 'Aurora freeable memory below 256 MB',
      metric: dbFreeMemMetric,
      threshold: 256 * 1024 * 1024,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.LESS_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    dbMemoryAlarm.addAlarmAction(snsAction);
    dbMemoryAlarm.addOkAction(snsAction);

    // ── Redis Metrics ────────────────────────────────────────

    const redisDimensions = {
      ReplicationGroupId: redisReplicationGroupId,
    };

    const redisCpuMetric = new cloudwatch.Metric({
      namespace: 'AWS/ElastiCache',
      metricName: 'EngineCPUUtilization',
      dimensionsMap: redisDimensions,
      statistic: 'Average',
      period: cdk.Duration.minutes(5),
    });

    const redisMemoryMetric = new cloudwatch.Metric({
      namespace: 'AWS/ElastiCache',
      metricName: 'DatabaseMemoryUsagePercentage',
      dimensionsMap: redisDimensions,
      statistic: 'Average',
      period: cdk.Duration.minutes(5),
    });

    const redisEvictionsMetric = new cloudwatch.Metric({
      namespace: 'AWS/ElastiCache',
      metricName: 'Evictions',
      dimensionsMap: redisDimensions,
      statistic: 'Sum',
      period: cdk.Duration.minutes(5),
    });

    const redisCpuAlarm = new cloudwatch.Alarm(this, 'RedisCpuAlarm', {
      alarmName: `${PROJECT_PREFIX}-redis-cpu-high`,
      alarmDescription: 'Redis engine CPU exceeded 80%',
      metric: redisCpuMetric,
      threshold: 80,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    redisCpuAlarm.addAlarmAction(snsAction);
    redisCpuAlarm.addOkAction(snsAction);

    const redisMemoryAlarm = new cloudwatch.Alarm(this, 'RedisMemoryAlarm', {
      alarmName: `${PROJECT_PREFIX}-redis-memory-high`,
      alarmDescription: 'Redis memory usage exceeded 80%',
      metric: redisMemoryMetric,
      threshold: 80,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    redisMemoryAlarm.addAlarmAction(snsAction);
    redisMemoryAlarm.addOkAction(snsAction);

    const redisEvictionsAlarm = new cloudwatch.Alarm(this, 'RedisEvictionsAlarm', {
      alarmName: `${PROJECT_PREFIX}-redis-evictions`,
      alarmDescription: 'Redis is evicting keys -- memory pressure',
      metric: redisEvictionsMetric,
      threshold: 100,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    redisEvictionsAlarm.addAlarmAction(snsAction);
    redisEvictionsAlarm.addOkAction(snsAction);

    // ── ECS Metrics ──────────────────────────────────────────

    const ecsCpuMetric = ecsService.metricCpuUtilization({ period: cdk.Duration.minutes(5) });
    const ecsMemoryMetric = ecsService.metricMemoryUtilization({ period: cdk.Duration.minutes(5) });
    const ecsRunningTasksMetric = ecsService.metric('RunningTaskCount', {
      statistic: 'Average',
      period: cdk.Duration.minutes(1),
    });

    const ecsCpuAlarm = new cloudwatch.Alarm(this, 'EcsCpuAlarm', {
      alarmName: `${PROJECT_PREFIX}-ecs-cpu-high`,
      alarmDescription: 'ECS service CPU exceeded 85%',
      metric: ecsCpuMetric,
      threshold: 85,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    ecsCpuAlarm.addAlarmAction(snsAction);
    ecsCpuAlarm.addOkAction(snsAction);

    const ecsMemoryAlarm = new cloudwatch.Alarm(this, 'EcsMemoryAlarm', {
      alarmName: `${PROJECT_PREFIX}-ecs-memory-high`,
      alarmDescription: 'ECS service memory exceeded 85%',
      metric: ecsMemoryMetric,
      threshold: 85,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    ecsMemoryAlarm.addAlarmAction(snsAction);
    ecsMemoryAlarm.addOkAction(snsAction);

    // ── ALB Metrics ──────────────────────────────────────────

    const albArn = alb.loadBalancerArn;
    const albFullName = cdk.Fn.select(1, cdk.Fn.split('loadbalancer/', albArn));

    const albDimensions = { LoadBalancer: albFullName };

    const alb5xxMetric = new cloudwatch.Metric({
      namespace: 'AWS/ApplicationELB',
      metricName: 'HTTPCode_ELB_5XX_Count',
      dimensionsMap: albDimensions,
      statistic: 'Sum',
      period: cdk.Duration.minutes(5),
    });

    const albResponseTimeMetric = new cloudwatch.Metric({
      namespace: 'AWS/ApplicationELB',
      metricName: 'TargetResponseTime',
      dimensionsMap: albDimensions,
      statistic: 'Average',
      period: cdk.Duration.minutes(5),
    });

    const albRequestCountMetric = new cloudwatch.Metric({
      namespace: 'AWS/ApplicationELB',
      metricName: 'RequestCount',
      dimensionsMap: albDimensions,
      statistic: 'Sum',
      period: cdk.Duration.minutes(5),
    });

    const alb5xxAlarm = new cloudwatch.Alarm(this, 'Alb5xxAlarm', {
      alarmName: `${PROJECT_PREFIX}-alb-5xx-high`,
      alarmDescription: 'ALB returning elevated 5xx errors',
      metric: alb5xxMetric,
      threshold: 10,
      evaluationPeriods: 2,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    alb5xxAlarm.addAlarmAction(snsAction);
    alb5xxAlarm.addOkAction(snsAction);

    const albLatencyAlarm = new cloudwatch.Alarm(this, 'AlbLatencyAlarm', {
      alarmName: `${PROJECT_PREFIX}-alb-latency-high`,
      alarmDescription: 'ALB average response time exceeded 2 seconds',
      metric: albResponseTimeMetric,
      threshold: 2,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    albLatencyAlarm.addAlarmAction(snsAction);
    albLatencyAlarm.addOkAction(snsAction);

    // ── Operations Dashboard ─────────────────────────────────

    this.dashboard = new cloudwatch.Dashboard(this, 'OpsDashboard', {
      dashboardName: `${PROJECT_PREFIX}-operations`,
    });

    this.dashboard.addWidgets(
      new cloudwatch.TextWidget({
        markdown: '# CrimeReport Operations Dashboard',
        width: 24,
        height: 1,
      }),
    );

    // Database row
    this.dashboard.addWidgets(
      new cloudwatch.TextWidget({ markdown: '## Database (Aurora PostgreSQL)', width: 24, height: 1 }),
    );
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({ title: 'DB CPU %', left: [dbCpuMetric], leftAnnotations: [dbCpuAlarm.toAnnotation()], width: 8 }),
      new cloudwatch.GraphWidget({ title: 'DB Connections', left: [dbConnectionsMetric], leftAnnotations: [dbConnectionsAlarm.toAnnotation()], width: 8 }),
      new cloudwatch.GraphWidget({ title: 'DB Freeable Memory', left: [dbFreeMemMetric], leftAnnotations: [dbMemoryAlarm.toAnnotation()], width: 8 }),
    );

    // Redis row
    this.dashboard.addWidgets(
      new cloudwatch.TextWidget({ markdown: '## Redis (ElastiCache)', width: 24, height: 1 }),
    );
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({ title: 'Redis CPU %', left: [redisCpuMetric], leftAnnotations: [redisCpuAlarm.toAnnotation()], width: 8 }),
      new cloudwatch.GraphWidget({ title: 'Redis Memory %', left: [redisMemoryMetric], leftAnnotations: [redisMemoryAlarm.toAnnotation()], width: 8 }),
      new cloudwatch.GraphWidget({ title: 'Redis Evictions', left: [redisEvictionsMetric], leftAnnotations: [redisEvictionsAlarm.toAnnotation()], width: 8 }),
    );

    // ECS row
    this.dashboard.addWidgets(
      new cloudwatch.TextWidget({ markdown: '## ECS (Fargate API)', width: 24, height: 1 }),
    );
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({ title: 'ECS CPU %', left: [ecsCpuMetric], leftAnnotations: [ecsCpuAlarm.toAnnotation()], width: 8 }),
      new cloudwatch.GraphWidget({ title: 'ECS Memory %', left: [ecsMemoryMetric], leftAnnotations: [ecsMemoryAlarm.toAnnotation()], width: 8 }),
      new cloudwatch.GraphWidget({ title: 'Running Tasks', left: [ecsRunningTasksMetric], width: 8 }),
    );

    // ALB row
    this.dashboard.addWidgets(
      new cloudwatch.TextWidget({ markdown: '## ALB (Application Load Balancer)', width: 24, height: 1 }),
    );
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({ title: 'Request Count', left: [albRequestCountMetric], width: 8 }),
      new cloudwatch.GraphWidget({ title: '5xx Errors', left: [alb5xxMetric], leftAnnotations: [alb5xxAlarm.toAnnotation()], width: 8 }),
      new cloudwatch.GraphWidget({ title: 'Response Time (s)', left: [albResponseTimeMetric], leftAnnotations: [albLatencyAlarm.toAnnotation()], width: 8 }),
    );

    // ── Custom Application Metrics (EMF) ───────────────────

    const emfNamespace = 'CrimeReport';
    const emfDimensions = { Service: 'api' };

    const reportsCreatedMetric = new cloudwatch.Metric({
      namespace: emfNamespace,
      metricName: 'ReportsCreated',
      dimensionsMap: emfDimensions,
      statistic: 'Sum',
      period: cdk.Duration.minutes(5),
    });

    const mediaUploadsCompletedMetric = new cloudwatch.Metric({
      namespace: emfNamespace,
      metricName: 'MediaUploadsCompleted',
      dimensionsMap: emfDimensions,
      statistic: 'Sum',
      period: cdk.Duration.minutes(5),
    });

    const mediaFailureRateMetric = new cloudwatch.Metric({
      namespace: emfNamespace,
      metricName: 'MediaFailureRate',
      dimensionsMap: emfDimensions,
      statistic: 'Sum',
      period: cdk.Duration.minutes(5),
    });

    const mediaProcessingLatencyMetric = new cloudwatch.Metric({
      namespace: emfNamespace,
      metricName: 'MediaProcessingLatency',
      dimensionsMap: emfDimensions,
      statistic: 'Average',
      period: cdk.Duration.minutes(5),
    });

    const wsConnectionsMetric = new cloudwatch.Metric({
      namespace: emfNamespace,
      metricName: 'WebSocketConnections',
      dimensionsMap: emfDimensions,
      statistic: 'Average',
      period: cdk.Duration.minutes(1),
    });

    const rateLimitHitsMetric = new cloudwatch.Metric({
      namespace: emfNamespace,
      metricName: 'RateLimitHits',
      dimensionsMap: emfDimensions,
      statistic: 'Sum',
      period: cdk.Duration.minutes(5),
    });

    const mediaFailureAlarm = new cloudwatch.Alarm(this, 'MediaFailureRateAlarm', {
      alarmName: `${PROJECT_PREFIX}-media-failure-rate`,
      alarmDescription: 'Media processing failures exceeded threshold — possible pipeline issue',
      metric: mediaFailureRateMetric,
      threshold: 5,
      evaluationPeriods: 3,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    mediaFailureAlarm.addAlarmAction(snsAction);
    mediaFailureAlarm.addOkAction(snsAction);

    // Distinct alarm for AWS-side pipeline failures (Rekognition unsupported
    // codec, transient outages, etc.) so ops can tell pipeline outages apart
    // from user content moderation rejections.
    const mediaPipelineProcessingErrorsMetric = new cloudwatch.Metric({
      namespace: emfNamespace,
      metricName: 'MediaPipelineProcessingErrors',
      dimensionsMap: { Service: 'media-pipeline' },
      statistic: 'Sum',
      period: cdk.Duration.minutes(5),
    });

    const mediaPipelineProcessingErrorsAlarm = new cloudwatch.Alarm(this, 'MediaPipelineProcessingErrorsAlarm', {
      alarmName: `${PROJECT_PREFIX}-media-pipeline-processing-errors`,
      alarmDescription: 'Media pipeline produced AWS-side processing errors (e.g. unsupported codec, Rekognition outage)',
      metric: mediaPipelineProcessingErrorsMetric,
      threshold: 1,
      evaluationPeriods: 1,
      comparisonOperator: cloudwatch.ComparisonOperator.GREATER_THAN_OR_EQUAL_TO_THRESHOLD,
      treatMissingData: cloudwatch.TreatMissingData.NOT_BREACHING,
    });
    mediaPipelineProcessingErrorsAlarm.addAlarmAction(snsAction);
    mediaPipelineProcessingErrorsAlarm.addOkAction(snsAction);

    // Application metrics dashboard row
    this.dashboard.addWidgets(
      new cloudwatch.TextWidget({ markdown: '## Application Metrics (EMF)', width: 24, height: 1 }),
    );
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({ title: 'Reports Created', left: [reportsCreatedMetric], width: 8 }),
      new cloudwatch.GraphWidget({ title: 'Media Uploads Completed', left: [mediaUploadsCompletedMetric], width: 8 }),
      new cloudwatch.GraphWidget({ title: 'Media Failures', left: [mediaFailureRateMetric], leftAnnotations: [mediaFailureAlarm.toAnnotation()], width: 8 }),
    );
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({ title: 'Media Processing Latency (ms)', left: [mediaProcessingLatencyMetric], width: 8 }),
      new cloudwatch.GraphWidget({ title: 'WebSocket Connections', left: [wsConnectionsMetric], width: 8 }),
      new cloudwatch.GraphWidget({ title: 'Rate Limit Hits', left: [rateLimitHitsMetric], width: 8 }),
    );
    this.dashboard.addWidgets(
      new cloudwatch.GraphWidget({
        title: 'Media Pipeline Processing Errors',
        left: [mediaPipelineProcessingErrorsMetric],
        leftAnnotations: [mediaPipelineProcessingErrorsAlarm.toAnnotation()],
        width: 24,
      }),
    );

    // Alarms summary
    this.dashboard.addWidgets(
      new cloudwatch.TextWidget({ markdown: '## Alarm Status', width: 24, height: 1 }),
    );
    this.dashboard.addWidgets(
      new cloudwatch.AlarmStatusWidget({
        title: 'All Alarms',
        alarms: [
          dbCpuAlarm, dbConnectionsAlarm, dbMemoryAlarm,
          redisCpuAlarm, redisMemoryAlarm, redisEvictionsAlarm,
          ecsCpuAlarm, ecsMemoryAlarm,
          alb5xxAlarm, albLatencyAlarm,
          mediaFailureAlarm, mediaPipelineProcessingErrorsAlarm,
        ],
        width: 24,
      }),
    );
  }
}
