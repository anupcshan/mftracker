#!/bin/bash

function log() {
	level=$1
	msg=$2
	if [ $DEBUG -ge $level ]
	then
		echo $msg
	fi
}

MFROOT=$HOME/.mftracker
DBFILE=$MFROOT/mftracker.db
if [ -z $DEBUG ]
then
	DEBUG=0
else
	log 4 "Debugging enabled..."
fi

if [ ! -d $MFROOT ]
then
	log 4 "Creating $MFROOT..."
	mkdir $MFROOT
fi

if [ ! -f $DBFILE ]
then
	log 0 "Creating DB file $DBFILE..."
	touch $DBFILE
fi

if [ -z "`sqlite3 $DBFILE '.schema portfolio'`" ]
then
	log 4 "Creating table PORTFOLIO..."
	sqlite3 $DBFILE 'CREATE TABLE portfolio(
		id integer primary key,
		mfid varchar(20),
		sipid integer,
		buydate date,
		buyprice price,
		quantity float
		);'
fi

if [ -z "`sqlite3 $DBFILE '.schema sips'`" ]
then
	log 4 "Creating table SIPS..."
	sqlite3 $DBFILE 'CREATE TABLE sips(
		sipid integer primary key,
		mfid varchar(20),
		sipamount float,
		sipdate integer,
		installments integer,
		previnstallment varchar(10)
		);'
fi

if [ -z "`sqlite3 $DBFILE '.schema mfinfo'`" ]
then
	log 4 "Creating table MFINFO..."
	sqlite3 $DBFILE 'CREATE TABLE mfinfo(
		mfid varchar(20) primary key,
		mfname varchar2(40),
		startdate integer
		);'
fi

if [ -z "`sqlite3 $DBFILE '.schema navhistory'`" ]
then
	log 4 "Creating table NAVHISTORY..."
	sqlite3 $DBFILE 'CREATE TABLE navhistory(
		mfid varchar(20),
		nav float,
		date integer,
		PRIMARY KEY(mfid, date)
		);'
fi
