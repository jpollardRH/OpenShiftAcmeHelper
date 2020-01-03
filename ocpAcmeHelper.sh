#!/bin/bash
ACMEHOME="~/acme.sh" # Path to where you downloaded the acme.sh script
CURRDIR=`pwd`
CERTDIR=${CURRDIR}/certificates

# Prompt the user to ensure he/she has logged into the desired OpenShift cluster
echo "----------------------------------------------------------------------"
echo "Let's Encrypt Helper tool for OpenShift 4 clusters"
echo ""
echo "This tool will generate and register public certificates against"
echo "an OpenShift 4 cluster. It can also be run subsequently to renew/"
echo "rotate the certs on a running system."
echo "----------------------------------------------------------------------"
echo "By J Pollard (jamie@redhat.com)                    "
echo "using Wolfgang Kulhanek's blog and OpenShift 4 docs"
echo "----------------------------------------------------------------------"
echo "Please note the following requirements for this helper:"
echo "1. Run this script from a separate subdirectory for each cluster. Certificates will be generated and placed in a new subdirectory named certificates."
echo "2. You must log in to the OpenShift cluster using the oc client before running this tool."
echo "3. You must have downloaded the acme.sh tool from https://github.com/Neilpang/acme.sh"
echo "4. You must be using AWS and have credentials cached (usually from a previous run of the openshift-installer)"
echo ""
echo "Please confirm you are in the correct directory and have logged in by typing the letter y below:"
read confirmvar

if [ "$confirmvar" != "y" ]
then
    echo "Please log in via oc client and then rerun this utility."
    exit 1
else
  # continue
  echo "Continuing..."
fi

LE_API=$(oc whoami --show-server | cut -f 2 -d ':' | cut -f 3 -d '/' | sed 's/-api././')
LE_WILDCARD=$(oc get ingresscontroller default -n openshift-ingress-operator -o jsonpath='{.status.domain}')

mkdir -p ${CERTDIR}

# Call acme script to generate the certs from Let's Encrypt. Force option to force a renewal.
${ACMEHOME}/acme.sh --issue -d ${LE_API} -d *.${LE_WILDCARD} --dns dns_aws --force

# Call acme script to put certs in the right place
${ACMEHOME}/acme.sh --install-cert -d ${LE_API} -d *.${LE_WILDCARD} --cert-file ${CERTDIR}/cert.pem --key-file ${CERTDIR}/key.pem --fullchain-file ${CERTDIR}/fullchain.pem --ca-file ${CERTDIR}/ca.cer

# First create the secret for the certs
#oc create secret tls letsencryptcert --cert=${CERTDIR}/fullchain.pem --key=${CERTDIR}/key.pem -n openshift-ingress
# New method to patch to a new secret for easier changeover
CURRDATE=$(date +"%Y%m%d-%H%M%S")
SECRETNAME=letsencryptcert-${CURRDATE}
oc create secret tls ${SECRETNAME} \
--cert=${CERTDIR}/fullchain.pem \
--key=${CERTDIR}/key.pem \
-n openshift-ingress

# Now patch the Ingress Controller to pick up the new certs
oc patch ingresscontroller.operator default --type=merge \
-p "{\"spec\":{\"defaultCertificate\":  {\"name\": \"${SECRETNAME}\"}}}" -n openshift-ingress-operator

echo "---------------------------------------------------------"
echo "-----------------SCRIPT COMPLETED------------------------"
echo "---------------------------------------------------------"
echo "PLEASE NOTE: It will take 2-3 minutes for the new certificates to be used on the cluster, this is normal."

