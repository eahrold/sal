#!/bin/bash

#set -xv
export PATH="$PATH:/usr/local/bin:/usr/local/sbin:/Applications/Xcode.app/Contents/Developer/usr/bin"

PROJECT_NAME='sal'
PROJECT_SETTINGS_DIR="sal"
EXAMPLE_SETTINGS_FILE="example_settings.py"

GIT_REPO="https://github.com/eahrold/sal.git"
GIT_BRANCH="master"
USER_NAME='sal'
GROUP_NAME='sal'
APACHE_SUBPATH='sal'

VIRENV_NAME='sal_env'

## you only need to set one of the following two requirements...
DJANGO_REQUIREMENTS_FILE="setup/requirements.txt"
##DJANGO_REQUIREMENTS=(Django django-bootstrap-toolkit, south, markdown2)

SOUTH_MANAGED_DJANGO_APPS=('server')

OSX_CONF_FILE_DIR="OSX"
OSX_WEBAPP_PLIST='com.grahamgilbert.sal.webapp.plist'
APACHE_CONFIG_FILE='httpd_sal.conf'
WSGI_FILE='sal.wsgi'

OSX_SERVER_WSGI_DIR="/Library/Server/Web/Data/WebApps/"
OSX_SERVER_APACHE_DIR="/Library/Server/Web/Config/apache2/"
OSX_SERVER_SITES_DEFAULT="/Library/Server/Web/Data/Sites/"

pre_condition_test(){
	[[ -z $(which git) ]] && cecho alert "you must first install git. you can download it from Apple." && exit 1
	
	if [[ $EUID != 0 ]]; then
		cecho red "This script needs to run with elevated privileges, enter your password"
	    sudo "$0" "$@"
	    exit 1
	fi
}

custom_config(){
	echo running custom configurations
}

make_user_and_group(){
	cecho bold "Checking user and group..."
	local USER_EXISTS=$(dscl . list /Users | grep -c "${USER_NAME}")
	local GROUP_EXISTS=$(dscl . list /Groups | grep -c "${GROUP_NAME}")
	
	if [ $USER_EXISTS -eq 0 ]; then
		cecho bold "Creating user ${USER_NAME}..."
		
		USER_ID=$(check_ID Users UniqueID)
		dscl . create /Users/"${USER_NAME}"
		dscl . create /Users/"${USER_NAME}" passwd *
		dscl . create /Users/"${USER_NAME}" UniqueID "${USER_ID}"
	else
		cecho bold "User ${USER_NAME} already exists, skipping..."
	fi

	if [ $GROUP_EXISTS -eq 0 ]; then
		cecho bold "Creating user ${USER_NAME}..."
		GROUP_ID=$(check_ID Groups PrimaryGroupID)
		dseditgroup -o create -i "${GROUP_ID}" -n . "${GROUP_NAME}"
	else
		cecho bold "Group ${GROUP_NAME} already exists, skipping..."
		GROUP_ID=$(dscl . read /Groups/"${GROUP_NAME}" PrimaryGroupID)
	fi
	
	### this is outside of the conditional statement 
	### to correct any previously set GroupID
	dscl . create /Users/"${USER_NAME}" PrimaryGroupID "${GROUP_ID}"
}

