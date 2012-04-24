package Asterysk::Playlist;

use Moose;
use namespace::autoclean;

use Carp qw/croak/;

use Asterysk::Common;
use Asterysk::Playlist::Item::FeedItem;
use Asterysk::Playlist::Item::Share;
use Asterysk::Playlist::Item::ShareIntro;
use Asterysk::Playlist::Item::Recommendation;
use Asterysk::Playlist::Item::DirectConnect;
use Asterysk::Playlist::Item::Related;
use Asterysk::Playlist::Item::Comment;
use Asterysk::Playlist::Item::QuikHit;

use DBIx::Class::ResultClass::HashRefInflator;

has 'caller' => (
    is => 'rw',
    isa => 'Asterysk::Schema::AsteryskDB::Result::Caller',
    required => 1,
);

# for caching
# (all feed subscriptions, not just active)
has 'caller_feed_subscriptions' => (
    is => 'ro',
    isa => 'ArrayRef',
    builder => 'build_caller_feed_subscriptions',
    lazy => 1,
);

# current position
has 'i' => (
    is => 'rw',
    isa => 'Int',
    default => 0,
);

has 'itemsref' => (
    is => 'rw',
    isa => 'ArrayRef',
    default => sub { [] },
);

has 'dbh' => (
    is => 'rw',
);

has 'partner' => (
    is => 'rw',
    isa => 'Maybe[Asterysk::Schema::AsteryskDB::Result::Partner]',
);

has 'loaded' => (
    is => 'rw',
    isa => 'Bool',
    clearer => 'clear_loaded',
);

has 'loaded_recommendations' => (
    is => 'rw',
    isa => 'Bool',
);


######################################

# count how many of each type of item there are
sub share_count {
    my ($self) = @_;
    return scalar (grep { $_->is_share } @{$self->itemsref});
}
sub subscribed_item_count {
    my ($self) = @_;
    return scalar (grep { $_->is_feed_item } @{$self->itemsref});
}
sub recommendation_count {
    my ($self) = @_;
    return scalar (grep { $_->is_recommendation } @{$self->itemsref});
}

# returns all feeds ever subscribed to (not just active)
sub build_caller_feed_subscriptions {
    my ($self) = @_;
    my @subs = $self->caller->subscriptions;
    return \@subs;
}

sub load_recommendations {
    my ($self) = @_;
    
    return if $self->loaded_recommendations;
    
    my $items = $self->all_items;
    push @$items, @{$self->all_recommendations};
    
    $self->loaded_recommendations(1);
}

# returns arrayref of Asterysk::Playlist::Item instances of shares, rtqs, feeds, recommendations
*load_items = \&all_items;
sub all_items {
    my ($self) = @_;
    
    return $self->itemsref if $self->loaded;

    my $items = $self->itemsref;

    push @$items, @{$self->all_partner_items};
    #push @$items, @{$self->all_shares_and_share_intros};                                          
    push @$items, @{$self->all_subscribed_items};

    my $first_item = $items->[0];
    if ($first_item && $first_item->content && $self->caller->contentmark) {
        my $content_id = int($self->caller->contentmark / 10000);
        my $offset = $self->caller->contentmark % 10000;
        if ($offset && $first_item->content->id == $content_id) {
            $first_item->content->offset_in_seconds($offset);
            $first_item->perfect_memory(1);
        }
    }

    $self->loaded(1);

    return $items;
}

=head2

L<insert_items(@items)>:  insert @items after the current position in the playlist

=cut
sub insert_items {
    my ($self, @items) = @_;
    
    my $items = $self->itemsref || [];
    my $i = $self->i;
        
    splice(@$items, $i + 1, 0, @items);
}

# expects feeditem
sub insert_quikhit {
    my ($self, $quikhit_item) = @_;
    
    my $playlistitem = Asterysk::Playlist::Item::QuikHit->new(
        playlist => $self,
        content => $quikhit_item->content,
        feed_item => $quikhit_item,
    );
    $self->insert_items($playlistitem);
    return $playlistitem;
}

=head2

L<remove_related_items>: delete all related items from the playlist, mantaining current position

=cut
sub remove_related_items {
    my ($self) = @_;
    
    my $items = $self->itemsref || [];
    my $i = $self->i;
    
    # count how many related asterysks we've heard so far
    my $heard_related_count = grep { $_->is_related } @{$items}[0..$i];
    
    my @new_items = grep { ! $_->is_related } @$items;
    $self->itemsref(\@new_items);

    $i -= $heard_related_count;
    $i = 0 if $i < 0;
    $self->i($i);
}

