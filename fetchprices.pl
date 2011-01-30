#!/usr/bin/perl

use HTTP::Request::Common qw(POST);
use LWP::UserAgent;
use Date::Manip;
use DBI;

$ua = new LWP::UserAgent;
$dbh = DBI->connect("dbi:SQLite:dbname=/home/anup/.mftracker/mftracker.db", "", "");

sub fetchnavs() {
	my $datetime = $_[0];
	my $mfid = $_[1];
	my @sch_name = split (/\|/, $mfid);
	my $day = substr ($datetime, 6, 2), $month = substr ($datetime, 4, 2), $year = substr ($datetime, 0, 4);
	my $request = POST 'http://www.mutualfundsindia.com/historical_nav_rpt.asp',
			[sch_name => $sch_name[0], sch_name1 => $sch_name[1], day1 => $day, mon1 => $month, year1 => $year];
	my $response = $ua->request($request);
	my $body = $response->content;
	my $date = "", $nav = 0, $isdate = 1;
	my $retdatetime = "00000000";

	for(split /\n/, $body) {
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
				if ($retdatetime == "00000000") {
					$retdatetime = $date;
				}
			}
			else {
				$nav = $line;
				$isdate = 1;
				# Got date,nav pair. Add to DB now...
				print "$date :: $nav\n";
				my $query = "INSERT INTO navhistory VALUES('$mfid', $nav, $date)";
				$dbh->do($query);
			}
		}
	}

	return $retdatetime;
}


sub fetchallnavs() {
	my $mfid = $_[0];
	my $enddate = "20050101", $retdate, $startdate;
	$startdate = UnixDate(ParseDate("today"), "%Y%m%d");
	my $histcountquery = "SELECT COUNT(*) FROM navhistory WHERE mfid = '$mfid'";
	my @qresult = $dbh->selectall_arrayref($histcountquery);
	if ($qresult[0][0][0] > 0) {
		my $mindatequery = "SELECT MIN(date) FROM navhistory WHERE mfid = '$mfid'";
		my @qresult = $dbh->selectall_arrayref($mindatequery);
		$startdate = $qresult[0][0][0];
		$startdate = UnixDate(DateCalc($startdate, "- 5 days"), "%Y%m%d");
		if ($startdate <= $enddate) {
			return 0;
		}
	}

	print "Starting from $startdate\n";
	while (1) {
		$retdate = &fetchnavs($startdate, $mfid);
		if ($retdate == "00000000") {
			return 0;
		}
		if ($retdate <= $enddate) {
			return 0;
		}
		$startdate = UnixDate(DateCalc($retdate, "- 5 days"), "%Y%m%d");
	}
}

&fetchallnavs("MF041|ZI006");
&fetchallnavs("MF030|SN017");
