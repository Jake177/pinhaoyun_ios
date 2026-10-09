#!/usr/bin/env python3
"""Isolated API hosting. Run with 'service' for the image-dependent stack."""
import json, sys
prefix = 'pinhaoyun-ios-dev-api'
ref = lambda name: {'Ref': name}
sub = lambda value: {'Fn::Sub': value}
att = lambda name, key: {'Fn::GetAtt': [name, key]}
parameters = {}
resources = {}
def parameter(name, **extra):
    parameters[name] = {'Type': 'String', **extra}
    return ref(name)
def role(name, principal, statements):
    resources[name] = {'Type': 'AWS::IAM::Role', 'Properties': {
        'RoleName': prefix + '-' + name.lower(),
        'AssumeRolePolicyDocument': {'Version': '2012-10-17', 'Statement': [{'Effect': 'Allow', 'Principal': {'Service': principal}, 'Action': 'sts:AssumeRole'}]},
        'Policies': [{'PolicyName': 'isolated-api', 'PolicyDocument': {'Version': '2012-10-17', 'Statement': statements}}]}}
def allow(actions, resource):
    return {'Effect': 'Allow', 'Action': actions, 'Resource': resource}

if 'service' not in sys.argv:
    artifact = parameter('ArtifactBucket')
    for name in ('MediaTable', 'DeletionsTable', 'OriginalBucket', 'ThumbnailBucket', 'ProfileBucket', 'UserPoolId', 'WebSecretArn', 'MobileSecretArn'):
        parameter(name)
    repo_arn = att('Repository', 'Arn')
    resources['Repository'] = {'Type': 'AWS::ECR::Repository', 'DeletionPolicy': 'Retain', 'Properties': {
        'RepositoryName': prefix, 'ImageTagMutability': 'IMMUTABLE', 'ImageScanningConfiguration': {'ScanOnPush': True},
        'LifecyclePolicy': {'LifecyclePolicyText': json.dumps({'rules': [{'rulePriority': 1, 'description': 'Retain recent rollback images', 'selection': {'tagStatus': 'any', 'countType': 'imageCountMoreThan', 'countNumber': 5}, 'action': {'type': 'expire'}}]})}}}
    pull = [allow(['ecr:GetAuthorizationToken'], '*'), allow(['ecr:BatchCheckLayerAvailability', 'ecr:GetDownloadUrlForLayer', 'ecr:BatchGetImage', 'ecr:DescribeImages'], repo_arn)]
    role('AccessRole', 'build.apprunner.amazonaws.com', pull)
    role('BuildRole', 'codebuild.amazonaws.com', pull + [
        allow(['ecr:InitiateLayerUpload', 'ecr:UploadLayerPart', 'ecr:CompleteLayerUpload', 'ecr:PutImage'], repo_arn),
        allow(['s3:GetObject'], sub('arn:aws:s3:::${ArtifactBucket}/api/*')),
        allow(['logs:CreateLogStream', 'logs:PutLogEvents'], sub('arn:aws:logs:${AWS::Region}:${AWS::AccountId}:log-group:/aws/codebuild/' + prefix + ':*'))])
    role('InstanceRole', 'tasks.apprunner.amazonaws.com', [
        allow(['dynamodb:GetItem', 'dynamodb:PutItem', 'dynamodb:UpdateItem', 'dynamodb:DeleteItem', 'dynamodb:Query', 'dynamodb:Scan', 'dynamodb:TransactWriteItems', 'dynamodb:ConditionCheckItem'], [sub('arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${MediaTable}'), sub('arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${MediaTable}/index/*'), sub('arn:aws:dynamodb:${AWS::Region}:${AWS::AccountId}:table/${DeletionsTable}')]),
        allow(['s3:GetObject', 's3:PutObject', 's3:DeleteObject', 's3:ListBucket', 's3:ListBucketMultipartUploads', 's3:ListMultipartUploadParts', 's3:AbortMultipartUpload'], [sub('arn:aws:s3:::${' + name + '}' + suffix) for name in ('OriginalBucket', 'ThumbnailBucket', 'ProfileBucket') for suffix in ('', '/*')]),
        allow(['sqs:SendMessage'], sub('arn:aws:sqs:${AWS::Region}:${AWS::AccountId}:pinhaoyun-ios-dev-*')),
        allow(['secretsmanager:GetSecretValue'], [ref('WebSecretArn'), ref('MobileSecretArn')]),
        allow(['cognito-idp:AdminDisableUser', 'cognito-idp:AdminUserGlobalSignOut', 'cognito-idp:AdminGetUser'], sub('arn:aws:cognito-idp:${AWS::Region}:${AWS::AccountId}:userpool/${UserPoolId}'))])
    resources['BuildLog'] = {'Type': 'AWS::Logs::LogGroup', 'Properties': {'LogGroupName': '/aws/codebuild/' + prefix, 'RetentionInDays': 14}}
    resources['Build'] = {'Type': 'AWS::CodeBuild::Project', 'Properties': {
        'Name': prefix, 'ServiceRole': att('BuildRole', 'Arn'), 'TimeoutInMinutes': 20,
        'Artifacts': {'Type': 'NO_ARTIFACTS'},
        'Source': {'Type': 'S3', 'Location': sub('${ArtifactBucket}/api/source.zip'), 'BuildSpec': 'buildspec.mobile.yml'},
        'Environment': {'Type': 'LINUX_CONTAINER', 'ComputeType': 'BUILD_GENERAL1_MEDIUM', 'Image': 'aws/codebuild/standard:7.0', 'PrivilegedMode': True,
            'EnvironmentVariables': [{'Name': 'REPOSITORY_URI', 'Value': att('Repository', 'RepositoryUri')}]},
        'LogsConfig': {'CloudWatchLogs': {'Status': 'ENABLED', 'GroupName': ref('BuildLog')}}}}
    resources['Scaling'] = {'Type': 'AWS::AppRunner::AutoScalingConfiguration', 'Properties': {'AutoScalingConfigurationName': prefix, 'MinSize': 1, 'MaxSize': 1, 'MaxConcurrency': 50}}
    outputs = {name: att(name, 'Arn') for name in ('AccessRole', 'InstanceRole')}
    outputs.update(RepositoryUri=att('Repository', 'RepositoryUri'), ScalingArn=att('Scaling', 'AutoScalingConfigurationArn'), BuildName=ref('Build'))