=head2

L<remove_comments>: delete all comments from the playlist, mantaining current position

=cut
sub remove_comments {
    my ($self) = @_;
    
    my $items = $self->itemsref || [];
    my $i = $self->i;
    
    # count how many comments we've heard so far
    my $existing_count = grep { $_->is_comment } @{$items}[0..$i];
    
    my @new_items = grep { ! $_->is_comment } @$items;
    $self->itemsref(\@new_items);

    $i -= $existing_count;
    $i = 0 if $i < 0;
    $self->i($i);
}

=head2

L<get_next_item()>:  an iterator that returns the next item

Call like this:

while (defined (my $item = $playlist->get_next_item())) {
    ... do something with $item
}

=cut
sub get_next_item {
    my ($self) = @_;
    
    $self->go_forward(1);
    return $self->get_current_item;
}

=head2 get_previous_item

Return the previous item, but without affecting the internal counter
used by the get_next_item iterator.

=cut

sub get_previous_item {
    my ($self) = @_;

    $self->load_items;

    my $last_idx = $self->i - 1;
    $last_idx = 0 if $last_idx < 0;

    return $self->all_items->[ $last_idx ];
}

sub item_count {
    my ($self) = @_;
    
    return scalar @{ $self->all_items };
}

sub get_current_item {
    my ($self) = @_;
    
    if ($self->i < @{ $self->all_items }) {
        return $self->all_items->[ $self->i ];
    } else {
        if (! $self->loaded_recommendations) {
            $self->load_recommendations;
            
            if ($self->i < @{ $self->all_items }) {
                return $self->all_items->[ $self->i ];
            }
        }
        
        return;
    }
}

=head2 go_back

L<go_back($n)>: go back in the iteration.  Call this to decrement the index on
$self->itemsref.  *Then* call L<get_next_item()> to get the previous item.

For instance, to play the currrent item again, you would do:

=over 4
$playlist->go_back(1);
my $same_item = $playlist->get_next_item();
=back

To play the last item before this one, you would do:

=over 4
$playlist->go_back(2);
my $previous_item = $playlist->get_next_item();
=back

If you try to go back beyond the beginning of the playlist (i.e. if you pass a
number that is too big), you just get the first item.

Dies with a string exception if you try to go back 0 items (or undef items), since
that doesn't make sense.

See also:  L<get_next_item()>.

=cut
sub go_back {
    my ($self, $n) = @_;
    
    $self->load_items;

    if (!defined $n) {
        croak "go_back() requires an integer argument.  Got undef";
    }
    if ($n == 0) {
        croak "Going back 0 items is meaningless.  Error";
    }
    elsif (($self->i - $n) < 0) {
        $self->i(0);
    }
    else {
        $self->i($self->i - $n);
        return;
    }
}

sub go_forward {
    my ($self, $n) = @_;
    
    $self->load_items;
    
    if (!defined $n) {
        croak "go_back() requires an integer argument.  Got undef";
    }
    
    if ($n == 0) {
        croak "Going back 0 items is meaningless.  Error";
    }
    
    $self->i($self->i + $n); # It's all right to increment i past the end of items, because get_next_item checks
                             # to see if i > length and returns undef if so.
    
    # if we're at the end, load recommendations
    if (! $self->loaded_recommendations && ! $self->get_current_item) {
        $self->load_recommendations;
    }
    
    return;
}

# are we at the first item in the playlist?
sub at_start {
    my ($self) = @_;
    
    return ! $self->i;
}

# sub insert_jumpfile {
#     my ($self, $jumpfile) = @_;
#     if (!defined $self->{i}) {
#         croak 'invalid call to Asterysk::Playlist->insert_jumpfile:  it was called before any files were played,';
#     } else {
#         my @items_copy = @{ $self->{itemsref} };
#         splice @items_copy
#     }
# }

=head2 all_shares_and_share_intros

L<all_shares_and_share_intros()> - returns a reference to a flat list of shares and
share intros.  Not all shares have intros, so the list might look like this:

[
    $intro_1,
    $share_1,
    $share_2,
    $share_3,
    $intro_4,
    $share_4,
]

Each share is of type Asterysk::Playlist::Item::Share; each share intro is of type
Asterysk::Item::ShareIntro.
=cut

