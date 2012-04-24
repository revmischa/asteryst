package Asteryst::AGI::Controller::Publish;

use Moose;
extends 'Asteryst::AGI::Controller';

use Asteryst::Notification;
use File::Temp qw/tempfile/;

# select a asterystcast to publish to
sub entry {
    my ($self, $c) = @_;
    
    $c->log(1, "Caller " . ($c->caller->name || $c->caller->phonenumber) . " entered publisher app");
        
    unless ($c->caller->has_rtqs) {
        # caller doesn't have any feeds to publish to
        
        $c->log(1, "Caller has no asterystcasts to publish to");
        $c->prompt('publisher/not-ready');
        
        return;
    }
    
    $c->forward('/Publish/choose_feed_begin');
}

sub choose_feed_begin {
    my ($self, $c) = @_;
    
    # get caller's asterystcasts
    my @feeds = $c->caller->rtqs;
    
    if (@feeds == 1) {
        # only one asterystcast
        # welcome to asterystcasting. ready to record a new post of
        $c->prompt('publisher/welcomeToAsterystCasting');
        # (feed name)
        $c->forward('/Prompt/play_feed_title', $feeds[0]);
        $c->forward('/Publish/begin_recording', $feeds[0]);
    } else {
        # welcome to asterystcasting
        $c->prompt('publisher/welcome');

        # pick asterystcast
        $c->session->caller_can_publish_multiple_rtqs(1);
        $c->forward('/Publish/choose_feed', \@feeds);
    }
}

# give caller a menu of feeds to choose from
sub choose_feed {
    my ($self, $c, $feeds) = @_;
    
RESTART:
    $c->log(1, "Selecting asterystcast a publish to...");
    
    # how many digits of input we're expecting
    my $max_digits = @$feeds < 10 ? 1 : 2;
    
    $c->prompt('publisher/choose/choose');
    
    my $process_digit = sub {
        my ($digit) = @_;
        
        if ($digit eq '*') {
            # back to start
            goto RESTART;
        } elsif ($digit > @$feeds) {
            # invalid number
            # that's not one of the choices
            $c->prompt('publisher/choose/wrong');
            return 0;
        } else {
            my $selected_feed = $feeds->[$digit - 1]
                or return $c->fatal_detach("Failed to find feed number $digit in feed publish list");
        
            # cool, ready to record
            $c->forward('/Publish/prepare_record', $selected_feed);
            return 1;
        }
    };
    
    for (my $num = 1; $num <= @$feeds; $num++) {
        return if $c->hungup;
        
        $c->prompt('publisher/digit/' . $num);
        
        my $feed = $feeds->[$num - 1]
            or return $c->fatal_detach("Failed to find feed number $num in feed publish list");
        
        my $cname = $feed->canonicalname or next;
        
        my $feed_title_path = $c->forward('/Prompt/get_path', "programs/$cname");
        $c->log(4, " > $num - $cname");
        
        if (! -e ($feed_title_path . '.' . $c->config->{agi}{sound_file_extension})) {
            # no title prompt exists for this feed, do TTS
            $c->log(3, "Could not locate feed title $feed_title_path");
            $c->forward('/Prompt/tts', $feed->shortname);
            
            $feed_title_path = undef;
        }
        
        my $lc_num = $c->forward('/UserInput/get_dtmf_input',
            $feed_title_path,
            0.1, # timeout
            $max_digits,
        );
        
        return if $c->hungup;
    
        if ($lc_num && $lc_num > 0) {
            # they entered some numbers
            $c->log(3, "Caller chose feed $lc_num");
    
            # TODO: go back to start if *
    
            return if $process_digit->($lc_num);
        }
    }

    return if $c->hungup;
    
    # wait for input
    my $input = '';
    for (1 .. $max_digits) {
        # wait_for_digit returns ascii value of the digit for some dumb reason
	my $digit = $c->agi->wait_for_digit(4000);
	last if $digit <= 0;

	$input .= chr($digit);

	if (length $input >= $max_digits) {
	    last;
	}
    }

    return if $c->hungup;
    if ($input) {
        $c->log(3, "wait_for_digit returned: $input");
        return if $process_digit->($input);
    }
    
    # fell through, no input.
    # try pressing the number on your keypad
    $c->prompt('publisher/choose/nm');
    goto RESTART;
}

sub prepare_record {
    my ($self, $c, $feed) = @_;
    
    # press one when you are ready to record a new post of
    $c->prompt('publisher/start');
    
    # feed name
    $c->forward('/Prompt/play_feed_title', $feed);
    
    if ($c->session->caller_can_publish_multiple_rtqs) {
        # press star to go back and record a different asterystcast
        $c->prompt('publisher/different');
    }
    
    return if $c->hungup;
    
PREPARE:
    my $input = $c->agi->wait_for_digit(30000);
    return if $c->hungup;
    if ($input && chr($input) eq '1') {
        
        # "1", ready to record
        $c->forward('/Publish/begin_recording', $feed);
    } elsif ($input && chr($input) eq '*' 
        && $c->session->caller_can_publish_multiple_rtqs) {
        
        # "*", pick different asterystcast
        return $c->forward('/Publish/choose_feed_begin');
    } elsif (defined $input && $input == 0) {
        # no input
        
        # please call back when you are ready to record
        $c->prompt('publisher/not-ready');
        return $c->detach;
    } elsif ($input > 0) {
        # invalid input
        goto PREPARE;
    } else {
        # error most likely
        return if $c->hungup;
        return $c->fatal_detach("Got result code $input on wait_for_digit in publisher.");
    }
}

