# interface to related asterysks

package Asterysk::Related;

use Moose;
use Asterysk::Common;
use Carp qw/croak/;

# get feeds related to $opts{feed} for $opts{caller}
# $opts{caller} is optional
sub related_to_feed {
    my ($class, %opts) = @_;
    
    my $feed = delete $opts{feed} or croak "No feed passed in";
    my $caller = delete $opts{caller};
    my $lmt = delete $opts{limit};
    my $xcl_ref = delete $opts{exclude} || [];
    
    croak "Unknown opts: " . join(', ', keys %opts) if keys %opts;
    
    my $feed_id = $feed->id;
    my @xcl = (@$xcl_ref, $feed_id);   # build list of excluded feed. don't include the current feed
    
    if ($caller) {
        # don't suggest things the caller has subscribed to
        my @subscribed_feed_ids = $caller->subscriptions->get_column('id')->all;
        push @xcl, @subscribed_feed_ids;
    }
    
    my $dbh;
	unless ( $dbh = &get_db_connection() ) {
		die "getSimilar: $DBI::errstr";
		return;
	}
	    
	# Get publisher ID of the audioFeed if it exists.
	# Get only one publisher for now even though it is possible to have multiple ones.
	my $sth = $dbh->prepare('select publisher from publisherFeeds where audioFeed=?');
	unless ( $sth->execute($feed_id) ) {
		die "getSimilar: " . $dbh->errstr;
		$dbh->disconnect;
		return;
	}
	my ($cId) = $sth->fetchrow_array;
	$sth->finish;

	# Get a list of visible QCs by the same author in descending popularity order (measuring voice listens within a month).
	my $xcl_bind = join(',', map { '?' } @xcl);
	my $count = 0;
	my @samePublisher = ();
	my ($feedId, $canonical, $nam, $dsc, $content, $vce, $afi);
	my $sthCmt = $dbh->prepare('select count(*) from audioComment where audioFeedItem=?');
	if ($cId) {
		# If author not NULL.
		$sth = $dbh->prepare("select a.id,a.canonicalName,a.name,a.description,a.lastContent,a.voiceCommentsEnabled,i.id from audioFeedItem i,audioFeed a,publisherFeeds p where p.audioFeed=a.id and a.lastContent=i.content and p.publisher=? and a.id not in ($xcl_bind) and a.invisible != 1 order by (select count(*) from voiceActionTracking_log2 where audioFeed=a.id and action in (11,12,13) and actionTime > timestampadd(month,-1,now()) ) desc, a.id asc");
		unless ($sth->execute($cId, @xcl)) {
			ERROR ("getSimilar: " . $dbh->errstr);
			$dbh->disconnect;
			return;
		}
		while (($feedId, $canonical, $nam, $dsc, $content, $vce, $afi) = $sth->fetchrow_array) {

			# Get number of associated comments.

			$sthCmt->execute($afi);
			my ($comments) = $sthCmt->fetchrow_array || 0;
			$sthCmt->finish;

			push(@samePublisher, [$feedId, $canonical, $nam, $dsc, $content, $vce, $comments, $afi]);
			push @xcl, $feedId;
			last if ($lmt && ++$count >= $lmt);
		}
	}

	# Get tags of the QC and make comma-separated string from them.

	$sth = $dbh->prepare('select tag from feedTag where audioFeed=?');
	unless ( $sth->execute($feed_id) ) {
		ERROR ("getSimilar: $dbh->errstr");
		$dbh->disconnect;
		return;
	}
	my @tags = ();
	my @tagsFiltered = ();
	# Ignore tags: Entertainment,Asterysk Help Center,New Asteryskcasters,Featured Asterysks,Newly Added,Under Construction
	my %badTag = (2=>1,17=>1,18=>1,19=>1,20=>1,21=>1);
	while (my ($tag) = $sth->fetchrow_array) {
		push(@tags, $tag);
		push(@tagsFiltered, $tag) if (! $badTag{$tag});
	}
	my $in = join(',', ((@tagsFiltered > 0)? @tagsFiltered : @tags));
	unless ($in) {
		$dbh->disconnect;
		return ();
	}

	# Get a list of QCs (not including QC in param) with the same tag in descending popularity order (measuring listens within a month).
	$xcl_bind = join(',', map { '?' } @xcl);
	$sth = $dbh->prepare("select a.id,a.canonicalName,a.name,a.description,a.lastContent,a.voiceCommentsEnabled,i.id from feedTag f,audioFeedItem i,audioFeed a where a.lastContent=i.content and f.audioFeed=a.id and tag in ($in) and a.id not in ($xcl_bind) and a.invisible != 1 order by (select count(*) from voiceActionTracking_log2 where audioFeed=a.id and action in (11,12,13) and actionTime > timestampadd(month,-1,now()) ) desc, a.id asc");
	unless ($sth->execute(@xcl)) {
		$dbh->disconnect;
		die "getsimilar: " . $dbh->errstr;
	}

=for later

select a.id,a.canonicalName,a.lastContent,a.voiceCommentsEnabled 
	from feedTag f,audioFeed a,(select audioFeed as af,count(*) as c from voiceActionTracking_log2 
								where action in (11,12,13) and actionTime > timestampadd(month,-1,now()) group by audioFeed) c 
	where c.af=a.id and f.audioFeed=a.id and f.tag in (11) and a.id != 2 and a.invisible != 1 order by c.c desc, a.id asc

=cut

	# QC with multiple intersection in tags are ordered as consecutive rows. Pick out n consecutives and store them separately
	# so that QCs with multiple tag intersections are weighed to display more prominently than ones with less intersection, but
	# with more listens.

	my $terminate = 0;
	my $last = [];
	my @results;
	do {
		($feedId, $canonical, $nam, $dsc, $content, $vce, $afi) = $sth->fetchrow_array;
		if ($last->[0] && $feedId == $last->[0]) {

		} else {
			if ($last->[0] && $last->[0] ne '') {
				# Do not push for special case of first row.
				push(@results, $last);
				# Can improve performance if I exclude entire section on getting tag if limit is already satisfied.
				# But, that instance is very rare.
				if ($lmt && ++$count >= $lmt) {
					$terminate = 1;
					$sth->finish;
				}
			}

			# Get number of associated comments.
			$sthCmt->execute($afi);
			my ($comments) = $sthCmt->fetchrow_array || 0;
			$sthCmt->finish;

			$last = [$feedId, $canonical, $nam, $dsc, $content, $vce, $comments, $afi];
		}
	} while ($feedId ne '' && ! $terminate);

	# Put ones with same publisher in front of ones with same tags.

	push(@results, @samePublisher) if (@samePublisher);

	$dbh->disconnect;
	return @results;
}

1;
