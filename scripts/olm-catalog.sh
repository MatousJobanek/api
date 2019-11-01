#!/usr/bin/env bash

user_help () {
    echo "Generate ClusterServiceVersion and additional deployment files for openshift-marketplace"
    echo "options:"
    echo "-pr, --project-root      path to the root of the project the CSV should be generated for/in"
    echo "-cv, --current-version   current CSV version"
    echo "-nv, --next-version      next CSV version"
    exit 0
}

if [[ $# -lt 2 ]]
then
    user_help
fi

while test $# -gt 0; do
       case "$1" in
            -h|--help)
                user_help
                ;;
            -pr|--project-root)
                shift
                PRJ_ROOT_DIR=$1
                shift
                ;;
            -cv|--current-version)
                shift
                CURRENT_CSV_VERSION=$1
                shift
                ;;
            -nv|--next-version)
                shift
                NEXT_CSV_VERSION=$1
                shift
                ;;
            *)
               echo "$1 is not a recognized flag!" >> /dev/stderr
               user_help
               exit -1
               ;;
      esac
done

indentList() {
    local INDENT="      "
    sed -e "s/^/${INDENT}/;1s/^${INDENT}/${INDENT:0:${#INDENT}-2}- /"
  }

if [[ -z PRJ_ROOT_DIR ]]; then
    echo "--project-root parameter is not specified" >> /dev/stderr
    user_help
    exit 1;
fi

# Version vars
NEXT_CSV_VERSION=${NEXT_CSV_VERSION:-0.0.1}

# Files and directories related vars
PRJ_NAME=`basename ${PRJ_ROOT_DIR}`
OPERATOR_NAME=toolchain-${PRJ_NAME}
CRDS_DIR=${PRJ_ROOT_DIR}/deploy/crds
PKG_DIR=${PRJ_ROOT_DIR}/deploy/olm-catalog/${OPERATOR_NAME}
PKG_FILE=${PKG_DIR}/${OPERATOR_NAME}.package.yaml
CSV_DIR=${PKG_DIR}/${NEXT_CSV_VERSION}

# Name and display name vars for CatalogSource
NAME=codeready-toolchain-saas-${OPERATOR_NAME}
DISPLAYNAME=$(echo ${NAME} | tr '-' ' ' | awk '{for (i=1;i<=NF;i++) $i=toupper(substr($i,1,1)) substr($i,2)} 1')

# Generate CSV
if [[ -n "${CURRENT_CSV_VERSION}" ]]; then
    FROM_VERSION_PARAM=--from-version ${CURRENT_CSV_VERSION}
fi

CURRENT_DIR=${PWD}
cd ${PRJ_ROOT_DIR}
operator-sdk olm-catalog gen-csv --csv-version ${NEXT_CSV_VERSION} ${FROM_VERSION_PARAM} --update-crds --operator-name ${OPERATOR_NAME}
cd ${CURRENT_DIR}

# Create hack directory if is missing
if [[ ! -d ${PRJ_ROOT_DIR}/hack ]]; then
    mkdir ${PRJ_ROOT_DIR}/hack
fi

# CatalogSource and ConfigMap for easy deployment
echo "# This file was autogenerated by github.com/codeready-toolchain/api/olm-catalog.sh'
---
apiVersion: operators.coreos.com/v1alpha1
kind: CatalogSource
metadata:
  name: ${NAME}
  namespace: openshift-marketplace
spec:
  configMap: ${NAME}
  displayName: $DISPLAYNAME
  publisher: Red Hat
  sourceType: internal
---
kind: ConfigMap
apiVersion: v1
metadata:
  name: ${NAME}
  namespace: openshift-marketplace
data:
  customResourceDefinitions: |-
$(for crd in `ls ${CRDS_DIR}/*crd.yaml`; do cat ${crd} | indentList; done)
  clusterServiceVersions: |-
$(cat ${CSV_DIR}/*clusterserviceversion.yaml | indentList)
  packages: |
$(cat ${PKG_FILE} | indentList "packageName")" > ${PRJ_ROOT_DIR}/hack/deploy_csv.yaml


echo "# This file was autogenerated by github.com/codeready-toolchain/api/olm-catalog.sh'
---
apiVersion: operators.coreos.com/v1
kind: OperatorGroup
metadata:
  name: ${NAME}
  namespace: REPLACE_NAMESPACE
spec:
  targetNamespaces:
  - REPLACE_NAMESPACE
---
apiVersion: operators.coreos.com/v1alpha1
kind: Subscription
metadata:
  name: ${NAME}
  namespace: REPLACE_NAMESPACE
spec:
  channel: alpha
  installPlanApproval: Automatic
  name: ${OPERATOR_NAME}
  source: ${NAME}
  sourceNamespace: openshift-marketplace
  startingCSV: ${OPERATOR_NAME}.v0.0.1" > ${PRJ_ROOT_DIR}/hack/install_operator.yaml