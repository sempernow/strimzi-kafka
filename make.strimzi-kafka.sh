#!/usr/bin/env bash
#####################################
# Manage strimzi-kafka-operator
#####################################

ver=0.48.0 # K8S 1.27+
ver=0.47.0 
# Kafka image is obtainable only from helm.template.yaml of the Strimzi Operator
chart=strimzi-kafka-operator
release=strimzi-operator
ns=sko
values=values.diff.yaml
cluster=kafka.yaml
clients=kafka-clients.yaml
# Has no actual helm repo
# URL from GitHub 
url=https://github.com/strimzi/$chart/releases/download/$ver/$chart-helm-3-chart-$ver.tgz
# https://artifacthub.io/packages/helm/strimzi-kafka-operator/strimzi-kafka-operator
# URL from ArtifactHUB

export KAFKA_CLUSTER='k1'
export KAFKA_VERSION='4.0.0'
export KAFKA_NODEPORT='32100'

export KAFKA_IMAGE="quay.io/strimzi/kafka:${ver}-kafka-${KAFKA_VERSION}"

pull(){
    url=oci://quay.io/strimzi-helm/$chart
    helm pull $url --version $ver &&
        tar -xaf ${chart}-$ver.tgz &&
            mv $chart/values.yaml . &&
                rm -rf $chart ||
                    return 1

    [[ -f $values ]] || {
        [[ -f values.yaml ]] && cp values.yaml $values
    }
}

make(){
    envsubst < $values.tpl > $values
    envsubst < $cluster.tpl > $cluster
    envsubst < $clients.tpl > $clients
}

template(){
    helm template $release $url -n $ns --values $values |
        tee helm.template.yaml
}

strimzi(){
    up(){
        helm upgrade $release $url --install \
            --values $values \
            --namespace $ns \
            --create-namespace
    }
    down(){
        helm delete $release -n $ns
    }
    status(){
        helm status $release -n $ns
    }
    get(){
        kinds='Role,RoleBinding,ClusterRole,ClusterRoleBinding,sa,deploy,ds,sts,pod,secret,cm' 
        kubectl -n $ns get $kinds -l app=strimzi
        echo
        kubectl -n $ns get $kinds -l name=strimzi-cluster-operator

        #getcr # Operator creates none; it merely adds the CRDs.
        
        echo -e '\nℹ️ CRDs added by Strimzi Operator\n'
        kubectl api-resources |grep strimzi |awk '{print $5}'
    }

    "$@"
}

manifest(){
    helm template $release $url -n $ns --values $values |
        tee helm.manifest.yaml
}

diffs(){
    diff helm.template.yaml helm.manifest.yaml
}

cluster(){
    up(){
        kubectl -n $ns apply -f $cluster
    }
    down(){
        kubectl -n $ns delete -f $cluster
    }
    get(){
        kubectl -n $ns get cm,secret,svc,ingress,deploy,pod \
            -l strimzi.io/cluster=$KAFKA_CLUSTER
        getcr
    }

    "$@"
}
clients(){
    up(){
        kubectl -n $ns apply -f $clients
    }
    down(){
        kubectl -n $ns delete -f $clients
    }
    get(){
        kubectl -n $ns get pod,cm,secret \
            -l app=${KAFKA_CLUSTER}-clients
    }

    "$@"
}

getcr(){
    #kubectl api-resources |grep -i strimzi |cut -d' ' -f1 |
    kubectl api-resources |grep -i strimzi |awk '{print $5}' |
        xargs -n1 /bin/bash -c '
            kubectl -n $0 get --ignore-not-found $1 |
                sed -e "s/NAME /\n@ $1\nNAME /"
        ' $ns
}

[[ $1 ]] || { cat $BASH_SOURCE; exit; }

"$@"

