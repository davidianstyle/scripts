#!/bin/sh

BACKUP=0
RESTORE=0
VERBOSE=0
# OUTPUT='1> /dev/null'
# ERROR='2>&1'
while getopts ":brvoe" opt; do
	case $opt in
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
WEBSITE=$1
DBPASSWORD=$2
RESTOREDATE=$3

if [ $RESTORE -eq 1 ] && [ -z $RESTOREDATE ]
then
	read -s "Please specify a date to restore (YYYYMMDD): " RESTOREDATE
fi

# Set variable values
if [ $BACKUP -eq 1 ]
then
	DATE=`date +%Y%m%d`
else
	DATE=$RESTOREDATE
fi

YEAR=`date +%Y`
DIRECTORY="/home/dchang/backup/sites/${WEBSITE}"
FULLDIRECTORY="${DIRECTORY}/${DATE}"
DATABASE="${WEBSITE}db"
SQLFILENAME="${DATABASE}.${DATE}.sql"
SQLFILE="${FULLDIRECTORY}/${SQLFILENAME}"
SQLFILEERROR="${FULLDIRECTORY}/${SQLFILENAME}.error"
TARFILENAME="${WEBSITE}-${DATE}.tar.gz"
TARFILE="${DIRECTORY}/${TARFILENAME}"
ANNUALTARFILENAME="${WEBSITE}-${YEAR}.tar.gz"
ANNUALTARFILE="${DIRECTORY}/${ANNUALTARFILENAME}"

# Prompt for database password if none is specified
if [ -z $DBPASSWORD ]
then
	read -s -p "Please enter password for $DATABASE: " DBPASSWORD
fi

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
	if [ ! -d $FULLDIRECTORY ]; then
	    mkdir $FULLDIRECTORY
	fi

	# Perform the rsync
	if [ $VERBOSE -eq 1 ]
	then
		echo "Running rsync..."
	fi
	/usr/bin/rsync -avr /home/dchang/sites/$WEBSITE $FULLDIRECTORY 1> /dev/null # 2>&1 $OUTPUT $ERROR

	# Do the mysql dump
	if [ $VERBOSE -eq 1 ]
	then
		echo "Running mysqldump..."
	fi
	/usr/bin/mysqldump -u dchang -p${DBPASSWORD} $DATABASE > $SQLFILE # 2> $SQLFILEERROR

	# Compress everything
	if [ $VERBOSE -eq 1 ]
	then
		echo "Compressing..."
	fi
	tar -C $FULLDIRECTORY -zcvf $TARFILE $WEBSITE $SQLFILENAME 1> /dev/null # 2>&1 $OUTPUT $ERROR

	# Create annual archive
	# if [ $VERBOSE -eq 1 ]
	# then
	# 	echo "Creating annual archive..."
	# fi
	# tar -C $DIRECTORY -zcvf $ANNUALTARFILE ${YEAR}* 1> /dev/null # 2>&1 $OUTPUT $ERROR

	# Send it to S3
	if [ $VERBOSE -eq 1 ]
	then
		echo "Syncing to S3..."
	fi
	aws s3 cp $TARFILE s3://$WEBSITE/backup/$TARFILENAME 1> /dev/null # 2>&1 $OUTPUT $ERROR
	# aws s3 cp $ANNUALTARFILE s3://$WEBSITE/backup/$ANNUALTARFILENAME 1> /dev/null # 2>&1 $OUTPUT $ERROR
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
	aws s3 cp s3://$WEBSITE/backup/$TARFILENAME /home/dchang/$TARFILENAME 1> /dev/null # 2>&1 $OUTPUT $ERROR

	# Extract from archive
	if [ $VERBOSE -eq 1 ]
	then
		echo "Extracting from archive..."
	fi
	tar -zxvf /home/dchang/$TARFILENAME

	# MySQL drop database if it exists
	mysql -u dchang -p${DBPASSWORD} -e "drop database if exists ${DATABASE}"

	# MySQL create database if it doesn't exist
	mysql -u dchang -p${DBPASSWORD} -e "create database if not exists ${DATABASE}"

	# MySQL restore
	if [ $VERBOSE -eq 1 ]
	then
		echo "Running MySQL restore..."
	fi
	mysql -u dchang -p${DBPASSWORD} $DATABASE < /home/dchang/$SQLFILENAME

	# Create symlink from /var/www directory
	if [ ! -h /var/www/${WEBSITE} ]
	then
		if [ $VERBOSE -eq 1 ]
		then
			echo "Creating symlink..."
		fi
		ln -s /home/dchang/sites/${WEBSITE}/ /var/www/${WEBSITE}
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

	# Restart apache
	# /etc/init.d/httpd restart

	# File cleanup
	# rm /home/dchang/tmp/$SQLFILENAME
	# rm /home/dchang/tmp/$TARFILENAME
fi

if [ $VERBOSE -eq 1 ]
then
	echo "Complete."
fi