else:
    for name in ('ImageIdentifier', 'AccessRoleArn', 'InstanceRoleArn', 'ScalingArn', 'UserPoolId', 'WebClientId', 'MobileClientId', 'WebSecretArn', 'MobileSecretArn', 'MediaTable', 'DeletionsTable', 'OriginalBucket', 'ThumbnailBucket', 'ProfileBucket', 'MediaDeleteQueueUrl', 'LocationQueueUrl', 'AccountDeleteQueueUrl'):
        parameter(name)
    parameter('TestEmails', NoEcho=True)
    env = {'APP_ENV': 'development', 'PH_API_ONLY': 'true', 'POLICIES_APPROVED': 'false', 'HOSTNAME': '0.0.0.0', 'COGNITO_REGION': sub('${AWS::Region}'),
        'COGNITO_USER_POOL_ID': ref('UserPoolId'), 'COGNITO_CLIENT_ID': ref('WebClientId'), 'COGNITO_SECRET_ID': ref('WebSecretArn'),
        'COGNITO_MOBILE_CLIENT_ID': ref('MobileClientId'), 'COGNITO_MOBILE_SECRET_ID': ref('MobileSecretArn'),
        'VIDEOS_TABLE': ref('MediaTable'), 'USERS_TABLE': ref('MediaTable'), 'ACCOUNT_DELETIONS_TABLE': ref('DeletionsTable'),
        'S3_ORIGINAL_BUCKET': ref('OriginalBucket'), 'S3_THUMBNAIL_BUCKET': ref('ThumbnailBucket'), 'S3_PROFILE_BUCKET': ref('ProfileBucket'),
        'VIDEOS_DELETE_QUEUE_URL': ref('MediaDeleteQueueUrl'), 'LOCATION_ENRICH_QUEUE_URL': ref('LocationQueueUrl'), 'ACCOUNT_DELETE_QUEUE_URL': ref('AccountDeleteQueueUrl'),
        'TIMELINE_INDEX_NAME': 'TimelineIndex', 'MOBILE_TEST_EMAILS': ref('TestEmails')}
    resources['Service'] = {'Type': 'AWS::AppRunner::Service', 'Properties': {
        'ServiceName': prefix, 'AutoScalingConfigurationArn': ref('ScalingArn'),
        'InstanceConfiguration': {'Cpu': '512', 'Memory': '1024', 'InstanceRoleArn': ref('InstanceRoleArn')},
        'HealthCheckConfiguration': {'Protocol': 'HTTP', 'Path': '/api/mobile/health', 'Interval': 10, 'Timeout': 5, 'HealthyThreshold': 1, 'UnhealthyThreshold': 5},
        'SourceConfiguration': {'AutoDeploymentsEnabled': False, 'AuthenticationConfiguration': {'AccessRoleArn': ref('AccessRoleArn')},
            'ImageRepository': {'ImageRepositoryType': 'ECR', 'ImageIdentifier': ref('ImageIdentifier'), 'ImageConfiguration': {'Port': '3000', 'StartCommand': 'node /app/server.js', 'RuntimeEnvironmentVariables': [{'Name': key, 'Value': value} for key, value in env.items()]}}}}}
    outputs = {'ServiceUrl': att('Service', 'ServiceUrl'), 'ServiceArn': att('Service', 'ServiceArn')}

print(json.dumps({'AWSTemplateFormatVersion': '2010-09-09', 'Description': 'Isolated PinHaoYun mobile API hosting', 'Parameters': parameters, 'Resources': resources, 'Outputs': {key: {'Value': value} for key, value in outputs.items()}}, indent=2))
