#!/bin/bash

#set -x

###
# Copyright (c) 2018-2019 Sandeep Jangity
###

# ===================
# Simple bash enahancement to support deploying node github repos onto CentOS/Linode server.

# Change GIT_BASE_PATH appropriately.
# ===================

EXPECTED_ARGS=2
E_BADARGS=65

# load config
. `dirname $0`/config-$1.sh

function usage {
  echo "============================================================="
  echo "Usage: `basename $0` (dev|prod) (app-name) (module|sub-module) (secure)}"
  echo "app-name:        sandeepjangity.co"
  echo "module:          web"
  echo "sub-module:      admin, stats, ops, mobile"
  echo "secure:          true, false"
  echo ""
  echo "Usage Example: ./pull-new.sh prod sandeepjangity web|all peerflight.com"
  echo "============================================================="
}

# usage prompt
if [ $# -lt $EXPECTED_ARGS ]
then
    echo "============================================================="
    echo "ERROR: Unexpected argument count"

    usage
    exit $E_BADARGS
fi

# DEPLOY MODES
DEPLOY_MODE_DEV="dev"
DEPLOY_MODE_PROD="prod"

# MODULES
MODULE_WEB="web"

# param check and initialize
# deploy mode
DEPLOY_MODE=$1

# deploy app
DEPLOY_APPNAME=$2

# deploy app FQDN
DEPLOY_ROOT=$4

# deploy module or sub-module?
DEPLOY_MODULE=$3
if [[ -z $DEPLOY_MODULE ]]; then
    DEPLOY_MODULE="web"
fi
if [[ ("$DEPLOY_MODULE" != $MODULE_WEB) && ("$DEPLOY_MODULE" != $MODULE_STATS) && ("$DEPLOY_MODULE" != $MODULE_ADMIN) && ("$DEPLOY_MODULE" != $MODULE_OPS) && ("$DEPLOY_MODULE" != $MODULE_MOBILE) ]]; then
    echo "============================================================="
    echo "ERROR: Unexpected input"
    usage
    exit
fi

# secure mode?
SECURE_MODE=true
#if [[ $4 = 0 ]]; then
#	SECURE_MODE=false
#fi

# skip pass
SKIP_PASS=0

# base variables needed for deployment
DEPLOY_PATH=/web/$DEPLOY_ROOT/$DEPLOY_MODE
TMP_DEPLOY_PATH=/web/tools/current
GLOBAL_DEPLOY_PATH=$DEPLOY_PATH
DEPLOY_DIR=$DEPLOY_PATH
GLOBAL_DEPLOY_DIR=$DEPLOY_PATH

# git base path
GIT_BASE_PATH=https://github.com/sjangity/$DEPLOY_APPNAME.git

# create tmp deploy path for git checkouts
if [ -d $TMP_DEPLOY_PATH ]; then
    echo "Deleting old release temp dir..."
    rm -rf $TMP_DEPLOY_PATH
    mkdir $TMP_DEPLOY_PATH
else
	echo "Creating new release temp dir..."
    mkdir $TMP_DEPLOY_PATH
fi

# create base deploy dir or log, if none exists
if [[ $DEPLOY_MODE = $DEPLOY_MODE_DEV ]]; then
	DEPLOY_PATH=/home/sandeep/code
	DEPLOY_DIR=$DEPLOY_PATH/$DEPLOY_MODE-$DEPLOY_APPNAME	

	if [ ! -d $GLOBAL_DEPLOY_DIR ]; then
		echo "Creating $GLOBAL_DEPLOY_DIR directory"
		mkdir -p $GLOBAL_DEPLOY_DIR 
	fi
else
	if [ ! -d $GLOBAL_DEPLOY_DIR/logs ]
	then
		echo "Creating $GLOBAL_DEPLOY_DIR/logs directory"
		mkdir -p $GLOBAL_DEPLOY_DIR/logs
		chmod 777 $GLOBAL_DEPLOY_DIR/logs
	fi
fi

# get GIT version (web+stats)
GIT_WEB_VERSION=`git ls-remote $GIT_BASE_PATH HEAD | head -1 | sed "s/\tHEAD//"`
if [[ $DEPLOY_MODE = $DEPLOY_MODE_DEV ]]; then
	RELEASE_WEB_DIR=$DEPLOY_DIR
else
	RELEASE_WEB_DIR=$DEPLOY_DIR/web/archive/$GIT_WEB_VERSION
fi

RELEASE_ASSET_DIR='/static/'$DEPLOY_APPNAME-$DEPLOY_MODE'/archive/'$GIT_WEB_VERSION
RELEASE_UPLOAD_DIR='/static/'$DEPLOY_APPNAME-$DEPLOY_MODE'/uploads'


# ===================
# STANDARD FUNCTIONS

function create_all_release_dirs {
    create_web_dir
}

function create_web_dir {
    # create release web dir
    if [ ! -d $RELEASE_WEB_DIR ]; then
        echo "Creating ${RELEASE_WEB_DIR} directory"
        mkdir -p $RELEASE_WEB_DIR
    else
        echo "RE-CREATING ${RELEASE_WEB_DIR} directory"
        rm -rf $RELEASE_WEB_DIR
        mkdir -p $RELEASE_WEB_DIR
    fi
}

function release_module {
    # build-deploy-release web
    if [[ $DEPLOY_MODE = $DEPLOY_MODE_DEV ]]; then
        pushd $DEPLOY_DIR >&2 > /dev/null
    else
        pushd $DEPLOY_DIR/web >&2 > /dev/null
    fi
            echo "Building web release..."
            if [[ $DEPLOY_MODE = $DEPLOY_MODE_DEV ]]; then
                rsync -a $TMP_DEPLOY_PATH/* $RELEASE_WEB_DIR >&2 > /dev/null
            else
                rsync -a $TMP_DEPLOY_PATH/code/ $RELEASE_WEB_DIR >&2 > /dev/null
            fi

			echo "Compiling package.json..."
			pushd $RELEASE_WEB_DIR >&2 /dev/null
				# build node_modules in package.json
				npm i

				# generate compiled static site (assumes /dist)
				npm run build	
			popd

			pushd $GLOBAL_DEPLOY_DIR >&2 > /dev/null

                # release
				echo "Setting symlinks..."
                if [ -d $DEPLOY_MODE-$DEPLOY_APPNAME-latest ]; then
                    rm $DEPLOY_MODE-$DEPLOY_APPNAME-latest
                fi
				rm web-latest
                if [[ $DEPLOY_MODE = $DEPLOY_MODE_DEV ]]; then
					# nothing here
					echo "release to dev..."
                else
                    # used by any sub-modules referencing the core web module (eg. mobile api relies on core web module)
                    ln -s $RELEASE_WEB_DIR web-latest
                fi

			popd

        popd >&2 > /dev/null
}

echo "*************************************"
echo "Target: ${1}"
echo "Application: ${2}"
echo "Deploy Path: ${DEPLOY_PATH}"
if [[ $DEPLOY_MODULE = "web" ]]; then
	echo "GIT Release Head: ${GIT_WEB_VERSION}"
	echo ""
	echo "Temp Build Path: ${TMP_DEPLOY_PATH}"
	echo "Release Module: $DEPLOY_MODULE"
	echo "Release web path: ${RELEASE_WEB_DIR}"
	echo "Release asset path: ${RELEASE_ASSET_DIR}"
fi
echo "*************************************"

# create release in temp dir
pushd $TMP_DEPLOY_PATH >&2 > /dev/null
echo "Cloning repo: git clone --branch master --single-branch $GIT_BASE_PATH ."
git clone --branch master --single-branch $GIT_BASE_PATH .
    if [[ $DEPLOY_MODULE = $MODULE_WEB ]]; then
        # release all modules AND sub-modules
        create_all_release_dirs
        release_module web
    fi
popd >&2 > /dev/null

