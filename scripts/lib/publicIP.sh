#!/bin/bash

source ~/dotfiles/scripts/shellTextVariables.sh

## Get the current external IP address
getPublicIP () {
	echo -n "Retrieving Public IP Address..."
	for i in {1..3}; do
		case $i in
			1 )
				#/bin/echo "1) Dig"
				PUBLICIP=$(dig +short myip.opendns.com @resolver1.opendns.com 2> /dev/null)
				;;
			2 )
				#/bin/echo "2) Curl amazon"
				PUBLICIP=$(curl -w "\n" -s -X GET https://checkip.amazonaws.com 2> /dev/null)
				;;
			3 )
				#/bin/echo "3) Curl ifconfig.io"
				PUBLICIP=$(curl -s ifconfig.io 2> /dev/null)
				;;
		esac

		# Break the loop if a valid IP address was retrieved
		[ -n "$PUBLICIP" ] && break
	done
}

getPublicIP

# Clear line
echo -en "\033[999D\033[K"
echo -e "${CYAN}${Undr}${OnPurple}Public IP:${NOCOLOR}"
echo -e "${PURPLE}$PUBLICIP${NOCOLOR}"
echo
echo -e "${CYAN}${Undr}${OnPurple}Local IPs:${NOCOLOR}"
for i in {0..20}; do
    output=$(ip a show en${i} 2> /dev/null)
    if echo "$output" | grep -q "status UP"; then
        echo -e "Interface en${i} - IP Addresses:"
        echo "$output" | awk '/inet / {print $2}'
    fi
done
echo
