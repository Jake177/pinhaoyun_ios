#!/usr/bin/env python3
"""Emit the isolated development CloudFormation template. Never imports production resources."""
import json
R={}
def ref(name): return {'Ref':name}
def att(name,key): return {'Fn::GetAtt':[name,key]}
def sub(value): return {'Fn::Sub':value}
def resource(name,kind,props,**extras):
 R[name]={'Type':kind,'Properties':props,**extras};return ref(name)
acct='883086653724'; prefix='pinhaoyun-ios-dev'
bucket_names={n:f'{prefix}-{n.lower()}-{acct}' for n in ('Original','Thumbnail','Profile')}
for name in ('Media','Deletions'):
 attrs=[{'AttributeName':'email','AttributeType':'S'},{'AttributeName':'sk','AttributeType':'S'},{'AttributeName':'timelinePk','AttributeType':'S'},{'AttributeName':'timelineSk','AttributeType':'S'}] if name=='Media' else [{'AttributeName':'requestId','AttributeType':'S'}]
 props={'TableName':f'{prefix}-{name.lower()}','BillingMode':'PAY_PER_REQUEST','AttributeDefinitions':attrs,'KeySchema':[{'AttributeName':'email','KeyType':'HASH'},{'AttributeName':'sk','KeyType':'RANGE'}] if name=='Media' else [{'AttributeName':'requestId','KeyType':'HASH'}], 'SSESpecification':{'SSEEnabled':True},'TimeToLiveSpecification':{'AttributeName':'expiresAt','Enabled':True}}
 if name=='Media': props['GlobalSecondaryIndexes']=[{'IndexName':'TimelineIndex','KeySchema':[{'AttributeName':'timelinePk','KeyType':'HASH'},{'AttributeName':'timelineSk','KeyType':'RANGE'}],'Projection':{'ProjectionType':'ALL'}}]
 resource(name,'AWS::DynamoDB::Table',props,DeletionPolicy='Retain',UpdateReplacePolicy='Retain')
for name in ('MediaDelete','Location','AccountDelete'):
 resource(name+'DLQ','AWS::SQS::Queue',{'QueueName':f'{prefix}-{name.lower()}-dlq','MessageRetentionPeriod':1209600,'SqsManagedSseEnabled':True})
 resource(name+'Queue','AWS::SQS::Queue',{'QueueName':f'{prefix}-{name.lower()}','VisibilityTimeout':1800,'MessageRetentionPeriod':1209600,'SqsManagedSseEnabled':True,'RedrivePolicy':{'deadLetterTargetArn':att(name+'DLQ','Arn'),'maxReceiveCount':5}})
base_statements=[
 {'Effect':'Allow','Action':['dynamodb:GetItem','dynamodb:PutItem','dynamodb:UpdateItem','dynamodb:DeleteItem','dynamodb:Query','dynamodb:Scan','dynamodb:TransactWriteItems','dynamodb:ConditionCheckItem','dynamodb:BatchWriteItem'], 'Resource':[att('Media','Arn'),sub('${Media.Arn}/index/*'),att('Deletions','Arn')]},
 {'Effect':'Allow','Action':['s3:GetObject','s3:PutObject','s3:DeleteObject','s3:DeleteObjectVersion','s3:ListBucket','s3:ListBucketVersions','s3:ListBucketMultipartUploads','s3:AbortMultipartUpload','s3:ListMultipartUploadParts'], 'Resource':[f'arn:aws:s3:::{b}{suffix}' for b in bucket_names.values() for suffix in ('','/*')]},
 {'Effect':'Allow','Action':['sqs:SendMessage','sqs:SendMessageBatch','sqs:ReceiveMessage','sqs:DeleteMessage','sqs:GetQueueAttributes','sqs:ChangeMessageVisibility'], 'Resource':[att(n+'Queue','Arn') for n in ('MediaDelete','Location','AccountDelete')]},
 {'Effect':'Allow','Action':['logs:CreateLogGroup','logs:CreateLogStream','logs:PutLogEvents'],'Resource':f'arn:aws:logs:ap-southeast-2:{acct}:log-group:/aws/lambda/{prefix}-*:*'}]
