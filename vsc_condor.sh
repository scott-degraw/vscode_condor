#!/bin/bash

########################################
# configurables
ssh_host=int12_base
port=8080
condor_batch_name=vcs
host_user=degraw
client_user=$(whoami)
submit_template_file=code_server/vscode_server.submit.template
submit_filename=code_server/${submit_template_file%.*}
code_executable="/usr/bin/code --enable-features=UseOzonePlatform,WaylandWindowDecorations --ozone-platform-hint=auto"
########################################

vscode_server_dir=/home/$host_user/.vscode-server

code_hash=$($code_executable -v | sed -n '2p')

cp $submit_template_file $submit_filename
sed "s/<port>/$port/g" -i $submit_filename 
code_server_exe=$vscode_server_dir/cli/servers/Stable-$code_hash/server/bin/code-server
# We need to make this usable by sed through escaping 
code_server_exe=$(echo $code_server_exe | sed 's/\//\\\//g') 
sed "s/<code_server_executable>/$code_server_exe/g" -i $submit_filename

sleep_interval=0.5

# If already running get job id
job_id=$(ssh $ssh_host 'condor_q degraw -format "%s," JobBatchName -format "%d." ClusterID -format "%d\n" ProcID' | grep $condor_batch_name -m1 | cut -d, -f 2)

# If not running create job
if [ -z "$job_id" ]; then
	tmp_submit_file=/tmp/$submit_filename_$(date +%s)
	scp $submit_filename $ssh_host:$tmp_submit_file
	job_id=$(ssh $ssh_host condor_submit $tmp_submit_file | grep -oP "(?<=cluster )\d+(?=\.)")
fi

condor_ssh_tunnel_cmd="condor_ssh_to_job -auto-retry $job_id -NfL localhost:$port:localhost:$port"

function condor_ssh_tunnel_check() {
	#ssh $ssh_host "pgrep -f \"$condor_ssh_tunnel_cmd\"" > /dev/null
	ssh $ssh_host "pgrep -u $host_user -f \"condor_ssh_to_job\"" > /dev/null
	return $?
}

if ! condor_ssh_tunnel_check; then
	eval "ssh -f $ssh_host $condor_ssh_tunnel_cmd" > /dev/null
	while ! condor_ssh_tunnel_check; do
		sleep $sleep_interval
	done
fi

local_tunnel_cmd="ssh $ssh_host -NfL localhost:$port:localhost:$port"
if ! pgrep -u "$client_user" -f "$local_tunnel_cmd" > /dev/null; then
	eval $local_tunnel_cmd > /dev/null
	while ! pgrep -u "$client_user" -f "$local_tunnel_cmd" > /dev/null; do
		sleep $sleep_interval
	done
fi

sleep 2

#TODO need to figure out what kind of delay I need before executing
$code_executable --remote localhost:$port 
