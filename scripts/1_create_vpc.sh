#!/bin/bash +x

aws cloudformation create-stack --stack-name ${CLUSTER_NAME}-vpc --template-body file://templates/1_vpc_template.yaml  --parameters file://parameters/1_vpc_params.json

aws cloudformation wait stack-create-complete --stack-name ${CLUSTER_NAME}-vpc

echo "stack: '${CLUSTER_NAME}-vpc' created. "

aws cloudformation describe-stacks --stack-name ${CLUSTER_NAME}-vpc | jq .Stacks[].Outputs
