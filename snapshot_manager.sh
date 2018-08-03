#!/bin/bash


function print_help()
{
	cat <<-EOF
		aws_script v0.1

Usage: aws_script <option>

Options:
-y/--year x             Delete older than x years
-m/--month x            Delete older than x months
-d/--day x              Delete older than x days
-v/--volume             Select spesific volume
-h/--help               Show help menu
-l/--logfile            Select logfile location

Example:	./snapshot_manager.sh --volume --day 7 --logfile ~/snapshots_manager.log
	EOF
	exit 1
}

function arguments()
{
	if [[ $# < 2 ]]; then
		print_help
	fi

	while [[ $# != 0 ]]; do
		case $1 in
		    -y | --year)
		    x_time=$2
		    t_type="year"
		    shift; shift;;
		    -m | --month)
		    x_time=$2
		    t_type="month"
		    shift; shift;;
		    -d | --day)
		    x_time=$2
		    t_type="day"
		    shift; shift;;
		    -l | --logfile)
			logfile=$2
		    shift; shift;;
		    -v | --volume)
		    volume=1
		    shift;;
		    -h | --help)
		    print_help
		    shift;;
		    *)
			print_help;;
		esac
	done
}

function create_log_file()
{
	if [ ! -e "$logfile" ]; then
	    touch "$logfile" || { echo "ERROR: check root or sudo permission!"; exit 1; }
	fi
	date >> $logfile || { echo "ERROR: Cannot write to $logfile check root or sudo permission!"; exit 1; }
}

function check_requirments()
{
	if  ! command -v aws &> /dev/null; then
		echo "aws cli must be installed on your system. type: sudo apt install awscli"; exit 1
	fi
}

function check_aws_credential()
{
	status=$(aws sts get-caller-identity)
	if [[ $? != 0 ]]; then
		exit 1
	fi
}

function get_volume_list()
{
	if [[ $volume == 1 ]]; then
		echo "---Volume List---"
		aws ec2 describe-volumes --query 'Volumes[*].{ID:VolumeId,Size:Size,Tag:Tags}' --output table
		echo "-----------------"
		read -p "Enter VolumeId: " volume_id
		echo -e "\nSelected VolumeId: $volume_id\n" >> $logfile
	fi
}


remove_old_snapshots()
{
	echo -e "\n..."
	x_time_ago=$(date +%s --date "$x_time $t_type ago")
	if [[ $volume_id != "" ]]; then				# with --volume parameter
		snapshot_list=$(aws ec2 describe-snapshots --output=text --filters "Name=volume-id,Values=$volume_id" --query Snapshots[].SnapshotId)
		for snapshot in $snapshot_list; do
			snapshot_date=$(aws ec2 describe-snapshots --output=text --snapshot-ids $snapshot --query Snapshots[].StartTime | awk -F "T" '{printf "%s\n", $1}')
			snapshot_time=$(date "--date=$snapshot_date" +%s)
			snapshot_description=$(aws ec2 describe-snapshots --snapshot-id $snapshot --query Snapshots[].Description)
			if (( $snapshot_time <= $x_time_ago )); then
				echo  "DELETING snapshot $snapshot. Description: $snapshot_description"|tee -a $logfile
				aws ec2 delete-snapshot --snapshot-id $snapshot
			else
				echo  "Not deleting snapshot $snapshot. Description: $snapshot_description Snapshot Date: $snapshot_date"|tee -a $logfile
			fi
		done
	else										# all snapshots
		owner_id=$(aws sts get-caller-identity|grep -m1 -oP '"Account"\s*:\s*"\K[^"]+')
		echo -e "\nSelected OwnerId: $owner_id\n"|tee -a $logfile
		snapshot_list=$(aws ec2 describe-snapshots --output=text --filters "Name=owner-id,Values=$owner_id" --query Snapshots[].SnapshotId)
		for snapshot in $snapshot_list; do
			snapshot_date=$(aws ec2 describe-snapshots --output=text --snapshot-ids $snapshot --query Snapshots[].StartTime | awk -F "T" '{printf "%s\n", $1}')
			snapshot_time=$(date "--date=$snapshot_date" +%s)
			snapshot_description=$(aws ec2 describe-snapshots --snapshot-id $snapshot --query Snapshots[].Description)
			if (( $snapshot_time <= $x_time_ago )); then
				echo "DELETING snapshot $snapshot. Description: $snapshot_description"|tee -a $logfile
				aws ec2 delete-snapshot --snapshot-id $snapshot
			else
				echo "Not deleting snapshot $snapshot. Description: $snapshot_description Snapshot Date: $snapshot_date"|tee -a $logfile
			fi
		done
	fi
}
logfile="/dev/null"			# if user pass
arguments $*
create_log_file
check_requirments
check_aws_credential
get_volume_list
remove_old_snapshots
echo "----------------------------------------------------------------------------------------------------" >> $logfile
echo -e "\nsaved $logfile"