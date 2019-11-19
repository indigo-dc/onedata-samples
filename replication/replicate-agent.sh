#!/usr/bin/env bash

usage() {
cat <<EOF
This script helps to preform data replication between two Oneproviders.

${0##*/} --oz <onezone url> { --sn <space name> | --sid <space id> } --sp <provider url or name> --dp <provider url or name>
         -t <token> [ --log-stream ] [ --save-seq ] [ --seq <change number> ] [ -env ]
Options:
  --dp               url or name of replicaton destination oneprovider
  -h, --help         display this help and exit
  --oz               onezone url
  --sid              instead of space name you can supply space id. space id takes precedence over --sn
  --seq              space change event sequence id from which you will start receiving events
  --seq-save         when the script is interputed, save the sequence number of last recieved event to the file ./last_seq
                     when starting the script try to read ./last_seq for the sequence number
  --cache-freq       how often should cache file be check for pending replication requests (default: 2 seconds)
  --log-stream       log raw stream of changes to stream.log
  --log-replicas     log raw stream of requests and responses to the replicasion API replicas.log
  --sn               space name
  --sp               url or name of replicaton source oneprovider
  -t                 onezone API token
  --env              try to get all needed parameters from the environment
  --defer-time       how long (in seconds) to wait before scheduling transfer of a modified file since the last activity on it.
                     Default: 180 seconds
  --debug            additional data transfer information

Examples:

The simplest way to initalize the replication of data on space 'par-n-lis-c' from example providers 'krakow' to destination provider 'paris': 
${0##*/} --oz develop-onezone.develop.svc.dev.onedata.uk.to \\
                   --sp develop-oneprovider-paris.develop.svc.dev.onedata.uk.to \\
                   --dp develop-oneprovider-lisbon.develop.svc.dev.onedata.uk.to \\
                   --sn par-n-lis-c \\
         -t MDAxNWxvY2F0...

If user has 2 spaces named 'par-n-lis-c' the script will fail. The solution is to provider space id instead of space name:
${0##*/} --oz develop-onezone.develop.svc.dev.onedata.uk.to \\
                   --sp develop-oneprovider-paris.develop.svc.dev.onedata.uk.to \\
                   --dp develop-oneprovider-lisbon.develop.svc.dev.onedata.uk.to \\
                   --sid ced4b8030a033ee22eaad8c79fc519b1 \\
         -t MDAxNWxvY2F0....

By default script starts replication by monitoring latest changes in the space. You can controll it by providing seq number.
${0##*/} --oz develop-onezone.develop.svc.dev.onedata.uk.to \\
                   --sp develop-oneprovider-paris.develop.svc.dev.onedata.uk.to \\
                   --dp develop-oneprovider-lisbon.develop.svc.dev.onedata.uk.to \\
                   --sn par-n-lis-c \\
                   --seq 100 \\
         -t MDAxNWxvY2F0...

The above command will start replication process by getting all changes since the change numbered as 100.

To run a continous replication you can save the last received seq number upon scrip exit:
${0##*/} --oz develop-onezone.develop.svc.dev.onedata.uk.to \\
                   --sp develop-oneprovider-paris.develop.svc.dev.onedata.uk.to \\
                   --dp develop-oneprovider-lisbon.develop.svc.dev.onedata.uk.to \\
                   --sid ced4b8030a033ee22eaad8c79fc519b1 \\
                   --save-seq \\
         -t MDAxNWxvY2F0...

When run next time, above command will read the last sequence number from the file ./last_seq.

You can provide most parameters also as exported variables. Create a file with content:

export  onezone_url="develop-onezone.develop.svc.dev.onedata.uk.to"
export  source_space_name="par-n-lis-c"
export  source_provider="develop-oneprovider-paris.develop.svc.dev.onedata.uk.to"
export  target_provider="develop-oneprovider-lisbon.develop.svc.dev.onedata.uk.to"
export  api_token="MDAxNWxvY2F00aW9uIG9uZXpvbmUKMDAzMGlkZW500aWZpZXIgNDgzNzRhNzE00YjhiNTQ1YWFkYTA4ZDEzZWVlNzBhM2IKMDAxYWNpZCB00aW1lIDwgMTU3MTQwNDQyNwowMDJmc2lnbmF00dXJlIGp4es01iyU02j1A1Jm61W5XzuCsc3nvFD7h7OmBfWswIeCg"

and source it. Make sure your variables are present in env. You can now run replication using command:
${0##*/} --env

EOF
exit 1
}

aliases() {
  case $( uname -s ) in
    Linux)
          _stdbuf=stdbuf
          _date=date
          _awk=awk
          ;;
    Darwin)
          _stdbuf=gstdbuf
          _date=gdate
          _awk=gawk
          ;;
  esac
}

strip_url() { 
  local url=$1
  url=${1#https://}
  url=${url#http://}
  url=${url#www.}
  url=${url%%/*}
  echo "$url"
}

command_exists() {
  command -v "$@" > /dev/null 2>&1
}

check_dependency() {
  if ! command_exists $1 ; then
    echo "Error: please install command: $1"
    exit 1
  fi
}

main() {

  if (( ! $# )); then
    usage
  fi

  # Default values
  seq_save=0
  log_stream=0
  defer_time=5
  cache_scan_frequency=2
  debug=0

  while (( $# )); do
      case $1 in
          -h|-\?|--help)   # Call a "usage" function to display a synopsis, then exit.
              usage
              exit 0
              ;;
          --env)
              ;;
          --oz)
              onezone_url=$(strip_url "$2")
              shift
              ;;
          --dp)
              target_provider=$(strip_url "$2")
              shift
              ;;
          --sp)
              source_provider=$(strip_url "$2")
              shift
              ;;
          --sid)
              source_space_id=$2
              shift
              ;;
          --seq)
              last_seq_number=$2
              shift
              ;;
          --seq-save)
              seq_save=1
              ;;
          --cache-freq)
              cache_scan_frequency=$2
              shift
              ;;
          --log-stream)
              log_stream=1
              ;;
          --log-replicas)
              log_replicas=1
              ;;
          --sn)
              source_space_name=$2
              shift
              ;;
          -t)
              api_token=$2
              shift
              ;;
          --defer-time)
              defer_time=$2
              shift
              ;;
          --debug)
              debug=1
              ;;
          -?*|*)
              printf 'WARN: Unknown option (ignored): %s\n' "$1" >&2
              exit 1
              ;;
      esac
      shift
  done


  ###
  # Parameters validation
  ##

  errors=0;
  # On 17 line, port change port to 8443
  if [[ -z ${onezone_url+x} ]]; then
    echo "ERROR: Missign onezone url." ;
    errors=1
  else
    onezone_url="https://$onezone_url" 
  fi

  if [[ -z ${source_space_name+x} && -z ${source_space_id+x} ]]; then
    echo "ERROR: You must supply space name or space id." 
    errors=1
  fi

  if [[ -z ${source_provider+x} ]]; then
    echo "ERROR: Missign source provider name or url." ;
    errors=1
  fi

  if [[ -z ${source_provider+x} ]]; then
    echo "ERROR: Missign target provider name or url." ;
    errors=1
  fi

  if [[ -z ${source_provider+x} ]]; then
    echo "ERROR: Missign onezone api token." ;
    errors=1
  fi

  if (( errors )); then
    echo "Please see --help, study examples and supply needed parameters."
    exit 1
  fi

  # One curl command to rule them all
  _curl=(curl -k -N --tlsv1.2 --fail --show-error --silent -H "X-Auth-Token:$api_token")
  
  ###
  # If space name is supplied try to match find matching space id
  ##

  if [[ -z ${source_space_id+x} ]]; then
    all_spaces=$(${_curl[@]} "$onezone_url/api/v3/onezone/user/spaces" | jq -r '.spaces[]')

    matched_spaces=()
    for space_id in $all_spaces ; do
      space_name=$(${_curl[@]} "$onezone_url/api/v3/onezone/spaces/$space_id" | jq -r ".name")
      if [[ "$source_space_name" == "$space_name" ]]; then
        matched_spaces+=($space_name $space_id)
      fi
    done

    if [[ ${#matched_spaces[@]} -eq 0 ]]; then 
      echo "No space with name <$source_space_name> found in onezone <$onezone_url>"
      exit 1
    fi

    if [[ ${#matched_spaces[@]} -ge 3 ]]; then 
      echo "Found 2 or more spaces with name <$source_space_name> found in onezone <$onezone_url>:"
      for (( i = 0; i < ${#matched_spaces[@]}; i += 2 )); do
        printf 'Space name: <%s> , space id: <%s>\n' "${matched_spaces[i]}" "${matched_spaces[i+1]}"
      done
      echo "Cannot decide which one to use. Exiting."
      exit 1
    fi
    source_space_id=${matched_spaces[1]}
  fi

  ###
  # Using space id get space information and validate it against providers parameters
  ##

  read space_name space_id providers < <(${_curl[@]} "$onezone_url/api/v3/onezone/spaces/$source_space_id" | jq -r '.name,.spaceId,(.providers | to_entries[] | "\(.key):\(.value)" )' | tr  '\n' ' ') 

  cat <<EOF
  ┌──────────────────────────────────────────────────────────┐
  │ Information about space                                  │
  └──────────────────────────────────────────────────────────┘

EOF
  
  echo "    Space name: <$space_name>"
  echo "    Space id: <$space_id>"
  for provider in $providers; do
    IFS=':' read provider_id support_size <<<"$provider"
    read provider_name domain < <(${_curl[@]} "$onezone_url/api/v3/onezone/providers/$provider_id" | jq -r ".name,.domain" | tr  '\n' ' ')
    echo "    Provider <$provider_name>"
    echo "      with id <$provider_id>"
    echo "      domain url <$domain>"
    echo "      suppots space <$space_name> with storage size of <$support_size> bytes"

    if [[ "$source_provider" =~ "$domain" ]]; then
      source_provider_id="$provider_id" ;
    fi

    if [[ "$target_provider" =~ "$domain" ]]; then
      targert_provider_id="$provider_id" ;
    fi
  done
  echo ""

  if [[ -z ${targert_provider_id} ]]; then
    echo "ERROR: <$target_provider> did not match any of the providers that supports the space <$space_name>"
    exit 1
  fi

  if [[ -z ${source_provider_id} ]]; then
    echo "ERROR: <$source_provider> did not match any of the providers that supports the space <$space_name>"
    exit 1
  fi

  ###
  # Using space id get space information and validate it against providers parameters
  ##

  cat <<EOF
  ┌──────────────────────────────────────────────────────────┐
  │ Replication information                                  │
  └──────────────────────────────────────────────────────────┘

    Starting monitoring of changes of space <$space_name>, on provider <$source_provider>.
    All changess will be replicated to provider <$target_provider> that also supports space <$space_name>

EOF
  echo "targert_provider_id=$targert_provider_id"
  echo "source_provider_id=$source_provider_id"



  log_steam_cmd() { if (( log_stream )); then $_stdbuf -i0 -o0 -e0 tee -a stream.log; else cat; fi; }
  log_replicas_cmd() { if (( log_replicas )); then $_stdbuf -i0 -o0 -e0 tee -a replicas.log; else cat; fi; }
  
  check_cache() {
    while true ; do
      sleep $cache_scan_frequency ;
      while IFS=$'\t' read ctimestamp cfile_path cseq cfile_name cfile_id ; do 
        echo "Requested file transfer: <$cfile_name>"
        echo "  change stream number: <$cseq>"
        echo "  path: <$cfile_path>"
        echo "  id: <$cfile_id>"
        echo "${_curl[@]} -H 'Content-type: application/json' -X POST \"https://$source_provider/api/v3/oneprovider/replicas-id/$cfile_id?provider_id=$targert_provider_id\"" | log_replicas_cmd > /dev/null
        #transfer=$(${_curl[@]} -H 'Content-type: application/json' -X POST "https://$source_provider/api/v3/oneprovider/replicas-id/$cfile_id?provider_id=$targert_provider_id" | xargs -0 printf "%s\n" | log_replicas_cmd | jq -r ".transferId")
        {
          IFS= read -rd '' transfer_errors
          IFS= read -rd '' transfer
        } < <(
          {
            transfer=$(
            ${_curl[@]} -vv -H 'Content-type: application/json' -X POST "https://$source_provider/api/v3/oneprovider/replicas-id/$cfile_id?provider_id=$targert_provider_id" | xargs -0 printf "%s\n" | log_replicas_cmd | jq -r ".transferId"
            ); 
          } 2>&1; printf '\0%s' "$transfer"
        ) ;

        echo "  replication transfer id: $transfer"
        echo ""
        if [ "$transfer" != "" ] && [ "$transfer" != "null" ]; then
          $_awk -F $'\t' -i inplace -v filename="$cfile_path" '$2 != filename' "$changes_cache"
        else
          echo "No trasnfer id recived. This request will be retried." ;
          printf "Errors:\n${transfer_errors}\n"
        fi
      done < <($_awk -F $'\t' -v defer_time=$defer_time -v date_now="$($_date +%s)" '(date_now - $1) > defer_time {print}' cache.db)

    done
  }

  changes_cache=cache.db
  touch "$changes_cache"
  last_seq_func_verbose=1
  _curl=(curl -k -N --tlsv1.2 --show-error --silent -H "X-Auth-Token:$api_token")

  last_seq_func() {
    if [[ -z ${last_seq_number+x } ]]; then 
      if (( seq_save )); then
        if [[ -f ./last_seq ]]; then
          last_seq_number=$(cat ./last_seq)
        fi
      fi
    fi
    if [[ "$last_seq_number" != "" ]] ; then
      if [[ $last_seq_number =~ ^[0-9]+$ ]] ; then
          last_seq="last_seq=$last_seq_number"
          [[ $last_seq_func_verbose -eq 1 ]] && printf "    Requesting stream of changes from the event number <$last_seq_number>:\n\n"
      else
        [[ $last_seq_func_verbose -eq 1 ]] && echo "WARNING: Last sequence number <$last_seq_number> does not match regexp ^[0-9]+$, ommiting."
      fi
    else
        [[ $last_seq_func_verbose -eq 1 ]] && printf "    Subscribing to the stream of changes:\n\n"
    fi
  }

  check_cache &


  stream_number=0;
  echo ${_curl[@]} -H 'Content-type: application/json' -X POST -d "{}"  -vv  "https://$source_provider/api/v3/oneprovider/changes/metadata/$space_id?${last_seq}"
  
  while true ; do

  ((stream_number++))
    echo "defer_time=${defer_time}. The curl stream <${stream_number}> has started at: $($_date)."
    last_seq_func

    while IFS=$'\t' read seq file_name file_path file_id ; do
      echo "raw: <$seq> <$file_name> <$file_path> <$file_id>"
      seq="${seq#seq=}"
      file_name="${file_name#name=}"
      file_path="${file_path#file_path=}"
      if [ "$file_path" = "" ] ; then
        file_path="MISSING_FILE_PATH"
      fi
      file_id="${file_id#file_id=}"
      echo "parsed: $seq $file_name $file_path $file_id"
      date_cache="$($_date --date="$defer_time seconds ago" +%s)"
      if ! $_awk -F $'\t' -i inplace -v time=$($_date +%s) -v filename="$file_path" 'BEGIN{err=1};match($0, filename) {gsub($1,time); err=0};{print} END {exit err}' "$changes_cache"; then
          date_now="$($_date +%s)"
          change=$(printf "%s\\t%s\\t%s\\t%s\\t%s\\n" "$date_now" "$file_path" "$seq" "$file_name" "$file_id")
          echo "$change" >> "$changes_cache"
          if [[ $debug -eq 1 ]]; then
            echo "New file added to transfer cache: <$file_name>"
            echo "  change stream number: <$seq>"
            echo "  path: <$file_path>"
            echo "  id: <$file_id>"
            echo "  If no changes to this file occures for $defer_time [s] its transfer will be enqueued."
            echo ""
          fi
          $_awk -F $'\t' -i inplace -v filename="$cfile_path" '$2 != filename' "$changes_cache"
      else
          if [[ $debug -eq 1 ]]; then
            echo "Updated cached file trasnfer: <$file_name>"
            echo "  change stream number: <$seq>"
            echo "  path: <$file_path>"
            echo "  id: <$file_id>"
            echo "  If no changes to this file occures for $defer_time [s] its transfer will be enqueued."
            echo ""
          fi
          $_awk -F $'\t' -i inplace -v filename="$cfile_path" '$2 != filename' "$changes_cache"
      fi
      if (( seq_save )); then
        (( seq++ ))
        echo "$seq" > last_seq
      fi
    done < <(${_curl[@]} -vv -H 'Content-type: application/json' -X POST -d '{"fileMeta":{ "always": true, "fields":["name","type"] }, "fileLocation":{}}' "https://$source_provider/api/v3/oneprovider/changes/metadata/$space_id?${last_seq}" | log_steam_cmd | $_stdbuf -i0 -o0 -e0 jq -r 'select((.fileMeta.fields.type=="REG") and (.fileMeta.deleted!=true)) | "seq=\(.seq)\tname=\(.fileMeta.fields.name)\tfile_path=\(.filePath)\tfile_id=\(.fileId)"' )
    #done < <(${_curl[@]} -H 'Content-type: application/json' -X POST -d "{}"  -vv  "https://$source_provider/api/v3/oneprovider/changes/metadata/$space_id?${last_seq}" | log_steam_cmd | $_stdbuf -i0 -o0 -e0 jq -r 'select((.deleted==false ) and (.changes.type=="REG")) | "seq=\(.seq)\tname=\(.name)\tfile_path=\(.file_path)\tfile_id=\(.file_id)"' )
    echo "The curl stream <${stream_number}> has ended at: $($_date)."
    last_seq_func_verbose=0
  done
}

aliases
check_dependency "jq"
check_dependency $_stdbuf
check_dependency $_date
check_dependency $_awk
main "$@"