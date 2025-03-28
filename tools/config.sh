#!/bin/bash

IDF_COMPS="$IDF_PATH/components"

if [ -z $IDF_BRANCH ]; then
	IDF_BRANCH="v4.4_dev"
fi

if [ -z $AR_PR_TARGET_BRANCH ]; then
	AR_PR_TARGET_BRANCH="master"
fi

if [ -z $IDF_TARGET ]; then
	if [ -f sdkconfig ]; then
		IDF_TARGET=`cat sdkconfig | grep CONFIG_IDF_TARGET= | cut -d'"' -f2`
		if [ "$IDF_TARGET" = "" ]; then
			IDF_TARGET="esp32"
		fi
	else
		IDF_TARGET="esp32"
	fi
fi

IDF_TOOLCHAIN="xtensa-$IDF_TARGET-elf"

# Owner of the target ESP32 Arduino repository
AR_USER="tasmota"

# The full name of the repository
AR_REPO="$AR_USER/arduino-esp32"

# Arduino branch to use
AR_BRANCH="esp32-s3-support"

AR_REPO_URL="https://github.com/$AR_REPO.git"
if [ -n $GITHUB_TOKEN ]; then
	AR_REPO_URL="https://$GITHUB_TOKEN@github.com/$AR_REPO.git"
fi

AR_ROOT="$PWD"
AR_COMPS="$AR_ROOT/components"
AR_OUT="$AR_ROOT/out"
AR_TOOLS="$AR_OUT/tools"
AR_PLATFORM_TXT="$AR_OUT/platform.txt"
AR_ESPTOOL_PY="$AR_TOOLS/esptool.py"
AR_GEN_PART_PY="$AR_TOOLS/gen_esp32part.py"
AR_SDK="$AR_TOOLS/sdk/$IDF_TARGET"

function get_os(){
  	OSBITS=`arch`
  	if [[ "$OSTYPE" == "linux"* ]]; then
        if [[ "$OSBITS" == "i686" ]]; then
        	echo "linux32"
        elif [[ "$OSBITS" == "x86_64" ]]; then
        	echo "linux64"
        elif [[ "$OSBITS" == "armv7l" ]]; then
        	echo "linux-armel"
        else
        	echo "unknown"
	    	return 1
        fi
	elif [[ "$OSTYPE" == "darwin"* ]]; then
	    echo "macos"
	elif [[ "$OSTYPE" == "cygwin" ]] || [[ "$OSTYPE" == "msys" ]] || [[ "$OSTYPE" == "win32" ]]; then
	    echo "win32"
	else
	    echo "$OSTYPE"
	    return 1
	fi
	return 0
}

AR_OS=`get_os`

export SED="sed"
export SSTAT="stat -c %s"

if [[ "$AR_OS" == "macos" ]]; then
	export SED="gsed"
	export SSTAT="stat -f %z"
fi

function git_commit_exists(){ #git_commit_exists <repo-path> <commit-message>
	local repo_path="$1"
	local commit_message="$2"
	local commits_found=`git -C "$repo_path" log --all --grep="$commit_message" | grep commit`
	if [ -n "$commits_found" ]; then echo 1; else echo 0; fi
}

function git_branch_exists(){ # git_branch_exists <repo-path> <branch-name>
	local repo_path="$1"
	local branch_name="$2"
	local branch_found=`git -C "$repo_path" ls-remote --heads origin "$branch_name"`
	if [ -n "$branch_found" ]; then echo 1; else echo 0; fi
}

function git_pr_exists(){ # git_pr_exists <branch-name>
	local pr_num=`curl -s -k -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3.raw+json" "https://api.github.com/repos/$AR_REPO/pulls?head=$AR_USER:$1&state=open" | jq -r '.[].number'`
	if [ ! "$pr_num" == "" ] && [ ! "$pr_num" == "null" ]; then echo 1; else echo 0; fi
}

function git_create_pr(){ # git_create_pr <branch> <title>
	local pr_branch="$1"
	local pr_title="$2"
	local pr_target="$3"
	local pr_body=""
	for component in `ls "$AR_COMPS"`; do
		if [ ! $component == "arduino" ] && [ -d "$AR_COMPS/$component/.git" ]; then
			pr_body+="$component: "$(git -C "$AR_COMPS/$component" symbolic-ref --short HEAD)" "$(git -C "$AR_COMPS/$component" rev-parse --short HEAD)"\r\n"
		fi
	done
	local pr_data="{\"title\": \"$pr_title\", \"body\": \"$pr_body\", \"head\": \"$AR_USER:$pr_branch\", \"base\": \"$pr_target\"}"
	git_create_pr_res=`echo "$pr_data" | curl -k -H "Authorization: token $GITHUB_TOKEN" -H "Accept: application/vnd.github.v3.raw+json" --data @- "https://api.github.com/repos/$AR_REPO/pulls"`
	local done_pr=`echo "$git_create_pr_res" | jq -r '.title'`
	if [ ! "$done_pr" == "" ] && [ ! "$done_pr" == "null" ]; then echo 1; else echo 0; fi
}

