#!/bin/bash
BASE_DIR=$(
    cd "$(dirname "$0")"
    pwd
)
PROJECT_DIR=${BASE_DIR}
SCRIPT_DIR=${BASE_DIR}/scripts
UTILS_DIR=${BASE_DIR}/utils
action=$1

#工具函数
function read_from_input() {
    var=$1
    msg=$2
    choices=$3
    default=$4
    if [[ ! -z "${choices}" ]]; then
        msg="${msg} (${choices}) "
    fi
    if [[ -z "${default}" ]]; then
        msg="${msg} (无默认值)"
    else
        msg="${msg} (默认为${default})"
    fi
    echo -n "${msg}: "
    read input
    if [[ -z "${input}" && ! -z "${default}" ]]; then
        export ${var}="${default}"
    else
        export ${var}="${input}"
    fi
}
function set_docker_config() {
    cwd=$(pwd)
    cd ${PROJECT_DIR}
    url=$1
    user=$2
    password=$3
    authed=$(echo -n ${user}:${password} | base64)
    #bug
    # sed -i '/registry/c\ \"\'${url}'\",' utils/docker-config.json
    # sed -i "s,'password'/${auth},g" utils/docker-config.json

    echo '{
	    "auths": {
            "'${url}'": {
			    "auth": "'${authed}'"
		        }
	        },
	    "HttpHeaders": {
		    "User-Agent": "Docker-Client/18.09.9 (linux)"
	    }
    }' >utils/docker-config.json

    secret=$(base64 -w 0 utils/docker-config.json)
    all_variables_secret="secret=${secret}"
    #替换Secert
    resourcefile=`cat apps/userdefined-secret.yaml`
    printf "$all_variables_secret\ncat << EOF\n$resourcefile\nEOF" | bash >apps/jenkins/templates/userdefined-secret.yaml
    printf "$all_variables_secret\ncat << EOF\n$resourcefile\nEOF" | bash >apps/gitlab-ce/templates/userdefined-secret.yaml
    printf "$all_variables_secret\ncat << EOF\n$resourcefile\nEOF" | bash >apps/sonarqube/templates/userdefined-secret.yaml
    printf "$all_variables_secret\ncat << EOF\n$resourcefile\nEOF" | bash >apps/harbor/templates/userdefined-secret.yaml

    #TODO
    #替换source
    # registryfile=`cat apps/jenkins/values.yaml`
    # all_variables_source="imageregistry=\"${url}\""
    # printf "$all_variables_source\ncat << EOF\n$registryfile\nEOF" | bash >apps/jenkins/values.yaml
    sed "s/imageregistryvalue/\"${url}\"/g" apps/jenkins/values_default.yaml > apps/jenkins/values.yaml
    sed "s/imageregistryvalue/\"${url}\"/g" apps/gitlab-ce/values_default.yaml > apps/gitlab-ce/values.yaml
    sed "s/imageregistryvalue/\"${url}\"/g" apps/sonarqube/values_default.yaml > apps/sonarqube/values.yaml
    sed "s/imageregistryvalue/\"${url}\"/g" apps/sonarqube/chart/mysql/values_default.yaml > apps/sonarqube/chart/mysql/values.yaml
    sed "s/imageregistryvalue/\"${url}\"/g" apps/sonarqube/chart/postgresql/values_default.yaml > apps/sonarqube/chart/postgresql/values.yaml
    sed "s/imageregistryvalue/\"${url}\"/g" apps/harbor/values_default.yaml > apps/harbor/values.yaml
}

