# Red Hat OpenShift Container Platform v4 on AWS China

目前OCP v4 Installer Provisioned Infrastructure (IPI) 


## 需要准备的资源
1. AWS中国区域的帐号。
2. Red Hat 账号，用于下载installer和pull secret。
3. 已备案的域名。

## 1. 安装配置aws cli和jq

首先需要在您用于运行安装程序的电脑上安装并配置aws cli。具体步骤请参考[AWS文档](https://docs.amazonaws.cn/cli/latest/userguide/cli-chap-install.html)。

配置aws cli，添加两个profile. 详细步骤参考[aws cli文档](https://docs.aws.amazon.com/zh_cn/cli/latest/userguide/cli-configure-profiles.html).
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


按照需要更新[vpc参数文件](parameters/1_vpc_params.json). 然后执行下面的命令新建VPC。

```bash

./scripts/1_create_vpc.sh

```