def role(name,principal,statements):
 return resource(name,'AWS::IAM::Role',{'RoleName':f'{prefix}-{name.lower()}','AssumeRolePolicyDocument':{'Version':'2012-10-17','Statement':[{'Effect':'Allow','Principal':{'Service':principal},'Action':'sts:AssumeRole'}]},'Policies':[{'PolicyName':'isolated-development','PolicyDocument':{'Version':'2012-10-17','Statement':statements}}]})
role('ProcessingRole','lambda.amazonaws.com',base_statements)
env={'APP_ENV':'development','VIDEOS_TABLE':ref('Media'),'USERS_TABLE':ref('Media'),'TIMELINE_INDEX_NAME':'TimelineIndex','S3_ORIGINAL_BUCKET':bucket_names['Original'],'S3_THUMBNAIL_BUCKET':bucket_names['Thumbnail'],'S3_PROFILE_BUCKET':bucket_names['Profile'],'LOCATION_ENRICH_QUEUE_URL':ref('LocationQueue'),'VIDEOS_DELETE_QUEUE_URL':ref('MediaDeleteQueue'),'ACCOUNT_DELETE_QUEUE_URL':ref('AccountDeleteQueue'),'ACCOUNT_DELETIONS_TABLE':ref('Deletions'),'DELETION_QUIESCENCE_SECONDS':'300','MAPBOX_TOKEN':ref('MapboxToken'),'PRESIGN_TTL_SECONDS':'900'}
functions={'PostConfirmation':('postConfirmation',128,30,[]),'PhotoIngest':('photoIngest',512,120,[f'arn:aws:lambda:ap-southeast-2:{acct}:layer:ImageMagick:4']),'TranscodeVideo':('transcodeVideo',2048,200,[f'arn:aws:lambda:ap-southeast-2:{acct}:layer:ffmpeg:1']),'EnrichLocation':('enrichLocation',128,30,[]),'DeleteVideo':('deleteVideo',128,60,[]),'DeleteAccount':('deleteAccount',512,900,[]),'CleanupUploads':('cleanupUploads',128,120,[])}
for name,(source,memory,timeout,layers) in functions.items():
 resource(name+'Log','AWS::Logs::LogGroup',{'LogGroupName':f'/aws/lambda/{prefix}-{source}','RetentionInDays':30})
 fn_env=dict(env)
 if name=='PhotoIngest': fn_env.update({'MAGICK_HOME':'/opt','LD_LIBRARY_PATH':'/opt/lib','MAGICK_CONFIGURE_PATH':'/opt/etc/ImageMagick-7','MAGICK_CODER_MODULE_PATH':'/opt/lib/ImageMagick-7.1.1/modules-Q16HDRI/coders'})
 if name=='DeleteAccount': fn_env['COGNITO_USER_POOL_ID']=ref('UserPool')
 props={'FunctionName':f'{prefix}-{source}','Runtime':'nodejs24.x','Architectures':['x86_64'],'Handler':'index.handler','MemorySize':memory,'Timeout':timeout,'Role':att('AccountRole' if name=='DeleteAccount' else 'ProcessingRole','Arn'),'Code':{'S3Bucket':ref('ArtifactBucket'),'S3Key':sub('${ArtifactPrefix}/'+source+'.zip')},'Environment':{'Variables':fn_env}}
 if layers: props['Layers']=layers
 if name in ('PhotoIngest','TranscodeVideo'): props['EphemeralStorage']={'Size':3072}
 resource(name,'AWS::Lambda::Function',props,DependsOn=name+'Log')