## 检查环境 安装helm push
function env_check() {
    echo "检查Docker......"
    docker -v
    if [ $? -eq 0 ]; then
        echo "检查到Docker已安装!"
    else
        echo "请先安装Docker"
    fi
    echo "检查Helm......"
    helm version
    if [ $? -eq 0 ]; then
        echo "检查到Helm已安装!"
    else
        echo "请先安装Helm"
    fi
    #安装Helm Push Plugins
    mv ${UTILS_DIR}/push $(helm home)/plugins/
    echo "安装 Push Plugins 完成"
}
registry_host=""
registry_user=""
registry_pass=""
function set_external_registry() {

    read_from_input registry_host "请输入registry的域名" "" "${registry_host}"

    read_from_input registry_user "请输入registry的用户名" "" "${registry_user}"

    read_from_input registry_pass "请输入registry的密码" "" "${registry_pass}"

    #test_registry_connect ${registry_host} ${registry_port} ${registry_user} ${registry_pass} ${registry_db}
    # if [[ "$?" != "0" ]]; then
    #     echo "测试连接数据库失败, 请重新设置"
    #     set_external_registry
    #     return
    # fi
    set_docker_config ${registry_host} ${registry_user} ${registry_pass}
}

function set_internal_registry() {
    registry_host="registry.kubeapps.fit2cloud.com"
    registry_user="admin"
    registry_pass="admin123"
    set_docker_config ${registry_host} ${registry_user} ${registry_pass}
}

function set_registry() {
    echo ">>> 配置registry"
    use_external_registry="n"
    read_from_input use_external_registry "是否使用外部Docker Image Registry" "y/n" "${use_external_registry}"

    if [[ "${use_external_registry}" == "y" ]]; then
        set_external_registry
    else
        set_internal_registry
    fi
}

#docker retag & push

function docker_upload_image() {

    #jenkins start
    cd ${PROJECT_DIR}/apps/image
    docker load <jenkins.jar
    docker load <jnlp-slave.jar
    docker tag 22b8b9a84dbe ${registry_host}/jenkins/jenkins:lts
    docker tag 6bf8f3767d8b ${registry_host}/jenkins/jnlp-slave:3.27-1
    docker push ${registry_host}/jenkins/jenkins:lts
    docker push ${registry_host}/jenkins/jnlp-slave:3.27-1
    #jenkins end

    #gitlab start
    docker load <gitlab.jar
    docker tag 6099ff61e4ff ${registry_host}/gitlab/gitlab:lts
    docker push ${registry_host}/gitlab/gitlab:lts
    #gitlab end

    #sonarqube start
    docker load <sonarqube.jar
    docker tag ea9ce8f562b5 ${registry_host}/sonarqube/sonarqube:lts
    docker push ${registry_host}/sonarqube/sonarqube:lts
    docker load < mysql-5.7.jar
    docker tag 4b3b6b994512 ${registry_host}/mysql:5.7.14
    docker push ${registry_host}/mysql:5.7.14
    docker load < busybox-125.jar
    docker tag b3b8a2229953 ${registry_host}/busybox:1.25.0
    docker push ${registry_host}/busybox:1.25.0
    docker load < postgres.jar 
    docker tag b3b8a2229953 ${registry_host}/postgres:9.6.2
    docker push ${registry_host}/postgres:9.6.2
    #gitlab end

    #harbor start
    docker load <harbor-chartmuseum-photon.jar
    docker load <harbor-clair-adapter-photon.jar
    docker load <harbor-clair-photon.jar
    docker load <harbor-core.jar
    docker load <harbor-db.jar
    docker load <harbor-jobservice.jar
    docker load <harbor-nginx-photon.jar
    docker load <harbor-notary-server-photon.jar
    docker load <harbor-notary-signer-photon.jar
    docker load <harbor-portal.jar
    docker load <harbor-redis-photon.jar
    docker load <harbor-registryctl.jar
    docker load <harbor-registry-photon.jar
    
    docker tag 72907320ffac ${registry_host}/harbor/harbor-chartmuseum-photon:lts
    docker tag ad64fa39c62b ${registry_host}/harbor/harbor-clair-adapter-photon:lts
    docker tag 53440cf589b9 ${registry_host}/harbor/harbor-clair-photon:lts
    docker tag 26436ee0e558 ${registry_host}/harbor/harbor-core:lts
    docker tag 5f4b52e24061 ${registry_host}/harbor/harbor-db:lts
    docker tag 362bfafa892b ${registry_host}/harbor/harbor-jobservice:lts
    docker tag f49106ca9f4a ${registry_host}/harbor/harbor-nginx-photon:lts
    docker tag 0f05fe55ce34 ${registry_host}/harbor/harbor-notary-server-photon:lts
    docker tag e98944d2dbd6 ${registry_host}/harbor/harbor-notary-signer-photon:lts
    docker tag 9cf90487afc9 ${registry_host}/harbor/harbor-portal:lts
    docker tag 3b5fc4767360 ${registry_host}/harbor/harbor-redis-photon:lts
    docker tag 2e6fe7b484bb ${registry_host}/harbor/harbor-registryctl:lts
    docker tag bd03f4313216 ${registry_host}/harbor/harbor-registry-photon:lts

    docker push ${registry_host}/harbor/harbor-chartmuseum-photon:lts
    docker push ${registry_host}/harbor/harbor-clair-adapter-photon:lts
    docker push ${registry_host}/harbor/harbor-clair-photon:lts
    docker push ${registry_host}/harbor/harbor-core:lts
    docker push ${registry_host}/harbor/harbor-db:lts
    docker push ${registry_host}/harbor/harbor-jobservice:lts
    docker push ${registry_host}/harbor/harbor-nginx-photon:lts
    docker push ${registry_host}/harbor/harbor-notary-server-photon:lts
    docker push ${registry_host}/harbor/harbor-notary-signer-photon:lts
    docker push ${registry_host}/harbor/harbor-portal:lts
    docker push ${registry_host}/harbor/harbor-redis-photon:lts
    docker push ${registry_host}/harbor/harbor-registryctl:lts
    docker push ${registry_host}/harbor/harbor-registry-photon:lts
    #gitlab end
}

