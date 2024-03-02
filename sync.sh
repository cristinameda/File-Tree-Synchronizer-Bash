#! /bin/bash

# Let it be tree A and tree B
# For each file p:
# 1 - 1.1 - both p/A and p/B are compliant to the journal + same content => ALREADY SYNCHRONIZED
#   - 1.2 - both p/A and p/B are compliant to the journal + different content => CONFLICT
# 2 - both p/A and p/B are directories, nothing is done
# 3 - different file types (one is directory, the other is a regular file) => CONFLICT
# 4 - p exists only in A and not in B or vice-versa => p is copied to the tree missing the file => SYNCHRONIZED
# 5 - 5.1 - one of p/A or p/B is compliant to the journal and the other isn't + same content => copy only the metadata of the updated file to the compliant file and update journal
#   - 5.2 - one of p/A or p/B is compliant to the journal and the other isn't + different content => copy metadata and content of the updated file to the compliant file and update journal
# 6 - 6.a - both files are not compliant or entry not found + same metadata and content => add/update entry to journal => SYNCHRONIZED
#   - 6.b - both files are not compliant or entry not found + same metadata, different content => CONFLICT
#   - 6.c - both files are not compliant or entry not found + different metadata (and same or different content) => CONFLICT

# get_metadata relative_path absolute_path
# function that takes the relative path and the absolute path of the file and returns its metadata
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

# copy_content paths_file source_tree_path destination_tree_path
# function copies the directories and files from paths_file located in source_tree_path to destination_tree_path
copy_content() {
    local paths_file=$1
    local source=$2
    local destination=$3

    while IFS= read -r line; do

        path1="$source$line"
        path2="$destination$line"

        data=$(get_metadata $line $path1)

        if [ -d $path1 ]; then
            mkdir $path2
        else
            cp -p $path1 $path2
        fi

        echo $data >> journal

    done < $paths_file
}

# step 1
# check if arguments are valid directory paths
if [ ! -d $1 ]; then
    echo "Error: the first argument is not a valid tree path"
    exit
fi

if [ ! -d $2 ]; then
    echo "Error: the second argument is not a valid tree path"
    exit
fi

# step 2
# check if the journal file exists
if [ ! -s "journal" ]; then
    # if it doesn't exist, create a new file
    # write the two paths on the first line, separated by a space character
    echo "$1 $2" > journal
fi

# journal exists, check if the journal is for the same paths
firstLine=$(head -n 1 journal)
echo $firstLine

# if it's not, erase content and add the 2 paths at on the first line (start a new journal)
if [[ $firstLine != "$1 $2" ]] && [[ $firstLine != "$2 $1" ]]; then
    echo "$1 $2" > journal
fi

# step 3
# check if the conflicts file exists
if [ -e "conflicts" ]; then
    # if it exists, truncate it (make it empty)
    > conflicts
else
    # if it doesn't exist, create a new empty file
    touch conflicts
fi

# step 4
# store all absolute paths from the tree1 in the file paths1
find $1 > paths1
# store all absolute paths from the tree2 in the file paths2
find $2 > paths2

# delete the tree path => relative paths
sed "s|$1||g" paths1 > paths_tree1
sed "s|$2||g" paths2 > paths_tree2

# files and directories that exist only in the first tree (case #4)
comm -23 <(sort paths_tree1) <(sort paths_tree2) > only_tree1

# files and directories that exist only in the second tree (case #4)
comm -13 <(sort paths_tree1) <(sort paths_tree2) > only_tree2

# sync + add to journal the paths in only_tree1 and only_tree2
copy_content only_tree1 $1 $2

copy_content only_tree2 $2 $1

# common paths in both trees (files and directories that exist in both trees)
comm -12 <(sort paths_tree1) <(sort paths_tree2) > common