sub all_shares_and_share_intros {
    my ($self) = @_;

    my @shares = $self->rs('Audioshare')->search({
	    touser     =>  $self->caller->id,
	    dateheard  =>  undef,
    }, {
        prefetch => [qw( content )],
        order_by => ['dateshared DESC'],
    });
    
    # construct share playlist items
    my @items;

    foreach my $share (@shares) {
        next unless $share->content;

        my $share_item = Asterysk::Playlist::Item::Share->new(
          playlist => $self,
          content  => $share->content,
          share    => $share,
        );

        if (defined $share->messagecontent) {
          my $share_intro = Asterysk::Playlist::Item::ShareIntro->new(
              playlist => $self,
              share    => $share,
              content  => $share->messagecontent,
          );
          push @items, $share_intro;
        }
        push @items, $share_item;
    }
    

    return \@items;
}

# returns arrayref of pending recommendations
sub all_recommendations {
    my ($self) = @_;
    
    my @feeds = $self->recommendation_feeds(use_precomputed => 1);
    return [] unless @feeds;
    
    my @items; # recommendation playlist items
    
    # preload content
    my @content_ids = grep { $_ } map { $_->lastcontent } @feeds;
    my @content = $self->rs('Content')->search({
        id => \@content_ids,
    });
    # map id => content row
    my $content_map = {
        map { ($_->id => $_) } @content
    };
    
    foreach my $f (@feeds) {
        my $content = $content_map->{$f->lastcontent};
        
        my %rec = (
            playlist => $self,
        );
        
        unless ($content) {
            my $feed_item = $f->latest_item or next;
            $content = $feed_item->content or next;
            $rec{feed_item} = $feed_item;
        }
        
        $rec{content} = $content;
        
        push @items, Asterysk::Playlist::Item::Recommendation->new(%rec);
    }
    
    return \@items;
}

# returns recommended feeds
sub recommendation_feeds {
    my ($self, %opts) = @_;
    
    my $partner_constraint;
    if ($self->caller->numvisits < 50 && $self->partner) {
        $partner_constraint = $self->partner->id;
    }
    
    my @rec_ids;

    if ($opts{use_stored_procedure}) {
        my $dbh = $self->dbh || Asterysk::Common::get_db_connection();
        $dbh->{RaiseError} = 1;
        $self->dbh($dbh);
        
        my $feed_ids_ref = $dbh->selectcol_arrayref(
            q{ call get_featured_content(?,?) },
            undef,
            $partner_constraint, $self->caller->id,
        );
        my @feed_ids = @$feed_ids_ref;
        
        # select from virtual view, which uses stored procedure
        #$partner_constraint ||= 0;
        #my @feed_ids = $self->rs('Recommendation')->search({}, {
        #    bind => [$partner_constraint, $self->caller->id],
        #x})->all;
        
        return $self->rs('Audiofeed')->search({ id => \@feed_ids }) if @feed_ids;
    } elsif ($opts{use_precomputed}) {
        my $dbh = $self->dbh || Asterysk::Common::get_db_connection();
        $dbh->{RaiseError} = 1;
        $self->dbh($dbh);
        
        $partner_constraint ||= 0;
        my $feed_ids_ref = $dbh->selectall_arrayref(
            q{
            	SELECT bucket1Feed, bucket2Feed, bucket3Feed, bucket4Feed, bucket5Feed
            		FROM featuredFeeds
            		WHERE partner=?
            		ORDER BY RAND()
            		LIMIT 1
            }, 
            undef,
            $partner_constraint,
        );
        
        if ($feed_ids_ref && $feed_ids_ref->[0]) {      
            my @raw_feed_ids = @{ $feed_ids_ref->[0] };

            # remove feeds which caller has ever subscribed to
            my @caller_feed_subscriptions = @{ $self->caller_feed_subscriptions };
            foreach my $feed_id (@raw_feed_ids) {
                next if grep { $_->id == $feed_id } @caller_feed_subscriptions;
                push @rec_ids, $feed_id;
            }
        }
    } else {
        # fallback to doing a bunch of queries
    
        my @exclude_feed_ids = $self->caller_subscriptions->get_column('audiofeed')->all;
    
        my $RECOMMENDATION_LIMIT = 5;
    
        # feeds must be recommendable
        # feeds must have never been subscribed to by caller
    
        # IF numVisits < 50
            # if there is a DC partner, only select feeds with that partner in buckets
        # ELSE
            # buckets
        
        # no duplicate feeds, even if tagged in multiple buckets    
    
        # get recs from bucketTags
        # go through each bucket
        my @buckets = $self->rs('Bucket')->search({}, { order_by => ['position'] })->all;
        
        foreach my $bucket (@buckets) {
            # pick random tag
        
            my @bucket_tags = $bucket->buckettags->search({}, {
                order_by => [\'RAND()'],
            });
        
            # find first tag with recommendable feeds
            foreach my $bucket_tag (@bucket_tags) {
                # pick random feed from tag
                # join on feed, search where feed.recommendable=1
                my $feedtag_search = {
                    tag => $bucket_tag->tag->id,
                    'feed.recommendable' => 1,
                };
                my @feedtag_joins = qw/feed/;
                my $feedtag_attr = {
                    order_by => [\'RAND()'],
                    join => \@feedtag_joins,
                };
        
                # join on partner recommendation if DC
                if ($partner_constraint) {
                    push @feedtag_joins, 'recommendable_feeds';
                    $feedtag_search->{'recommendable_feeds.partner'} = $partner_constraint;
                }
        
                # skip dupes
                $feedtag_search->{'feed.id'} ||= {
                    'NOT IN' => \@exclude_feed_ids,
                };
        
                my $feed_id = $self->rs('Feedtag')->search(
                    $feedtag_search,
                    $feedtag_attr,
                )->get_column('audiofeed')->first;
    
                next unless $feed_id;
                push @rec_ids, $feed_id;
                push @exclude_feed_ids, $feed_id;
                last;
            }
        
            last if @rec_ids >= $RECOMMENDATION_LIMIT;
        }
    }
    
    my $recs_rs;
    if (! @rec_ids) {
        # fallback to recommendable feeds if nothing found
        $recs_rs = $self->rs('Audiofeed')->search({
            recommendable => 1,
        }, {
            order_by => [\'RAND()'],
            rows => 10,
        });
    } else {
        @rec_ids = grep { $_ } @rec_ids;
        $recs_rs = $self->rs('Audiofeed')->search({
            'me.id' => \@rec_ids,
        });
    }
    
    my @feeds = $recs_rs->all;
    
    # sort by order of @rec_ids, not returned from query
    if (@rec_ids) {
        my $feed_map = {
            map { ($_->id => $_) } @feeds
        };

        my @sorted_feeds;
        foreach my $rec_id (@rec_ids) {            
            my $f = $feed_map->{$rec_id};
            unless ($f) {
                print STDERR "\nERROR: could not fetch recommended feed $rec_id\n";
                next;
            }
            
            push @sorted_feeds, $f;
        }
        
        return @sorted_feeds;
    }
    
    return @feeds;
}

