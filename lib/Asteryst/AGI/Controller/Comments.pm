package Asterysk::AGI::Controller::Comments;

use Moose;
extends 'Asterysk::AGI::Controller';

use Asterysk::Playlist::Item::Comment;
use aliased 'Asterysk::AGI::Commands::GiveComment' => 'Command';

sub entry {
    my ($self, $c, $item) = @_;
    my $playlist = $item->playlist;

    $c->context('comments');
    
    my @comments = $item->comments;
    my $comment_count = @comments;

    if (!$comment_count) {
        # "You're the first to leave a comment on"
        $c->prompt('givecomment/first');
        $c->forward('/Prompt/play_item_title', $item->feed_item);
    } else {
        # there are N comments
        $c->prompt('comments/status-' . $comment_count);
    }

    $c->session->introduced_comments(1);

    if ($comment_count == 0) {
        $c->forward('/Comments/leave_comment', $item);
    } else {
        my @comment_items;
        COMMENT:  for my $comment (@comments) {
            my $content = $comment->content or next COMMENT;
            my $comment_item = Asterysk::Playlist::Item::Comment->new(
                content => $content,
                playlist => $playlist,
                comment => $comment,
            );
            push @comment_items, $comment_item;
        }
        $playlist->insert_items(@comment_items);
        
        # point at next item in playlist (comments)
        $playlist->go_forward(1) if @comment_items;
        
        # reset prompt
        $c->session->introduced_comments(0);
    }

    return;
}

sub leave_comment {
    my ($self, $c, $item) = @_;
    
    $c->log(3, "leaving comment on feed " . $item->feed->name);
    
    my $feed = $item->feed;
    unless ($feed->voicecommentsenabled) {
        # prompt
        $c->prompt('comments/disabled');
        $c->context('playlist');
    }

    $c->prompt('givecomment/record_press_1');
    
    # generate temp filename
    my $filename_base = '/tmp/cmt_' . $item->feed_item->id . '_' . time() . 
        '_' . int(rand(10000));
    my $filename = $filename_base . '.' . $c->config->{agi}{sound_file_extension};
    
    # configuration for silence detection / max length
    my $silence = $c->config->{agi}{comment_silence_detection} || 0;
    my $max_duration = $c->config->{agi}{comment_max_length} || 0;
    
    # record comment, stops when user hits #
    $c->earcon("beep");
    return if $c->hungup;
    my $rv = $c->agi->exec("Record", "$filename, $silence, $max_duration");
    return if $c->hungup;
    
    # get recorded file path
    my $path = $filename;
    # $c->var('RECORDED_FILE');
    
    if ($path) {
        $c->log(2, "Recorded new comment, path=$path");
        
        # supports "publish comment", "try again" and "cancel"
        $c->push_grammar('givecomment');
        
        # play comment, get input
        CONFIRM_COMMENT:

        # okay i'll play back your comment. press one to publish, two to try again, star to cancel
        # or say "Publish comment" / "Retry" / "Cancel" 
        $c->prompt('givecomment/confirm2');
        
        return $c->detach if $c->hungup;

        # playback comment
        eval {
            # strip extension
            $c->forward('/UserInput/play_file', path => $filename_base, timeout => 20);
        };
        
        if ($@) {
            my $event = $@;

            if ($event->isa('Asterysk::AGI::UserGaveCommand')) {
                if ($event->score < $c->config->{agi}{speech_score_threshold}) {
                    # didn't understand what they said
                    goto CONFIRM_COMMENT; # lame!
                } else {
                    # recognized speech
                    if ($event->command =~ Command->publish_comment) {
                        # publish the comment
                        #$c->busy; # tick tock tick tock....
                        
                        # okay, i'm about to publish your comment... hang on
                        $c->prompt('comments/saving');
                        
                        if ($self->_publish_comment($c, $path)) {
                            my $content_id = $c->var('stored_comment_content_id');
                            if ($content_id) {
                                # create audioComment row
                                my $cmt = $c->schema->resultset('Audiocomment')->create({
                                    caller => $c->caller->id,
                                    audiofeeditem => $item->feed_item->id,
                                    content => $content_id,
                                });
                                $c->log(2, "Created audioComment, id=" . $cmt->id);
                                
                                # your comment has been published
                                $c->prompt("givecomment/published");
                            } else {
                                # failed to save comment
                                return $c->fatal_detach("failed to publish comment");
                            }
                        } else {
                            # publishing failed
                            return $c->fatal_detach("failed to publish comment");
                        }
                    } elsif ($event->command =~ Command->try_again) {
                        # try again
                        $c->forward('/Comments/leave_comment', $item);
                    } elsif ($event->command =~ Command->cancel) {
                        # back out
                        #  ... falls through
                    }
                }
            } elsif ($event->isa('Asterysk::AGI::UserHungUp')) {
                # caller hung up while leaving a comment... what do we do?
                $c->log(2, "Caller hung up while leaving a comment");
                return $c->detach;
            } else {
                $c->log(1, "got unknown event from play_file in leave_comment: $event");
            }
        }
        
        # got no event, either timeout or GET DATA error. can't be sure which, so just bail out
        
        $c->pop_grammar; # don't need givecomment grammar
        
    } else {
        return $c->fatal_detach("Failed to get recorded file path after Record()");
    }

    # done commenting, back to playlist
    $c->context('playlist');
}

sub _publish_comment {
    my ($self, $c, $path) = @_;

    $c->agi->exec("AGI", "asterysk_publish_comment.pl,$path");
    my $content_id = $c->var('stored_comment_content_id'); # does this work? maybe
    
    # assume success for now
    return 1;
}

1;
