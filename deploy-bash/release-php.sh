#!/bin/bash

###
# Copyright (c) 2018-2019 Sandeep Jangity
###

# ===================
# Shell script can be used to deploy github code to a VPS hosting multiple dev-staging-prod environments/applications in under 2-3 seconds. 
# It is intended to be run in a server-env you control. Please make sure to have the system permissions properly defined. 
# This is a primitive deployment mechanism and is not intended for high-throughput pipelines. However, it is an 
# excellent strategy for proof-of-concept development and early stage product development with a few team members.

# We need to understand two directory structures: Github Project Structure and Deployment Structure

# Github (PHP) Project structure assumed is as follows with one main module and 1+ sub-modules.
# Main Module - Has code associated with the main application
# Sub-module - Represents sub-artificats that aid in management of main module including internal OPS-pages, ADMIN-pages, QA-pages, STATS-pages, etc.,
# /server/web/
#           /protected
#           /public/www

# Example of a sub-module:
# /server/admin/
#           /protected
#           /public/www
# etc.,

# The Deployment Structure (for staging-prod) assumes:
#           /web/<docroot>/module-or-submodule-latest <-- symlink to latest rel/patch below
#           /web/archive/<git-hash>/public/www

#           /web/<docroot>/static-latest <-- symlink to assets (JS/CSS/*images*) rel/patch below
#           /static/archive/<git-hash>/public/www/assets/

# The Deployment Structure (for dev) assumes:
#           /web/<docroot>/dev-latest <-- symlink to latest rel/patch
#           /home/<dev>/<app>

# Additionaly:
#   Following sub-modules are supported (admin/stats/ops/mobile)
#   Web push will push all sub-modules as they are assumed to share lib dependency on web-codebase

# No warranty provided.
# ===================

EXPECTED_ARGS=2
E_BADARGS=65

# load config
. `dirname $0`/config-$1.sh

