pipeline {
  agent any
  stages {
    stage('Install dependencies') {
      steps {
        echo "Current working dir: $WORKSPACE"
        sh '''#!/bin/bash
        set -e
        printenv
        echo "Creating virtualenv and installing dependencies"
        python3 -m venv .venv
        .venv/bin/pip install -r requirements.txt # --no-cache-dir 
        .venv/bin/python --version
        docker --version
        '''
        stash(includes: '**/.venv/**/*', name: 'venv')
      }
    }

    stage('Test') {
      steps {
        unstash 'venv'
        sh '''#!/bin/bash
        set -e
        .venv/bin/flake8 --output result
        .venv/bin/flake8_junit result result.xml
        '''
        junit(allowEmptyResults: true, testResults: 'result.xml', skipPublishingChecks: true)
      }
    }

    stage('Build & push') {
      steps {
        withAWS(credentials: 'duongpd7-aws-credentials') {
          sh '''
          #!/bin/bash
          set -e
          aws ecr get-login-password | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

          if [ "$BRANCH_NAME" = "dev" ];
          then
              docker build -t my-dev-image:latest .
              docker tag my-dev-image:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${DEV_ECR_REPO}:latest
              docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${DEV_ECR_REPO}:latest

          elif [ "$BRANCH_NAME" = "master" ];
          then
              docker build -t my-master-image:latest .

              docker tag my-master-image:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${STAGING_ECR_REPO}:latest
              docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${STAGING_ECR_REPO}:latest

              docker tag my-master-image:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROD_ECR_REPO}:latest
              docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROD_ECR_REPO}:latest
          fi
          '''
        }

      }
    }

    stage('Clean') {
      steps {
        sh '''#!/bin/bash
        set -e
        rm -rf .venv/ result result.xml
        if [ "$BRANCH_NAME" = "dev" ];
        then
            docker rmi -f my-dev-image:latest
            docker rmi -f ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${DEV_ECR_REPO}:latest
        elif [ "$BRANCH_NAME" = "master" ];
        then
            docker rmi -f my-master-image:latest
            docker rmi -f ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${PROD_ECR_REPO}:latest
            docker rmi -f ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${STAGING_ECR_REPO}:latest

        fi
        '''
      }
    }

    stage('Dev Deploy') {
      when {
        branch 'dev'
      }
      steps {
        withAWS(credentials: 'duongpd7-aws-credentials') {
          sh '''#!/bin/bash
          set -e
          echo Starting Dev deployment...
          IS_CREATED=1
          FAILURE=$(aws ecs describe-services --cluster ${DEV_CLUSTER} --services ${DEV_SERVICE} --query "failures[0]" --output text)
          ECS_SERVICE_STATUS=$(aws ecs describe-services --cluster ${DEV_CLUSTER} --services ${DEV_SERVICE} --query \'services[0].status\' --output text)
          if [ "$FAILURE" != "None" ]; then
              echo "ECS service ${DEV_SERVICE} does not exist"
              IS_CREATED=0
          elif [ "$ECS_SERVICE_STATUS" != "ACTIVE" ]; then
              echo "ECS service ${DEV_SERVICE} is inactive"
              IS_CREATED=0
          else
              echo "ECS service ${DEV_SERVICE} has been already created"
          fi
          aws cloudformation deploy --template-file load-balancer.yaml --stack-name ${DEV_LOAD_BALANCER_STACK}
          TARGET_GROUP_ARN=$(aws cloudformation describe-stacks --stack-name ${DEV_LOAD_BALANCER_STACK} --query 'Stacks[0].Outputs[?OutputKey==`TargetGroupArn`].OutputValue' --output text)

          if [ $IS_CREATED = 0 ];
          then
              echo "Creating ${DEV_SERVICE} service..."
              aws ecs create-service \
              --cluster ${DEV_CLUSTER} \
              --service-name ${DEV_SERVICE} \
              --desired-count 1 \
              --task-definition ${DEV_TASK_DEFINITION} \
              --launch-type FARGATE --platform-version LATEST \
              --network-configuration "awsvpcConfiguration={subnets=[subnet-0344d44130e11b79c,subnet-0de56d1e9c2d97060,subnet-02bbfe46ba29ce20a],securityGroups=[sg-04741693a6494256c],assignPublicIp=ENABLED}" \
              --load-balancers "targetGroupArn=$TARGET_GROUP_ARN,containerName=${DEV_CONTAINER},containerPort=${CONTAINER_PORT}";
          else    
              echo "Updating ${DEV_SERVICE} service..."
              aws ecs update-service \
              --service ${DEV_SERVICE} \
              --cluster ${DEV_CLUSTER} \
              --force-new-deployment \
              --load-balancers "targetGroupArn=$TARGET_GROUP_ARN,containerName=${DEV_CONTAINER},containerPort=${CONTAINER_PORT}"
          fi

          echo "DNS of the load balancer:"
          aws cloudformation describe-stacks --stack-name ${DEV_LOAD_BALANCER_STACK} --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' --output text
          '''
        }

      }
    }

    stage('Staging Deploy') {
      when {
        branch 'master'
      }
      steps {
        withAWS(credentials: 'duongpd7-aws-credentials') {
          sh '''#!/bin/bash
          set -e
          echo Starting Staging deployment...
          IS_CREATED=1
          FAILURE=$(aws ecs describe-services --cluster ${STAGING_CLUSTER} --services ${STAGING_SERVICE} --query "failures[0]" --output text)
          ECS_SERVICE_STATUS=$(aws ecs describe-services --cluster ${STAGING_CLUSTER} --services ${STAGING_SERVICE} --query \'services[0].status\' --output text)
          if [ "$FAILURE" != "None" ]; then
              echo "ECS service ${STAGING_SERVICE} does not exist"
              IS_CREATED=0
          elif [ "$ECS_SERVICE_STATUS" != "ACTIVE" ]; then
              echo "ECS service ${STAGING_SERVICE} is inactive"
              IS_CREATED=0
          else
              echo "ECS service ${STAGING_SERVICE} has been already created"
          fi

          aws cloudformation deploy --template-file load-balancer.yaml --stack-name ${STAGING_LOAD_BALANCER_STACK}
          TARGET_GROUP_ARN=$(aws cloudformation describe-stacks --stack-name ${STAGING_LOAD_BALANCER_STACK} --query 'Stacks[0].Outputs[?OutputKey==`TargetGroupArn`].OutputValue' --output text)

          if [ $IS_CREATED = 0 ];
          then
              echo "Creating ${STAGING_SERVICE} service..."
              aws ecs create-service \
              --cluster ${STAGING_CLUSTER} \
              --service-name ${STAGING_SERVICE} \
              --desired-count 1 \
              --task-definition ${STAGING_TASK_DEFINITION} \
              --launch-type FARGATE --platform-version LATEST \
              --network-configuration "awsvpcConfiguration={subnets=[subnet-0344d44130e11b79c,subnet-0de56d1e9c2d97060,subnet-02bbfe46ba29ce20a],securityGroups=[sg-04741693a6494256c],assignPublicIp=ENABLED}" \
              --load-balancers "targetGroupArn=$TARGET_GROUP_ARN,containerName=${STAGING_CONTAINER},containerPort=${CONTAINER_PORT}";
          else    
              echo "Updating ${STAGING_SERVICE} service..."
              aws ecs update-service \
              --service ${STAGING_SERVICE} \
              --cluster ${STAGING_CLUSTER} \
              --load-balancers "targetGroupArn=$TARGET_GROUP_ARN,containerName=${STAGING_CONTAINER},containerPort=${CONTAINER_PORT}" \
              --force-new-deployment
          fi

          echo "DNS of the load balancer:"
          aws cloudformation describe-stacks --stack-name ${STAGING_LOAD_BALANCER_STACK} --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' --output text
          '''
        }
      }
    }

    stage('Prod Deploy') {
      when {
        branch 'master'
      }
      steps {
        input(message: 'Do you want to proceed to deploy to the Production environment')
        withAWS(credentials: 'duongpd7-aws-credentials') {
          sh '''#!/bin/bash
          set -e
          echo Starting Prod deployment...
          IS_CREATED=1
          FAILURE=$(aws ecs describe-services --cluster ${PROD_CLUSTER} --services ${PROD_SERVICE} --query "failures[0]" --output text)
          ECS_SERVICE_STATUS=$(aws ecs describe-services --cluster ${PROD_CLUSTER} --services ${PROD_SERVICE} --query \'services[0].status\' --output text)
          if [ "$FAILURE" != "None" ]; then
              echo "ECS service ${PROD_SERVICE} does not exist"
              IS_CREATED=0
          elif [ "$ECS_SERVICE_STATUS" != "ACTIVE" ]; then
              echo "ECS service ${PROD_SERVICE} is inactive"
              IS_CREATED=0
          else
              echo "ECS service ${PROD_SERVICE} has been already created"
          fi
          aws cloudformation deploy --template-file load-balancer.yaml --stack-name ${PROD_LOAD_BALANCER_STACK}
          TARGET_GROUP_ARN=$(aws cloudformation describe-stacks --stack-name ${PROD_LOAD_BALANCER_STACK} --query 'Stacks[0].Outputs[?OutputKey==`TargetGroupArn`].OutputValue' --output text)

          if [ $IS_CREATED = 0 ];
          then
              echo "Creating ${PROD_SERVICE} service..."
              aws ecs create-service \
              --cluster ${PROD_CLUSTER} \
              --service-name ${PROD_SERVICE} \
              --desired-count 1 \
              --task-definition ${PROD_TASK_DEFINITION} \
              --launch-type FARGATE \
              --platform-version LATEST \
              --network-configuration "awsvpcConfiguration={subnets=[subnet-0344d44130e11b79c,subnet-0de56d1e9c2d97060,subnet-02bbfe46ba29ce20a],securityGroups=[sg-04741693a6494256c],assignPublicIp=ENABLED}" \
              --load-balancers "targetGroupArn=$TARGET_GROUP_ARN,containerName=${PROD_CONTAINER},containerPort=${CONTAINER_PORT}";
          else    
              echo "Updating ${PROD_SERVICE} service..."
              aws ecs update-service \
              --service ${PROD_SERVICE} \
              --cluster ${PROD_CLUSTER} \
              --load-balancers "targetGroupArn=$TARGET_GROUP_ARN,containerName=${PROD_CONTAINER},containerPort=${CONTAINER_PORT}" \
              --force-new-deployment
          fi

          echo "DNS of the load balancer:"
          aws cloudformation describe-stacks --stack-name ${PROD_LOAD_BALANCER_STACK} --query 'Stacks[0].Outputs[?OutputKey==`LoadBalancerDNS`].OutputValue' --output text
          '''
        }

      }
    }

  }
  parameters {
    string(name: 'AWS_ACCOUNT_ID', defaultValue: '666243375423', description: 'AWS account id')
    string(name: 'AWS_REGION', defaultValue: 'us-east-2', description: 'AWS region')
    string(name: 'DEV_ECR_REPO', defaultValue: 'dev-web-app', description: 'ECR repo for development environment')
    string(name: 'STAGING_ECR_REPO', defaultValue: 'staging-web-app', description: 'ECR repo for staging environment')
    string(name: 'PROD_ECR_REPO', defaultValue: 'prod-web-app', description: 'ECR repo for production environment')
    string(name: 'DEV_CLUSTER', defaultValue: 'DevCluster', description: 'dev cluster name')
    string(name: 'STAGING_CLUSTER', defaultValue: 'StagingCluster', description: 'staging cluster name')
    string(name: 'PROD_CLUSTER', defaultValue: 'ProdCluster', description: 'production cluster name')
    string(name: 'DEV_TASK_DEFINITION', defaultValue: 'dev-web-app-definition', description: 'dev task definition name')
    string(name: 'STAGING_TASK_DEFINITION', defaultValue: 'staging-web-app-definition', description: 'staging task definition name')
    string(name: 'PROD_TASK_DEFINITION', defaultValue: 'prod-web-app-definition', description: 'production task definition name')
    string(name: 'DEV_CONTAINER', defaultValue: 'dev-web-app', description: 'Dev ecs container name')
    string(name: 'STAGING_CONTAINER', defaultValue: 'staging-web-app', description: 'Staging ecs container name')
    string(name: 'PROD_CONTAINER', defaultValue: 'prod-web-app', description: 'Prod ecs container name')
    string(name: 'CONTAINER_PORT', defaultValue: '80', description: 'Port of ecs container')
    string(name: 'DEV_SERVICE', defaultValue: 'dev-web-app-service', description: 'dev service name')
    string(name: 'STAGING_SERVICE', defaultValue: 'staging-web-app-service', description: 'staging service name')
    string(name: 'PROD_SERVICE', defaultValue: 'prod-web-app-service', description: 'production service name')
    string(name: 'DEV_LOAD_BALANCER_STACK', defaultValue: 'dev-load-balancer', description: 'dev load balancer stack name')
    string(name: 'STAGING_LOAD_BALANCER_STACK', defaultValue: 'staging-load-balancer', description: 'staging load balancer stack name')
    string(name: 'PROD_LOAD_BALANCER_STACK', defaultValue: 'prod-load-balancer', description: 'production load balancer stack name')
  }
}