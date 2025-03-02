# VSCode on Condor

A script for running and ssh'ing into a VSCode server as a Condor job to give a full VSCode environment on a compute node.
 Useful when login nodes lack sufficient compute or debugging code on specific hardware (e.g., GPUs) that are only available on compute nodes.

## Prerequisites

- `ssh` access to the Condor cluster
- `VSCode` installed on the local machine
- `autossh` installed (optional, for more reliable SSH tunnelling)
- A valid VSCode server installed on the cluster in `~/.vscode-server` with a version that matches the local version of VSCode. If you have ssh'ed into the login node before with VSCode, VSCode will have automatically installed it for you.

## Configuration

You can create a configuration file at `~/.config/vscode_condor_config` to override the default values. The configuration file can contain the following variables:

- `ssh_host`: The ssh host with a Condor batch system.
- `port`: The port that the tunnel and VSCode will use.
- `code_executable`: The path to the VSCode executable with any optional options.

Example configuration file:

   ```bash
   ssh_host=my_ssh_host
   port=8080
   code_executable="/usr/bin/code"
   ```

## Usage

Download the `vscode_condor` script or clone the repostiroy.

A Condor submit script needs to be supplied to the script.
The only requirement on the script is that it must contain the lines
`executable = $code_server_exe` and `arguments = <optional_args> $code_server_args`.
The submit script will be copied to the Condor cluster and the values of `$code_server_exe`
and `$code_server_args` will be substituted with the correct values.
Optionally, `<optional_args>` can be supplied.

   ```condor
   # example.submit

   batch_name = vcs
   output = out.log
   error = out.log
   log = interactive.log

   request_cpus = 2
   request_memory = 8GB

   executable = $code_server_exe
   arguments = $code_server_args
   ```

To start the VSCode session on the compute node:

```bash
./vscode_condor -s my_ssh_host example.submit
```

Other possible arguments can be found with `./vscode_condor --help`.

If connection is lost to the cluster temporarily, the tunnel will break.
The above command can be run again to restart the ssh tunnel without resubmitting the job.
The batch names of the running jobs are checked, and if a batch name matches the batch name in the submit script
another job will not be submitted.

The script performs the following:

1. Find the correct version of the VSCode server on the cluster to use
2. Take the submit file and substitute in correct values for `$code_server_exe` and `$code_server_args`  
3. Copy the submit file to the cluster and submit the job
4. Create an ssh tunnel to the job from the login node
5. Create a local ssh tunnel to the login node
6. Start VSCode through the local tunnel

## License

This project is licensed under the MIT License - see the LICENSE file for details.