while IFS= read -r line; do
    path1="$1$line"
    path2="$2$line"

    echo "Processing $path1 and $path2"

    # if both are directories, continue (case #2)
    if [ -d $path1 ] && [ -d $path2 ]; then
        printf "Both directories, continue\n\n"
        continue
    fi

    # if different file types, mark as conflict (case #3)
    if [ -f $path1 ] && [ -d $path2 ]; then
        # mark as conflict
        echo "$path1 $path2 Different file types." >> conflicts
        echo "Different file types."
        printf "CONFLICT\n\n"
        continue
    fi

    if [ -d $path1 ] && [ -f $path2 ]; then
        # mark as conflict
        echo "$path1 $path2 Different file types." >> conflicts
        echo "Different file types."
        printf "CONFLICT\n\n"
        continue
    fi

    # check for other cases by metadata and content

    # extract path1 metadata
    data1=$(get_metadata $line $path1)
    escaped_data1=$(echo $data1 | sed "s|\/|\\\/|g")

    # extract path2 metadata
    data2=$(get_metadata $line $path2)
    escaped_data2=$(echo $data2 | sed "s|\/|\\\/|g")

    # find the entry in the journal if existent
    entry=$(grep -h "^$line" journal)
    escaped_entry=$(echo $entry | sed "s|\/|\\\/|g")

    echo "Metadata1: $data1"
    echo "Medadata2: $data2"

    if [ -n "$entry" ]; then
        # entry is found
        echo "Entry is found: $entry"

        matches1=0
        matches2=0

        # check if path1 current metadata matches journal metadata
        if [[ $data1 == $entry ]]; then
            matches1=1
        fi

        # check if path2 current metadata matches journal metadata
        if [[ $data2 == $entry ]]; then
            matches2=1
        fi

        if [ $matches1 -eq 1 ] && [ $matches2 -eq 1 ]; then
            echo "Both paths are compliant to the journal."
            # both paths match journal metadata
            if cmp -s "$path1" "$path2"; then
                # same content (case #1.1)
                printf "ALREADY SYNCED\n\n"
                continue
            else
                # different content (case #1.2)
                echo "Same metadata, different content."
                echo "$path1 $path2 Same metadata, different content." >> conflicts
                printf "CONFLICT\n\n"
                continue
            fi
        elif [ $matches1 -eq 1 ]; then
            # path1 is compliant and path2 isn't (path2 updated)
            echo "First file is compliant and the second isn't."
            if cmp -s "$path1" "$path2"; then
                # same content (case #5.1)
                # copy only metadata of path2 to path1
                touch -r "$path2" "$path1"
                chmod --reference="$path2" "$path1"
                echo "Same content."
            else
                # different content (case #5.2)
                # copy content and metadata of path2 to path1
                cp --preserve=all "$path2" "$path1"
                echo "Different content."
            fi
            # update journal entry
            sed -i -e "s|$escaped_entry|$escaped_data2|" journal
            printf "SYNCED\n\n"
            continue
        elif [ $matches2 -eq 1 ]; then
            # path2 is compliant and path1 isn't (path1 updated)
            echo "Second file is compliant and the first isn't."
            if cmp -s "$path1" "$path2"; then
                # same content (case #5.1)
                # copy only metadata of path1 to path2
                touch -r "$path1" "$path2"
                chmod --reference="$path1" "$path2"
                echo "Same content."
            else
                # different content (case #5.2)
                # copy content and metadata of path1 to path2
                cp --preserve=all "$path1" "$path2"
                echo "Different content."
            fi
            # update journal entry
            sed -i -e "s|$escaped_entry|$escaped_data1|" journal
            printf "SYNCED\n\n"
            continue
        fi
    fi

    # both paths are not compliant to journal or entry not found
    # if same metadata, comapare content
    if [[ $data1 == $data2 ]]; then
        if cmp -s "$path1" "$path2"; then
            # same metadata and content => synced (case #6.a)
            # add or update entry in journal
            if [ -n "$entry" ]; then
                echo "Both files not comppliant. Same metadata and content."
                sed -i -e "s|$escaped_entry|$escaped_data1|" journal
            else
                echo "Entry not found. Same metadata and content."
                echo "$data1" >> journal
            fi
            printf "SYNCED\n\n"
        else
            # same metadata, different content (case 6.b)
            if [ -n "$entry" ]; then
                echo "Both files are not compliant to the journal."
            else
                echo "Entry not found."
            fi
            echo "Same metadata, but different content."
            printf "CONFLICT\n\n"
            echo "$path1 $path2 Same metadata, but different content." >> conflicts
        fi
    else
        # different metadata (case #6.c)
        if [ -n "$entry" ]; then
            echo "Both files are not compliant to the journal."
        else
            echo "Entry not found."
        fi
        echo "Different metadata (and same or different content)."
        printf "CONFLICT\n\n"
        echo "$path1 $path2 Different metadata (and same or different content)." >> conflicts
    fi

done < common

rm "paths1"
rm "paths2"
rm "paths_tree1"
rm "paths_tree2"
rm "only_tree1"
rm "only_tree2"
rm "common"

printf "The identified conflicts can be found in the output file \"conflicts\".\n\n"

echo "The following command can be used to resolve a conflict between 2 files (that can be found in the conflicts file):"
echo "resolve [options] <file-path1> <file-path2>"
echo "where the option determines which file should be chosen to be part of both files."
printf "\nOptions:\n"
echo "keep-first - selects the file from the first path file given to be kept and updates the data and metadata of the other one."
echo "keep-second - selects the file from the second path file given to be kept and updates the data and metadata of the other one."
echo "keep-latest - selects the file with the latest timestamp of modification to be kept and updates the data and metadata of the other one."
printf "keep-initial - selects the file with the earliest timestamp of modification to be kept and updates the data and metadata of the other one.\n\n"

echo "The next command can be used to resolve all the conflicts identified by the sychronization process:"
echo "resolveAll [options]"
echo "were all the paths from the \"conflicts\" file are going to be handled in the same manner, based on the chosen option."