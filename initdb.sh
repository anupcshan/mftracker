#!/bin/bash
#
# Copyright (C) 2011 Anup C Shan
#
# This program is free software; you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation; either version 2 of the License, or
# (at your option) any later version.
#
# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.
#
# You should have received a copy of the GNU General Public License
# along with this program; if not, write to the Free Software
# Foundation, Inc., 59 Temple Place, Suite 330, Boston, MA 02111-1307
# USA

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
		mfname varchar2(50),
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
