# Red Hat OpenShift Container Platform v4 on AWS China

目前OCP v4 Installer Provisioned Infrastructure (IPI) 部署方式还不支持AWS中国区域，可以通过User Provisioned Infrastructure (UPI)方式安装部署OCP v4. 

下面介绍OCP v4 UPI部署方法。

## 需要准备的资源
1. AWS中国区域的帐号和AWS Global区域的账号。
2. Red Hat 账号，用于下载installer和pull secret。 安装自动获得60天试用版Subscription。
3. 已备案的域名，并在AWS Global区域Route53中已经建立Hosted Zone。

## 1. 安装配置aws cli和jq

首先需要在您用于运行安装程序的电脑上安装并配置aws cli。具体步骤请参考[AWS文档](https://docs.amazonaws.cn/cli/latest/userguide/cli-chap-install.html)。

配置aws cli，添加两个profile. 详细步骤参考[aws cli文档](https://docs.aws.amazon.com/zh_cn/cli/latest/userguide/cli-configure-profiles.html).
* global：配置AWS Global区域管理员的AK/SK，区域设置为ap-southeast-1.
* china: 配置AWS中国区管理员的AK/SK，区域设置为cn-northwest-1.

安装命令行json工具jq。具体步骤请参考[jq wiki](https://github.com/stedolan/jq/wiki/Installation)。

## 2. 下载安装程序，生成ssh key

用Red Hat账号登录[Infrastructure Provider](https://cloud.redhat.com/openshift/install), infrastructure provider选择AWS，安装方式选择user-provisioned infrastructure。

下载对应镜像版本和你的操作系统的OpenShift installer，在同一个页面下载pull secret和Command-line interface。

选择您将用来登录集群的ssh key。如果您还没有ssh key，可以用下面的命令生成。

```bash
ssh-keygen -t rsa -b 4096 -N '' -f <path>/<file_name>
```

指明生成的key的位置，例如"~/.ssh/id_rsa"。 

并将ssh key加载到ssh agent中。 

```bash
eval "$(ssh-agent -s)"
ssh-add <path>/<file_name>
```

## 3. 新建VPC

设置CLUSTER_NAME环境变量. 

```bash

export CLUSTER_NAME=myocpcluster

```

激活AWS中国区域的Profile。

```bash
export AWS_DEFAULT_PROFILE=china
```

按照需要更新[vpc参数文件](parameters/1_vpc_params.json). 然后执行下面的命令新建VPC。

```bash

./scripts/1_create_vpc.sh

```

## 4. 新建本地镜像实例

由于跨境网络原因，导致OCP安装从Quay.io上下载容器镜像时非常缓慢，为了保证安装能够顺利完成，需要先制作离线的本地镜像库。

制作镜像实例的详细步骤请参考[OCP文档](https://docs.openshift.com/container-platform/4.3/installing/install_config/installing-restricted-networks-preparations.html#installing-restricted-networks-preparations)。

镜像实例请部署在上一步新建的VPC的公有子网中, 并在安全组入站规则中开放vpc网段对镜像服务器端口的访问。

请记录镜像实例过程中输出的3个信息，后面的安装步骤中会用到。

* 镜像仓库的ca证书： /opt/registry/certs/domain.crt的内容。例如：
```bash
  -----BEGIN CERTIFICATE-----
  many lines of data...
  -----END CERTIFICATE-----
```
* 镜像仓库的pull secret，保存为mirror-pull-secret.txt。例如：
```json
{
  "auths": {
    "cloud.openshift.com": {
      "auth": "b3BlbnNo...",
      "email": "you@example.com"
    },
    "quay.io": {
      "auth": "b3BlbnNo...",
      "email": "you@example.com"
    },
    "registry.connect.redhat.com": {
      "auth": "NTE3Njg5Nj...",
      "email": "you@example.com"
    },
    "<local_registry_host_name>:<local_registry_host_port>": {
      "auth": "<credentials>",
      "email": "you@example.com"
    },
    "registry.redhat.io": {
      "auth": "NTE3Njg5Nj...",
      "email": "you@example.com"
    }
  }
}
```

* 镜像命令成功后输出的imageContentSources，例如：

```bash
- mirrors:
  - ip-10-0-11-240.cn-northwest-1.compute.internal:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - ip-10-0-11-240.cn-northwest-1.compute.internal:5000/ocp4/openshift4
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev
```

* 参考第6点，为BASE_DOMAIN创建hostedZone

* 为镜像仓库创建ELB实例后，执行以下脚本，为镜像仓库创建域名

```bash
./scripts/2_create_registry_dns_records.sh
```

## 5. 生成Kubernetes manifest和ignition文件

把上一步下载的OpenShift Installer解压，把openshift-installer程序复制到bin目录下。

把第3步中获得的pull secret生成pull-secret.json放到parameters目录下。

```bash
cat <mirror-pull-secret.txt> | jq -c . > parameters/pull-secret.json
```

激活AWS Global区域的Profile。

```bash
export AWS_DEFAULT_PROFILE=global
```

生成安装配置文件
```bash
./bin/openshift-install create install-config --dir=${CLUSTER_NAME}
```
根据命令行提示，选择SSH Public Key，Platform选择aws，Region选择ap-southeast-1 (Singapore), Base Domain选择要使用的Route53域名，Cluster Name设置为选择的集群名称，Pull Secret复制pull-secret.json的内容。

编辑${CLUSTER_NAME}/install-config.yaml，把worker的副本数量设置为0. 如下所示。

```yaml

    compute:
    - hyperthreading: Enabled
    name: worker
    platform: {}
    replicas: 0

```

增加additionalTrustBundle部分。这部分的内容必须是第3步，新建本地镜像服务器所使用的CA证书文件的内容。示例如下： 

```yaml

additionalTrustBundle: |
  -----BEGIN CERTIFICATE-----
  ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
  ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
  ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
  ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
  ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
  ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
  ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
  ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
  ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
  ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
  ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
  ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
  ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
  ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
  ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
  ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
  -----END CERTIFICATE-----

```

添加imageContentSources部分。这个是第3步同步镜像内容后输出的信息。示例如下：

```yaml

imageContentSources:
- mirrors:
  - <bastion_host_name>:5000/<repo_name>/release
  source: quay.io/openshift-release-dev/ocp-release
- mirrors:
  - <bastion_host_name>:5000/<repo_name>/release
  source: quay.io/openshift-release-dev/ocp-v4.0-art-dev

```


然后运行下面的命令，生成集群的Kubernetes manifest
```bash
./bin/openshift-install create manifests --dir=${CLUSTER_NAME}
```

这个命令完成后，会新建一个名为${CLUSTER_NAME}的目录，下面有OCP集群相关的kubernetes声明文件。 

删除control plane和worker node相关的声明文件, 后面使用CloudFormation新建。

```bash
rm -f ${CLUSTER_NAME}/openshift/99_openshift-cluster-api_master-machines-*.yaml
rm -f ${CLUSTER_NAME}/openshift/99_openshift-cluster-api_worker-machineset-*.yaml
```

编辑${CLUSTER_NAME}/manifests/cluster-scheduler-02-config.yml，把mastersSchedulable的值改为false.


编辑${CLUSTER_NAME}/manifests/cluster-dns-02-config.yml文件，注释掉privateZone和publicZone部分。后面我们会单独添加ingress DNS记录。

```yaml
apiVersion: config.openshift.io/v1
kind: DNS
metadata:
  creationTimestamp: null
  name: cluster
spec:
  baseDomain: example.openshift.com
#  privateZone: 
#    id: mycluster-100419-private-zone
#  publicZone: 
#    id: example.openshift.com
status: {}
```

把配置文件中ap-southeast-1相关内容替换成cn-northwest-1. 

```bash

find ${CLUSTER_NAME} -type f -print0 | xargs -0 sed -i '' -e 's/ap-southeast-1/cn-northwest-1/g'

```

运行下面的命令，生成ignition文件。

```bash
./bin/openshift-install create ignition-configs --dir=${CLUSTER_NAME}
```

获取infrastructure ID

```bash
export InfraID=`jq -r .infraID ${CLUSTER_NAME}/metadata.json`
```


## 6. 新建ELB和Route53域名

激活AWS中国区域的Profile。

```bash
export AWS_DEFAULT_PROFILE=china
```

如果你还没有在AWS中国区的Route53中新建Hosted Zone，用下面的命令新建BASE_DOMAIN对应的Hosted Zone。

```bash 

export BASE_DOMAIN="example.com"
export CURRENT_DATE=`date`
export HostedZoneId=`aws route53 create-hosted-zone --name ${BASE_DOMAIN} --caller-reference "${CURRENT_DATE}" --endpoint-url=https://route53.amazonaws.com.cn | jq -r .HostedZone.Id`

```

更新parameters/2_elb_dns_params.json中的参数，运行下面的命令，新建ELB和DNS域名。

```bash

./scripts/2_create_elb_dns.sh

```


## 7. 新建安全组

更新parameters/3_sg_params.json中的参数，运行下面的命令，新建ELB和DNS域名。

```bash

./scripts/3_create_sg.sh

```

## 8. 新建bootstrap实例

更新parameters/4_bootstrap_node.json中的参数，运行下面的命令，新建bootrap实例。

```bash

./scripts/4_create_bootstrap_node.sh

```

## 9. 新建control plane实例

更新parameters/4_bootstrap_node.json中的参数. 通过下面的命令获得CertificateAuthorities的值.

```bash
cat ${CLUSTER_NAME}/master.ign | jq -r .ignition.security.tls.certificateAuthorities[].source
```

运行下面的命令，新建control plane实例。

```bash

./scripts/5_create_control_plane_nodes.sh 

```

配置KUBECONFIG，用oc查看集群的nodes.

```bash
export KUBECONFIG=${CLUSTER_NAME}/auth/kubeconfig 

oc get nodes
```

过一段时间可以看到集群的master节点已经ready。

```bash
[ec2-user@ip-10-0-11-240 ~]$ oc get nodes
NAME                                             STATUS   ROLES    AGE   VERSION
ip-10-0-63-243.cn-northwest-1.compute.internal   Ready    master   34m   v1.16.2
ip-10-0-78-164.cn-northwest-1.compute.internal   Ready    master   34m   v1.16.2
ip-10-0-89-250.cn-northwest-1.compute.internal   Ready    master   34m   v1.16.2

```


## 10. 新建worker nodes

更新parameters/6_worker_node{01, 02, 03}.json中的参数。通过下面的命令获得CertificateAuthorities的值.

```bash
cat ${CLUSTER_NAME}/worker.ign | jq -r .ignition.security.tls.certificateAuthorities[].source
```


运行下面的命令，新建3个worker实例。

```bash

./scripts/6_create_worker_nodes.sh

```

观察新生成的CSR。

```bash
oc get csr 
```

可以看到pending的证书签发请求。
```bash
[ec2-user@ip-10-0-11-240 ~]$ oc get csr
NAME        AGE   REQUESTOR                                                                   CONDITION
csr-9xkxb   41m   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Pending
csr-btqjb   26m   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Pending
csr-cbwks   41m   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Pending
csr-ctphr   41m   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Pending
csr-fvj5s   11m   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Pending
csr-kg4w7   11m   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Pending
csr-m7w9j   26m   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Pending
csr-q9wfm   26m   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Pending
csr-zg5w8   11m   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Pending
```

仔细确认CSR是来自集群的worker节点后，批准CSR。

```bash
oc get csr -ojson | jq -r '.items[] | select(.status == {} ) | .metadata.name' | xargs oc adm certificate approve
```

需要重复几次csr批准过程，直到没有新的csr出现。

```bash
[ec2-user@ip-10-0-11-240 ~]$ oc get csr
NAME        AGE   REQUESTOR                                                                   CONDITION
csr-6dr4k   11m   system:node:ip-10-0-53-197.cn-northwest-1.compute.internal                  Approved,Issued
csr-9xkxb   52m   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Approved,Issued
csr-btqjb   37m   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Approved,Issued
csr-cbwks   52m   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Approved,Issued
csr-ctphr   52m   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Approved,Issued
csr-fvj5s   22m   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Approved,Issued
csr-kg4w7   22m   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Approved,Issued
csr-lxlkc   11m   system:node:ip-10-0-78-244.cn-northwest-1.compute.internal                  Approved,Issued
csr-m7w9j   37m   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Approved,Issued
csr-q9wfm   37m   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Approved,Issued
csr-tb5mw   11m   system:node:ip-10-0-88-145.cn-northwest-1.compute.internal                  Approved,Issued
csr-zg5w8   22m   system:serviceaccount:openshift-machine-config-operator:node-bootstrapper   Approved,Issued
```

然后可以看到集群的worker节点也变成ready。

```bash
[ec2-user@ip-10-0-11-240 ~]$ oc get nodes
NAME                                             STATUS   ROLES    AGE   VERSION
ip-10-0-53-197.cn-northwest-1.compute.internal   Ready    worker   11m   v1.16.2
ip-10-0-63-243.cn-northwest-1.compute.internal   Ready    master   88m   v1.16.2
ip-10-0-78-164.cn-northwest-1.compute.internal   Ready    master   88m   v1.16.2
ip-10-0-78-244.cn-northwest-1.compute.internal   Ready    worker   11m   v1.16.2
ip-10-0-88-145.cn-northwest-1.compute.internal   Ready    worker   11m   v1.16.2
ip-10-0-89-250.cn-northwest-1.compute.internal   Ready    master   88m   v1.16.2
```


## 11. 新建ingress controller的dns记录


更新parameters/7_ingress_dns_records.json中的参数，运行下面的命令，新建ingress controller的dns记录。

```bash

./scripts/7_create_ingress_dns_records.sh

```


等待control plane部署完成。

```bash

./bin/openshift-install wait-for bootstrap-complete --dir=${CLUSTER_NAME} --log-level=info

```

获得console URL

```bash
8c85909aaff7:ocp-v4 sunhua$ oc -n openshift-console get route/console

```

就可以通过HTTPS访问console route的URL。登录的用户名为kubeadmin，密码在${CLUSTER_NAME}/auth/kubeadmin-password文件中。


## 12. 更新cloud-credential-operator和ingress-operator

v4.3中cloud-credential-operator和ingress-operator对AWS中国区的支持还有些问题。

目前有两种处理方法。
* 关闭cloud-credential-operator，手工新建IAM用户，并把AK/SK更新到对应的Secret中。操作步骤请参考[cloud-credential-operator文档](https://github.com/openshift/cloud-credential-operator/blob/master/docs/disabled-operator.md).
* 使用hot fix版本。 

```bash
oc edit cm cloud-credential-operator-config -n openshift-cloud-credential-operator
oc get cm cloud-credential-operator-config -n openshift-cloud-credential-operator -o yaml
apiVersion: v1
data:
  disabled: "true"
kind: ConfigMap

oc delete pod cloud-credential-operator-69479545fc-7cxp7 -n openshift-cloud-credential-operator

oc delete secret cloud-credentials -n openshift-ingress-operator
oc create secret generic cloud-credentials --from-literal=aws_access_key_id=myaccesskey --from-literal=aws_secret_access_key=mysecretkey --namespace openshift-ingress-operator

oc delete secret aws-cloud-credentials -n openshift-machine-api
oc create secret generic aws-cloud-credentials --from-literal=aws_access_key_id=myaccesskey --from-literal=aws_secret_access_key=mysecretkey --namespace openshift-machine-api

```

## 13. 配置imageregistry 内置镜像仓库

默认安装可能从cloud-credential-operator拿不到AK, SK, 需要手动配置

```bash

oc create secret generic image-registry-private-configuration-user --from-literal=REGISTRY_STORAGE_S3_ACCESSKEY=myaccesskey --from-literal=REGISTRY_STORAGE_S3_SECRETKEY=mysecretkey --namespace openshift-image-registry

oc edit configs.imageregistry.operator.openshift.io/cluster
  managementState: Managed
  storage:
    s3:
      bucket: paas-p22mk-image-registry-cn-northwest-1-xxxxx
      encrypt: true
      keyID: ""
      region: cn-northwest-1
      regionEndpoint: ""

```

## 14. 为work节点准备并创建machineSet, 使计算节点能够获得自动缩扩容能力

```bash
oc create -f machineset/99_openshift-cluster-api_worker-machineset-0.yaml
oc create -f machineset/99_openshift-cluster-api_worker-machineset-1.yaml
oc create -f machineset/99_openshift-cluster-api_worker-machineset-2.yaml

```