resource('UserPool','AWS::Cognito::UserPool',{'UserPoolName':prefix,'UsernameAttributes':['email'],'AutoVerifiedAttributes':['email'],'UsernameConfiguration':{'CaseSensitive':False},'Policies':{'PasswordPolicy':{'MinimumLength':8,'RequireUppercase':True,'RequireLowercase':True,'RequireNumbers':True,'RequireSymbols':True}},'Schema':[{'Name':n,'AttributeDataType':'String','Required':True,'Mutable':True} for n in ['email','given_name','family_name','preferred_username','gender']],'LambdaConfig':{'PostConfirmation':att('PostConfirmation','Arn')},'AccountRecoverySetting':{'RecoveryMechanisms':[{'Name':'verified_email','Priority':1}]}})
resource('PostConfirmationPermission','AWS::Lambda::Permission',{'FunctionName':ref('PostConfirmation'),'Action':'lambda:InvokeFunction','Principal':'cognito-idp.amazonaws.com','SourceArn':att('UserPool','Arn')})
for name in ('Web','Mobile'):
 resource(name+'Client','AWS::Cognito::UserPoolClient',{'UserPoolId':ref('UserPool'),'ClientName':prefix+'-'+name.lower(),'GenerateSecret':True,'ExplicitAuthFlows':['ALLOW_USER_PASSWORD_AUTH','ALLOW_REFRESH_TOKEN_AUTH','ALLOW_USER_SRP_AUTH'],'RefreshTokenValidity':30,'AccessTokenValidity':1,'IdTokenValidity':1,'TokenValidityUnits':{'RefreshToken':'days','AccessToken':'hours','IdToken':'hours'},'EnableTokenRevocation':True,'PreventUserExistenceErrors':'ENABLED'})
 resource(name+'Secret','AWS::SecretsManager::Secret',{'Name':f'pinhaoyun/ios-dev/{name.lower()}-cognito','Description':'Cognito confidential client secret; provisioned without logging its contents','GenerateSecretString':{'PasswordLength':32}},DeletionPolicy='Retain',UpdateReplacePolicy='Retain')
cognito_policy={'Effect':'Allow','Action':['cognito-idp:AdminDisableUser','cognito-idp:AdminUserGlobalSignOut','cognito-idp:AdminDeleteUser'],'Resource':att('UserPool','Arn')}
role('AccountRole','lambda.amazonaws.com',base_statements+[cognito_policy])
role('SSRRole','amplify.amazonaws.com',base_statements+[cognito_policy,{'Effect':'Allow','Action':['secretsmanager:GetSecretValue'],'Resource':[ref('WebSecret'),ref('MobileSecret')]}])
for name in ('PhotoIngest','TranscodeVideo'):
 resource(name+'Permission','AWS::Lambda::Permission',{'FunctionName':ref(name),'Action':'lambda:InvokeFunction','Principal':'s3.amazonaws.com','SourceArn':f'arn:aws:s3:::{bucket_names["Original"]}','SourceAccount':acct})
for name,bucket in bucket_names.items():
 props={'BucketName':bucket,'BucketEncryption':{'ServerSideEncryptionConfiguration':[{'ServerSideEncryptionByDefault':{'SSEAlgorithm':'AES256'}}]},'PublicAccessBlockConfiguration':{'BlockPublicAcls':True,'BlockPublicPolicy':True,'IgnorePublicAcls':True,'RestrictPublicBuckets':True},'LifecycleConfiguration':{'Rules':[{'Id':'abort-stale-multipart','Status':'Enabled','AbortIncompleteMultipartUpload':{'DaysAfterInitiation':2}}]}}
 depends=[]
 if name=='Original':
  props['CorsConfiguration']={'CorsRules':[{'AllowedOrigins':['http://localhost:3000','http://127.0.0.1:3000','https://feat-mobile-api.dfajjdq9ocxzi.amplifyapp.com'],'AllowedMethods':['GET','PUT','HEAD'],'AllowedHeaders':['*'],'ExposedHeaders':['ETag'],'MaxAge':3000}]}
  props['NotificationConfiguration']={'LambdaConfigurations':[{'Event':'s3:ObjectCreated:*','Function':att(fn,'Arn'),'Filter':{'S3Key':{'Rules':[{'Name':'prefix','Value':pref}]}}} for fn,pref in [('PhotoIngest','photo/'),('TranscodeVideo','video/')]]}
  depends=['PhotoIngestPermission','TranscodeVideoPermission']
 resource(name+'Bucket','AWS::S3::Bucket',props,DeletionPolicy='Retain',UpdateReplacePolicy='Retain',**({'DependsOn':depends} if depends else {}))
 resource(name+'BucketPolicy','AWS::S3::BucketPolicy',{'Bucket':ref(name+'Bucket'),'PolicyDocument':{'Version':'2012-10-17','Statement':[{'Effect':'Deny','Principal':'*','Action':'s3:*','Resource':[f'arn:aws:s3:::{bucket}',f'arn:aws:s3:::{bucket}/*'],'Condition':{'Bool':{'aws:SecureTransport':'false'}}}]}})
