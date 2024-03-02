#!/bin/bash

type(){
path=$1
if [ -d "$path" ]; then
	local type="directory"
	echo "$type"
elif [ -f "$path" ]; then
	local type="regular"
	echo "$type"
fi
}

get_metadata() {
	local relative=$1
	local path=$2
	
	type_and_permissions=$(stat $path | awk '/^Access:/{ perm=substr($2, 7, 10); print perm; }')
	type=${type_and_permissions:0:1}
	perm=${type_and_permissions:1:9}
	size=$(du -h $path | awk '{ print $1}')
	last_modification=$(stat -c %y $path)
	
	data="$relative $type $perm $size $last_modification"
	echo $data
}

get_relative_path() {
		tree="$1"
		path_file="$2"
		find $path_file > paths
		sed "s|$tree||g" paths > relative_paths
		relative=$(<relative_paths)
		echo "$relative"
		rm paths
		rm relative_paths
	}

#validates number of arguments
if [ "$#" -ne 3 ]; then
	echo "Error: three arguments are needed in order to execute the command"
	exit 1
fi

option="$1"
path_file1="$2"
path_file2="$3"

#checks if option is correct
case "$option" in
	keep-first | keep-second | keep-latest | keep-initial)
		#continues resolution
		;;
	*)
		echo "Error: Invalid resolution option. Supported options are keep-first, keep-second, keep-latest and keep-initial."
		exit 1
		;;
esac

#reads conflicts file to find the entry
conflict_entry=$(grep "^$path_file1 $path_file2" conflicts)

#checks if entry was found
if [ -z "$conflict_entry" ]; then
	echo "Error: No conflict found for the provided paths"
	exit 1
fi

#resolution
type1=$(type "$path_file1")
type2=$(type "$path_file2")

if [ "$type1" == "regular" ] && [ "$type2" == "regular" ]; then

	case "$option" in
	
		keep-first)
		cp -a "$path_file1" "$path_file2"
		success_flag=1
		kept_file="$path_file1"
		echo "Resolved conflict: keeping file from $path_file1"
		;;
		
		keep-second)
		cp -a "$path_file2" "$path_file1"
		success_flag=1
		kept_file="$path_file2"
		echo "Resolved conflict: keeping file from $path_file2"
		;;
		
		keep-latest)
		latest_file=$(ls -t "$path_file1" "$path_file2" | head -n 1)
		if [ "$latest_file" == "$path_file1" ]; then
			cp -a "$latest_file" "$path_file2"
		else
			cp -a "$latest_file" "$path_file1"
		fi
		success_flag=1
		kept_file="$latest_file"
		echo "Resolved conflict: keeping file from $latest_file"
		;;
		
		keep-initial)
		initial_file=$(ls -t "$path_file1" "$path_file2" | tail -n 1)
		if [ "$initial_file" == "$path_file1" ]; then
			cp -a "$initial_file" "$path_file2"
		else
			cp -a "$initial_file" "$path_file1"
		fi
		success_flag=1
		kept_file="$initial_file"
		echo "Resolved conflict: keeping file from $initial_file"
		;;
	esac
elif [ "$type1" == "directory" ] && [ "$type2" == "regular" ]; then

	case "$option" in
	
		keep-first)
		rm "$path_file2"
		cp -a "$path_file1" "$path_file2"
		success_flag=1
		kept_file="$path_file1"
		echo "Resolved conflict: keeping directory from $path_file1"
		;;
		
		keep-second)
		rm -r "$path_file1"
		cp -a "$path_file2" "$path_file1"
		success_flag=1
		kept_file="$path_file2"
		echo "Resolved conflict: keeping file from $path_file2"
		;;
		
		keep-latest)
		latest_file=$(stat -c '%Y %n' "$path_file1" "$path_file2" | sort -n | tail -n 1 | cut -d' ' -f2-)

		if [ "$latest_file" == "$path_file1" ]; then
			rm "$path_file2"
			cp -a "$latest_file" "$path_file2"
		else
			rm -r "$path_file1"
			cp -a "$latest_file" "$path_file1"
		fi
		success_flag=1
		kept_file="$latest_file"
		echo "Resolved conflict: keeping file from $latest_file"
		;;
		
		keep-initial)
		initial_file=$(stat -c '%Y %n' "$path_file1" "$path_file2" | sort -n | head -n 1 | cut -d' ' -f2-)
		
		if [ "$initial_file" == "$path_file1" ]; then
			rm "$path_file2"
			cp -a "$initial_file" "$path_file2"
		else
			rm -r "$path_file1"
			cp -a "$initial_file" "$path_file1"
		fi
		success_flag=1
		kept_file="$initial_file"
		echo "Resolved conflict: keeping file from $initial_file"
		;;
	esac
	
elif [ "$type1" == "regular" ] && [ "$type2" == "directory" ]; then
	
	case "$option" in
	
		keep-first)
		rm -r "$path_file2"
		cp -a "$path_file1" "$path_file2"
		success_flag=1
		kept_file="$path_file1"
		echo "Resolved conflict: keeping directory from $path_file1"
		;;
		
		keep-second)
		rm "$path_file1"
		cp -a "$path_file2" "$path_file1"
		success_flag=1
		kept_file="$path_file2"
		echo "Resolved conflict: keeping file from $path_file2"
		;;
		
		keep-latest)
		latest_file=$(stat -c '%Y %n' "$path_file1" "$path_file2" | sort -n | tail -n 1 | cut -d' ' -f2-)

		if [ "$latest_file" == "$path_file2" ]; then
			rm "$path_file1"
			cp -a "$latest_file" "$path_file1"
		else
			rm -r "$path_file2"
			cp -a "$latest_file" "$path_file2"
		fi
		success_flag=1
		kept_file="$latest_file"
		echo "Resolved conflict: keeping file from $latest_file"
		;;
		
		keep-initial)
		initial_file=$(stat -c '%Y %n' "$path_file1" "$path_file2" | sort -n | head -n 1 | cut -d' ' -f2-)
		
		if [ "$initial_file" == "$path_file2" ]; then
			rm "$path_file1"
			cp -a "$initial_file" "$path_file1"
		else
			rm -r "$path_file2"
			cp -a "$initial_file" "$path_file2"
		fi
		success_flag=1
		kept_file="$initial_file"
		echo "Resolved conflict: keeping file from $initial_file"
		;;
	esac
fi

#Conflicts file handling
if [ "$success_flag" == 1 ]; then
	escaped_conflict_entry=$(printf '%s\n' "$conflict_entry" | sed -e 's/[\/&]/\\&/g')
	sed -i "/^$escaped_conflict_entry/d" conflicts
	echo "Conflict resolved succesfully."

	#Journal file handling
	first_line=$(head -n 1 journal)
	if [ "$kept_file" == "$path_file1" ]; then
		tree=$(echo "$first_line" | awk '{print $1}')
		relative=$(get_relative_path $tree $path_file1)
		data=$(get_metadata $relative $path_file1)

	else
		tree=$(echo "$first_line" | awk '{print $2}')
		relative=$(get_relative_path $tree $path_file2)							
		data=$(get_metadata $relative $path_file2)

	fi

	entry=$(grep -h "^$relative" journal)
	if [ -n "$entry" ]; then
		sed -i -e "s|$entry|$data|" journal
		echo "Journal updated succesfully."
	else
		echo "$data" >> journal
		echo "Journal updated succesfully."
	fi	
	echo "The synchronization is done"
	
else
	echo "The resolution did not succeed."
fi

#Feedback
if [ -s conflicts ]; then
	echo "The following conflicts are left:"
	cat conflicts
else
	echo "No more conflicts left."
fi


