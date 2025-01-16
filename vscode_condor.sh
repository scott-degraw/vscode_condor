#!/bin/bash

########################################
##### SSH host
ssh_host=int12_base
##### Optional configurables
port=8080
condor_batch_name=vcs
code_executable=code
client_user=$USER
submit_template_file=$(dirname $0)/vscode_server.submit.template
submit_filename=$(basename $submit_template_file)
submit_filename=/tmp/${submit_filename%.*}
host_user=$(ssh $ssh_host 'echo $USER')
vscode_server_dir=/home/$host_user/.vscode-server
sleep_interval=0.5
########################################

code_hash=$($code_executable -v | sed -n '2p')

cp $submit_template_file $submit_filename
sed "s/<port>/$port/g" -i $submit_filename 
code_server_exe=$vscode_server_dir/cli/servers/Stable-$code_hash/server/bin/code-server
# We need to make this usable by sed through escaping 
code_server_exe=$(echo $code_server_exe | sed 's/\//\\\//g') 
sed "s/<code_server_executable>/$code_server_exe/g" -i $submit_filename

# If already running get job id
job_id=$(ssh $ssh_host "condor_q $host_user -format \"%s,\" JobBatchName -format \"%d.\" ClusterID -format \"%d\n\" ProcID" | grep $condor_batch_name -m1 | cut -d, -f 2)

# If not running create job
if [ -z "$job_id" ]; then
	tmp_submit_file=/tmp/$submit_filename_$(date +%s)
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