for queue,fn in [('MediaDelete','DeleteVideo'),('Location','EnrichLocation'),('AccountDelete','DeleteAccount')]:
 resource(fn+'Source','AWS::Lambda::EventSourceMapping',{'EventSourceArn':att(queue+'Queue','Arn'),'FunctionName':ref(fn),'BatchSize':1,'Enabled':True,**({'FunctionResponseTypes':['ReportBatchItemFailures']} if fn=='DeleteAccount' else {})})
for fn in ('DeleteAccount','CleanupUploads'):
 resource(fn+'Schedule','AWS::Events::Rule',{'ScheduleExpression':'rate(5 minutes)','State':'ENABLED','Targets':[{'Arn':att(fn,'Arn'),'Id':fn}]})
 resource(fn+'SchedulePermission','AWS::Lambda::Permission',{'FunctionName':ref(fn),'Action':'lambda:InvokeFunction','Principal':'events.amazonaws.com','SourceArn':att(fn+'Schedule','Arn')})
resource('DeletionFailureAlarm','AWS::CloudWatch::Alarm',{'AlarmName':prefix+'-deletion-dlq','Namespace':'AWS/SQS','MetricName':'ApproximateNumberOfMessagesVisible','Dimensions':[{'Name':'QueueName','Value':att('AccountDeleteDLQ','QueueName')}],'Statistic':'Maximum','Period':300,'EvaluationPeriods':1,'Threshold':1,'ComparisonOperator':'GreaterThanOrEqualToThreshold','TreatMissingData':'notBreaching'})
resource('DeletionDeadlineMetric','AWS::Logs::MetricFilter',{'LogGroupName':ref('DeleteAccountLog'),'FilterPattern':'"Account deletion overdue"','MetricTransformations':[{'MetricNamespace':'PinHaoYun/iOS/Dev','MetricName':'DeletionOverdue','MetricValue':'1','DefaultValue':0}]})
resource('DeletionDeadlineAlarm','AWS::CloudWatch::Alarm',{'AlarmName':prefix+'-deletion-overdue','Namespace':'PinHaoYun/iOS/Dev','MetricName':'DeletionOverdue','Statistic':'Sum','Period':300,'EvaluationPeriods':1,'Threshold':1,'ComparisonOperator':'GreaterThanOrEqualToThreshold','TreatMissingData':'notBreaching'})
outputs={'UserPoolId':ref('UserPool'),'WebClientId':ref('WebClient'),'MobileClientId':ref('MobileClient'),'WebSecretArn':ref('WebSecret'),'MobileSecretArn':ref('MobileSecret'),'MediaTable':ref('Media'),'DeletionsTable':ref('Deletions'),'OriginalBucket':ref('OriginalBucket'),'ThumbnailBucket':ref('ThumbnailBucket'),'ProfileBucket':ref('ProfileBucket'),'MediaDeleteQueueUrl':ref('MediaDeleteQueue'),'LocationQueueUrl':ref('LocationQueue'),'AccountDeleteQueueUrl':ref('AccountDeleteQueue'),'SSRRoleArn':att('SSRRole','Arn')}
print(json.dumps({'AWSTemplateFormatVersion':'2010-09-09','Description':'Isolated PinHaoYun iOS development resources; no production mutations','Parameters':{'ArtifactBucket':{'Type':'String'},'ArtifactPrefix':{'Type':'String'},'MapboxToken':{'Type':'String','NoEcho':True,'Default':''}},'Resources':R,'Outputs':{k:{'Value':v} for k,v in outputs.items()}},indent=2))
