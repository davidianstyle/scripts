#!/bin/sh

BACKUP=0
RESTORE=0
VERBOSE=0
# OUTPUT='1> /dev/null'
# ERROR='2>&1'
while getopts "w:brvp:d:f:oe" opt; do
	case $opt in
		w)
			WEBSITE="$OPTARG"
			# echo "-w was triggered!" >&2
			;;
		b)
			BACKUP=1
			# echo "-b was triggered!" >&2
			;;
		r)
			RESTORE=1
			# echo "-r was triggered!" >&2
			;;
		v)
			VERBOSE=1
			# echo "-v was triggered!" >&2
			;;
		p)
			DBPASSWORD="$OPTARG"
			# echo "-p was triggered!" >&2
			;;
		d)
			RESTOREDATE="$OPTARG"
			# echo "-d was triggered!" >&2
			;;
		f)
			FREQUENCY="$OPTARG"
			# echo "-f was triggered!" >&2
			;;
		# o)
		# 	OUTPUT=""
		# 	# echo "-o was triggered!" >&2
		# 	;;
		# e)
		# 	ERROR=""
		# 	# echo "-e was triggered!" >&2
		# 	;;
		\?)
			echo "Invalid option: -$OPTARG" >&2
			exit
			;;
	esac
done

if [ $BACKUP -eq 0 ] && [ $RESTORE -eq 0 ]
then
	echo "Must specify either -b (backup) or -r (restore)."
	exit
fi

# Grab the script arguments
# Make sure that special characters are escaped when used on the command line!
shift $(($OPTIND - 1))

while [ -z $WEBSITE ]
do
	echo "Please specify a website: "
	read WEBSITE
done

# Prompt for database password if none is specified
if [ -z $DBPASSWORD ]
then
	echo "Please specify a database password: "
	read -s DBPASSWORD
fi

# Grab restore date if not provided
while [ $RESTORE -eq 1 ] && [[ ! "$RESTOREDATE" =~ ^([0-9]{8})$ ]]
do
	echo "Please specify a date to restore (YYYYMMDD): "
	read RESTOREDATE
done

while [[ ! "$FREQUENCY" =~ ^(daily|monthly|yearly)$ ]]
do
	echo "Please specify a valid frequency (daily|monthly|yearly): "
	read FREQUENCY
done

# Set variable values
if [ $BACKUP -eq 1 ]
then
	DATE=`date +%Y%m%d`
else
	DATE=$RESTOREDATE
fi

YEAR=`date +%Y`
RESTOREDIRECTORY="/home/dchang/restores/${WEBSITE}"
BACKUPDIRECTORY="/home/dchang/backups/${WEBSITE}"
FULLBACKUPDIRECTORY="${BACKUPDIRECTORY}/${DATE}"
DATABASE="${WEBSITE}_db"
SQLFILENAME="${WEBSITE}-${DATE}.sql"
SQLFILE="${FULLBACKUPDIRECTORY}/${SQLFILENAME}"
SQLFILEERROR="${FULLBACKUPDIRECTORY}/${SQLFILENAME}.error"
TARFILENAME="${WEBSITE}-${DATE}.tar.gz"
TARFILE="${BACKUPDIRECTORY}/${TARFILENAME}"
ANNUALTARFILENAME="${WEBSITE}-${YEAR}.tar.gz"
ANNUALTARFILE="${BACKUPDIRECTORY}/${ANNUALTARFILENAME}"
S3LOCATION="s3://david-chang-websites/$WEBSITE/$FREQUENCY"

if [ $BACKUP -eq 1 ]
then
	if [ $VERBOSE -eq 1 ]
	then
		echo "Backing up..."
	fi

	# Create the web directory if it doesn't exist
	if [ ! -d $DIRECTORY ]; then
	    mkdir $DIRECTORY
	fi

	# Create the date directory if it doesn't exist
	if [ ! -d $FULLBACKUPDIRECTORY ]; then
	    mkdir $FULLBACKUPDIRECTORY
	fi

	# Perform the rsync
	if [ $VERBOSE -eq 1 ]
	then
		echo "Running rsync..."
	fi
	/usr/bin/rsync -avr /var/www/$WEBSITE $FULLBACKUPDIRECTORY 1> /dev/null # 2>&1 $OUTPUT $ERROR

	# Do the mysql dump
	if [ $VERBOSE -eq 1 ]
	then
		echo "Running mysqldump..."
	fi
	/usr/bin/mysqldump -u dchang -p${DBPASSWORD} $DATABASE > $SQLFILE 2> $SQLFILEERROR

	# Compress everything
	if [ $VERBOSE -eq 1 ]
	then
		echo "Compressing..."
	fi
	tar -C $FULLBACKUPDIRECTORY -zcvf $TARFILE $WEBSITE $SQLFILENAME 1> /dev/null # 2>&1 $OUTPUT $ERROR

	# Send it to S3
	if [ $VERBOSE -eq 1 ]
	then
		echo "Syncing to S3..."
	fi
	aws s3 cp $TARFILE $S3LOCATION/$TARFILENAME 1> /dev/null # 2>&1 $OUTPUT $ERROR
fi

if [ $RESTORE -eq 1 ]
then
	if [ $VERBOSE -eq 1 ]
	then
		echo "Restoring..."
	fi

	# Pull from S3
	if [ $VERBOSE -eq 1 ]
	then
		echo "Syncing from S3..."
	fi
	aws s3 cp $S3LOCATION/$TARFILENAME $RESTOREDIRECTORY/$TARFILENAME 1> /dev/null # 2>&1 $OUTPUT $ERROR

	# Extract from archive
	if [ $VERBOSE -eq 1 ]
	then
		echo "Extracting from archive..."
	fi
	tar -zxvf $RESTOREDIRECTORY/$TARFILENAME -C $RESTOREDIRECTORY

	# MySQL drop database if it exists
	mysql -u dchang -p${DBPASSWORD} -e "drop database if exists ${DATABASE}"

	# MySQL create database if it doesn't exist
	mysql -u dchang -p${DBPASSWORD} -e "create database if not exists ${DATABASE}"

	# MySQL restore
	if [ $VERBOSE -eq 1 ]
	then
		echo "Running MySQL restore..."
	fi
	mysql -u dchang -p${DBPASSWORD} $DATABASE < $RESTOREDIRECTORY/$SQLFILENAME

	# Create document root directory in /var/www
	if [ ! -d /var/www/${WEBSITE} ]
	then
		if [ $VERBOSE -eq 1 ]
		then
			echo "Creating www directory..."
		fi
		mkdir /var/www/${WEBSITE}
	fi

	# Create log directory in /etc/httpd/logs
	if [ ! -d /etc/httpd/logs/${WEBSITE} ]
	then
		if [ $VERBOSE -eq 1 ]
		then
			echo "Creating log directory..."
		fi
		mkdir /etc/httpd/logs/${WEBSITE}
	fi
fi

if [ $VERBOSE -eq 1 ]
then
	echo "Complete."
fi
