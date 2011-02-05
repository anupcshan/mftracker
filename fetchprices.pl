#!/usr/bin/perl

use HTTP::Request::Common qw(POST GET);
use LWP::UserAgent;
use Date::Manip;
use DBI;

$ua = new LWP::UserAgent;
$dbh = DBI->connect("dbi:SQLite:dbname=/home/anup/.mftracker/mftracker.db", "", "");

sub fetchnavs() {
	my $datetime = $_[0];
	my $mfid = $_[1];
	my $direction = $_[2] || -1;
	my @sch_name = split (/\|/, $mfid);
	my $day = substr ($datetime, 6, 2), $month = substr ($datetime, 4, 2), $year = substr ($datetime, 0, 4);
	my $request = POST 'http://www.mutualfundsindia.com/historical_nav_rpt.asp',
			[sch_name => $sch_name[0], sch_name1 => $sch_name[1], day1 => $day, mon1 => $month, year1 => $year];
	my $response = $ua->request($request);
	my $body = $response->content;
	my $date = "", $nav = 0, $isdate = 0;
	my $retdatetime = "00000000";

	for(reverse (split /\n/, $body)) {
		my($line) = $_;
		chomp($line);
		if($line =~ /<td align="left" valign="middle" bgcolor="#FFFFFF" class="bluebig">/) {
			$line =~ s/<[^>]*>//g;
			$line =~ s/^\s*//;
			$line =~ s/\s*$//;
			if ($isdate) {
				$date = `date --date="$line" "+%Y%m%d"`;
				$date =~ s/\s*$//;
				$isdate = 0;
				if ($retdatetime == "00000000" && $direction == -1) {
					$retdatetime = $date;
				}
				if ($direction == 1) {
					$retdatetime = $date;
				}
				# Got date,nav pair. Add to DB now...
				my $query = "INSERT INTO navhistory VALUES('$mfid', $nav, $date)";
				$dbh->do($query) && print "Adding $date :: $nav\n";
			}
			else {
				$nav = $line;
				$isdate = 1;
			}
		}
	}

	return $retdatetime;
}


sub fetchallnavs() {
	my $mfid = $_[0];
	my $enddate = "20050101", $retdate, $startdate, $maxdate;
	my @qresult, $maxdatequery;
	$startdate = UnixDate(ParseDate("today"), "%Y%m%d");
	my $histcountquery = "SELECT COUNT(*) FROM navhistory WHERE mfid = '$mfid'";
	@qresult = $dbh->selectall_arrayref($histcountquery);
	if ($qresult[0][0][0] > 0) {
		$maxdatequery = "SELECT MAX(date) FROM navhistory WHERE mfid = '$mfid'";
		@qresult = $dbh->selectall_arrayref($maxdatequery);
		$maxdate = $qresult[0][0][0];
		if ($startdate != $maxdate) {
			$startdate = $maxdate;
			while (1) {
				$retdate = &fetchnavs($startdate, $mfid, 1);
				if ($retdate == "00000000") {
					last;
				}
				if ($retdate <= $enddate) {
					last;
				}
				$startdate = UnixDate(DateCalc($retdate, "+ 4 days"), "%Y%m%d");
			}
		}

		my $mindatequery = "SELECT MIN(date) FROM navhistory WHERE mfid = '$mfid'";
		@qresult = $dbh->selectall_arrayref($mindatequery);
		$startdate = $qresult[0][0][0];
		$startdate = UnixDate(DateCalc($startdate, "- 5 days"), "%Y%m%d");
		if ($startdate <= $enddate) {
			return 0;
		}
	}

	print "Starting from $startdate\n";
	while (1) {
		$retdate = &fetchnavs($startdate, $mfid, -1);
		if ($retdate == "00000000") {
			return 0;
		}
		if ($retdate <= $enddate) {
			return 0;
		}
		$startdate = UnixDate(DateCalc($retdate, "- 5 days"), "%Y%m%d");
	}
}

sub getandupdatemfinfo() {
	my $mfid = $_[0];
	my ($amc_name, $sch_name) = split (/\|/, $mfid);
	my $mfname = "";

	my $response = $ua->request(GET "http://www.mutualfundsindia.com/sch_info.asp?scheme=".$amc_name);
	my $body = $response->content;

	for(split /\n/, $body) {
		my($line) = $_;
		chomp($line);
		if($line =~ /scheme=$sch_name/) {
			$line =~ s/<[^>]*>//g;
			$line =~ s/^\s*//;
			$line =~ s/\s*$//;
			$mfname = $line;
			print $mfid." is ".$mfname."\n";
			my $updatemfnamequery = "UPDATE mfinfo SET mfname = '$mfname' WHERE mfid = '$mfid'";
			$dbh->do($updatemfnamequery);
		}
	}

	return $mfname;
}

sub updateallmfs() {
	my $listmfsquery = "SELECT mfid, mfname FROM mfinfo";
	my $qresult = $dbh->selectall_arrayref($listmfsquery);
	for my $mfrow (@$qresult) {
		my ($mfid, $mfname) = @$mfrow;
		if ($mfname =~ /^$/) {
			$mfname = &getandupdatemfinfo($mfid);
		}
		print "Updating data for $mfname...\n";
		&fetchallnavs($mfid);
	}
}

open STDERR, '>/dev/null';
updateallmfs();
close STDERR;