# returns arrayref of feeds for a partner directconnect #
sub all_partner_items {
    my ($self) = @_;
    return [] unless $self->partner;
    
    # get first feed associated with this partner
    my @feeds = ($self->rs('Audiofeed')->search({
        'me.partner'   => $self->partner->id,
    })->first);
    
    my @items = map { $_->latest_item } @feeds;
    return [ map {
        Asterysk::Playlist::Item::DirectConnect->new(
            content   => $_->content,
            playlist  => $self,
            feed_item => $_,
        );
    } @items ];
}


# returns arrayref of all feeditems the caller has subscriptions to
sub all_subscribed_items {
    my ($self) = @_;

    my $dbh = $self->dbh || Asterysk::Common::get_db_connection();
    $dbh->{RaiseError} = 1;
    $self->dbh($dbh);
    
    my @all_items;
    
    my $sth = $dbh->prepare(q{
        select
            subscription.id,
            subscription.audioFeed,
            audioFeed.lastContent

		from subscription,audioFeed

		where caller=?
        
        and audioFeed.lastContent != 0
		and subscription.audioFeed = audioFeed.id
		and ! subscription.unsubscribedFlag
		and ! heardLastContent

		group by audioFeed

		order by heardLastContent desc, (rtq*audioFeed.lastUpdate) desc, subscription.id asc
    });
    $sth->{RaiseError} = 1;
    
    if ($sth->execute($self->caller->id)) {
        while (my ($subscription_id, $feed_id, $last_content_id) = $sth->fetchrow_array) {
            next unless $last_content_id;

            # skip dupes (from directconnect)
            next if grep { $feed_id == $_->feed->id } @{ $self->itemsref };
            
            my $playlist_item = Asterysk::Playlist::Item::FeedItem->new(
                content_id      => $last_content_id,
                subscription_id => $subscription_id,
                playlist        => $self,
            ); 

            push @all_items, $playlist_item;
        }
    } else {
        print STDERR "Failed to get playlist: " . $sth->errstr;
    }

    return \@all_items;
}

# get resultset (using caller's result_source)
sub rs {
    my ($self, $class) = @_;
    
    return $self->caller->result_source->schema->resultset($class);
}

__PACKAGE__->meta->make_immutable;