install(){
	COMP_PATH=$(dirname `dirname $0`)
	local VEV=$(which virtualenv)
	[[ -z "${VEV}" ]] && easy_install virtualenv

### Install the Vitrual Environment
	"${VEV}" "${VIR_ENV}"
	
### Copy the Project into the New Virtual Environment
	# cp -R ${COMP_PATH} "${VIR_ENV}/${PROJECT_NAME}"
	git clone $GIT_REPO "${VIR_ENV}/${PROJECT_NAME}"
	cd "${VIR_ENV}"
		
	source bin/activate
	if [ -f "./${PROJECT_NAME}/${DJANGO_REQUIREMENTS_FILE}" ] ;then
		pip install -r ./"${PROJECT_NAME}/${DJANGO_REQUIREMENTS_FILE}"
	elif [ ${#DJANGO_PIP_REQUIREMENTS[@]} -gt 0 ]; then
		for i in ${DJANGO_REQUIREMENTS[@]}; do
			pip install ${i}
		done
	fi
	
	cd "${PROJECT_NAME}"
	
	if [ "${PROJECT_SETTINGS_DIR}" != "" ]; then
		eval_dir PROJECT_SETTINGS_DIR
	fi
		
	cp "${PROJECT_SETTINGS_DIR}${EXAMPLE_SETTINGS_FILE}" "${PROJECT_SETTINGS_DIR}settings.py"
	local SETTINGS_FILE="${PROJECT_SETTINGS_DIR}settings.py"
	cecho purple "Now we'll do some basic configuring to the settings.py file"
	
## Generate A Unique Secret Key For Django Site
	local _seckey=$(LC_CTYPE=C tr -dc A-Za-z0-9_\!\@\#\$\%\^\*\(\)-+= < /dev/urandom | head -c 50 | xargs)
	ised "SECRET_KEY" "SECRET_KEY = '${_seckey}'" "${SETTINGS_FILE}"
	
	while true; do
	cread question "Do you want to run on an apache subpath ${APACHE_SUBPATH}? [y/n]" yesno
	if [[ $REPLY =~ ^[Yy]$ ]];then
		RUN_ON_SUBPATH=true
		break
	elif [[ $REPLY =~ ^[Nn]$ ]]; then
		RUN_ON_SUBPATH=false		
		break
	fi	
	done
	
	if [ ${RUN_ON_SUBPATH} == true ]; then
		ised "RUN_ON_SUBPATH" "RUN_ON_SUBPATH = [True,'${APACHE_SUBPATH}/']" "${SETTINGS_FILE}"
	else
		ised "RUN_ON_SUBPATH" "RUN_ON_SUBPATH = [False,'${APACHE_SUBPATH}/']" "${SETTINGS_FILE}"
		APACHE_SUBPATH=""
	fi
		
	while true; do
	cread question "Run in DEBUG mode [y/n]? " yesno
	if [[ $REPLY =~ ^[Yy]$ ]];then
		ised "DEBUG =" "DEBUG = True" "${SETTINGS_FILE}"
		break
	elif	[[ $REPLY =~ ^[Nn]$ ]]; then
		break
	fi	
	done
	
	while true;do
	HOST_NAME=`scutil --get HostName`
	cread question "Set ALLOWED_HOST as this: $HOST_NAME [y/n]? " yesno
	if [[ $REPLY =~ ^[Yy]$ ]];then
		ised "ALLOWED_HOSTS =" "ALLOWED_HOSTS = ['${HOST_NAME}']" "${SETTINGS_FILE}"
		break
	elif [[ $REPLY =~ ^[Nn]$ ]]; then
		echo "you will need to edit this in the settings.py file once we're done."
		break
	fi	
	done
	
	python manage.py collectstatic

## Perform any needed Custom Configuration 
	custom_config
	
## Initialize the DB and Subsequently Set Permissions
	python manage.py syncdb
	
	for i in ${SOUTH_MANAGED_DJANGO_APPS[@]}; do
		if [ `ls -l ./${i}/migrations/ | wc -l` -eq 0 ]; then
			python manage.py schemamigration ${i} --initial
		else
			python manage.py schemamigration ${i} --auto
		fi
		python manage.py migrate ${i}
	done	
	
## Set Permissions
	cecho "Setting  User ${USER_NAME} and group ${GROUP_NAME} on `pwd`"
	chown -R "${USER_NAME}":"${GROUP_NAME}" "${VIR_ENV}"
	
## Install OSX Server Components If needed
	if [ ${OSX_SERVER_INSTALL} == true ];then
		ised "RUNNING_ON_APACHE=" "RUNNING_ON_APACHE=True" "${SETTINGS_FILE}"
		install_osx_server_components
	else
		cread question "Do you Want to start the django test server now [y/n]?" yesno
		if [[ $REPLY =~ ^[Yy]$ ]];then
			python manage.py runserver
			echo ""
			cecho info "to run in the future you need do..."
			cecho bold "sudo -u ${USER_NAME} ${python ${VIR_ENV}${PROJECT_NAME}/manage.py runserver}"
		fi
	fi
}

install_osx_server_components(){
	cecho bold "installing os x server items..."
	[[ ! -d "${OSX_SERVER_APACHE_DIR}/webapps/" ]] && mkdir -p "${OSX_SERVER_APACHE_DIR}/webapps/"
	cp -p "${VIR_ENV}/${PROJECT_NAME}/${OSX_CONF_FILE_DIR}/${OSX_WEBAPP_PLIST}" "${OSX_SERVER_APACHE_DIR}/webapps/"	
	
	## configure the .conf file
	
	local alias_str="Alias /static_${PROJECT_NAME}/ ${VIR_ENV}${PROJECT_NAME}/${PROJECT_SETTINGS_DIR}/static/"
	local daemonprocess_str="WSGIDaemonProcess ${USER_NAME} user=${USER_NAME} group=${GROUP_NAME}"
	local processgroup_str="WSGIProcessGroup ${GROUP_NAME}"
	local wsgiscript_str="WSGIScriptAlias /${APACHE_SUBPATH} /Library/Server/Web/Data/WebApps/${PROJECT_NAME}.wsgi"
	
	if [ ${USER_NAME} == "www" ]; then
		echo "${alias_str}" > "${OSX_SERVER_APACHE_DIR}/${APACHE_CONFIG_FILE}"
		echo "${wsgiscript_str}" >> "${OSX_SERVER_APACHE_DIR}/${APACHE_CONFIG_FILE}"
	else
		cp -p "${VIR_ENV}/${PROJECT_NAME}/${OSX_CONF_FILE_DIR}/${APACHE_CONFIG_FILE}" "${OSX_SERVER_APACHE_DIR}/"
		
		ised "Alias" "${alias_str}" "${OSX_SERVER_APACHE_DIR}/${APACHE_CONFIG_FILE}"
		ised "WSGIScriptAlias" "${wsgiscript_str}" "${OSX_SERVER_APACHE_DIR}/${APACHE_CONFIG_FILE}"
		ised "WSGIDaemonProcess" "${daemonprocess_str}" "${OSX_SERVER_APACHE_DIR}/${APACHE_CONFIG_FILE}"
		ised "WSGIProcessGroup" "${processgroup_str}" "${OSX_SERVER_APACHE_DIR}/${APACHE_CONFIG_FILE}"
	fi
	
	
	
	## copy and configure the .wsgi file
	[[ ! -d "${OSX_SERVER_WSGI_DIR}/" ]] && mkdir -p "${OSX_SERVER_WSGI_DIR}/"	
	cp -p "${VIR_ENV}/${PROJECT_NAME}/${OSX_CONF_FILE_DIR}/${WSGI_FILE}" "${OSX_SERVER_WSGI_DIR}/"
	local venv_str="VIR_ENV_DIR = \'${VIR_ENV}\'"
	ised "VIR_ENV_DIR" "${venv_str}" "${OSX_SERVER_WSGI_DIR}/${WSGI_FILE}"
	
	cecho purple "OS X server items installed. "
	cecho blue "Open Server.app, select the site, go to Advanced and enable the webapp."
}


check_ID(){
	# $1 is the dscl path and $2 is the Match
	local ID=$(/usr/bin/dscl . list /$1 $2 | awk '{print $2}'| grep '[4][0-9][0-9]'| sort| tail -1)
	[[ -n $ID ]] && ((ID++)) || ID=400
		
	while true; do
		local IDCK=$(/usr/bin/dscl . list /$1 $2 | awk '{print $2}'| grep -c ${ID})
		if [ $IDCK -eq 0 ]; then
			break
		else
			cecho alert "That %2 is in use"
			read -e -p "Please specify another (press c to cancel auto-install script):" ID
		fi
	done
	
	if [ "${ID}" == "c" ] ; then
		cecho alert "exiting script."
		exit 1
	fi
	echo $ID
	 
}

############################# Utility Functions ############
cecho(){	
	case "$1" in
		red|alert) local COLOR=$(printf "\\e[1;31m");;
		green|attention) local COLOR=$(printf "\\e[1;32m");;
		yellow|warn) local COLOR=$(printf "\\e[1;33m");;
		blue|question) local COLOR=$(printf "\\e[1;34m");;
		purple|info) local COLOR=$(printf "\\e[1;35m");;
		cyan|notice) local COLOR=$(printf "\\e[1;36m");;
		bold|prompt) local COLOR=$(printf "\\e[1;30m");;
		*) local COLOR=$(printf "\\e[0;30m");;
	esac
	
	if [ -z "${2}" ];then
		local MESSAGE="${1}"
	else
		local MESSAGE="${2}"
	fi

	local RESET=$(printf "\\e[0m")	
	echo "${COLOR}${MESSAGE}${RESET} ${3}"	
}