sub begin_recording {
    my ($self, $c, $feed) = @_;
    
    my $cancelled = 0;
    
NEW_RECORDING:
    $c->no_detach_on_hangup(0);
    # press * at any time to start over, press # when you are finished
    # begin speaking in 
    # 3
    # 2
    # 1
    # ...
    $c->prompt('publisher/' . ($cancelled ? 'confirm/cancel' : 'rerecord'));
    return if $c->hungup;
    
START_RECORDING:
    my $record_filename;
    my $use_tempfile = 0;
    if ($use_tempfile) {
        # doesn't work so if fastagi is on a different OS
        (undef, $record_filename) = tempfile();
    } else {
        my $cache_dir = $c->config->{agi}{content_cache_directory};
        $record_filename = $cache_dir . "/" . $feed->canonicalname . '-' . time();
    }
    
    my $publisher_format = $c->config->{agi}{publisher_format}
        or return $c->fatal_detach("No publisher_format config defined");
    
    # don't automatically stop everything when caller hangs up, we need to handle saving a draft
    $c->no_detach_on_hangup(1);
    
    my $max_record_time = 60 * 60 * 20 * 1000;  # 20 minutes
    $c->log(1, "Recording new episode of " . $feed->shortname . " to $record_filename");
    my $rec_status = $c->agi->record_file(
        $record_filename,  # filename
        $publisher_format, # format
        '#*1234567890',    # escape digits
        $max_record_time,  # max rec length
        0,                 # beep
        undef,             # offset
        15,                # max silence (seconds)
    );
    
    if ($rec_status < 1) {
        $c->log(3, "record_file status: $rec_status (error)");
        
        # save as draft
        return $c->forward('/Publish/save_draft', $feed, "${record_filename}.$publisher_format");
    } else {
        if (chr($rec_status) eq '*') {
            # start over
            $cancelled = 1;
            goto NEW_RECORDING;
        } else {
CONFIRM:
            # play preview
            # I will now play a preview of your post, press 1 to publish or * to start over
            $c->prompt('publisher/confirm/confirm');
            
            my $confirm = $c->forward('/UserInput/get_dtmf_input',
                $record_filename,
                5, # timeout
                1, # max digits
            );
            
            if ($c->hungup) {
                # save draft
                return $c->forward('/Publish/save_draft', $feed, "${record_filename}.$publisher_format");
            }
            
            if ($confirm) {
                $c->log(3, "Publish recording confirm: $confirm");
                
                if ($confirm eq '*') {
                    # recording cancelled. please begin a new asterystpost after the beep
                    $c->prompt('publisher/confirm/cancel');
                    goto START_RECORDING;
                }
            } else {
                goto CONFIRM;
            }
            
            # save episode
            $c->forward('/Publish/save_episode', $feed, "${record_filename}.$publisher_format");
        } 
    }
    
    $c->no_detach_on_hangup(0);
    
    return $c->detach;
}

sub slurp {
    my ($self, $c, $file) = @_;
    
    my $filesize = -l $file
                    ? (lstat $file)[7]
                    : ( stat $file)[7];
    
    $c->log(3, "Slurping file $file, size: $filesize");
    
    unless ($filesize) {
        return $c->fatal_detach("Tried to read $file, but it appears to be empty! Check free disk space");
    }
    
    my ($fh, $contents);
    unless (open($fh, $file)) {
        return $c->fatal_detach("Failed to open $file: $!");
    }
    
    {
        local $/;
        $contents = <$fh>;
    }
    close $fh;
    
    return \$contents;
}

sub save_episode {
    my ($self, $c, $feed, $file) = @_;
    
    $c->busy;

    $c->log(1, "Saving new episode of " . $feed->shortname . ", file=$file");
    $c->no_detach_on_hangup(0);
    
    unless (-e $file) {
        return $c->fatal_detach("Failed to find saved recording $file");
    }
    
    my $audioref = $c->forward('/Publish/slurp', $file) or return;
    
    # SMS title notif
    $c->prompt('publisher/text');
    
    # actually publish. this might block for a few seconds
    $c->log(1, "Publishing episode $file to content server...");
    my $content_server_response = $c->content_saver->save_episode($c->caller, $feed, $audioref);
    unless ($content_server_response->is_success) {
        return $c->fatal_detach("Error saving episode: " . $content_server_response->error_message);
    }
}

sub save_draft {
    my ($self, $c, $feed, $file) = @_;
    
    $c->busy;
    
    $c->log(1, "Saving draft of " . $feed->shortname . ", file=$file");
    
    unless (-e $file) {
        return $c->fatal_detach("Failed to find saved recording $file");
    }

    my $audioref = $c->forward('/Publish/slurp', $file) or return;
    
    $c->log(1, "Publishing draft $file to content server...");
    my $content_server_response = $c->content_saver->save_draft($c->caller, $feed, $audioref);
    unless ($content_server_response->is_success) {
        return $c->fatal_detach("Error saving draft: " . $content_server_response->error_message);
    }
    
    # send draft saved notif
    $c->log(2, "Sending draft saved notification to caller " . $c->caller->phonenumber);
    Asteryst::Notification->send_episode_title_prompt($c->caller->id, $content_server_response->item_id);
    
    $c->no_detach_on_hangup(0);
    
    return $c->detach;
}

1;
