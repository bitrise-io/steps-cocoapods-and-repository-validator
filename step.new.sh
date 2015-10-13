#!/bin/bash

export THIS_SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${THIS_SCRIPTDIR}/_bash_utils/utils.sh"
source "${THIS_SCRIPTDIR}/_bash_utils/formatted_output.sh"

if [ -z "${source_root_path}" ]; then
	echo "source_root_path input is missing"
  exit 1
fi

export green='\e[32m'
export red="\e[31m"
export reset="\e[0m"

cd ${source_root_path}
if [ $? -ne 0 ]; then
  printf "${error}Failed to cd into ${source_root_path}${reset}"
  exit 1
fi

project_types=(
	"Xamarin",
	"iOS"
	)

project_type_detectors=(
	"${THIS_SCRIPTDIR}/detect_xamarin.rb"
	"${THIS_SCRIPTDIR}/ios.rb"
	)

if [ ! -z "${scan_only_branch}" ] ; then
	echo "Scanning only: ${scan_only_branch}"
  branches_to_scan=("origin/${scan_only_branch}")
else
  echo "Scanning all branches"
  branches_to_scan=$(git branch -r | grep -v -- "->")
fi

for branch in ${branches_to_scan} ; do
	echo ""
	echo "Switching to ${branch}..."

	# remove every file before switch; except the .git folder
	find . -not -path '*.git/*' -not -path '*.git' -delete
  
  # remove the prefix "origin/" from the branch name
  branch_without_remote=$(printf "%s" "${branch}" | cut -c 8-)
  export BRANCH=${branch_without_remote}

  # switch to branch
  GIT_ASKPASS=echo GIT_SSH="${THIS_SCRIPTDIR}/ssh_no_prompt.sh" git checkout -f "${branch_without_remote}"
  if [ $? -ne 0 ]; then
  	printf "${red}[ERR]${reset}\n"
  	printf "${red}Failed to checkout branch: ${branch_without_remote}${reset}\n"
  	exit 1
  fi

  GIT_ASKPASS=echo GIT_SSH="${THIS_SCRIPTDIR}/ssh_no_prompt.sh" git submodule foreach git reset --hard
  if [ $? -ne 0 ]; then
  	printf "${red}[ERR]${reset}\n"
  	printf "${red}Failed to reset submodules${reset}\n"
  	exit 1
  fi

  GIT_ASKPASS=echo GIT_SSH="${THIS_SCRIPTDIR}/ssh_no_prompt.sh" git submodule update --init --recursive
  if [ $? -ne 0 ]; then
  	printf "${red}[ERR]${reset}\n"
  	printf "${red}"Failed to update submodules"${reset}\n"
  	exit 1
  fi

  printf "${green}[OK]${reset}\n"

  echo ""
  echo "Running detection scripts"

  for i in ${!project_type_detectors[@]}; do
		ruby "${project_type_detectors[$i]}"

		if [ $? -ne 0 ]; then
			exit 1
		fi
	done

	# Cleanup vars
	export is_update_cocoapods="false" # if it was set to true, than we already updated it
done

