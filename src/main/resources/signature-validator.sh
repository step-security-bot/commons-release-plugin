#!/bin/bash -x
###########
#   Licensed to the Apache Software Foundation (ASF) under one or more
#  contributor license agreements.  See the NOTICE file distributed with
#  this work for additional information regarding copyright ownership.
#  The ASF licenses this file to You under the Apache License, Version 2.0
#  (the "License"); you may not use this file except in compliance with
#  the License.  You may obtain a copy of the License at
#
#       http://www.apache.org/licenses/LICENSE-2.0
#
#   Unless required by applicable law or agreed to in writing, software
#   distributed under the License is distributed on an "AS IS" BASIS,
#   WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
#   See the License for the specific language governing permissions and
#   limitations under the License.
###########
# DOCUMENTATION.
# This script is to be placed in the root of the svn dist checkout.
# For example, my directory looks like:
#
#   drwxr-xr-x@  8 usr  staff   256 Oct  1 11:22 .svn
#   -rw-r--r--@  1 usr  staff  1230 Oct  1 11:22 HEADER.html
#   -rw-r--r--@  1 usr  staff  2649 Oct  1 11:22 README.html
#   -rw-r--r--@  1 usr  staff  5093 Oct  1 11:22 RELEASE-NOTES.txt
#   drwxr-xr-x@ 10 usr  staff   320 Oct  1 11:22 binaries
#   -rw-r--r--@  1 usr  staff  3900 Oct  1 13:40 signature-validation.sh
#   drwxr-xr-x@ 44 usr  staff  1408 Oct  1 11:22 site
#   drwxr-xr-x@ 10 usr  staff   320 Oct  1 11:37 source
#
# From here you run ./signature-validation.sh and it will create a directory "artifacts-for-validation-deletable-post-validation
# in which all of the binaries generated by a release are copied and then it checks to see that all of the signatures and hashes
# are infact correct for the artifacts.
#
###########

if test "$#" != "1"
then
  echo "ERROR:"
  echo "We expect the a url like https://repository.apache.org/content/repositories/orgapachecommons-1531/commons-net/commons-net/3.7.1/"
  echo "to be passed in as a parameter to the script."
fi



BASEDIR="$( cd "$(dirname "$0")" >/dev/null 2>&1 ; pwd -P )"
VALIDATION_DIR=${BASEDIR}/artifacts-for-validation-deletable-post-validation
BINARIES_DIR=${BASEDIR}/binaries
SOURCE_DIR=${BASEDIR}/source

BASE_NEXUS_URL="$1"

function clean_and_build_validation_dir() {
	mkdir -p ${VALIDATION_DIR}
}

function copy_in_checked_out_artifacts() {
	cp ${BASEDIR}/binaries/commons* ${VALIDATION_DIR}
	cp ${BASEDIR}/source/commons* ${VALIDATION_DIR}
}

function download_nexus_artifacts_to_validation_directory() {
	# Curls html page and does text modification to put artifacts in semicolon delimited list
	# ...(ugly but works, debug by removing pipes one at a time)
	echo "INFO: Downloading artifacts from nexus"

  echo ${BASE_NEXUS_URL}
	NEXUS_ARTIFACTS=$(curl ${BASE_NEXUS_URL} \
	                       | grep "${BASE_NEXUS_URL}" \
	                       | cut -d '>' -f3 \
	                       | sed "s|</a|;|g" \
                         | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/ /g' \
                         | sed 's/ //g'
	                )
	IFS=';' read -r -a array <<< "${NEXUS_ARTIFACTS}"

	for element in "${array[@]}"
	do
		ARTIFACT_NAME=$(echo $element | cut -d '/' -f7)
		echo $ARTIFACT_NAME
		URL="${BASE_NEXUS_URL}${element}"
		curl $URL -o ${VALIDATION_DIR}/$ARTIFACT_NAME
	done
}

function validate_signatures() {
	echo "INFO: Validating Signatures in ${VALIDATION_DIR}"
	ALL_ARTIFACTS=$(ls -Al ${VALIDATION_DIR} \
	                                  | awk -F':[0-9]* ' '/:/{print $2}' \
                                    | sed -e ':a' -e 'N' -e '$!ba' -e 's/\n/;/g' \
	                         )

  ARTIFACTS_FOR_VALIDATION=()

  IFS=';' read -r -a array <<< "${ALL_ARTIFACTS}"

  for element in "${array[@]}"
  do
    if [[ ! (${element} =~ ^.*asc$ || ${element} =~ ^.*sha512$ || ${element} =~ ^.*md5$ || ${element} =~ ^.*sha1$) ]];
    then
      ARTIFACTS_FOR_VALIDATION=("${ARTIFACTS_FOR_VALIDATION[@]}" $element)
    fi
  done

	for element in "${ARTIFACTS_FOR_VALIDATION[@]}"
  do
    if [[ ${element} =~ ^.*tar.gz.*$ || ${element} =~ ^.*zip.*$ ]];
    then
      ARTIFACT_SHA512=$(openssl sha512 ${VALIDATION_DIR}/$element | cut -d '=' -f2 | cut -d ' ' -f2)
      FILE_SHA512=$(cut -d$'\r' -f1 ${VALIDATION_DIR}/$element.sha512)
      if test "${ARTIFACT_SHA512}" != "${FILE_SHA512}"
      then
        echo "$element failed sha512 check"
        echo "==${ARTIFACT_SHA512}=="
        echo "==${FILE_SHA512}=="
        exit 1;
      fi
    else
      ARTIFACT_MD5=$(openssl md5 ${VALIDATION_DIR}/$element | cut -d '=' -f2 | cut -d ' ' -f2)
      FILE_MD5=$(cut -d$'\r' -f1 ${VALIDATION_DIR}/$element.md5)
      ARTIFACT_SHA1=$(openssl sha1 ${VALIDATION_DIR}/$element | cut -d '=' -f2 | cut -d ' ' -f2)
      FILE_SHA1=$(cut -d$'\r' -f1 ${VALIDATION_DIR}/$element.sha1)
      if test "${ARTIFACT_MD5}" != "${FILE_MD5}"
      then
        echo "$element failed md5 check"
        echo "==${ARTIFACT_MD5}=="
        echo "==${FILE_MD5}=="
        exit 1;
      fi
      if test "${ARTIFACT_SHA1}" != "${FILE_SHA1}"
      then
        echo "$element failed sha1 check"
        echo "==${ARTIFACT_SHA1}=="
        echo "==${FILE_SHA1}=="
        exit 1;
      fi


      gpg --verify ${VALIDATION_DIR}/$element.asc ${VALIDATION_DIR}/$element > /dev/null 2>&1
      if test "$?" != "0"
      then
        echo "$element failed gpg signature check"
        exit 1;
      fi
    fi
  done

  echo "SUCCESSFUL VALIDATION"
}

function clean_up_afterwards() {
  rm -rf ${VALIDATION_DIR}
}


echo $(clean_and_build_validation_dir)
echo $(copy_in_checked_out_artifacts)
echo $(download_nexus_artifacts_to_validation_directory)
echo $(validate_signatures)
#clean_up_afterwards

