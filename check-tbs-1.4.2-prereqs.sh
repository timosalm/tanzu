#!/bin/bash

G='\033[0;32m'
R='\033[0;31m'
N='\033[0m'

echo    "###################################################"
echo -e "#            Checking Prerequisits for"
echo -e "#               ${G}Tanzu Build Service${N}"
echo -e "#                     ${G}1.4.2${N}"
echo    "###################################################"

KAPP_NAMESPACE=${1:-kapp}

vercomp () {
    if [[ $1 == $2 ]]
    then
        return 0
    fi
    local IFS=.
    local i ver1=($1) ver2=($2)
    # fill empty fields in ver1 with zeros
    for ((i=${#ver1[@]}; i<${#ver2[@]}; i++))
    do
        ver1[i]=0
    done
    for ((i=0; i<${#ver1[@]}; i++))
    do
        if [[ -z ${ver2[i]} ]]
        then
            # fill empty fields in ver2 with zeros
            ver2[i]=0
        fi
        if ((10#${ver1[i]} > 10#${ver2[i]}))
        then
            return 1
        fi
        if ((10#${ver1[i]} < 10#${ver2[i]}))
        then
            return 2
        fi
    done
    return 0
}

check_command () {
  NAME=$1
  LOCATION=$(which $1)
  if [ $? -ne 0 ]; then
    echo -e "$1: not installed. ${R}FAIL${N}."
    return 1
  fi
  echo -e "$1: available at $LOCATION. ${G}OK${N}."
  return 0
}

check_command_version () {
  CMD=$1
  VERSION=$2
  MINVERSION=$3
  vercomp "$VERSION" "$MINVERSION"
  RESULT=$?
  echo -e -n "$CMD: available version is $VERSION (>= $MINVERSION): "
  if [ $RESULT -eq 0 ] || [ $RESULT -eq 1 ]; then
    echo -e "${G}OK${N}."
  else
    echo -e "${R}FAIL${N}."
  fi
}

check_ytt() {
  check_command ytt
  if [ $? -eq 0 ]; then
    check_ytt_version
  fi
}

check_ytt_version () {
  VERSION=$(ytt --version | awk '{print $3}')
  check_command_version ytt $VERSION 0.35.0
}

check_imgpkg() {
  check_command imgpkg
  if [ $? -eq 0 ]; then
    check_imgpkg_version
  fi
}

check_imgpkg_version () {
  VERSION=$(imgpkg --version | grep version | awk '{print $3}')
  check_command_version imgpkg $VERSION 0.12.0
}

check_kp() {
  check_command kp
  if [ $? -eq 0 ]; then
    check_kp_version
  fi
}

check_kp_version () {
  VERSION=$(kp version | cut -d "-" -f 1)
  check_command_version kp $VERSION 0.4.0
}

check_kubectl() {
  check_command kubectl
  SRV_MIN_VERS=$(kubectl version -o json | jq .serverVersion.minor)
  if [ $SRV_MIN_VERS == "null" ]; then
    echo -e "kubectl: not connected to any k8s cluster. ${R}FAIL${N}."
    return 1
  fi
  echo -e "kubectl: connected to k8s cluster: ${G}OK${N}."
  check_k8s_default_storageclass
}

check_kapp() {
  check_command kapp
}

check_kbld () {
  check_command kbld
}

check_k8s_default_storageclass () {
  SC=$(kubectl get sc -o json | jq '.items[] | select(.metadata.annotations."storageclass.kubernetes.io/is-default-class" == "true")' | jq -r .metadata.name)
  if [ -z "$SC" ]; then
    echo -e "k8s: no default storage class found. ${R}FAIL${N}."
    return 1
  fi
  echo -e "k8s: default storage class found: $SC. ${G}OK${N}."
  return 0
}

check_carvel () {
  check_kapp
  check_ytt
  check_kbld
  check_imgpkg
}

check_k8s_permission () {
  NS=$1
  NOUN=$2
  VERBS="${@:3}"

  RESULT=0
  for VERB in $VERBS; do
    if [ $NS == "none" ]; then
      kubectl auth can-i $VERB $NOUN > /dev/null 2>&1
    else
      kubectl auth can-i $VERB $NOUN --namespace $NS > /dev/null 2>&1
    fi
    RES=$?
    if [ $RES -ne 0 ]; then
      if [ $NS == "none" ]; then
        echo -e "k8s: missing permission: $VERB $NOUN. ${R}FAIL${N}."
      else
        echo -e "k8s: missing permission in namespace $NS: $VERB $NOUN. ${R}FAIL${N}."
      fi
      RESULT=1
    fi
  done
  if [ $NS == "none" ]; then
    echo -e "k8s: permission(s) $(echo $VERBS | sed 's# #/#g') $NOUN. ${G}OK${N}."
  else
    echo -e "k8s: permission(s) $(echo $VERBS | sed 's# #/#g') $NOUN in namespace $NS. ${G}OK${N}."
  fi
  return $RESULT
}

check_k8s () {
  ALL_VERBS="create get update patch delete watch"
  check_kubectl
  check_k8s_permission none mutatingwebhookconfigurations $ALL_VERBS
  check_k8s_permission none validatingwebhookconfigurations $ALL_VERBS
  check_k8s_permission none clusterroles $ALL_VERBS
  check_k8s_permission none clusterrolebindings $ALL_VERBS
  check_k8s_permission none customresourcedefinitions $ALL_VERBS
  check_k8s_permission none storageclasses $ALL_VERBS
  check_k8s_permission none storageclasses get list watch
  check_k8s_permission none builds $ALL_VERBS
  check_k8s_permission none builds/status $ALL_VERBS
  check_k8s_permission none builds/finalizers $ALL_VERBS
  check_k8s_permission none images $ALL_VERBS
  check_k8s_permission none images/status $ALL_VERBS
  check_k8s_permission none images/finalizers $ALL_VERBS
  check_k8s_permission none builders $ALL_VERBS
  check_k8s_permission none builders/status $ALL_VERBS
  check_k8s_permission none clusterbuilders $ALL_VERBS
  check_k8s_permission none clusterbuilders/status $ALL_VERBS
  check_k8s_permission none clusterstores $ALL_VERBS
  check_k8s_permission none clusterstores/status $ALL_VERBS
  check_k8s_permission none clusterstacks $ALL_VERBS
  check_k8s_permission none clusterstacks/status $ALL_VERBS
  check_k8s_permission none sourceresolvers $ALL_VERBS
  check_k8s_permission none sourceresolvers/status $ALL_VERBS
  check_k8s_permission none projects $ALL_VERBS

  check_k8s_permission build-service configmaps $ALL_VERBS
  check_k8s_permission build-service secrets $ALL_VERBS
  check_k8s_permission build-service serviceaccounts $ALL_VERBS
  check_k8s_permission build-service services $ALL_VERBS
  check_k8s_permission build-service namespaces $ALL_VERBS
  check_k8s_permission build-service roles $ALL_VERBS
  check_k8s_permission build-service rolebindings $ALL_VERBS
  check_k8s_permission build-service deployments $ALL_VERBS
  check_k8s_permission build-service daemonsets $ALL_VERBS

  check_k8s_permission kpack services $ALL_VERBS
  check_k8s_permission kpack serviceaccounts $ALL_VERBS
  check_k8s_permission kpack namespaces $ALL_VERBS
  check_k8s_permission kpack secrets $ALL_VERBS
  check_k8s_permission kpack configmaps $ALL_VERBS
  check_k8s_permission kpack roles $ALL_VERBS
  check_k8s_permission kpack rolebindings $ALL_VERBS
  check_k8s_permission kpack deployments $ALL_VERBS
  check_k8s_permission kpack daemonsets $ALL_VERBS

  check_k8s_permission $KAPP_NS configmaps $ALL_VERBS
}


check_carvel
check_kp
check_k8s