#打包Helm Chart

# function pakcage_chart() {
#     echo ">>> 打包Chart"
#     cd ${PROJECT_DIR}/jenkins
#     helm pakcage .
#     if [ $? -eq 0 ]; then
#         echo ">>> 打包完成"
#     else
#         echo ">>> 打包失败"
#     fi
# }

#配置chart 仓库

function set_external_chartrepo() {
    repo_url=""
    read_from_input repo_url "请输入Chart Repo的主机域名 例: http://chartmuseum.kubeapps.fit2cloud.com" "" "${repo_url}"

    repo_username=""
    read_from_input repo_username "请输入Repo的用户名" "" "${repo_username}"

    repo_password=""
    read_from_input repo_password "请输入Repo的密码" "" "${repo_password}"

    helm repo add localrepo ${repo_url} --username ${repo_username} --password ${repo_password}
}

function set_internal_chartrepo() {
    helm repo add localrepo http://chartmuseum.kubeapps.fit2cloud.com
}

function set_chartrepo() {
    echo ">>> 配置 Chart 仓库"
    use_external_chartrepo="n"
    read_from_input use_external_chartrepo "是否使用外部 Chart 仓库" "y/n" "${use_external_chartrepo}"

    if [[ "${use_external_chartrepo}" == "y" ]]; then
        set_external_chartrepo
    else
        set_internal_chartrepo
    fi
}

#上传Chart 到 Chart Repo

function upload_chart() {
    cd ${PROJECT_DIR}/apps/gitlab-ce
    helm package .
    helm push . localrepo -f
    cd ${PROJECT_DIR}/apps/harbor
    helm package .
    helm push . localrepo -f
    cd ${PROJECT_DIR}/apps/jenkins
    helm package .
    helm push . localrepo -f
    cd ${PROJECT_DIR}/apps/sonarqube
    helm package .
    helm push . localrepo -f
    if [ $? -eq 0 ]; then
        echo ">>> 上传完成"
    else
        echo ">>> 上传失败"
    fi
}

function usage() {
    echo "Kubeapps 推送Docker镜像及Helm Chart包脚本"
    echo
    echo "Usage: "
    echo "  ./kubeappsctl.sh [COMMAND] [ARGS...]"
    echo "  ./kubeappsctl.sh --help"
    echo
    echo "Commands: "
    echo "  start 推送Docker镜像及Helm Chart包"
}

#主进程
function main() {
    case "${action}" in
    start)
        env_check
        set_registry
        docker_upload_image
        set_chartrepo
        upload_chart
        ;;
    help)
        usage
        ;;
    --help)
        usage
        ;;
    *)
        usage
        ;;
    esac
}
main
