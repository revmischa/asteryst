package Asteryst::AGI::Controller::Ad;

use Moose;
extends 'Asteryst::AGI::Controller';

use LWP::UserAgent;
use XML::Simple;
use Asteryst::Util;
use Digest::SHA1;

sub play {
    my ($self, $c) = @_;
    
    # don't play ads unless caller has > 1 visit
    #return unless $c->caller->numvisits > 1;

    my $provider = $c->config->{agi}{ads}{provider}
        or die "Ads enabled but no provider specified";
    
    my $config = $c->config->{agi}{ads}{$provider}
        or die "No configuration specified for ad provider $provider";
        
    return if $c->session->has_played_ad;
    $c->session->has_played_ad(1);
    
    if ($provider eq 'apptera') {
        $c->forward('/Ad/apptera', $config) or return;
    } elsif ($provider eq 'voodoovox') {
        $c->forward('/Ad/voodoovox', $config) or return;
    } else {
        return $c->fatal_detach("Unknown ad provider '$provider'");
    }
    
    $c->earcon('AdOut');
}

sub voodoovox {
    my ($self, $c, $config) = @_;

    my $callerid = $c->caller_id;

    my $agi_addr = $config->{fastagi_address}
        or die "No ad fastagi_address configured";
        
    my $ad_key = $config->{client_key}
        or die "No ad client_key configured";
        
    $c->log(2, "Playing voodoovox ad");
    $c->earcon('AdIn');

    $c->agi->exec("AGI", "$agi_addr/key=${ad_key}&callerId=$callerid");
    return 1;
}

sub apptera {
    my ($self, $c, $config) = @_;
    
    my $url = $config->{ad_url}
        or die "No ad url configured";
        
    $url .= "&callerId=" . Asteryst::Util->format_number($c->caller_id);
    
    my $ua = new LWP::UserAgent;
    my $res = $ua->get($url);
    
    unless ($res->is_success) {
        $c->log(1, "Error fetching apptera campaign info from $url: " . $res->status_line);
        return;
    }
    
    my $resp_text = $res->content or return;
    my $res_obj = XMLin($resp_text) or return;
    
    my $cache_dir = $c->config->{agi}{ads}{cache_dir}
        or return $c->fatal_detach("No ads->cache_dir configured");

    my $bill_url = $config->{billing_url}
        or return $c->fatal_detach("No apptera billing url configured");
    
    mkdir $cache_dir or die $c->fatal_detach($!) unless -e $cache_dir;
    $c->fatal_detach("$cache_dir is not writable") unless -w $cache_dir;

    #use Data::Dumper;
    #$c->log(1, Dumper($res_obj));

    my $audio_info = $res_obj->{campaign}{content}{audio} or return;
    my $category = $res_obj->{campaign}{placement}{data}{datum}{step}{value} or return;

    my @urls;

    my $parse_audio_url = sub {
        my ($audio_data) = @_;

        my $base_url = $audio_data->{url} or return;
        my $ad_path = $audio_data->{file_name} or return;
        my $source_id = $res_obj->{campaign}{advertiser}{id} or return;

        $ad_path =~ s/ /%20/g;
        my $ad_url = $base_url . $source_id . '/' . $ad_path;

        push @urls, $ad_url;
    };

    if (ref $audio_info eq 'HASH') {
        $parse_audio_url->($res_obj->{campaign}{content}{audio});
    } else {
        # got two (or more?) audio files
        foreach my $audio (@$audio_info) {
            $parse_audio_url->($audio);
        }
    }

    my $call_transfer_target = $res_obj->{campaign}{placement}{route}{target};
    my $route_type = $res_obj->{campaign}{placement}{route}{type};
    my $origin_id = $res_obj->{origin_request_id};
    my $timestamp = $res_obj->{timestamp};
    my $rule_id = $res_obj->{campaign}{placement}{rule_id};
    
    # routine to fetch apptera audio content and save it
    my $fetch_audio_content = sub {
        my ($ad_url) = @_;

        my $local_ad_file_path = "$cache_dir/" . Digest::SHA1::sha1_hex($ad_url);
        $local_ad_file_path =~ s/ /_/g;
        $local_ad_file_path .= '.wav' unless $local_ad_file_path =~ /\.wav$/i;

        unless (-e $local_ad_file_path) {
            $res = $ua->get($ad_url, ':content_file' => $local_ad_file_path);
            unless ($res->is_success && -e $local_ad_file_path) {
                $c->log(1, "Error fetching apptera ad from $ad_url: " . $res->status_line);
                return;
            }
        }

        $local_ad_file_path =~ s/\.wav$//i;
        return $local_ad_file_path;
    };
    
    $bill_url .= '?originRequestId=' . $origin_id . '&timestamp=' . $timestamp .
        '&ruleId=' . $rule_id;

    my $opt_in = 0;


    # ready to play ad
    my $playfile = $fetch_audio_content->(shift @urls) or return;
    $c->log(2, "Playing apptera ad $playfile");
    $c->earcon('AdIn');

    # play ad, terminating if they press 1 (opt in)
    $res = $c->agi->get_option($playfile, '1', 100);  # ad, escape digits, timeout (ms)
    $c->log(4, "get_option res=" . (defined $res ? $res : "undef"));
    
    # did they opt in?
    my $played_billed = 0;
    if ($res && $res != -1) {
        if ($category == 4 && @urls) {
            # we are playing a double-opt-in ad, they just opted in the first time
            # now we need to fetch and play the second clip

            # hit billing url with first opt-in status
            my $first_bill_url = "$bill_url&action=played,transferred";
            $ua->get($first_bill_url);
            $c->log(3, "Hitting first billing url $first_bill_url");
            $played_billed = 1;

            my $url = shift @urls;
            $playfile = $fetch_audio_content->($url) or return;
            $c->log(2, "Playing second step of apptera ad");

            # play second component of the ad
            $res = $c->agi->get_option($playfile, '1', 100);
            $c->log(4, "get_option res=" . (defined $res ? $res : "undef"));

            if ($res && $res != -1) {
                # double-opt-in complete
                $opt_in = 1;
            }
        } else {
            $opt_in = 1;
        }

        if ($call_transfer_target && $route_type && $route_type eq 'Phone Number') {
            # do billing request now since we're not coming back
            $ua->get("$bill_url&action=played,sent");

            # user wants to be transferred
            $c->log(1, "Transferring caller to ad target $call_transfer_target");
            $call_transfer_target =~ s/\-//g;
            $c->agi->exec("Dial", "SIP/bw-in-primary/+1$call_transfer_target,60,r");
            return $c->detach;
        }
    }

    # if doing double opt-in, we may have already sent action=played
    if (! $played_billed && ! $opt_in) {
        $bill_url = "$bill_url&action=played";
        $bill_url .= ',sent' if $opt_in;
        $c->log(3, "Hitting billing url $bill_url");
        $ua->get($bill_url);
    }

    return 1;
}

1;
