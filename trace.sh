#!/bin/bash
FUNC="${1}"
KERNEL_DIR="${2:-.}"
DEPTH=3                        #levels upto which we're going to trace
OUTPUT="deps_${FUNC}.txt"

#pretty our console
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
BLU='\033[0;34m'
CYN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

if [ -z "$FUNC" ]; then
    echo "Usage: $0 <function_name> [kernel_dir]"
    echo "Example: $0 mas_store ~/linux_mainline"
    exit 1
fi

cd "$KERNEL_DIR" || { echo "Cannot cd to $KERNEL_DIR"; exit 1; }

# this is a helper function which maps file path to subsystem name... this is what we want the most
get_subsystem() {
    local filepath="$1"
    local dir
    dir=$(echo "$filepath" | sed 's|/[^/]*$||')

    case "$dir" in
        fs/ext4*)       echo "ext4 filesystem" ;;
        fs/btrfs*)      echo "btrfs filesystem" ;;
        fs/xfs*)        echo "xfs filesystem" ;;
        fs/nfs*)        echo "NFS filesystem" ;;
        fs/fat*)        echo "FAT filesystem" ;;
        fs/proc*)       echo "procfs (virtual)" ;;
        fs/sysfs*)      echo "sysfs (virtual)" ;;
        fs/*)           echo "VFS / filesystem layer" ;;
        mm/*)           echo "memory management (mm)" ;;
        net/core*)      echo "networking core" ;;
        net/*)          echo "networking" ;;
        kernel/sched*)  echo "scheduler" ;;
        kernel/*)       echo "core kernel" ;;
        lib/*)          echo "kernel library / data structures" ;;
        arch/x86*)      echo "x86 architecture" ;;
        arch/arm*)      echo "ARM architecture" ;;
        arch/*)         echo "architecture-specific" ;;
        drivers/usb*)   echo "USB driver" ;;
        drivers/*)      echo "device drivers" ;;
        tools/testing*) echo "kernel selftests / testing" ;;
        ipc/*)          echo "IPC (inter-process communication)" ;;
        security/*)     echo "security / LSM" ;;
        crypto/*)       echo "cryptography" ;;
        block/*)        echo "block layer / IO" ;;
        *)              echo "$dir" ;;
    esac
}

#build cscopedb if not present....
if [ ! -f cscope.out ]; then
    echo -e "${YLW}[*] cscope.out not found! building index (this takes a moment)...${NC}"
    cscope -R -b
    echo -e "${GRN}[+] cscope index built.${NC}"
else
    echo -e "${GRN}[+] cscope index found.${NC}"
fi

#output starting
{
echo "  DEPENDENCY TRACE: $FUNC"
echo "  Kernel root: $KERNEL_DIR"
echo "  Traced: $(date)"
echo "  Depth: $DEPTH levels up"
echo ""
} | tee "$OUTPUT"

# 1 -Where is the function defined in which file, subsys?
{
echo " 1- DEFINITION OF: $FUNC"
} | tee -a "$OUTPUT"

cscope -L -1 "$FUNC" | while read -r file func line content; do
    subsys=$(get_subsystem "$file")
    echo "  Defined in : $file (line $line)"
    echo "  Subsystem  : $subsys"
    echo "  Signature  : $content"
    echo ""
done | tee -a "$OUTPUT"

# 2 -Direct callers of the function we're interested to change (level 1)
{
echo "2 -  DIRECT CALLERS of $FUNC  (level 1)"
} | tee -a "$OUTPUT"

# collect direct callers into array
mapfile -t DIRECT < <(cscope -L -3 "$FUNC" | awk '{print $1, $2, $3}')

if [ ${#DIRECT[@]} -eq 0 ]; then
    echo "  None found." | tee -a "$OUTPUT"
else
    declare -A SUBSYS_MAP   #list of caller subsystems

    for entry in "${DIRECT[@]}"; do
        file=$(echo "$entry" | awk '{print $1}')
        func=$(echo "$entry" | awk '{print $2}')
        line=$(echo "$entry" | awk '{print $3}')
        subsys=$(get_subsystem "$file")

        echo "  $func()" | tee -a "$OUTPUT"
        echo "    File      : $file  (line $line)" | tee -a "$OUTPUT"
        echo "    Subsystem : $subsys" | tee -a "$OUTPUT"
        echo "" | tee -a "$OUTPUT"

        #build the subsystem summary
        SUBSYS_MAP["$subsys"]+="$func "
    done

    #subsystem summary
    echo "  -- Subsystems affected at level 1 --" | tee -a "$OUTPUT"
    for subsys in "${!SUBSYS_MAP[@]}"; do
        echo "    [$subsys]  →  ${SUBSYS_MAP[$subsys]}" | tee -a "$OUTPUT"
    done
    echo "" | tee -a "$OUTPUT"
fi

# 3 - Level 2 callers 
{
echo "  3 LEVEL 2 CALLERS " #(who calls the direct callers?)
} | tee -a "$OUTPUT"

declare -A SEEN_FUNCS
declare -A L2_SUBSYS

for entry in "${DIRECT[@]}"; do
    caller_func=$(echo "$entry" | awk '{print $2}')

    # skip if already processed
    [ "${SEEN_FUNCS[$caller_func]}" ] && continue
    SEEN_FUNCS["$caller_func"]=1

    mapfile -t L2 < <(cscope -L -3 "$caller_func" | awk '{print $1, $2, $3}')

    if [ ${#L2[@]} -gt 0 ]; then
        echo "  Callers of $caller_func():" | tee -a "$OUTPUT"
        for l2entry in "${L2[@]}"; do
            l2file=$(echo "$l2entry" | awk '{print $1}')
            l2func=$(echo "$l2entry" | awk '{print $2}')
            l2line=$(echo "$l2entry" | awk '{print $3}')
            l2subsys=$(get_subsystem "$l2file")

            echo "    $l2func()  →  $l2file (line $l2line)" | tee -a "$OUTPUT"
            echo "    Subsystem: $l2subsys" | tee -a "$OUTPUT"
            echo "" | tee -a "$OUTPUT"

            L2_SUBSYS["$l2subsys"]+="$l2func "
        done
    fi
done

echo "  Subsystems which are affected at level 2 " | tee -a "$OUTPUT"
for subsys in "${!L2_SUBSYS[@]}"; do
    echo "    [$subsys]  →  ${L2_SUBSYS[$subsys]}" | tee -a "$OUTPUT"
done
echo "" | tee -a "$OUTPUT"

# 4 - which headers declare this function?
{
echo "4- HEADER DECLARATIONS"
} | tee -a "$OUTPUT"

grep -rn "${FUNC}" include/ 2>/dev/null | grep "\.h:" | while read -r line; do
    echo "  $line" | tee -a "$OUTPUT"
done
echo "" | tee -a "$OUTPUT"

# 5 get MAINTAINERS for each affected file
{
echo "  [5] MAINTAINERS TO NOTIFY"
} | tee -a "$OUTPUT"

#collect all unique files seen
ALL_FILES=()
while IFS= read -r line; do
    file=$(echo "$line" | awk '{print $1}')
    [ -f "$file" ] && ALL_FILES+=("$file")
done < <(cscope -L -3 "$FUNC")

SEEN_MAINTAINERS=()
for f in "${ALL_FILES[@]}"; do
    if [ -f scripts/get_maintainer.pl ]; then
        result=$(perl scripts/get_maintainer.pl --file "$f" 2>/dev/null | head -3)
        if [[ ! " ${SEEN_MAINTAINERS[*]} " =~ $result ]]; then
            echo "  File: $f" | tee -a "$OUTPUT"
            echo "$result" | sed 's/^/    /' | tee -a "$OUTPUT"
            echo "" | tee -a "$OUTPUT"
            SEEN_MAINTAINERS+=("$result")
        fi
    fi
done
#6- get full subsystem blast radius summary
{
echo "FULL BLAST RADIUS SUMMARY"
echo ""
echo "  Direct callers by subsystem:"
git grep -l "${FUNC}(" -- "*.c" 2>/dev/null \
    | sed 's|/[^/]*$||' \
    | sort | uniq -c | sort -rn \
    | awk '{printf "    %3d files  →  %s\n", $1, $2}'
echo ""
echo "  All files calling $FUNC directly:"
git grep -n "${FUNC}(" -- "*.c" 2>/dev/null \
    | awk -F: '{printf "    %-60s line %s\n", $1, $2}'
echo ""
echo "  Output saved to: $OUTPUT"
} | tee -a "$OUTPUT"
