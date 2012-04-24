package Asterysk::AGI::Controller::Playlist;

use Moose;
extends 'Asterysk::AGI::Controller';
    
use Carp qw( croak );
use Data::Dumper;
use Readonly;
use Switch 'Perl6'; #FIXME:  once the production server is on Perl 5.10 or higher, replace with the built-in "use feature 'switch'";

use Asterysk::AGI::Events;
use Asterysk::AGI::Exceptions;
use Asterysk::AGI::Controller::Prompt;
use Asterysk::Playlist;
use Asterysk::Notification;
use Asterysk::ContentFetcher;
use aliased 'Asterysk::AGI::Commands::Navigation' => 'Command';
use aliased 'Asterysk::AGI::Commands::Comments' => 'CommentsCommand';

Readonly my $subscribed    => 'subscribed';
Readonly my $unsubscribed  => 'unsubscribed';
Readonly my $debug_timing  => 0;

has 'playlist' => (
    is  => 'rw',
    isa => 'Asterysk::Playlist',
);

has 'feed_waiting_for_quikhit' => (
    is => 'rw',
    isa => 'Asterysk::Schema::AsteryskDB::Result::Audiofeed',
    clearer => 'clear_feed_waiting_for_quikhit',
);

sub play {
    my ($self, $c, @params) = @_;

    my $agi = $c->agi;

    my $debug = 1;

    $c->log(4, 'In /Playlist/play') if $debug_timing;

    # play thinking sound while we load the playlist
    $c->busy;

    my $caller = $c->caller;
    
    $self->activate_grammar;

    my $playlist;
    $playlist = Asterysk::Playlist->new(
        caller => $caller,
        dbh => $c->dbh,
        partner => $c->partner,
    );

    if (! $playlist) {
        $c->error(q[Couldn't fetch playlist for caller ] . $caller->id);
        return;
    }
    else {
        $self->playlist($playlist);
    }
    
    $c->context('playlist');
    
    # load playlist items
    $c->profile_mark;
    $playlist->load_items;
    $c->profile_did("load_playlist");
    
    # get playlist item counts and play prompts
    my $share_count           = $playlist->share_count;
    my $subscribed_item_count = $playlist->subscribed_item_count;
    my $recommendation_count  = $playlist->recommendation_count;
    
    # play greeting
    my $played_greeting = 0;
    my $played_dc_intro = 0;
    my $first_item_is_dc = 0;
    my $first_item_is_quikhit = 0;
    my $no_playlist_earcon = 0;
    
    my $first_item = $playlist->get_current_item;
    
    my $is_fresh_quikhit = 
        $first_item->feed && $first_item->feed->is_quikhit && 
        $first_item->feed->is_for_latest_team_game;
    
    if ($first_item && $first_item->is_direct_connect && $c->direct_connect) {
        $first_item_is_dc = 1;
        
        if ($first_item->feed && $first_item->feed->is_quikhit && ! $is_fresh_quikhit) {
            # suppress greeting if it's a quikhit and not ready
            $no_playlist_earcon = 1;
        } else {
            # try and play DC intro
            if ($c->prompt('greetings/intro-' . $first_item->feed->canonicalname)) {
                # played DC intro
                $played_dc_intro = 1;
            } else {
                # no partner-specific intro
            
                if ($caller->numvisits > 1) {
                    # DC non-virgin
                    $c->prompt('greetings/dc-greeting');
                } else {
                    # DC virgin
                    $c->prompt('greetings/dc-virgin');
                }
            
            }
        }
        
        $played_greeting = 1;
    }
    if (! $played_greeting) {
        $c->forward('/Prompt/greeting') unless $c->config->{agi}{skip_greeting};
    }
    
    # nothing at all on playlist
    if (! $playlist->item_count) {
        # prompt...
    }
    
    # no status prompts for virgins or DCs
    if (! $first_item_is_dc && $caller->numvisits > 1) {
        if ($share_count) {
            # you've got ___ new shares
            $c->forward('/Prompt/play', qq{status/shareonly-$share_count});
            $c->forward('/Prompt/play', qq{status/updates-$subscribed_item_count});
        } elsif ($subscribed_item_count) {
            # you have ___ new items
            $c->forward('/Prompt/play', qq{status/found-$subscribed_item_count});
        } elsif ($caller->subscriptions) {
            # no new items for your subscriptions
            $c->forward('/Prompt/play', qq{status/nonew});
        } else {
            # no subscriptions so i'll start with a recommendation
            $c->forward('/Prompt/play', qq{status/nosubscriptions});
        }
    }
    
    $c->earcon('playback') unless $no_playlist_earcon;

    my $last_command = '';
    ITEM:  while(defined (my $item = $playlist->get_current_item)) {
        if ($c->hungup) {
            last;
        }
        
        # look at the last item and compare it to the next item.
        my $last_item = $playlist->get_previous_item;
        if ($last_item) {
            if ($last_item->is_comment && ! $item->is_comment) {
                
                if ($last_item->feed->voicecommentsenabled) {
                    # end of comment playback, ask if they want to leave a comment or return
                    # default to leaving a comment in a few seconds
                    #
                    # "That's it for comments. Would you like to leave your own comment?
                    # If not, press 2

                    if ($c->forward('/Prompt/yes_or_no', 'comments/would', 4)) {
                        $c->log(3, 'User wants to leave a comment');
                        $c->forward('/Comments/leave_comment', $last_item);
                    }
                }
                
                $c->forward('/Playlist/exit_comments_context');

                next ITEM;
            }

            if ($last_item->is_related && ! $item->is_related) {
                # exiting related mode
                $c->context('playlist');
            }
        }
        
        # log listen
        my $type;
        if ($item->is_feed_item) {
            if ($playlist->get_previous_item->is_share) {
                # that's your last share, let's move on to your asterysklist
                $self->play_transition($c, 'playlist');
            }
            # voice playlist episode
            $type = 11;
        } elsif ($item->is_share) {
            $type = 'listen to voice share';
        } elsif ($item->is_recommendation) {
            $type = 'listen to recommendation';
            
            if ($playlist->get_previous_item->is_feed_item) {
                # that's it for your playlist, but i've got some sports, humor...
                $self->play_transition($c, 'lastone');
            } elsif ($playlist->get_previous_item->is_direct_connect) {
                # next up
                $self->play_transition($c, 'dc-afterfirst');
            }
            
        } elsif ($item->is_share_intro) {
            # don't log this
        } elsif ($item->is_related) {
            $type = 'listen to related asterysk';
        } elsif ($item->is_direct_connect) {
            # voice playlist episode
            $type = 11; # should we track DC listen as well?
        } elsif ($item->is_comment) {
            # we don't log listening to individual comments
        } else {
            $c->error("Unknown playlist item type " . ref $item);
            $playlist->go_forward(1);
            next ITEM;
        }
        
        if (! $item->has_logged_listen) {
            $c->log_action_for_playlist_item($type, $item) if $type;
            $item->feed_item->increment_voice_listen_count if $item->has_feed_item;
            
            $item->has_logged_listen(1);
        }
        
        # postpone quikhit if not ready
        if ($item->feed && $item->is_direct_connect && $playlist->at_start &&
            $item->feed->is_quikhit && ! $c->session->checked_quikhit) {
                
            $c->session->checked_quikhit(1);

            # is it ready?
            $c->log(4, "Checking quikhit status for feed " . $item->feed->id);
            my $game_time = $item->feed->latest_team_game_time;
            if ($game_time) {
                $c->log(4, "Game time = " . $game_time->epoch);
                $c->log(4, "Post time = " . $item->feed_item->date->epoch . " id = " . $item->feed_item->id);
            }
            
            if ($is_fresh_quikhit) {
                # need prompt?
                $c->log(3, "Playing quikhit for feed " . $item->feed->name);
                $c->log_action_for_playlist_item('quickhit ready', $item);
            } else {
                # not ready
                $c->log(3, "Quikhit is not ready for feed " . $item->feed->name . ", playing something else");
                $c->log_action_for_playlist_item(47, $item); # quikhit not ready
                $self->feed_waiting_for_quikhit($item->feed);
                
                $c->prompt('quikhit/not_ready');
                
                # play stale quikhit
                
                #$playlist->go_forward(1);
                #next ITEM;
            }
        }
        
        my $play_item_success;
        eval { $play_item_success = $c->forward('/Playlist/play_item', $item, $last_command); };

        EVENT_HANDLER:  my $event = $@;
        my ($filename, $line) = (caller())[1, 2];
        if ($debug_timing) {
            if (! $event) {
                $c->log(3, 'No event occurred');
            } else {
                my $event_type;
                if (! ref $event) {
                    $event_type = qq(string:  '$event');
                } else {
                    $event_type = ref $event;
                }
                $c->log(3, "/Playlist/play_item threw $event_type at $filename line $line");
            }
        }
            
        $c->log(4, 'Back from /Playlist/play_item') if $debug_timing;
        if (! $event) {
            # The user listened all the way through the item (or it failed to play).
            if ($play_item_success) {
                $item->stopped_listening({ debug => $debug_timing });
                $item->reset_timer();
                $item->mark_heard() unless $c->config->{agi}{do_not_mark_as_heard};
                $self->finished_listening_to_item($c, $item);
            } else {
                # some sort of unknown failure
                $c->error("Failed to play item, cause unknown") unless $c->hungup;
            }
            
            if ($c->hungup) {
                $c->log(1, "User hung up while listening to an item");
                last;
            }
            
            $playlist->go_forward(1);
            next ITEM;
        }
        elsif (! ref $event) {
            # Some code blew up with a string exception.
            # Rethrow it so the caller can handle it.
            # If the caller is Asterysk::AGI::dispatch(), it will simply print
            # an informative error message and end the AGI request.
            $item->stopped_listening({ debug => $debug_timing });
            $item->reset_timer();
            die $event;
        } elsif ($event->isa('Asterysk::AGI::MissingSoundFile')) {
            my $content_id = $event->content ? $event->content->id : '(unknown)';
            $c->log(2, "Missing content id=$content_id, path: " . $event->path);
            $playlist->go_forward(1);
            next ITEM;
        } elsif ($event->isa('Asterysk::AGI::UserGaveCommand')) {
            $last_command = $event->command;
            
            if ($event->score < $c->config->{agi}{speech_score_threshold}) {
                # Couldn't decipher what the user said.  Resume playback from wherever we left off.
                $item->stopped_listening({ debug => $debug_timing });
                $item->record_offset({ debug => $debug_timing });
                $item->reset_timer();

                # The behavior is just like the pause command's (except that we don't wait
                # for a keypress before resuming playback).
                $last_command = Command->pause;
                next ITEM;
            } else {
                my $command_mode = Asterysk::AGI::Commands->mode($last_command);
                
                given ($last_command) {
                    when Command->play_next {
                        $item->stopped_listening({ debug => $debug_timing });
                        $item->reset_timer();
                        $item->mark_heard() unless $c->config->{agi}{do_not_mark_as_heard};
                        
                        $c->earcon('skipthis');
                        $c->log_action_for_playlist_item('skip', $item, { mode => $command_mode });
                        $c->log(3, 'COMMAND play_next');
                        
                        $self->finished_listening_to_item($c, $item);
                                                
                        if ($item->is_share && $item->messagecontent) {
                            # Skip past both the share and the share intro.
                            $playlist->go_forward(2);
                        } else {
                            $playlist->go_forward(1);
                        }
                                                
                        next ITEM;
                    }
                    when Command->previous {
                        $item->stopped_listening({ debug => $debug_timing });
                        $item->reset_timer;

                        $c->earcon('previous');
                        $c->log_action_for_playlist_item('previous', $item, { mode => $command_mode });
                        $c->log(3, 'COMMAND previous');
                        if ($item->is_share && $item->messagecontent) {
                            # Skip past both the share and the share intro.
                            $playlist->go_back(2);
                        } else {
                            $playlist->go_back(1);
                        }                            
                        next ITEM;
                    }
                    when Command->replay {
                        $item->stopped_listening({ debug => $debug_timing });
                        $item->reset_timer;
                        $item->reset_offset;

                        $c->earcon('replay');
                        $c->prompt('playcontent/backtop');  # ok from the beginning
                        
                        $c->log_action_for_playlist_item('replay', $item, { mode => $command_mode });
                        $c->log(3, 'COMMAND replay');

                        # Now replay this same content, from the beginning.
                        next ITEM;
                    }
                    when Command->rewind {
                        my $s = $c->config->{agi}{rewind_seconds};
                        $item->stopped_listening({ debug => $debug_timing });
                        $item->record_offset({ with_extra_seconds => $s, debug => $debug_timing });
                        $item->add_to_listen_length($s);
                        $item->reset_timer;

                        $c->earcon('rewind');
                        $c->log(3, 'COMMAND rewind');
                        $c->log_action_for_playlist_item('rewind on phone', $item, { mode => $command_mode });
                        next ITEM;
                    }
                    when Command->pause {
                        my $s = $c->config->{agi}{resume_seconds};
                        $item->stopped_listening({ debug => $debug_timing });
                        $item->record_offset({ with_extra_seconds => $s, debug => $debug_timing });
                        $item->reset_timer;

                        $c->log(3, 'COMMAND pause');
                        $c->log_action_for_playlist_item('pause on phone', $item, { mode => $command_mode });
                        $c->forward('/Prompt/wait_to_unpause');
                        next ITEM;
                    }
                    when Command->fast_forward {
                        my $s = $c->config->{agi}{fast_forward_seconds};
                        $item->stopped_listening({ debug => $debug_timing });
                        $item->record_offset({ with_extra_seconds => $s, debug => $debug_timing });
                        $item->reset_timer;

                        $c->earcon('fastforward');
                        $c->log_action_for_playlist_item('fast forward on phone', $item, { mode => $command_mode });
                        $c->log(3, 'COMMAND fast_forward');
                        next ITEM;
                    }
                    when Command->help {
                        my $s = $c->config->{agi}{resume_seconds};
                        $item->stopped_listening({ debug => $debug_timing });
                        $c->log_action('help', { mode => $command_mode });
                        $c->log(3, 'COMMAND help');

                        eval { $c->forward('/Help/playback') };
                        my $event = $@ || '';
                        my $event_type = ref $event;
                        if (! $event || ($event_type eq 'Asterysk::AGI::UserGaveCommand'
                                && $event->command() =~ Command->resume)) {
                            # Just start playing where we left off.
                            $item->record_offset({ with_extra_seconds => $s, debug => $debug_timing });
                            $item->reset_timer();
                            next ITEM;                            
                        } else {
                            # Let the item loop's main exception handler catch it.
                            # This has the effect of executing whatever command the user gave:
                            # rewind, fast-forward, et cetera.
                            $c->log(3, 'about to propagate event');
                            $last_command = $event->command;
                            goto EVENT_HANDLER;
                        }
                    }
                    when Command->subscribe {
                        my $s = $c->config->{agi}{resume_seconds};
                        $item->stopped_listening({ debug => $debug_timing });
                        $item->record_offset({ with_extra_seconds => $s, debug => $debug_timing });
                        $item->reset_timer;

                        $c->debug('COMMAND subscribe');
                        
                        if ($item->is_direct_connect && $c->direct_connect
                            && $c->direct_connect->unsubscribable) {

                            # you're already subscribed
                            $c->prompt('unsubscribe/alreadysubscribed1');
                            
                            next ITEM;
                        }
                        
                        my $state = $c->forward('/Playlist/toggle_subscription', $item, $command_mode);
                        if ($state eq $subscribed) {
                            next ITEM;
                        } elsif ($state eq $unsubscribed) {
                            $playlist->go_forward(1);
                            next ITEM;
                        } else {
                            Asterysk::Exception->UnreachableCodeReached->throw;
                        }
                    }
                    when Command->related {
                        # record timing
                        my $s = $c->config->{agi}{resume_seconds};
                        $item->stopped_listening({ debug => $debug_timing });
                        $item->record_offset({ with_extra_seconds => $s, debug => $debug_timing });
                        $item->reset_timer;
                        
                        if ($c->session->in_related_context) {
                            # already in related asterysks, they pressed 3 to get back to the playlist
                            $c->context('playlist');
                            
                            # remove related items from playlist
                            $playlist->remove_related_items;
                            
                            # back to your playlist
                            $c->prompt('comments/back');
                            
                            next ITEM;
                        } else {
                            # go into related asterysks context
                            $c->log_action_for_playlist_item('listen to related asterysk', $item, { mode => $command_mode });
                        
                            # get related items
                            my @related = $c->forward('/Related/get_for_feed', $item->feed);
                        
                            unless (@related) {
                                # sorry i can't find any related asterysks
                                $c->prompt('relevant/no-relevant');
                            
                                # resume playback
                                next ITEM;
                            }
                            
                            # this may take a while to load
                            $c->forward('/Prompt/play_busy');

                            # mark current item as heard (correct behavior? maybe not)
                            $item->mark_heard unless $c->config->{agi}{do_not_mark_as_heard};
                        
                            # instantiate related playlist items for insertion into the current playlist
                            my @related_items;
                            foreach my $related_info (@related) {
                                my ($feedId, $canonical, $nam, $dsc, $content, $vce, $comments, $afi) = (@$related_info);
                                next unless $feedId && $canonical && $content;
                                my $playlist_item = Asterysk::Playlist::Item::Related->new(
                                    content_id => $content,
                                    playlist   => $playlist,
                                );
                            
                                push @related_items, $playlist_item;
                            }
                        
                            # insert related items into playlist
                            $playlist->insert_items(@related_items);
                        
                            # reset prompt
                            $c->session->introduced_related_asterysks(0);
                            
                            # set context
                            $c->context('related');
                            
                            # press three to return to your playlist
                            $c->prompt('relevant/press3');
                                                    
                            # i found X related asterysks
                            $c->prompt('relevant/found-' . (scalar @related_items));
                            
                            # advance playlist
                            $playlist->go_forward(1);
                            
                            next ITEM;
                        }
                    }
                    when (Command->text_me && $c->session->context ne 'comments') {
                        my $s = $c->config->{agi}{resume_seconds};
                        $item->stopped_listening({ debug => $debug_timing });
                        $item->record_offset({ with_extra_seconds => $s, debug => $debug_timing });
                        $item->reset_timer;

                        $c->log_action_for_playlist_item('textme', $item, { mode => $command_mode });
                        $c->log(3, 'COMMAND text_me');
                        $c->forward('/Playlist/text_me', $item);
                        next ITEM;
                    }
                    when Command->comments {
                        if (! $c->session->in_comments_context) {
                            # enter comments mode
                            
                            $item->stopped_listening;
                            $item->reset_timer;

                            $c->log_action_for_playlist_item('listen to feeditem comments', $item, { mode => $command_mode });
                            $c->log(3, 'COMMAND comments');

                            $c->forward('/Comments/entry', $item);
                        } else {
                            $c->forward('/Playlist/exit_comments_context');
                        }

                        next ITEM;
                    }
                    when CommentsCommand->leave_comment {
                        # leave comment
                        $c->log(3, 'COMMAND leave_comment');
                        
                        $item->stopped_listening;
                        $item->reset_timer;
                        
                        $c->forward('/Comments/leave_comment', $item);
                    }

                    when CommentsCommand->go_back {
                        $c->log(3, 'COMMAND go_back');
                        $c->forward('/Playlist/exit_comments_context');
                        
                        # we're pointed at the next item, go back to what they were listening to
                        $playlist->go_back(1);
                        
                        next ITEM;
                    }
                    default {
                        $c->log(1, 'Unrecognized command ', $event->command);
                        $item->stopped_listening({ debug => $debug_timing });
                        $item->reset_timer;

                        $playlist->go_forward(1);
                        next ITEM;
                    }
                }
            }
        }
        elsif (ref $event && $event->isa('Asterysk::AGI::NoPathToContent')
                   || $event->isa('Asterysk::AGI::MissingSoundFile')) {
            
            # didn't start listening, think this is unnecessary
            #$item->stopped_listening({ debug => $debug_timing });
            #$item->reset_timer();

            $c->log(1, 'In /Playlist/play, had a problem playing content.  Skipping to the next item.  Exception dump:');
            my $content_id = $event->content ? $event->content->id : "undef";
            $c->error("Error locating content $content_id");
            
            # what should we do when a file is missing? hang up?
            $playlist->go_forward(1);
            next ITEM;
        }
        elsif (ref $event && $event->isa('Asterysk::AGI::UserHungUp')) {
            $item->stopped_listening({ debug => $debug_timing });
            $item->record_offset({ debug => $debug_timing });
            $item->reset_timer;
            
            $self->_store_perfect_memory($c, item => $item);
            $c->log(3, 'User hung up while listening to an item') if $debug;
            $c->detach;
            last;
        }
        else {
            # Unknown error.  Rethrow it so the caller can handle it.
            die $event;
        }
    }
    
    $self->deactivate_grammar;
    
    # that's it! bye
    $c->prompt('finalwrapup/thatsall');
}

sub exit_comments_context {
    my ($self, $c) = @_;
    
    # back to your playlist
    $c->prompt('comments/back');
    
    $c->context('playlist');
    
    $c->log(3, 'exiting comments context');
    $self->playlist->remove_comments;
}

sub _store_perfect_memory {
    my ($self, $c, %args) = @_;
    my $item = $args{item};
    my $content = $item->content;
    my $debug = 1;
    
    my $absolute_offset = $content->offset_in_seconds if $debug_timing;
    return unless $absolute_offset;
    
    $c->log(3, 'Storing Perfect Memory');
    $c->log(4, "Absolute offset is $absolute_offset");
    $c->caller->update({ contentmark => $content->id * 10000 + $absolute_offset });

    return;
}

sub toggle_subscription {
    my ($self, $c, $item, $command_mode) = @_;
    
    # don't ask to subscribe to comments
    return if $c->session->in_comments_context;
    
    my $feed_item = $item->feed_item
        or return $c->fatal_detach("No feed item for playlist item $item in toggle_subscription");
        
    my $feed = $feed_item->audiofeed
        or return $c->fatal_detach("Could not find audiofeed for item " . $feed_item->id);
        
    my $caller = $c->caller;
    
    if ($caller->has_subscription_to_feed($feed)) {
        $c->earcon('unsubscribe');
        
        # ask y/n if they want to unsubscribe
        my $do_unsub = $c->forward("/Prompt/yes_or_no", 'unsubscribe/confirm', 10);
        if ($do_unsub) {
            $c->prompt('unsubscribe/unsubscribed');
            $c->forward('/Subscription/remove_subscription_for_feed', $feed);
            return $unsubscribed;
        } else {
            $c->prompt('unsubscribe/keep');
            return $subscribed;
        }
    } else {
        # create subscription
        $c->prompt('unsubscribe/notsubscribed');  # Ok, I'll add this program to your Asterysklist
        $c->forward('/Subscription/create_subscription', $feed);
        
        push @{$c->session->subscribed_feeds}, $item->feed;
        
        # log it
        my $log_action = $item->subscribe_action;
        if ($log_action) {
            $c->log_action_for_playlist_item($log_action, $item, { mode => $command_mode });
        }

        return $subscribed;
    }
}

sub text_me {
    my ($self, $c, $item) = @_;
    
    my $feed_item = $item->feed_item;
    my ($sent_email, $sent_sms, $info) = Asterysk::Notification->textme($c->caller, $feed_item);
    $c->log(2, "Sent $info textme. email=$sent_email sms=$sent_sms");
    if ($sent_sms) {
	    $c->prompt('textme/text');
    } elsif ($sent_email) {
	    $c->prompt('textme/email');
    }
}

# finished with a section of the playlist, moving on to the next
# e.g. "that's your last share, let's move on to your asterysklist..."
sub play_transition {
    my ($self, $c, $trans) = @_;

    $c->log(4, "Playing transition $trans");

    $c->stash->{played_transitions} ||= {};
    return if $c->stash->{played_transitions}{$trans}++;

    # here's where we randomly play tips
    my $tip_freq = $c->config->{agi}{tip_frequency} || 0.2;
    if (rand() < $tip_freq) {
        $c->forward('/Tip/play_random');
    }

    $c->prompt('sectionwrapup/' . $trans);
}

sub play_intro_for_item {
    my ($self, $c, $item, $last_command) = @_;
    my $content = $item->content;

    # What prompt to play (if any) depends on where's we're coming from
    # and what kind of item this is.

    $c->log(4, "content offset: " . ($content->offset_in_seconds || 0) . " perfect memory: " . (
        $content->perfect_memory ? 'yes': 'no'));

    if ($content->offset_in_seconds) {
        # We're in the middle of an item.
        
        if ($content->perfect_memory) {
            # We're resuming from a previous call, via Perfect Memory.            
            # Play "resuming playback of [title]."
            $c->prompt('introduceunhearditem/resume');
            $c->forward('/Prompt/play_item_title', $item->feed_item) if $item->has_feed_item;
        } else {
            # Play nothing; the offset indicates we're still in the same item, and we
            # don't want to play the item a second time.
        }
        
        return;
    }
    
    if ($item->is_recommendation) {
        # It's a recommendation.  
        if (! $c->session->introduced_recommendations) {
            $c->prompt('introduceunhearditem/recommend'); # "here's a asteryskpost from..."
            $c->forward('/Prompt/play_item_title', $item->feed_item) if $item->has_feed_item;
        } else {
            $c->session->introduced_recommendations(1);
            $c->prompt('introduceunhearditem/nextrecommendation'); # "here's another Asterysk you might like."
        }
    } elsif ($item->is_share_intro) {
        # Intros don't get intros.  Play nothing.
    } elsif ($item->is_share) {
        # It's a share.  Does it have a custom intro, recorded by the sharing user?

        if ($item->share->messagecontent) {
            # It does have a custom intro.  We'll have played that already (it will be
            # the previous Item in the Playlist).  Don't play any additional intro.
        } else {
            # It doesn't have a custom intro.  Play "next, a share from a friend."
            # Then play the item title, if any.
            $c->prompt('introduceunhearditem/friend');
            $c->forward('/Prompt/play_item_title', $item->feed_item) if $item->has_feed_item;
        }
    } elsif ($item->is_direct_connect) {
        # just play title
        if ($item->feed->id == 1772 || $item->feed->id == 1768 || 
                $item->feed->notitleplay || $item->feed->is_quikhit) {
            # skipping titles for a few feeds for now
            # 5/12/10
        } else {
            $c->forward('/Prompt/play_item_title', $item->feed_item) if $item->has_feed_item;
        }
    } elsif ($item->is_feed_item) {
        # It's a "normal" feed item.  Play "next on your playlist,"
        # then play the title (if any).
        $c->prompt('introduceunhearditem/next');
        $c->forward('/Prompt/play_item_title', $item->feed_item) if $item->has_feed_item;
    } elsif ($item->is_related) {
        if ($c->session->introduced_related_asterysks) {
            $c->prompt('relevant/next'); # next, another related asterysk from
        } else {
            $c->session->introduced_related_asterysks(1);
            $c->prompt('relevant/introduce'); # here's a relayed asterysk from
        }
        $c->forward('/Prompt/play_item_title', $item->feed_item);
    } elsif ($item->is_comment) {
        if ($c->session->introduced_comments) {
            # "Next, a comment from"
            $c->prompt('comments/next');
            
            # TODO:  re-record prompt to remove the "from," or record a new prompt,
            # or do text-to-speech on the commentator's name.
            
            # get first name of commenter
            my $name = $item->comment->name || '';
            my ($first_name) = $name =~ /(\w)+\b/;
            $first_name ||= 'undefined';
            
            # say commenter name
            $c->prompt("/first-names/$first_name", $first_name);
        } else {
            # This is the first comment.  Play some canned instructions about how to
            # navigate comments (i.e. what commands are available).
            $c->prompt('comments/press2-back');
            $c->session->introduced_comments(1);
        }
    } else {
        $c->log(1, q[WARNING:  couldn't figure out what kind of intro to play.  Unhandled edge case]);
    }
    
    # ... with comments
    if ($item->is_feed_item || $item->is_share || $item->is_recommendation 
        || $item->is_direct_connect || $item->is_related) {
    
        my $comment_count = $item->feed_item->comments->count;
        if ($comment_count == 1) {
            $c->prompt('comments/have-1');
        } elsif ($comment_count > 1) {
            $c->prompt('comments/have-2');
        }
    }
    
    return;
}

=head2 play_item($c, $item, $last_command)

Plays a Asterysk::Playlist::Item

=cut
sub play_item {
    my ($self, $c, $item, $last_command) = @_;
    my $caller = $c->caller;
    my $debug = 1;
    
    my $content = $item->content;
    unless ($content) {
        $c->warn("Could not find content for item $item");
        return;
    }
    my $content_id = $content->id || '';
    
    $c->log(4, qq[In /Playlist/play_item, content is  '$content_id']) if $debug_timing;
    $c->forward('/Playlist/play_intro_for_item', $item, $last_command);

    # clear this flag so it doesn't resume twice
    $item->content->perfect_memory(0);

    $c->log(3, 'Playing ' . (ref $item) . ' content ' . $content->id . ' for caller ' . $caller->id) if $debug;
    
    # play ad
    if ($c->config->{agi}{play_ads} && ! $self->playlist->at_start
        && ! $c->session->in_comments_context && ! $item->is_comment) {
        $c->forward("/Ad/play");
    }
    
    return $c->forward('/Playlist/play_content', $content, $item);
}

=head2 play_content

DIAGNOSTICS:

=over 4

=item
Passes through any exceptions thrown by Asterysk::Content::get_wrapped_slin_filename.

=item
If Asterysk::Content::get_wrapped_slin_filename succeeds, but returns an empty path, throws
a Asterysk::AGI::NoPathToContent.

=back

=cut
sub play_content {
    # You must pass $optional_item if you want listen-length tracking.
    # It's optional only because a share's messagecontent object can be passed in as a "raw" content object.
    my ($self, $c, $content, $optional_item) = @_;
    my $agi = $c->agi;
    my $debug = 0;

    $c->log(4, 'In /Playlist/play_content') if $debug_timing;
        
    # reset jumpfile agi status vars
    $c->agi->set_variable(jumpfile => '');
    $c->agi->set_variable(jumpfile_size => 0);
    
    # fetch content (might take a sec)
    my $fetcher = $c->content_fetcher;
    my $orig_path = $fetcher->is_content_cached($content->id) || $c->fetch_content_cached($content);

    my $path;
    if (defined $content->offset_in_seconds && $content->offset_in_seconds == 0) {
        $path = $orig_path; # cool
    } else {
        $c->log(4, 'In /Playlist/play_content, offset_in_seconds ==', $content->offset_in_seconds) if $debug;

        # This might take a sec, so play an earcon.
        $c->forward('/Prompt/play_busy');
        
        my $secs = $content->offset_in_seconds;
        if (! $orig_path) {
            # content is missing
            $c->log(2, "Missing content " . $content->id);
            Asterysk::AGI::MissingSoundFile->throw(content => $content);
        }            

        $c->log(4, "making jumpfile for $orig_path offset $secs secs");
        $c->profile_mark;
        my $jumpfile_retval = $agi->exec(
            'AGI',
            "asterysk_make_jumpfile.pl,$orig_path,$secs",
        );
        $c->profile_did('asterysk_make_jumpfile');
        
        # get return values
        if ($jumpfile_retval == -1) {
            my $error = $c->var('error');
            die "Remote AGI call to asterysk_make_jumpfile.pl failed:  $error";
        } elsif ($jumpfile_retval == 0) {
            $path = $c->var('jumpfile');
        } else {
            Asterysk::Exception->UnreachableCodeReached->throw();
        }
        $c->log(4, "Jumpfile AGI returned $jumpfile_retval");
        $c->log(3, "Remote jumpfile:  $path");
    }

    if (! $path && ! $content->offset_in_seconds) {
        $c->prompt('root/invalid_item');
        Asterysk::AGI::NoPathToContent->throw( content => $content );
    }
    elsif (! $c->check_if_content_path_exists($path) && ! $content->offset_in_seconds) {
       # this check only works if the fastagi daemon is running on the content server
        $c->prompt('root/invalid_item');
        $c->log(2, "Missing content $content, path: $path");
       Asterysk::AGI::MissingSoundFile->throw(content => $content, path => $path);
    } elsif ($c->check_if_content_path_exists($path)) {
        my $id = $content->id;
        $c->log(3, "Playing content $id (remote path $path)") if $debug_timing;

        # SpeechBackground takes path minus extension
        my $content_ext = $c->config->{agi}{sound_file_extension};
        $path =~ s/(\.$content_ext)$//i;
    
        $optional_item->started_listening({ debug => $debug_timing }) if defined $optional_item;

        # Play file.  Unless the user listens straight through the whole item without giving
        # a command (and without errors), this will always throw an exception:
        # - a Asterysk::AGI::UserGaveCommand,
        # - a Asterysk::AGI::UserHungUp,
        # - or one of a number of error-type exceptions (maybe including strings)
        $c->forward('/UserInput/play_file', path => $path);
    }

    # if we get here, the caller finished listening to the whole
    # content without saying/pressing anything
    
    # if this is a directconnect item or recommendation
    # prompt caller to subscribe
    if ($optional_item &&
        (! ($c->direct_connect && $c->direct_connect->unsubscribable && $optional_item->is_direct_connect) || $optional_item->is_recommendation)) {
        
        $c->forward('/Playlist/offer_subscribe', $optional_item);
    }
    
    return 1;
}

sub offer_subscribe {
    my ($self, $c, $item) = @_;
    
    # don't ask to subscribe to comments
    return if $c->session->in_comments_context;
    
    # don't offer if caller has subscribed
    # don't offer if DC is unsubscribable
    if ($c->caller->has_subscribed_to_feed($item->feed) || 
        ($c->direct_connect && $c->direct_connect->unsubscribable)) {
        return;
    }
    
    # don't offer if commenting disabled
    return if $item->feed->voicecommentsenabled;
    
    # would you like to subscribe? say yes or no (5 second timeout)
    my $do_sub = $c->forward("/Prompt/yes_or_no", 'offersubscribe/subscribe', 5);
    if ($do_sub) {
        my $did_sub = $c->forward('/Playlist/toggle_subscription', $item, 'unknown');
    } else {
        $c->prompt('offersubscribe/nothanks');
    }
}

# called when the caller has finished listening to an episode, either by reaching the end or skipping it
sub finished_listening_to_item {
    my ($self, $c, $item) = @_;
    
    # play virgin greeting
    if ($c->session->needs_virgin_greeting) {
        $c->session->clear_needs_virgin_greeting;
        $c->prompt('greetings/intro-asterysk');
    }
    
    # if waiting for a quikhit, play it if available
    my $quikhit_feed = $self->feed_waiting_for_quikhit;
    if ($quikhit_feed) {
        $self->clear_feed_waiting_for_quikhit;
        
        if ($quikhit_feed->is_for_latest_team_game) {
            # its ready
            $c->log(2, "Quikhit for " . $quikhit_feed->name . " is now ready, playing");
            $c->log_action_for_playlist_item('quickhit became ready', $item);
            $c->prompt('quikhit/became_ready');
            
            $self->playlist->insert_quikhit($quikhit_feed->latest_item);
            $self->playlist->go_back(1);
        } else {
            # its not ready
            $c->log(2, "Quikhit for " . $quikhit_feed->name . " was not ready");
            $c->log_action_for_playlist_item('quickhit did not become ready', $item);

            $c->prompt('quikhit/still_not_ready');
        }
    }
}

1;