cread(){	
	case "$1" in
		red|alert) local COLOR=$(printf "\\e[1;31m");;
		green|attention) local COLOR=$(printf "\\e[1;32m");;
		yellow|warn) local COLOR=$(printf "\\e[1;33m");;
		blue|question) local COLOR=$(printf "\\e[1;34m");;
		purple|info) local COLOR=$(printf "\\e[1;35m");;
		cyan|notice) local COLOR=$(printf "\\e[1;36m");;
		bold|prompt) local COLOR=$(printf "\\e[1;30m");;
		*) local COLOR=$(printf "\\e[0;30m");;
	esac	
	
	local MESSAGE="${2}"
	local RESET=$(printf "\\e[0m")	
	if [ -z ${3} ];then
		read -e -p "${COLOR}${MESSAGE}${RESET} "
	elif [ ${3} == "yesno" ]; then
		read -e -p "${COLOR}${MESSAGE}${RESET} " -n 1 -r
	else
		read -e -p "${COLOR}${MESSAGE}${RESET} " VAR
		eval $3="'$VAR'"
	fi
}

eval_dir(){	 
# pass the name of the variable you want to eval
# so you would pass MYVAR rather than $MYVAR	
	eval local __myvar=${!1} 2>/dev/null
	if [ $? == 0 ]; then
			
		local __len=${#__myvar}-1
		if [ "${__myvar:__len}" != "/" ]; then
		  __myvar=$__myvar"/"
		fi
		eval $1="'$__myvar'"
	else
		return 1
	fi
}

ised(){
	sed -i "" -e "s;^${1}.*;${2};" "${3}"
}
###############################################################
############################ End Utility Functions ############
###############################################################


__main__(){
	pre_condition_test
	clear
	cecho alert "You are about to run the $PROJECT_NAME installer"
	cecho alert "There's a few things to get out of the way"
	cecho question "First we need to determine what user should own the webapp process" 
	
	while true; do
	cecho purple "1) create a user ${USER_NAME} and group ${GROUP_NAME}" "(recommended)"
	cecho purple "2) yourself" "(fine for testing)"
	cecho purple "3) the www user" "(if you're running on both http and https)" 
		read -e -p "Please Choose: " -n 1 -r
		if [[ $REPLY -eq 1 ]];then
			make_user_and_group
			if [ $? == 0 ]; then
				break
			else
				cecho alert "There was a problem creating the user, chose an alternate option (1 or 3)"
			fi
		elif [[ $REPLY -eq 2 ]];then
			USER_NAME=$(who | grep console | head -1 |awk '{print $1}')
			GROUP_NAME=$(dscl . read /Users/${USER_NAME} PrimaryGroupID|awk '{print $2}')
			break	
		elif [[ $REPLY -eq 3 ]];then
			USER_NAME='www'
			GROUP_NAME='www'
			break
		fi
	done
	
	
	if [ -d "/Applications/Server.app" ]; then
		while true; do
			cread question "will you be running on OS X Server [y/n]?" yesno
			if [[ $REPLY =~ ^[Yy]$ ]];then
				OSX_SERVER_INSTALL=true
				break
			elif [[ $REPLY =~ ^[Nn]$ ]];then
				OSX_SERVER_INSTALL=false
				break
			fi
		done 
	fi
	
	while true; do
		echo ""
		cecho question "Where Would you like to install the Virtual Environment?"
		if [ "${OSX_SERVER_INSTALL}" == true ]; then
			cecho question "Defaults to:" "${OSX_SERVER_SITES_DEFAULT}"
 			cread purple "Set Path:" T_VIR_ENV
			if [ ! -z "${T_VIR_ENV}" ]; then
				VIR_ENV="${T_VIR_ENV}"
			else
				VIR_ENV="${OSX_SERVER_SITES_DEFAULT}"
			fi
		else
			cread purple "Set Path: " VIR_ENV
		fi
		
		#This will make sure there's a trailing slash on the path
		eval_dir VIR_ENV
		
		if [ $? == 0 ]; then
			if [ -d  "${VIR_ENV}" ]; then
				VIR_ENV="${VIR_ENV}${VIRENV_NAME}"
				eval_dir VIR_ENV	
				cecho question "We will create a virtual environment at this path:" "${VIR_ENV}"
				cread question "Correct [y/n]? " yesno
				if [[ $REPLY =~ ^[Yy]$ ]];then
				    	break
				elif [[ $REPLY =~ ^[Cc]$ ]];then
					cecho bold "Canceling..."
					exit 1
				fi 
			else
				cecho alert "That's not a valid path, please try again"
			fi
		else
			cecho alert "Please choose a POSIX Compatible Path (i.e no spaces!)"
		fi
	done
	install
	cecho alert "Done!"
}

__main__

exit 0