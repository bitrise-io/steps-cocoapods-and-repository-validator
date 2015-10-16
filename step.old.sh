#!/bin/bash

THIS_SCRIPTDIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
source "${THIS_SCRIPTDIR}/_bash_utils/utils.sh"
source "${THIS_SCRIPTDIR}/_bash_utils/formatted_output.sh"


if [ -z "${source_root_path}" ]; then
  echo "# Error"
  write_section_start_to_formatted_output '* source_root_path input is missing'
  exit 1
fi
print_and_do_command_exit_on_error cd "${source_root_path}"

ruby "${THIS_SCRIPTDIR}/detect_xamarin.rb"
detect_xamarin_exit=$?
echo "detect_xamarin_exit: ${detect_xamarin_exit}"



# Handle xamarin project
go run ${THIS_SCRIPTDIR}/handle_xamarin_ios.go
handle_xamarin_ios_exit=$?
is_xamarin_ios_project=0
if [ ${handle_xamarin_ios_exit} -eq 0 ] ; then
  is_xamarin_ios_project=1
fi

is_podfile_found=0
if [ ${is_xamarin_ios_project} -eq 0 ] ; then
  # Update Cocoapods - if there's at least one Podfile
  podfile_find_out="$(find . -type f -iname 'Podfile' -not -path "*.git/*")"
  if [[ "${podfile_find_out}" != "" ]] ; then
    is_podfile_found=1
  else
    echo "*No Podfile found*"
  fi

  if [ ${is_podfile_found} -eq 1 ] ; then
    if [[ "${is_update_cocoapods}" != "false" ]] ; then
      print_and_do_command_exit_on_error bash "${THIS_SCRIPTDIR}/_steps-cocoapods-update/step.sh"
    else
      echo "*Skipping Cocoapods version update*"
    fi
  else
    echo "*Skipping CocoaPods update (No Podfile found)*"
  fi
fi


echo "# Gathering project configurations"
# create/cleanup ~/.schemes file
echo "" > ~/.schemes

if [ ! -z "${scan_only_branch}" ] ; then
  echo "*Scanning a single branch: ${scan_only_branch}*"
  branches_to_scan=("origin/${scan_only_branch}")
else
  echo "*Scanning all branches*"
  branches_to_scan=$(git branch -r | grep -v -- "->")
fi
echo " (i) branches_to_scan:"
echo "${branches_to_scan}"
for branch in ${branches_to_scan} ; do
  echo
  echo "==> Switching to branch: ${branch}"
  # remove every file before switch; except the .git folder
  print_and_do_command_exit_on_error find . -not -path '*.git/*' -not -path '*.git' -delete
  # remove the prefix "origin/" from the branch name
  branch_without_remote=$(printf "%s" "${branch}" | cut -c 8-)
  echo "Local branch: ${branch_without_remote}"
  # switch to branch
  GIT_ASKPASS=echo GIT_SSH="${THIS_SCRIPTDIR}/ssh_no_prompt.sh" git checkout -f "${branch_without_remote}"
  fail_if_cmd_error "Failed to checkout branch: ${branch_without_remote}"
  GIT_ASKPASS=echo GIT_SSH="${THIS_SCRIPTDIR}/ssh_no_prompt.sh" git submodule foreach git reset --hard
  fail_if_cmd_error "Failed to reset submodules"
  GIT_ASKPASS=echo GIT_SSH="${THIS_SCRIPTDIR}/ssh_no_prompt.sh" git submodule update --init --recursive
  fail_if_cmd_error "Failed to update submodules"

  echo "### Switching to branch: ${branch_without_remote}"

  if [ ${is_xamarin_ios_project} -eq 0 ] ; then
    if [ ${is_podfile_found} -eq 1 ] ; then
      export is_update_cocoapods="false" # if required it's already handled
      print_and_do_command_exit_on_error bash "${THIS_SCRIPTDIR}/_steps-cocoapods-install/run_pod_install.sh"
    fi
    print_and_do_command_exit_on_error bash "${THIS_SCRIPTDIR}/find_schemes.sh" "${branch_without_remote}"
  fi

  if [ ${is_xamarin_ios_project} -eq 1 ] ; then
    export __BRANCH__=${branch_without_remote}
    # Handle if xamarin project
    go run ${THIS_SCRIPTDIR}/handle_xamarin_ios.go
    handle_xamarin_ios_exit=$?
    if [ ${handle_xamarin_ios_exit} -ne 0 ] ; then
      echo "Xamarin failed on branch: ${branch}"
    fi
  fi

  echo "-> Finished on branch: ${branch}"
done

echo
if [ ! -z "${scan_result_submit_url}" ] ; then
  set -e
  echo " => Submitting scan results..."
  curl --fail -X POST --data-urlencode "api_token=${scan_result_submit_api_token}" --data-urlencode "scan_results=$(cat ~/.schemes)" "${scan_result_submit_url}"
else
  echo " => No scan_result_submit_url specified - skipping submit."
fi

echo
echo "DONE"

exit 0