function usage {
  echo "============================================================="
  echo "Usage: `basename $0` (dev|staging|prod) (app-name) (module|sub-module) (secure)}"
  echo "app-name:        [appname]"
  echo "module:          web"
  echo "sub-module:      admin, stats, ops, mobile"
  echo "secure:          true, false"
  echo ""
  echo "Usage Example: ./release.sh prod [appname] admin [app-docroot]"
  echo "Usage Example: ./release.sh prod [appname] stats [app-docroot]"
  echo "Usage Example: ./release.sh prod [appname] ops [app-docroot]"
  echo "Usage Example: ./release.sh prod [appname] mobile [app-docroot]"
  echo "Usage Example: ./release.sh prod [appname] web|all [app-docroot]"
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
DEPLOY_MODE_STAGING="staging"
DEPLOY_MODE_PROD="prod"

# MODULES
MODULE_WEB="web"
MODULE_STATS="stats"
MODULE_ADMIN="admin"
MODULE_OPS="ops"
MODULE_MOBILE="mobile"

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

# skip pass
SKIP_PASS=0

# base variables needed for deployment
DEPLOY_PATH=/web/$DEPLOY_ROOT/$DEPLOY_MODE
TMP_DEPLOY_PATH=/web/tools/current
GLOBAL_DEPLOY_PATH=$DEPLOY_PATH
DEPLOY_DIR=$DEPLOY_PATH
GLOBAL_DEPLOY_DIR=$DEPLOY_PATH

# git base path
GIT_BASE_PATH=https://github.com/<name>/$DEPLOY_APPNAME.git

# create tmp deploy path for git checkouts
if [ -d $TMP_DEPLOY_PATH ]; then
    echo "Deleting old release dir..."
    rm -rf $TMP_DEPLOY_PATH
else
    mkdir $TMP_DEPLOY_PATH
fi

# create base deploy dir or log, if none exists
if [[ $DEPLOY_MODE = $DEPLOY_MODE_DEV ]]; then
	DEPLOY_PATH=/home/<user>/code
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

# setup other env release path variables
GIT_STATS_VERSION=$GIT_WEB_VERSION
GIT_OPS_VERSION=$GIT_WEB_VERSION
GIT_ADMIN_VERSION=$GIT_WEB_VERSION
GIT_MOBILE_VERSION=$GIT_WEB_VERSION
if [[ $DEPLOY_MODE = $DEPLOY_MODE_DEV ]]; then
	RELEASE_STATS_DIR=$DEPLOY_DIR
	RELEASE_OPS_DIR=$DEPLOY_DIR
	RELEASE_ADMIN_DIR=$DEPLOY_DIR
    RELEASE_MOBILE_DIR=$DEPLOY_DIR
else
	RELEASE_STATS_DIR=$DEPLOY_DIR/stats/archive/$GIT_STATS_VERSION
	RELEASE_OPS_DIR=$DEPLOY_DIR/ops/archive/$GIT_OPS_VERSION
	RELEASE_ADMIN_DIR=$DEPLOY_DIR/admin/archive/$GIT_ADMIN_VERSION
    RELEASE_MOBILE_DIR=$DEPLOY_DIR/mobile/archive/$GIT_MOBILE_VERSION
fi
RELEASE_ASSET_DIR='/static/'$DEPLOY_APPNAME-$DEPLOY_MODE'/archive/'$GIT_WEB_VERSION
RELEASE_UPLOAD_DIR='/static/'$DEPLOY_APPNAME-$DEPLOY_MODE'/uploads'

# ===================
# STANDARD FUNCTIONS
# ===================

function create_all_release_dirs {
    create_web_dir
    create_stats_dir
    create_admin_dir
    create_ops_dir
    create_mobile_dir
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

	# create release asset dir
	if [ ! -d $RELEASE_ASSET_DIR ]
	then
        echo "Creating ${RELEASE_ASSET_DIR} directory"
        mkdir -p $RELEASE_ASSET_DIR
	else
        echo "RE-CREATING ${RELEASE_ASSET_DIR} directory"
        rm -rf $RELEASE_ASSET_DIR
        mkdir -p $RELEASE_ASSET_DIR
	fi
}

function create_stats_dir {
	# create release stats dir
	if [[ $DEPLOY_MODE != $DEPLOY_MODE_DEV ]]; then
		if [ ! -d $RELEASE_STATS_DIR ]
		then
			echo "Creating ${RELEASE_STATS_DIR} directory"
			mkdir -p $RELEASE_STATS_DIR
		else
			echo "RE-CREATING ${RELEASE_STATS_DIR} directory"
			rm -rf $RELEASE_STATS_DIR
			mkdir -p $RELEASE_STATS_DIR
		fi
	fi
}

function create_admin_dir {
	# create release admin dir
	if [[ $DEPLOY_MODE != $DEPLOY_MODE_DEV ]]; then
        if [ ! -d $RELEASE_ADMIN_DIR ]
        then
                echo "Creating ${RELEASE_ADMIN_DIR} directory"
                mkdir -p $RELEASE_ADMIN_DIR
        else
                echo "RE-CREATING ${RELEASE_ADMIN_DIR} directory"
                rm -rf $RELEASE_ADMIN_DIR
                mkdir -p $RELEASE_ADMIN_DIR
        fi
	fi
}

function create_ops_dir {
	# create release ops dir
	if [[ $DEPLOY_MODE != $DEPLOY_MODE_DEV ]]; then
        if [ ! -d $RELEASE_OPS_DIR ]
        then
                echo "Creating ${RELEASE_OPS_DIR} directory"
                mkdir -p $RELEASE_OPS_DIR
        else
                echo "RE-CREATING ${RELEASE_OPS_DIR} directory"
                rm -rf $RELEASE_OPS_DIR
                mkdir -p $RELEASE_OPS_DIR
        fi
	fi
}

function create_mobile_dir {
	# create release ops dir
	if [[ $DEPLOY_MODE != $DEPLOY_MODE_DEV ]]; then
        if [ ! -d $RELEASE_MOBILE_DIR ]
        then
                echo "Creating ${RELEASE_MOBILE_DIR} directory"
                mkdir -p $RELEASE_MOBILE_DIR
        else
                echo "RE-CREATING ${RELEASE_MOBILE_DIR} directory"
                rm -rf $RELEASE_MOBILE_DIR
                mkdir -p $RELEASE_MOBILE_DIR
        fi
	fi
}

function pass_unlock {
    PASS_DIR=$1

    # restore pass
    if [[ $SKIP_PASS != 1 ]]; then
        # specific pass unlock for APPS
        if [[ $DEPLOY_APPNAME = "example.com" ]]; then
            if [[ $DEPLOY_MODULE = $MODULE_STATS || $DEPLOY_MODULE = $MODULE_OPS || $DEPLOY_MODULE = $MODULE_MOBILE ]]; then
                echo ">> Pass unlock $DEPLOY_MODULE sub-module"
                PASS_APP_DB=`cat $SECRET_PATH/.private | grep "$DEPLOY_APPNAME $DEPLOY_MODULE PASS-APP-DB" | awk  ' { print $4 } '`
                sed -i -e "s/PASS-APP-DB/$PASS_APP_DB/g" $PASS_DIR
            elif [[ $DEPLOY_MODULE = $MODULE_WEB || $DEPLOY_MODULE = $MODULE_ADMIN ]]; then
                echo ">> Pass unlock $DEPLOY_MODULE module"
                PASS_APP_DB=`cat $SECRET_PATH/.private | grep "$DEPLOY_APPNAME $DEPLOY_MODULE PASS-APP-DB" | awk ' { print $4 } '`
                PASS_APP_ADMIN_DB=`cat $SECRET_PATH/.private | grep "$DEPLOY_APPNAME $DEPLOY_MODULE PASS-APP-ADMIN-DB" | awk ' { print $4 } '`
                PASS_DB_ADMIN=`cat $SECRET_PATH/.private | grep "$DEPLOY_APPNAME $DEPLOY_MODULE PASS-DB-ADMIN" | awk ' { print $4 } '`
                if [ -n $PASS_APP_DB ]; then
                    sed -i -e "s/PASS-APP-DB/$PASS_APP_DB/g" $PASS_DIR
                fi
                if [ -n $PASS_APP_ADMIN_DB ]; then
                    sed -i -e "s/PASS-APP-ADMIN-DB/$PASS_APP_ADMIN_DB/g" $PASS_DIR
                fi
                if [ -n $PASS_DB_ADMIN ]; then
                    sed -i -e "s/PASS-DB-ADMIN/$PASS_DB_ADMIN/g" $PASS_DIR
                fi

                # add tests to verify the credentials of the db systems
            fi
        fi
    fi
}

function release_module {
    # build-deploy-release web
    if [[ $DEPLOY_MODE = $DEPLOY_MODE_DEV ]]; then
        pushd $DEPLOY_DIR >&2 > /dev/null
    else
        pushd $DEPLOY_DIR/web >&2 > /dev/null
    fi
            # build-deploy
            echo "Building web release..."
            if [[ $DEPLOY_MODE = $DEPLOY_MODE_DEV ]]; then
                cp -R $TMP_DEPLOY_PATH/* $RELEASE_WEB_DIR >&2 > /dev/null
            else
                cp -R $TMP_DEPLOY_PATH/server/web/* $RELEASE_WEB_DIR >&2 > /dev/null
            fi

            # password unlock
            if [[ $DEPLOY_MODE != $DEPLOY_MODE_PROD ]]; then
                if [[ $DEPLOY_MODE = $DEPLOY_MODE_DEV ]]; then
                    cp $RELEASE_WEB_DIR/server/web/protected/config/local-$DEPLOY_MODE.inc.php $RELEASE_WEB_DIR/server/web/protected/config/local.inc.php
                    CONFIG_DIR=$RELEASE_WEB_DIR/server/web/protected/config/env.inc.php
                else
                    cp $RELEASE_WEB_DIR/protected/config/local-$DEPLOY_MODE.inc.php $RELEASE_WEB_DIR/protected/config/local.inc.php
                    CONFIG_DIR=$RELEASE_WEB_DIR/protected/config/env.inc.php
                fi
            else
                CONFIG_DIR=$RELEASE_WEB_DIR/protected/config/env.inc.php
            fi
            pass_unlock $CONFIG_DIR

            pushd $GLOBAL_DEPLOY_DIR >&2 > /dev/null
                # migrate assets to asset partition
                if [[ $DEPLOY_MODE = $DEPLOY_MODE_DEV ]]; then
                    echo ">> ignoring moving assets in dev mode"
                    #mv $RELEASE_WEB_DIR/server/web/public/www/assets/* $RELEASE_ASSET_DIR/
                else
                    mv $RELEASE_WEB_DIR/public/www/assets/* $RELEASE_ASSET_DIR/
                fi

                # update upload asset ref in release
                if [ ! -d $RELEASE_UPLOAD_DIR ]; then
                    mkdir -p $RELEASE_UPLOAD_DIR
                    chmod 777 $RELEASE_UPLOAD_DIR
                fi

                # release
                if [ -d $DEPLOY_MODE-$DEPLOY_APPNAME-latest ]; then
                    rm $DEPLOY_MODE-$DEPLOY_APPNAME-latest
                    rm assets-$DEPLOY_MODE-$DEPLOY_APPNAME-latest
                    rm cron-web-$DEPLOY_MODE-$DEPLOY_APPNAME-latest
                    rm web-latest
                fi
                if [[ $DEPLOY_MODE = $DEPLOY_MODE_DEV ]]; then
                    ln -s $RELEASE_WEB_DIR/server/web/public/www $DEPLOY_MODE-$DEPLOY_APPNAME-latest
                    ln -s $RELEASE_WEB_DIR/server/web/public/www/assets assets-$DEPLOY_MODE-$DEPLOY_APPNAME-latest
                    ln -s $RELEASE_WEB_DIR/server/web/protected/scripts/console cron-web-$DEPLOY_MODE-$DEPLOY_APPNAME-latest
                else

                    # used by any sub-modules referencing the core web module (eg. mobile api relies on core web module)
                    ln -s $RELEASE_WEB_DIR web-latest

                    # other symlinks
                    ln -s $RELEASE_WEB_DIR/public/www $DEPLOY_MODE-$DEPLOY_APPNAME-latest
                    ln -s $RELEASE_ASSET_DIR assets-$DEPLOY_MODE-$DEPLOY_APPNAME-latest
                    ln -s $RELEASE_WEB_DIR/protected/scripts/console cron-web-$DEPLOY_MODE-$DEPLOY_APPNAME-latest
                    ln -s $RELEASE_UPLOAD_DIR $RELEASE_ASSET_DIR/uploads
                fi
            popd >&2 > /dev/null
        popd >&2 > /dev/null

    if [[ $DEPLOY_MODULE == $MODULE_WEB ]]; then
        # doing a web release, updates all sub-modules as well
        release_sub_module admin
        release_sub_module stats
        release_sub_module ops
        release_sub_module mobile
    fi
}

function release_sub_module {
    GLOBAL_DEPLOY_MODULE=$DEPLOY_MODULE

    # support for deploy sub-module independtly from other modules
    if [ $1 != 0 ]; then
        DEPLOY_MODULE=$1
    fi

    echo ""
    
    if [ $DEPLOY_MODULE = $MODULE_STATS ]; then
        MODULE_RELEASE_DIR=$RELEASE_STATS_DIR
    elif [ $DEPLOY_MODULE = $MODULE_ADMIN ]; then
        MODULE_RELEASE_DIR=$RELEASE_ADMIN_DIR
    elif [ $DEPLOY_MODULE = $MODULE_OPS ]; then
        MODULE_RELEASE_DIR=$RELEASE_OPS_DIR
    elif [ $DEPLOY_MODULE = $MODULE_MOBILE ]; then
        MODULE_RELEASE_DIR=$RELEASE_MOBILE_DIR
    fi

    # build-deploy-release sub-modules
    if [[ $DEPLOY_MODE = $DEPLOY_MODE_DEV ]]; then
        pushd $DEPLOY_DIR >&2 > /dev/null
    else
        pushd $DEPLOY_DIR/$DEPLOY_MODULE >&2 > /dev/null
    fi
        # build-deploy
        echo "Building $DEPLOY_MODULE release..."
        if [[ $DEPLOY_MODE != $DEPLOY_MODE_DEV ]]; then
            cp -R $TMP_DEPLOY_PATH/server/$DEPLOY_MODULE/* $MODULE_RELEASE_DIR >&2 > /dev/null
        fi

        # password unlock
        if [[ $DEPLOY_MODE != $DEPLOY_MODE_PROD ]]; then
            if [[ $DEPLOY_MODE = $DEPLOY_MODE_DEV ]]; then
                CONFIG_DIR=$MODULE_RELEASE_DIR/server/$DEPLOY_MODULE/protected/config/local.inc.php
                cp $MODULE_RELEASE_DIR/server/$DEPLOY_MODULE/protected/config/local-$DEPLOY_MODE.inc.php $CONFIG_DIR
            else
                CONFIG_DIR=$MODULE_RELEASE_DIR/protected/config/local.inc.php
                cp $MODULE_RELEASE_DIR/protected/config/local-$DEPLOY_MODE.inc.php $CONFIG_DIR
            fi
        else
            CONFIG_DIR=$MODULE_RELEASE_DIR/protected/config/env.inc.php
        fi
        pass_unlock $CONFIG_DIR

        pushd $GLOBAL_DEPLOY_DIR >&2 > /dev/null
            if [ $DEPLOY_MODULE = $MODULE_STATS ]; then
                # release
                if [ -h stats-api-$DEPLOY_APPNAME-latest ]; then
                    rm stats-$DEPLOY_APPNAME-latest
                    rm stats-api-$DEPLOY_APPNAME-latest
                    rm stats-admin-$DEPLOY_APPNAME-latest
                    rm cron-stats-$DEPLOY_APPNAME-latest
                fi
                if [[ $DEPLOY_MODE = $DEPLOY_MODE_DEV ]]; then
                    ln -s $RELEASE_STATS_DIR/server/stats/public/www stats-$DEPLOY_APPNAME-latest
                    ln -s $RELEASE_STATS_DIR/server/stats/public/www/admin stats-admin-$DEPLOY_APPNAME-latest
                    ln -s $RELEASE_STATS_DIR/server/stats/public/www/api stats-api-$DEPLOY_APPNAME-latest
                    ln -s $RELEASE_STATS_DIR/server/stats/protected/scripts cron-stats-$DEPLOY_APPNAME-latest
                else
                    ln -s $RELEASE_STATS_DIR/public/www stats-$DEPLOY_APPNAME-latest
                    ln -s $RELEASE_STATS_DIR/public/www/admin stats-admin-$DEPLOY_APPNAME-latest
                    ln -s $RELEASE_STATS_DIR/public/www/api stats-api-$DEPLOY_APPNAME-latest
                    ln -s $RELEASE_STATS_DIR/protected/scripts cron-stats-$DEPLOY_APPNAME-latest
                fi
            elif [ $DEPLOY_MODULE = $MODULE_ADMIN ]; then
                # release
                if [ -h admin-$DEPLOY_APPNAME-latest ]; then
                    rm admin-$DEPLOY_APPNAME-latest
                fi
                if [[ $DEPLOY_MODE = $DEPLOY_MODE_DEV ]]; then
                    ln -s $RELEASE_ADMIN_DIR/server/admin/public/www admin-$DEPLOY_APPNAME-latest
                else
                    ln -s $RELEASE_ADMIN_DIR/public/www admin-$DEPLOY_APPNAME-latest
                fi
            elif [ $DEPLOY_MODULE = $MODULE_OPS ]; then
                # release
                if [ -h ops-$DEPLOY_APPNAME-latest ]; then
                    rm ops-$DEPLOY_APPNAME-latest
                fi
                if [[ $DEPLOY_MODE = $DEPLOY_MODE_DEV ]]; then
                    ln -s $RELEASE_OPS_DIR/server/ops/public/www ops-$DEPLOY_APPNAME-latest
                else
                    ln -s $RELEASE_OPS_DIR/public/www ops-$DEPLOY_APPNAME-latest
                fi
            elif [ $DEPLOY_MODULE = $MODULE_MOBILE ]; then
                # release
                if [ -h ops-$DEPLOY_APPNAME-latest ]; then
                    rm mobile-$DEPLOY_APPNAME-latest
                fi
                if [[ $DEPLOY_MODE = $DEPLOY_MODE_DEV ]]; then
                    ln -s $RELEASE_MOBILE_DIR/server/mobile/public/www mobile-$DEPLOY_APPNAME-latest
                else
                    ln -s $RELEASE_MOBILE_DIR/public/www mobile-$DEPLOY_APPNAME-latest
                fi
            fi
        popd >&2 > /dev/null
    popd >&2 > /dev/null

    # RESET global deploy module
    DEDPLOY_MODULE=$GLOBAL_DEPLOY_MODULE
}


echo "*************************************"
echo "Target: ${1}"
echo "Application: ${2}"
echo "Deploy Path: ${DEPLOY_PATH}"
if [[ $DEPLOY_MODULE = "web" ]]; then
	echo "GIT Release Head: ${GIT_WEB_VERSION}"
	echo ""
	echo "Release Module: $DEPLOY_MODULE"
	echo "Release web path: ${RELEASE_WEB_DIR}"
	echo "Release asset path: ${RELEASE_ASSET_DIR}"
	echo "Release stats path: ${RELEASE_STATS_DIR}"
	echo "Release admin path: ${RELEASE_ADMIN_DIR}"
	echo "Release ops path: ${RELEASE_OPS_DIR}"
	echo "Release mobile path: ${RELEASE_MOBILE_DIR}"
	echo "Release deploy dir: ${DEPLOY_DIR}"
	echo "Release global deploy dir: ${GLOBAL_DEPLOY_DIR}"
else
	echo ""
	echo "Release Module: $DEPLOY_MODULE"
		
	if [[ $DEPLOY_MODULE = $MODULE_ADMIN ]]; then
		echo "Release admin path: ${RELEASE_ADMIN_DIR}"
	elif [[ $DEPLOY_MODULE = $MODULE_STATS ]]; then
		echo "Release stats path: ${RELEASE_STATS_DIR}"
	elif [[ $DEPLOY_MODULE = $MODULE_OPS ]]; then
		echo "Release ops path: ${RELEASE_OPS_DIR}"
	elif [[ $DEPLOY_MODULE = $MODULE_MOBILE ]]; then
		echo "Release mobile path: ${RELEASE_MOBILE_DIR}"
	fi
fi
echo "*************************************"

# create release
pushd $TMP_DEPLOY_PATH >&2 > /dev/null
echo "Cloning repo: git clone --branch master --single-branch $GIT_BASE_PATH ."
git clone --branch master --single-branch $GIT_BASE_PATH .
    if [[ $DEPLOY_MODULE = $MODULE_WEB ]]; then
        # release all modules AND sub-modules
        create_all_release_dirs
        release_module web
    else
        # only pushing a sub-module
        if [[ $DEPLOY_MODULE = $MODULE_ADMIN ]]; then
            create_admin_dir
            release_sub_module admin
        elif [[ $DEPLOY_MODULE = $MODULE_STATS ]]; then
            create_stats_dir
            release_sub_module stats
        elif [[ $DEPLOY_MODULE = $MODULE_OPS ]]; then
            create_ops_dir
            release_sub_module ops
        elif [[ $DEPLOY_MODULE = $MODULE_MOBILE ]]; then
            create_mobile_dir
            release_sub_module mobile
        fi
    fi
popd >&2 > /dev/null

# any other script cleanups
rm -rf $TMP_DEPLOY_PATH
