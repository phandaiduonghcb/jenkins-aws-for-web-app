#!/bin/bash
aws ecs delete-service --cluster DevCluster --service dev-web-app-service --force --profile duongpd7 >/dev/null
aws ecs delete-service --cluster StagingCluster --service staging-web-app-service --force --profile duongpd7 >/dev/null
aws ecs delete-service --cluster ProdCluster --service prod-web-app-service --force --profile duongpd7 >/dev/null
