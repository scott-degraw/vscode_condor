#!/bin/bash

script_name="vscode_condor.sh"

########################################
##### SSH host
ssh_host=int12_base
##### Optional configurables
port=8080
condor_batch_name="vcs"
code_executable="/usr/bin/code --enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform-hint=auto"
client_user=$USER
submit_template_file=$(dirname $0)/template_submit_scripts/vscode_server.submit.template
submit_filename=$(basename $submit_template_file)
submit_filename=/tmp/${submit_filename%.*}
host_user=$(ssh $ssh_host 'echo $USER')
vscode_server_dir=/home/$host_user/.vscode-server
sleep_interval=0.5
########################################

set -u

usage_message="Usage: $script_name [-h | --help] [-p | --port] [-s | --ssh_host]"

options=$(getopt -o hp:s:n:b: --long help,port:,ssh_host:,batch_name: -n \'${script_name}\' -- "$@")

if [ $? -ne 0 ]; then
	echo $usage_message
	exit 1
fi

# Remove the annoying single quotes
options="${options//\'/}"

set -- $options

while [[ $# -gt 0 ]]; do
	case "$1" in
		-h|--help)
			echo $usage_message
			exit 0 ;;
		-p|--port)
			port="$2"
			shift 2 ;;
		-s|--ssh_host)
			ssh_host="$2"
			shift 2 ;;
		-b|--batch_name)
			condor_batch_name="$2"
			shift 2 ;;
		--)
			shift
			break ;;
		*)
			echo "Error with getopt. Exiting" >&2
			exit 1 ;;
	esac
done

code_hash=$($code_executable -v | sed -n '2p')

cp $submit_template_file $submit_filename
sed "s/<batch_name>/$condor_batch_name/g" -i $submit_filename
sed "s/<port>/$port/g" -i $submit_filename 
code_server_exe=$vscode_server_dir/cli/servers/Stable-$code_hash/server/bin/code-server
# We need to make this usable by sed through escaping 
code_server_exe=$(echo $code_server_exe | sed 's/\//\\\//g') 
sed "s/<code_server_executable>/$code_server_exe/g" -i $submit_filename

# If already running get job id
job_id=$(ssh $ssh_host "condor_q $host_user -format \"%s,\" JobBatchName -format \"%d.\" ClusterID -format \"%d\n\" ProcID" | grep $condor_batch_name -m1 | cut -d, -f 2)

# If not running create job
if [ -z "$job_id" ]; then
	tmp_submit_file=/tmp/$(basename $submit_filename)$(date +%s)
	scp $submit_filename $ssh_host:$tmp_submit_file
	job_id=$(ssh $ssh_host condor_submit $tmp_submit_file | grep -oP "(?<=cluster )\d+(?=\.)")

	# Wait until job starts
	while [[ $(ssh $ssh_host "condor_q $job_id -format \"%d\" JobStatus") != 2 ]]; do
		echo Waiting until condor job starts
		sleep $sleep_interval
	done
fi

# Check for condor_ssh_to_job already running. If not start ssh tunnel to job from login node.
function condor_ssh_tunnel_check() {
	ssh $ssh_host netstat -tulpn 2>&1 | grep -q 127.0.0.1:$port
	return $?
}

if ! condor_ssh_tunnel_check; then
	ssh $ssh_host "condor_ssh_to_job -auto-retry $job_id -NfL localhost:$port:localhost:$port" > /dev/null &
	condor_ssh_to_job_pid=$!
	while ! condor_ssh_tunnel_check; do
		sleep $sleep_interval
	done
	kill $condor_ssh_to_job_pid
fi

# Check for local tunnel to login node is running
function local_ssh_tunnel_check() {
	netstat -tulpn 2>&1 | grep -q 127.0.0.1:$port
	return $?
}

if ! local_ssh_tunnel_check; then
	ssh $ssh_host -NfL localhost:$port:localhost:$port
	while ! local_ssh_tunnel_check; do
		sleep $sleep_interval
	done
fi

# Finally, start vscode connecting to local tunnel 
$code_executable --remote localhost:$port 
